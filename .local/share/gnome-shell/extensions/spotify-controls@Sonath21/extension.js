/*
 * Spotify Controls Extension
 * Copyright (C) 2024 Athanasios Raptis
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import St from 'gi://St';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Clutter from 'gi://Clutter';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

import { Extension, gettext as _ } from 'resource:///org/gnome/shell/extensions/extension.js';

// Debugging flag and function to control debug logging
const DEBUG = false;

/**
 * Logs debug messages to the GNOME Shell log if debugging is enabled.
 * @param {string} message - The debug message to log.
 */
function logDebug(message) {
    if (DEBUG) {
        console.log(`[Spotify Controls DEBUG]: ${message}`);
    }
}

/**
 * Logs error messages to the GNOME Shell log.
 * @param {Error} error - The error object.
 * @param {string} message - Additional context for the error.
 */
function logError(error, message) {
    console.error(`[Spotify Controls ERROR]: ${message}`, error);
}

// Define constants for Spotify's MPRIS D-Bus interface
const SPOTIFY_BUS_NAME = 'org.mpris.MediaPlayer2.spotify'; // D-Bus bus name for Spotify
const SPOTIFY_OBJECT_PATH = '/org/mpris/MediaPlayer2'; // Object path for Spotify's MPRIS interface
const MPRIS_PLAYER_INTERFACE = 'org.mpris.MediaPlayer2.Player'; // Interface for player controls
const PROPERTIES_INTERFACE = 'org.freedesktop.DBus.Properties'; // Interface for property changes

/**
 * SpotifyIndicator Class
 * Extends PanelMenu.Button to create a Spotify controls indicator in the GNOME top bar.
 */
