var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __reExport = (target, mod, secondTarget) => (__copyProps(target, mod, "default"), secondTarget && __copyProps(secondTarget, mod, "default"));

// node_modules/@girs/gnome-shell/dist/extensions/extension.js
var extension_exports = {};
__reExport(extension_exports, extension_star);
import * as extension_star from "resource:///org/gnome/shell/extensions/extension.js";

// node_modules/@girs/gnome-shell/dist/ui/main.js
var main_exports = {};
__reExport(main_exports, main_star);
import * as main_star from "resource:///org/gnome/shell/ui/main.js";

// src/Utils.ts
var Utils = class {
  static ICONS = {
    INDICATOR_DEFAULT: "/icons/icon-symbolic.svg",
    INDICATOR_PAUSED: "/icons/icon-paused-symbolic.svg",
    INDICATOR_PLAYING: "/icons/icon-playing-symbolic.svg",
    POPUP_PLAY: "media-playback-start-symbolic",
    POPUP_STOP: "media-playback-stop-symbolic",
    POPUP_PAUSE: "media-playback-pause-symbolic"
  };
  //  TODO: refactor to put all keys here
  static SHORTCUTS = {
    PLAY_PAUSE_SHORTCUT: "play-pause-quick-lofi",
    STOP_SHORTCUT: "stop-quick-lofi"
  };
  static SETTINGS_KEYS = {
    ...this.SHORTCUTS
  };
  static debug(...message) {
    log("[ QUICK LOFI DEBUG ] >>> ", ...message);
  }
  static isCurrentRadioPlaying(settings, radioID) {
    const currentRadioPlaying = settings.get_string("current-radio-playing");
    return currentRadioPlaying.length > 0 && radioID === currentRadioPlaying;
  }
  static generateNanoIdWithSymbols(size) {
    const characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+-=[]{}|;:,.<>?";
    const charactersLength = characters.length;
    let result = "";
    for (let i = 0; i < size; i++) {
      result += characters.charAt(Math.floor(Math.random() * charactersLength));
    }
    return result;
  }
};

// node_modules/@girs/gnome-shell/dist/ui/slider.js
var slider_exports = {};
__reExport(slider_exports, slider_star);
import * as slider_star from "resource:///org/gnome/shell/ui/slider.js";

// node_modules/@girs/gnome-shell/dist/ui/panelMenu.js
var panelMenu_exports = {};
__reExport(panelMenu_exports, panelMenu_star);
import * as panelMenu_star from "resource:///org/gnome/shell/ui/panelMenu.js";

// node_modules/@girs/gnome-shell/dist/ui/popupMenu.js
var popupMenu_exports = {};
__reExport(popupMenu_exports, popupMenu_star);
import * as popupMenu_star from "resource:///org/gnome/shell/ui/popupMenu.js";