var SpotifyIndicator = GObject.registerClass(
    class SpotifyIndicator extends PanelMenu.Button {
        /**
         * Constructor for SpotifyIndicator.
         * @param {string} extensionPath - The path to the extension's directory.
         * @param {string} controlsPosition - Position of playback controls ('left' or 'right').
         * @param {Gio.Settings} settings - The settings object for the extension.
         */
        _init(extensionPath, controlsPosition, settings) {
            super._init(0.0, 'Spotify Controls');
            logDebug('SpotifyIndicator initialized');

            this.controlsPosition = controlsPosition;
            this._settings = settings;
            this._signalSubscriptionId = null;

            // Initialize the _activeTimeouts array
            this._activeTimeouts = [];

            // Store the extensionPath for later use
            this.extensionPath = extensionPath;

            this._buildUI(extensionPath);
            this._monitorSpotifyPresence();

            // Connect the 'button-press-event' to the updated handler
            this.connect('button-press-event', this._onExtensionClicked.bind(this));

            // Connect to changes in 'show-spotify-icon' and 'show-track-info' settings
            this._showIconChangedId = this._settings.connect('changed::show-spotify-icon', this._onShowIconChanged.bind(this));
            this._showTrackInfoChangedId = this._settings.connect('changed::show-track-info', this._onShowTrackInfoChanged.bind(this));
        }

        /**
         * Helper function to create a separator.
         * @returns {St.Label} - A new St.Label instance acting as a separator.
         */
        _createSeparator() {
            return new St.Label({ text: ' ' });
        }

        /**
         * Builds the user interface components of the Spotify indicator.
         * @param {string} extensionPath - The path to the extension's directory.
         */
        _buildUI(extensionPath) {
            logDebug('Building UI');

            // Create the main horizontal box layout for the indicator
            let hbox = new St.BoxLayout({ style_class: 'spotify-hbox' });
            this.add_child(hbox);

            // Create a container for playback controls
            let controlsBox = new St.BoxLayout({ style_class: 'spotify-controls-box' });

            // Conditionally add playback controls based on the setting
            if (this._settings.get_boolean('show-playback-controls')) {
                // Create the control buttons: Previous, Play/Pause, Next
                this.prevButton = new St.Button({
                    style_class: 'spotify-status-icon',
                    child: new St.Icon({ icon_name: 'media-skip-backward-symbolic' }),
                });
                this.playPauseButton = new St.Button({
                    style_class: 'spotify-status-icon',
                    child: new St.Icon({ icon_name: 'media-playback-pause-symbolic' }), 
                });
                this.nextButton = new St.Button({
                    style_class: 'spotify-status-icon',
                    child: new St.Icon({ icon_name: 'media-skip-forward-symbolic' }),
                });

                // Connect the 'clicked' signal of each button to their respective handler functions
                this.prevButton.connect('clicked', () => this._sendMPRISCommand('Previous'));
                this.playPauseButton.connect('clicked', () => this._sendMPRISCommand('PlayPause'));
                this.nextButton.connect('clicked', () => this._sendMPRISCommand('Next'));

                // Add buttons to the controlsBox
                controlsBox.add_child(this.prevButton);
                controlsBox.add_child(this.playPauseButton);
                controlsBox.add_child(this.nextButton);
            }

            // Spotify icon - Load the SVG from the icons directory using extensionPath
            this.spotifyIcon = new St.Icon({
                gicon: Gio.icon_new_for_string(`${extensionPath}/icons/spotify.svg`),
                icon_size: 16,
                style_class: 'spotify-icon',
            });

            // Initially set the visibility based on the settings
            this.spotifyIcon.visible = this._settings.get_boolean('show-spotify-icon');

            // Add the Spotify icon and separators to the UI
            hbox.add_child(this.spotifyIcon);
            hbox.add_child(this._createSeparator());
            hbox.add_child(this._createSeparator());
            hbox.add_child(this._createSeparator());

            // Artist and Song Title label
            this.trackLabel = new St.Label({
                text: _('No Track Playing'),
                y_expand: true,
                y_align: Clutter.ActorAlign.CENTER,
            });

            // Conditionally display the track info based on the setting
            this.trackLabel.visible = this._settings.get_boolean('show-track-info');

            // Add scroll event listener to trackLabel for volume control
            if (this._settings.get_boolean('enable-volume-control')) {
                this.connect('scroll-event', this._adjustVolume.bind(this));
            }

            // Based on controlsPosition, arrange the UI elements
            if (this.controlsPosition === 'left') {
                // Add playback controls first if they are enabled
                if (this._settings.get_boolean('show-playback-controls')) {
                    hbox.add_child(controlsBox);
                    hbox.add_child(this._createSeparator());
                    hbox.add_child(this._createSeparator());
                    hbox.add_child(this._createSeparator());
                }
                hbox.add_child(this.trackLabel);
            } else {
                // Add playback controls last (default behavior) if they are enabled
                hbox.add_child(this.trackLabel);
                if (this._settings.get_boolean('show-playback-controls')) {
                    hbox.add_child(this._createSeparator());
                    hbox.add_child(this._createSeparator());
                    hbox.add_child(controlsBox);
                }
            }

            logDebug('UI built with controls positioned to the ' + this.controlsPosition);
        }

        /**
         * Callback function when the 'show-spotify-icon' setting changes.
         * Shows or hides the Spotify icon based on the new setting.
         */
        _onShowIconChanged() {
            const showIcon = this._settings.get_boolean('show-spotify-icon');
            logDebug(`'show-spotify-icon' changed to ${showIcon}`);

            if (this.spotifyIcon) {
                this.spotifyIcon.visible = showIcon;
                logDebug(`Spotify icon visibility set to ${showIcon}`);
            } else if (showIcon) {
                // If for some reason the icon wasn't created, create and add it
                this.spotifyIcon = new St.Icon({
                    gicon: Gio.icon_new_for_string(`${this.extensionPath}/icons/spotify.svg`),
                    icon_size: 16,
                    style_class: 'spotify-icon',
                });
                this.spotifyIcon.visible = showIcon;

                // Add the Spotify icon to the UI
                this.add_child_before(this.spotifyIcon, this.trackLabel);
                this.add_child_after(this.spotifyIcon, this._createSeparator());
                this.add_child_after(this.spotifyIcon, this._createSeparator());
                this.add_child_after(this.spotifyIcon, this._createSeparator());

                logDebug('Spotify icon created and shown');
            }
        }

        /**
         * Callback function when the 'show-track-info' setting changes.
         * Shows or hides the Artist/Track information based on the new setting.
         */
        _onShowTrackInfoChanged() {
            const showInfo = this._settings.get_boolean('show-track-info');
            logDebug(`'show-track-info' changed to ${showInfo}`);

            if (this.trackLabel) {
                this.trackLabel.visible = showInfo;
                logDebug(`Track info visibility set to ${showInfo}`);
            }
        }

        /**
         * Handles the click event on the extension.
         * @param {Clutter.Actor} actor - The actor that received the event.
         * @param {Clutter.Event} event - The event object.
         */
        _onExtensionClicked(actor, event) {
            const button = event.get_button();
            
            // Retrieve user setting for enabling middle-click
            const enableMiddleClick = this._settings.get_boolean('enable-middle-click');

            if (button === Clutter.BUTTON_PRIMARY) {
                // Left-click: Toggle Spotify window
                this._activateSpotifyWindow();
            } else if (button === Clutter.BUTTON_MIDDLE && enableMiddleClick) {
                // Only do Play/Pause if middle-click is enabled
                this._sendMPRISCommand('PlayPause')
                    .catch(() => {
                        // If PlayPause fails, attempt to launch Spotify
                        this._launchSpotify();
                    });
            }
        }

        /**
         * Activates (or minimizes) the Spotify window, depending on user preferences
         * and the current window state.
         */
        _activateSpotifyWindow() {
            logDebug('Attempting to activate Spotify window');

            // Retrieve the user setting for whether to minimize on second click
            const minimizeOnSecondClick = this._settings.get_boolean('minimize-on-second-click');
            logDebug(`minimizeOnSecondClick = ${minimizeOnSecondClick}`);

            // Retrieve all window actors
            let windowActors = global.get_window_actors();

            // Flag to check if Spotify window is found
            let spotifyFound = false;

            for (let actor of windowActors) {
                let window = actor.get_meta_window();
                let wmClass = window.get_wm_class();

                // Log details for debugging
                logDebug(`Window WM_CLASS: ${JSON.stringify(wmClass)} (Type: ${typeof wmClass})`);
                logDebug(`Window Title: ${window.get_title()} (Type: ${typeof window.get_title()})`);
                logDebug(`Window Workspace: ${window.get_workspace()} (Type: ${typeof window.get_workspace()})`);

                let isSpotify = false;

                if (Array.isArray(wmClass)) {
                    // If wmClass is an array, check if any element matches 'spotify'
                    isSpotify = wmClass.some(cls => cls.toLowerCase() === 'spotify');
                } else if (typeof wmClass === 'string') {
                    // If wmClass is a string, check if it matches 'spotify'
                    isSpotify = wmClass.toLowerCase() === 'spotify';
                }

                if (isSpotify) {
                    // Validate that 'window' has the 'activate' method
                    if (typeof window.activate !== 'function') {
                        logDebug('Window does not have an activate method. Skipping.');
                        continue;
                    }

                    try {
                        if (window.minimized) {
                            // If the window is minimized, unminimize and activate
                            window.unminimize();
                            logDebug("Spotify window unminimized");
                            window.activate(global.get_current_time());
                            logDebug("Spotify window activated");
                        } else {
                            // If it's not minimized and the user wants to
                            // minimize on second click, do so. Otherwise, do nothing.
                            if (minimizeOnSecondClick) {
                                window.minimize();
                                logDebug("Spotify window minimized");
                            } else {
                                logDebug("Spotify already in foreground; doing nothing.");
                            }
                        }

                        spotifyFound = true;
                        break; // Exit once we handle the Spotify window
                    } catch (e) {
                        logError(e, 'Failed to activate Spotify window');
                    }
                }
            }

            if (!spotifyFound) {
                logDebug('Spotify window not found. Attempting to launch Spotify to show its window.');

                try {
                    // Create a new subprocess to execute the 'spotify' command
                    const subprocess = Gio.Subprocess.new(
                        ['spotify'],
                        Gio.SubprocessFlags.NONE
                    );

                    // Run the subprocess async
                    subprocess.wait_async(null, (proc, res) => {
                        try {
                            proc.wait_finish(res);
                            logDebug('Spotify launched successfully to show its window.');
                        } catch (e) {
                            logError(e, 'Failed to launch Spotify to show its window.');
                        }
                    });
                } catch (e) {
                    logError(e, 'Error while attempting to launch Spotify subprocess.', e);
                }
            }
        }

        /**
         * Monitors Spotify's presence on the D-Bus.
         * Shows or hides the indicator based on whether Spotify is running.
         */
        _monitorSpotifyPresence() {
            logDebug('Starting to monitor Spotify presence');
            this.hide();

            // Watch for the Spotify MPRIS D-Bus name to appear or vanish
            this._spotifyWatcherId = Gio.DBus.session.watch_name(
                SPOTIFY_BUS_NAME,
                Gio.BusNameWatcherFlags.NONE,
                this._onSpotifyAppeared.bind(this),
                this._onSpotifyVanished.bind(this)
            );
        }

        /**
         * Callback function when Spotify appears on the D-Bus.
         * Shows the indicator and subscribes to property changes.
         */
        async _onSpotifyAppeared() {
            logDebug('Spotify appeared on D-Bus');
            this.show();

            // Subscribe to the PropertiesChanged signal first
            this._signalSubscriptionId = Gio.DBus.session.signal_subscribe(
                SPOTIFY_BUS_NAME,
                PROPERTIES_INTERFACE,
                'PropertiesChanged',
                SPOTIFY_OBJECT_PATH,
                null,
                Gio.DBusSignalFlags.NONE,
                this._onPropertiesChanged.bind(this)
            );

            // Fetch the initial PlaybackStatus and Metadata from Spotify after subscribing
            try {
                let playbackStatus = await this._getPlaybackStatus();
                this._updatePlayPauseIcon(playbackStatus);
                await this._retryFetchMetadata();
            } catch (e) {
                logError(e, 'Failed to get initial PlaybackStatus or Metadata');
            }
        }

        /**
         * Retry fetching Metadata with specified retries and delay.
         * @param {number} retries - Number of retry attempts.
         * @param {number} delay - Delay between retries in milliseconds.
         */
        async _retryFetchMetadata(retries = 3, delay = 500) {
            for (let i = 0; i < retries; i++) {
                try {
                    let metadata = await this._getMetadata();
                    if (metadata['xesam:artist'] && metadata['xesam:title']) {
                        this._updateTrackInfo(metadata);
                        logDebug('Successfully fetched valid Metadata on retry');
                        return;
                    }
                } catch (e) {
                    logError(e, 'Retry fetching Metadata failed');
                }

                // Await the cancellable sleep
                await this._sleep(delay);
            }
            logDebug('Failed to fetch valid Metadata after retries');
        }

        /**
         * Sleeps for the specified delay in milliseconds.
         * The timeout is tracked and can be cleared upon destruction.
         * @param {number} delay - The delay in milliseconds.
         * @returns {Promise<void>} - A Promise that resolves after the delay.
         */
        _sleep(delay) {
            return new Promise((resolve) => {
                const timeoutID = setTimeout(() => {
                    resolve();
                    // Remove the timeoutID from activeTimeouts once resolved
                    const index = this._activeTimeouts.indexOf(timeoutID);
                    if (index > -1) {
                        this._activeTimeouts.splice(index, 1);
                    }
                }, delay);
                this._activeTimeouts.push(timeoutID);
            });
        }

        /**
         * Handler for the PropertiesChanged signal from Spotify.
         * Updates the UI elements based on the changed properties.
         * @param {Gio.DBusConnection} connection - The D-Bus connection.
         * @param {string} sender - The sender's bus name.
         * @param {string} objectPath - The object path of the signal.
         * @param {string} interfaceName - The interface name of the signal.
         * @param {string} signalName - The name of the signal.
         * @param {GLib.Variant} parameters - The parameters of the signal.
         */
        _onPropertiesChanged(connection, sender, objectPath, interfaceName, signalName, parameters) {
            let [iface, changedProps, invalidatedProps] = parameters.deep_unpack();

            // Check if the signal is from the MPRIS Player Interface
            if (iface === MPRIS_PLAYER_INTERFACE) {
                // If PlaybackStatus has changed, update the Play/Pause button icon
                if (changedProps.PlaybackStatus) {
                    let playbackStatus = changedProps.PlaybackStatus.deep_unpack();
                    this._updatePlayPauseIcon(playbackStatus);
                    logDebug(`PlaybackStatus changed to ${playbackStatus}`);
                }

                // If Metadata has changed, update the track information label
                if (changedProps.Metadata) {
                    let metadataVariant = changedProps.Metadata.deep_unpack();

                    // Convert the metadata Variant into a plain JavaScript object
                    let metadata = {};
                    for (let key in metadataVariant) {
                        metadata[key] = metadataVariant[key].deep_unpack();
                    }

                    logDebug(`PropertiesChanged Metadata: ${JSON.stringify(metadata)}`);
                    this._updateTrackInfo(metadata);
                }
            }
        }

        /**
         * Retrieves the current PlaybackStatus from Spotify using D-Bus.
         * @returns {Promise<string>} - A promise that resolves to the playback status.
         */
        async _getPlaybackStatus() {
            return new Promise((resolve, reject) => {
                Gio.DBus.session.call(
                    SPOTIFY_BUS_NAME,
                    SPOTIFY_OBJECT_PATH,
                    PROPERTIES_INTERFACE,
                    'Get',
                    new GLib.Variant('(ss)', [MPRIS_PLAYER_INTERFACE, 'PlaybackStatus']), // Parameters for the method
                    GLib.VariantType.new('(v)'), // Expected return type
                    Gio.DBusCallFlags.NONE,
                    -1,
                    null,
                    (connection, result) => {
                        try {
                            let response = connection.call_finish(result);
                            let [playbackStatusVariant] = response.deep_unpack();
                            let playbackStatus = playbackStatusVariant.deep_unpack();
                            logDebug(`Fetched PlaybackStatus: ${playbackStatus}`);
                            resolve(playbackStatus);
                        } catch (e) {
                            logError(e, 'Failed to fetch PlaybackStatus');
                            reject(e);
                        }
                    }
                );
            });
        }

        /**
         * Retrieves the current Metadata from Spotify using D-Bus.
         * @returns {Promise<Object>} - A promise that resolves to the metadata object.
         */
        async _getMetadata() {
            return new Promise((resolve, reject) => {
                Gio.DBus.session.call(
                    SPOTIFY_BUS_NAME,
                    SPOTIFY_OBJECT_PATH,
                    PROPERTIES_INTERFACE,
                    'Get',
                    new GLib.Variant('(ss)', [MPRIS_PLAYER_INTERFACE, 'Metadata']),
                    GLib.VariantType.new('(v)'),
                    Gio.DBusCallFlags.NONE,
                    -1,
                    null,
                    (connection, result) => {
                        try {
                            let response = connection.call_finish(result);
                            let [metadataVariant] = response.deep_unpack();
                            let metadata = metadataVariant.deep_unpack();

                            let metadataUnpacked = {};
                            for (let key in metadata) {
                                metadataUnpacked[key] = metadata[key].deep_unpack();
                            }

                            logDebug(`Fetched Metadata: ${JSON.stringify(metadataUnpacked)}`);
                            resolve(metadataUnpacked);
                        } catch (e) {
                            logError(e, 'Failed to fetch Metadata');
                            reject(e);
                        }
                    }
                );
            });
        }

        /**
         * Updates the track information label with the current artist and song title.
         * @param {Object} metadata - The metadata object containing track information.
         */
        _updateTrackInfo(metadata) {
            let artistArray = this._recursiveUnpack(metadata['xesam:artist']);
            let title = this._recursiveUnpack(metadata['xesam:title']);

            let artist = _('Unknown Artist');
            if (Array.isArray(artistArray) && artistArray.length > 0 && artistArray[0].trim() !== '') {
                artist = artistArray[0];
            }

            if (title && title.trim() !== '') {
                // Valid title
            } else {
                title = _('Unknown Title');
            }

            this.trackLabel.text = `${artist} - ${title}`;
            logDebug(`Updated track info: ${artist} - ${title}`);
        }

        /**
         * Recursively unpacks a GLib.Variant if necessary.
         * @param {any} variant - The value to unpack.
         * @returns {any} - The unpacked value.
         */
        _recursiveUnpack(variant) {
            if (variant instanceof GLib.Variant) {
                return variant.deep_unpack(); // Unpack the Variant to get the raw value
            } else {
                return variant; // Return the value as-is if it's not a Variant
            }
        }

        /**
         * Updates the Play/Pause button icon based on the current playback status.
         * @param {string} playbackStatus - The current playback status ('Playing' or other).
         */
        _updatePlayPauseIcon(playbackStatus) {
            let iconName = (playbackStatus === 'Playing')
                ? 'media-playback-pause-symbolic'
                : 'media-playback-start-symbolic';
            if (this.playPauseButton) {
                this.playPauseButton.child.icon_name = iconName;
            }
            logDebug(`Updated play/pause icon to ${iconName}`);
        }

        /**
         * Sends an MPRIS command (e.g., 'Previous', 'PlayPause', 'Next') to Spotify.
         * @param {string} command - The MPRIS command to send.
         * @returns {Promise<void>} - A promise that resolves when the command is sent successfully.
         */
        _sendMPRISCommand(command) {
            logDebug(`Sending MPRIS command: ${command}`);
            return new Promise((resolve, reject) => {
                Gio.DBus.session.call(
                    SPOTIFY_BUS_NAME,
                    SPOTIFY_OBJECT_PATH,
                    MPRIS_PLAYER_INTERFACE,
                    command,
                    null,
                    null,
                    Gio.DBusCallFlags.NONE,
                    -1,
                    null,
                    (conn, res) => {
                        try {
                            conn.call_finish(res);
                            logDebug(`MPRIS command '${command}' sent successfully`);
                            resolve();
                        } catch (e) {
                            logError(e, `Failed to send MPRIS command: ${command}`);
                            reject(e);
                        }
                    }
                );
            });
        }

        /**
         * Adjusts the volume based on the scroll direction.
         * @param {Clutter.Event} event - The scroll event.
         */
        _adjustVolume(actor, event) {
            logDebug(`Scroll event detected for volume control`);
            let direction = event.get_scroll_direction();
            if (direction === Clutter.ScrollDirection.UP) {
                this._sendMPRISVolumeCommand('Raise');
            } else if (direction === Clutter.ScrollDirection.DOWN) {
                this._sendMPRISVolumeCommand('Lower');
            }
        }

        /**
         * Sends an MPRIS volume command (e.g., 'Raise', 'Lower') to Spotify.
         * @param {string} command - The MPRIS volume command to send.
         */
        _sendMPRISVolumeCommand(command) {
            logDebug(`Sending MPRIS volume command: ${command}`);

            // First, get the current volume
            Gio.DBus.session.call(
                SPOTIFY_BUS_NAME,
                SPOTIFY_OBJECT_PATH,
                PROPERTIES_INTERFACE,
                'Get',
                new GLib.Variant('(ss)', [MPRIS_PLAYER_INTERFACE, 'Volume']),
                GLib.VariantType.new('(v)'),
                Gio.DBusCallFlags.NONE,
                -1,
                null,
                (conn, res) => {
                    try {
                        let response = conn.call_finish(res);
                        let [volumeVariant] = response.deep_unpack();
                        let currentVolume = volumeVariant.deep_unpack();
                        logDebug(`Current volume: ${currentVolume}`);

                        // Adjust the volume based on the command
                        let newVolume = currentVolume;
                        if (command === 'Raise') {
                            newVolume = Math.min(currentVolume + 0.1, 1.0); // Increase volume by 10%
                        } else if (command === 'Lower') {
                            newVolume = Math.max(currentVolume - 0.1, 0.0); // Decrease volume by 10%
                        }

                        // Set the new volume
                        Gio.DBus.session.call(
                            SPOTIFY_BUS_NAME,
                            SPOTIFY_OBJECT_PATH,
                            PROPERTIES_INTERFACE,
                            'Set',
                            new GLib.Variant('(ssv)', [MPRIS_PLAYER_INTERFACE, 'Volume', new GLib.Variant('d', newVolume)]),
                            null,
                            Gio.DBusCallFlags.NONE,
                            -1,
                            null,
                            (conn, res) => {
                                try {
                                    conn.call_finish(res);
                                    logDebug(`Volume set to ${newVolume}`);
                                } catch (e) {
                                    logError(e, `Failed to set volume to ${newVolume}`);
                                }
                            }
                        );
                    } catch (e) {
                        logError(e, 'Failed to get current volume');
                    }
                }
            );
        }

        /**
         * Callback function when Spotify vanishes from D-Bus.
         * Hides the indicator and cleans up signal subscriptions.
         */
        _onSpotifyVanished() {
            logDebug('Spotify vanished from D-Bus');
            this.hide();

            if (this._signalSubscriptionId) {
                Gio.DBus.session.signal_unsubscribe(this._signalSubscriptionId);
                this._signalSubscriptionId = null;
            }
        }

        /**
         * Cleans up resources when the SpotifyIndicator is destroyed.
         */
        destroy() {
            logDebug('Destroying SpotifyIndicator');

            // Unwatch Spotify's D-Bus name if it was being watched
            if (this._spotifyWatcherId) {
                Gio.DBus.session.unwatch_name(this._spotifyWatcherId);
                this._spotifyWatcherId = null;
            }

            // Unsubscribe from the PropertiesChanged signal if subscribed
            if (this._signalSubscriptionId) {
                Gio.DBus.session.signal_unsubscribe(this._signalSubscriptionId);
                this._signalSubscriptionId = null;
            }

            // Disconnect the 'show-spotify-icon' and 'show-track-info' setting change signals
            if (this._showIconChangedId) {
                this._settings.disconnect(this._showIconChangedId);
                this._showIconChangedId = null;
            }

            if (this._showTrackInfoChangedId) {
                this._settings.disconnect(this._showTrackInfoChangedId);
                this._showTrackInfoChangedId = null;
            }

            // Clear all active timeouts
            for (let timeoutID of this._activeTimeouts) {
                clearTimeout(timeoutID);
            }
            this._activeTimeouts = [];

            // Optionally, hide or destroy the Spotify icon and track label
            if (this.spotifyIcon) {
                this.spotifyIcon.destroy();
                this.spotifyIcon = null;
            }

            if (this.trackLabel) {
                this.trackLabel.destroy();
                this.trackLabel = null;
            }

            super.destroy();
        }

        _launchSpotify() {
            logDebug('Attempting to launch Spotify');

            try {
                Gio.Subprocess.new(
                    ['spotify'],
                    Gio.SubprocessFlags.NONE
                );
                logDebug('Spotify launched successfully');
            } catch (e) {
                logError(e, 'Failed to launch Spotify');
            }
        }
    }
);