// src/Player.ts
import GLib from "gi://GLib";
import Gio2 from "gi://Gio";
import GObject from "gi://GObject";
var _Player = class _Player extends GObject.Object {
  constructor(_settings) {
    super();
    this._settings = _settings;
  }
  _mpvSocket = "/tmp/quicklofi-socket";
  _isCommandRunning = false;
  _process = null;
  initVolumeControl() {
    this._settings.connect("changed::volume", (settings, key) => {
      if (this._process !== null && !this._isCommandRunning) {
        const volume = settings.get_int(key);
        const command = this.createCommand({
          command: ["set_property", "volume", volume]
        });
        this.sendCommandToMpvSocket(command);
      }
    });
  }
  stopPlayer() {
    if (this._process !== null) {
      this._process.force_exit();
      this._process = null;
      this.emit("playback-stopped");
      return;
    }
  }
  playPause() {
    const playPauseCommand = this.createCommand({ command: ["cycle", "pause"] });
    this.sendCommandToMpvSocket(playPauseCommand);
    const result = this.getProperty("pause");
    if (result) {
      const isPaused = result.data;
      this.emit("play-state-changed", isPaused);
    }
  }
  getProperty(prop) {
    if (this._process) {
      const command = this.createCommand({ command: ["get_property", prop] });
      const output = this.sendCommandToMpvSocket(command);
      return JSON.parse(output) ?? null;
    }
  }
  startPlayer(radio) {
    this.stopPlayer();
    try {
      const [, argv] = GLib.shell_parse_argv(
        `mpv --volume=${this._settings.get_int("volume")} --demuxer-lavf-o=extension_picky=0 --input-ipc-server=/tmp/quicklofi-socket --loop-playlist=force --no-video --ytdl-format='best*[vcodec=none]' --ytdl-raw-options-add='force-ipv4=' ${radio.radioUrl}`
      );
      this._process = Gio2.Subprocess.new(argv, Gio2.SubprocessFlags.NONE);
    } catch (e) {
      this._process = null;
      main_exports.notifyError(
        "MPV not found",
        "Did you have mpv installed?\nhttps://github.com/EuCaue/gnome-shell-extension-quick-lofi?tab=readme-ov-file#dependencies"
      );
    }
  }
  createCommand(command) {
    return JSON.stringify(command) + "\n";
  }
  sendCommandToMpvSocket(mpvCommand) {
    let response = null;
    if (this._isCommandRunning) {
      return null;
    }
    this._isCommandRunning = true;
    try {
      const address = Gio2.UnixSocketAddress.new(this._mpvSocket);
      const client = new Gio2.SocketClient();
      const connection = client.connect(address, null);
      const outputStream = connection.get_output_stream();
      const inputStream = connection.get_input_stream();
      const command = mpvCommand;
      const byteArray = new TextEncoder().encode(command);
      outputStream.write(byteArray, null);
      outputStream.flush(null);
      const dataInputStream = new Gio2.DataInputStream({ base_stream: inputStream });
      const [res] = dataInputStream.read_line_utf8(null);
      response = res;
      outputStream.close(null);
      inputStream.close(null);
      connection.close(null);
    } catch (e) {
      main_exports.notifyError("Error while connecting to the MPV SOCKET", e.message);
    }
    this._isCommandRunning = false;
    return response;
  }
};
GObject.registerClass(
  {
    Signals: {
      "play-state-changed": { param_types: [GObject.TYPE_BOOLEAN] },
      "playback-stopped": { param_types: [] }
    }
  },
  _Player
);
var Player = _Player;