let spotifyIndicator = null;

/**
 * SpotifyControlsExtension Class
 * Manages the lifecycle (enable/disable) of the Spotify Controls extension.
 * Extends the base Extension class to utilize its properties and methods.
 */
export default class SpotifyControlsExtension extends Extension {
    /**
     * Constructor for SpotifyControlsExtension.
     * @param {Object} metadata - The metadata object provided by GNOME Shell.
     */
    constructor(metadata) {
        super(metadata);
        logDebug('Initializing SpotifyControlsExtension');
    }

    /**
     * Called when the extension is enabled.
     * Initializes the SpotifyIndicator and adds it to the panel.
     */
    enable() {
        logDebug('Enabling SpotifyControlsExtension');
        this._settings = this.getSettings();

        // Connect to changes in various settings
        this._positionChangedId = this._settings.connect('changed::position', this._onSettingsChanged.bind(this));
        this._controlsPositionChangedId = this._settings.connect('changed::controls-position', this._onSettingsChanged.bind(this));
        this._showControlsChangedId = this._settings.connect('changed::show-playback-controls', this._onSettingsChanged.bind(this));
        this._volumeControlChangedId = this._settings.connect('changed::enable-volume-control', this._onSettingsChanged.bind(this));
        this._showSpotifyIconChangedId = this._settings.connect('changed::show-spotify-icon', this._onSettingsChanged.bind(this));
        this._showTrackInfoChangedId = this._settings.connect('changed::show-track-info', this._onSettingsChanged.bind(this));
        // (No need to connect a signal for minimize-on-second-click unless you
        // want to dynamically refresh the behavior mid-session. Typically not necessary.)

        this._updateIndicator();
    }