// src/Indicator.ts
import Gio3 from "gi://Gio";
import St from "gi://St";
import GObject2 from "gi://GObject";
var _Indicator = class _Indicator extends panelMenu_exports.Button {
  mpvPlayer;
  _activeRadioPopupItem = null;
  _radios;
  _icon;
  _extension;
  constructor(ext) {
    super(0, "Quick Lofi");
    this._extension = ext;
    this.mpvPlayer = new Player(this._extension._settings);
    this.mpvPlayer.initVolumeControl();
    this._icon = new St.Icon({
      gicon: Gio3.icon_new_for_string(this._extension.path + Utils.ICONS.INDICATOR_DEFAULT),
      iconSize: 20,
      styleClass: "system-status-icon indicator-icon"
    });
    this.add_child(this._icon);
    this._createMenu();
    this._bindSettingsChangeEvents();
    this._handleButtonClick();
  }
  _createRadios() {
    const radios = this._extension._settings.get_strv("radios");
    radios.forEach((entry) => {
      const [radioName, radioUrl, id] = entry.split(" - ");
      this._radios.push({ radioName, radioUrl, id });
    });
  }
  _handlePopupMaxHeight() {
    const isPopupMaxHeightSet = this._extension._settings.get_boolean("set-popup-max-height");
    const popupMaxHeight = this._extension._settings.get_string("popup-max-height");
    const styleString = isPopupMaxHeightSet ? popupMaxHeight : "auto";
    this.menu.box.style = `
        max-height: ${styleString};
      `;
  }
  _bindSettingsChangeEvents() {
    this._extension._settings.connect("changed", (_, key) => {
      if (key === "radios") {
        this._createMenu();
      }
    });
    this._extension._settings.connect("changed::set-popup-max-height", () => {
      this._handlePopupMaxHeight();
    });
    this._extension._settings.connect("changed::popup-max-height", () => {
      this._handlePopupMaxHeight();
    });
    this.mpvPlayer.connect("play-state-changed", (sender, isPaused) => {
      this._activeRadioPopupItem.setIcon(
        Gio3.icon_new_for_string(isPaused ? Utils.ICONS.POPUP_PAUSE : Utils.ICONS.POPUP_STOP)
      );
      this._updateIndicatorIcon({ playing: isPaused ? "paused" : "playing" });
    });
    this.mpvPlayer.connect("playback-stopped", () => {
      this._updateIndicatorIcon({ playing: "default" });
      this._activeRadioPopupItem.setIcon(Gio3.icon_new_for_string(Utils.ICONS.POPUP_PLAY));
      this._extension._settings.set_string("current-radio-playing", "");
      this._activeRadioPopupItem.set_style("font-weight: normal");
      this._activeRadioPopupItem = null;
    });
  }
  _updateIndicatorIcon({ playing }) {
    const extPath = this._extension.path;
    const icon = `INDICATOR_${playing.toUpperCase()}`;
    const iconPath = `${extPath}/${Utils.ICONS[icon]}`;
    const gicon = Gio3.icon_new_for_string(iconPath);
    this._icon.set_gicon(gicon);
  }
  _togglePlayingStatus(child, radioID, mouseButton) {
    const isRightClickOnActiveRadio = child === this._activeRadioPopupItem && mouseButton === 3;
    const isLeftClickOnActiveRadio = child === this._activeRadioPopupItem && mouseButton === 1;
    if (isRightClickOnActiveRadio) {
      this.mpvPlayer.stopPlayer();
      this._updateIndicatorIcon({ playing: "default" });
      this._activeRadioPopupItem.setIcon(Gio3.icon_new_for_string(Utils.ICONS.POPUP_PLAY));
      this._extension._settings.set_string("current-radio-playing", "");
      this._activeRadioPopupItem.set_style("font-weight: normal");
      this._activeRadioPopupItem = null;
      return;
    }
    if (isLeftClickOnActiveRadio) {
      const currentState = this._activeRadioPopupItem.get_child_at_index(0).icon_name;
      const isPlaying = currentState === Utils.ICONS.POPUP_STOP;
      this._activeRadioPopupItem.setIcon(
        Gio3.icon_new_for_string(isPlaying ? Utils.ICONS.POPUP_PAUSE : Utils.ICONS.POPUP_STOP)
      );
      this._updateIndicatorIcon({ playing: isPlaying ? "paused" : "playing" });
      this.mpvPlayer.playPause();
      return;
    }
    const currentRadio = this._radios.find((radio) => radio.id === radioID);
    if (this._activeRadioPopupItem) {
      this._activeRadioPopupItem.setIcon(Gio3.icon_new_for_string(Utils.ICONS.POPUP_PLAY));
      this._activeRadioPopupItem.set_style("font-weight: normal");
      this._updateIndicatorIcon({ playing: "default" });
    }
    this.mpvPlayer.startPlayer(currentRadio);
    this._updateIndicatorIcon({ playing: "playing" });
    child.setIcon(Gio3.icon_new_for_string(Utils.ICONS.POPUP_STOP));
    child.set_style("font-weight: bold");
    this._extension._settings.set_string("current-radio-playing", radioID);
    this._activeRadioPopupItem = child;
  }
  _handleButtonClick() {
    this.connect("button-press-event", (_, event) => {
      const RIGHT_CLICK = 3;
      if (event.get_button() === RIGHT_CLICK) {
        this.menu.close(false);
        this._extension.openPreferences();
        return;
      }
    });
  }
  _createMenu() {
    this._activeRadioPopupItem = null;
    this.menu.box.destroy_all_children();
    this._radios = [];
    this._createRadios();
    this._createMenuItems();
  }
  _createVolumeSlider(popup) {
    const separator = new popupMenu_exports.PopupSeparatorMenuItem();
    const volumeLevel = this._extension._settings.get_int("volume");
    const volumePopupItem = new popupMenu_exports.PopupBaseMenuItem({ reactive: false });
    const volumeBoxLayout = new St.BoxLayout({ vertical: true, x_expand: true });
    const volumeSlider = new slider_exports.Slider(volumeLevel / 100);
    volumeSlider.connect("notify::value", (slider) => {
      const currentVolume = (slider.value * 100).toFixed(0);
      volumeLabel.text = `Volume: ${currentVolume}`;
      this._extension._settings.set_int("volume", Number(currentVolume));
    });
    const volumeLabel = new St.Label({ text: `Volume: ${volumeSlider.value * 100}` });
    volumeBoxLayout.add_child(volumeLabel);
    volumeBoxLayout.add_child(volumeSlider);
    volumePopupItem.add_child(volumeBoxLayout);
    popup.addMenuItem(separator);
    popup.addMenuItem(volumePopupItem);
  }
  _createMenuItems() {
    const scrollView = new St.ScrollView();
    const popupSection = new popupMenu_exports.PopupMenuSection();
    scrollView.add_child(popupSection.actor);
    const isPaused = this.mpvPlayer.getProperty("pause");
    this._radios.forEach((radio) => {
      const isRadioPlaying = Utils.isCurrentRadioPlaying(this._extension._settings, radio.id);
      const menuItem = new popupMenu_exports.PopupImageMenuItem(
        radio.radioName,
        Gio3.icon_new_for_string(
          isRadioPlaying && isPaused.data ? Utils.ICONS.POPUP_PAUSE : isRadioPlaying ? Utils.ICONS.POPUP_STOP : Utils.ICONS.POPUP_PLAY
        )
      );
      if (isRadioPlaying) {
        menuItem.set_style("font-weight: bold");
        this._activeRadioPopupItem = menuItem;
      }
      menuItem.connect("activate", (item, event) => {
        const mouseButton = event.get_button();
        this._togglePlayingStatus(item, radio.id, mouseButton);
      });
      popupSection.addMenuItem(menuItem);
    });
    this._createVolumeSlider(popupSection);
    this.menu.box.add_child(scrollView);
    this._handlePopupMaxHeight();
  }
  dispose() {
    Utils.debug("extension disabled");
    this._extension._settings.set_string("current-radio-playing", "");
    this.mpvPlayer.stopPlayer();
    this.destroy();
  }
};
GObject2.registerClass(_Indicator);
var Indicator = _Indicator;

// src/ShortcutsHandler.ts
import Meta from "gi://Meta";
import Shell from "gi://Shell";
var ShortcutsHandler = class {
  constructor(_settings, _player) {
    this._settings = _settings;
    this._player = _player;
    this.handleShortcuts();
  }
  handleShortcuts() {
    main_exports.wm.addKeybinding(
      Utils.SHORTCUTS.PLAY_PAUSE_SHORTCUT,
      this._settings,
      Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
      Shell.ActionMode.NORMAL,
      () => {
        this._player.playPause();
      }
    );
    main_exports.wm.addKeybinding(
      Utils.SHORTCUTS.STOP_SHORTCUT,
      this._settings,
      Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
      Shell.ActionMode.NORMAL,
      () => {
        this._player.stopPlayer();
      }
    );
  }
  _removeShortcuts() {
    Object.values(Utils.SHORTCUTS).forEach((key) => {
      main_exports.wm.removeKeybinding(key);
    });
  }
  destroy() {
    this._removeShortcuts();
  }
};

// src/extension.ts
var QuickLofi = class extends extension_exports.Extension {
  _indicator = null;
  _settings = null;
  _shortcutsHandler = null;
  constructor(props) {
    super(props);
  }
  _migrateRadios() {
    const radios = this._settings.get_strv("radios");
    const updatedRadios = radios.map((radio) => {
      if (radio.split(" - ").length === 3) {
        return radio;
      }
      if (radio.includes(" - ")) {
        const [name, url] = radio.split(" - ");
        const id = Utils.generateNanoIdWithSymbols(10);
        return `${name} - ${url} - ${id}`;
      }
    });
    if (JSON.stringify(radios) === JSON.stringify(updatedRadios))
      return;
    this._settings.set_strv("radios", updatedRadios);
  }
  enable() {
    Utils.debug("extension enabled");
    this._settings = this.getSettings();
    this._settings.set_string("current-radio-playing", "");
    this._migrateRadios();
    this._indicator = new Indicator(this);
    this._shortcutsHandler = new ShortcutsHandler(this._settings, this._indicator.mpvPlayer);
    main_exports.panel.addToStatusArea(this.uuid, this._indicator);
  }
  disable() {
    this._indicator.dispose();
    this._indicator = null;
    this._settings = null;
    this._shortcutsHandler.destroy();
    this._shortcutsHandler = null;
  }
};
export {
  QuickLofi as default
};