    /**
     * Updates the position of the SpotifyIndicator based on user settings.
     */
    _updateIndicator() {
        if (spotifyIndicator) {
            spotifyIndicator.destroy();
            spotifyIndicator = null;
        }

        // Retrieve settings for indicator position and controls position
        let position = this._settings.get_string('position');
        let controlsPosition = this._settings.get_string('controls-position');

        // Validate 'position' setting
        const validPositions = [
            'far-left',
            'mid-left',
            'rightmost-left',
            'middle-left',
            'center',
            'middle-right',
            'leftmost-right',
            'mid-right',
            'far-right',
        ];

        if (!validPositions.includes(position)) {
            position = 'rightmost-left'; // Default to 'rightmost-left' if invalid
        }

        // Validate 'controls-position' setting
        if (controlsPosition !== 'left' && controlsPosition !== 'right') {
            controlsPosition = 'right'; // Default to 'right' if invalid
        }

        // Pass 'extensionPath', 'controlsPosition', and 'settings' to SpotifyIndicator
        spotifyIndicator = new SpotifyIndicator(this.path, controlsPosition, this._settings);

        // Determine which box (left, center, right) to add the indicator to and its offset
        let boxName;
        let offset = null;

        switch (position) {
            case 'far-left':
                boxName = 'left';
                offset = 0;
                break;
            case 'mid-left':
                boxName = 'left';
                offset = Math.floor(Main.panel._leftBox.get_children().length / 2);
                break;
            case 'rightmost-left':
                boxName = 'left';
                offset = Main.panel._leftBox.get_children().length;
                break;
            case 'middle-left':
                boxName = 'center';
                offset = Math.max(0, Math.floor(Main.panel._centerBox.get_children().length / 2) - 1);
                break;
            case 'center':
                boxName = 'center';
                offset = Math.floor(Main.panel._centerBox.get_children().length / 2);
                break;
            case 'middle-right':
                boxName = 'center';
                offset = Math.floor(Main.panel._centerBox.get_children().length / 2) + 1;
                break;
            case 'leftmost-right':
                boxName = 'right';
                offset = 0;
                break;
            case 'mid-right':
                boxName = 'right';
                offset = Math.floor(Main.panel._rightBox.get_children().length / 2);
                break;
            case 'far-right':
                boxName = 'right';
                offset = Main.panel._rightBox.get_children().length;
                break;
            default:
                boxName = 'right';
                offset = null;
        }

        Main.panel.addToStatusArea('spotify-indicator', spotifyIndicator, offset, boxName);
        logDebug(`Indicator added at position: ${position}, box: ${boxName}, offset: ${offset}`);
    }

    /**
     * Callback function when any relevant setting changes.
     * Updates the indicator's position or layout accordingly.
     */
    _onSettingsChanged() {
        logDebug('Settings changed: updating indicator');
        this._updateIndicator();
    }

    /**
     * Called when the extension is disabled.
     * Destroys the SpotifyIndicator and disconnects settings signals.
     */
    disable() {
        logDebug('Disabling SpotifyControlsExtension');
        if (spotifyIndicator) {
            spotifyIndicator.destroy();
            spotifyIndicator = null;
        }

        // Disconnect signal handlers for settings changes
        if (this._positionChangedId) {
            this._settings.disconnect(this._positionChangedId);
            this._positionChangedId = null;
        }

        if (this._controlsPositionChangedId) {
            this._settings.disconnect(this._controlsPositionChangedId);
            this._controlsPositionChangedId = null;
        }

        if (this._showControlsChangedId) {
            this._settings.disconnect(this._showControlsChangedId);
            this._showControlsChangedId = null;
        }

        if (this._volumeControlChangedId) {
            this._settings.disconnect(this._volumeControlChangedId);
            this._volumeControlChangedId = null;
        }

        if (this._showSpotifyIconChangedId) {
            this._settings.disconnect(this._showSpotifyIconChangedId);
            this._showSpotifyIconChangedId = null;
        }

        if (this._showTrackInfoChangedId) {
            this._settings.disconnect(this._showTrackInfoChangedId);
            this._showTrackInfoChangedId = null;
        }

        this._settings = null;
    }
}

