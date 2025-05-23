import GObject from 'gi://GObject';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import {QuickToggle, SystemIndicator} from 'resource:///org/gnome/shell/ui/quickSettings.js';

// Constants
const SHOW_INDICATOR = false;
const APP_FOLDER_SCHEMA_ID = 'org.gnome.desktop.app-folders';
const APP_FOLDER_SCHEMA_PATH = '/org/gnome/desktop/app-folders/folders/';

// Folder configurations
const FOLDER_CONFIGS = {
    'accessories': {name: 'Accessories', categories: ['Utility']},
    'chrome-apps': {name: 'Chrome Apps', categories: ['chrome-apps']},
    'games': {name: 'Games', categories: ['Game']},
    'graphics': {name: 'Graphics', categories: ['Graphics']},
    'internet': {name: 'Internet', categories: ['Network', 'WebBrowser', 'Email']},
    'office': {name: 'Office', categories: ['Office']},
    'programming': {name: 'Programming', categories: ['Development']},
    'science': {name: 'Science', categories: ['Science']},
    'sound---video': {name: 'Sound & Video', categories: ['AudioVideo', 'Audio', 'Video']},
    'system-tools': {name: 'System Tools', categories: ['System', 'Settings']},
    'universal-access': {name: 'Universal Access', categories: ['Accessibility']},
    'wine': {name: 'Wine', categories: ['Wine', 'X-Wine', 'Wine-Programs-Accessories']},
    'waydroid': {name: 'Waydroid', categories: ['Waydroid', 'X-WayDroid-App']}
};

class AppFolderManager {
    constructor() {
        this._folderSettings = new Gio.Settings({schema_id: APP_FOLDER_SCHEMA_ID});
    }

    setupFolders() {
        this._folderSettings.set_strv('folder-children', Object.keys(FOLDER_CONFIGS));

        for (const [folderId, config] of Object.entries(FOLDER_CONFIGS)) {
            const folderPath = `${APP_FOLDER_SCHEMA_PATH}${folderId}/`;
            const folderSchema = Gio.Settings.new_with_path('org.gnome.desktop.app-folders.folder', folderPath);

            folderSchema.set_string('name', config.name);
            folderSchema.set_strv('categories', config.categories);
        }
    }

    clearFolders() {
        console.log('App-Grid-Wizard: Clearing folders...');
        try {
            this._folderSettings.set_strv('folder-children', []);
            Gio.Settings.sync();
            this._refreshAppDisplay();
            console.log('App-Grid-Wizard: Folders cleared');
        } catch (error) {
            console.error(error, 'App-Grid-Wizard: Error clearing folders');
        }
    }

    _refreshAppDisplay() {
        const appDisplay = Main.overview.viewSelector?._appDisplay || Main.overview.viewSelector?.appDisplay;
        appDisplay?._redisplay();
    }
}

const WizardToggle = GObject.registerClass(
class WizardToggle extends QuickToggle {
    _init() {
        super._init({
            title: 'App Grid Wizard',
            iconName: 'view-grid-symbolic',
            toggleMode: true,
        });

        this._folderManager = new AppFolderManager();
        this._monitorId = null;

        // Restore the toggle state based on existing folders
        this.checked = this._folderManager._folderSettings.get_strv('folder-children').length > 0;
        this.connect('clicked', this._onClicked.bind(this));

        // Start monitoring if the toggle is already checked
        if (this.checked) {
            this._startMonitoring();
        }
    }

    _onClicked() {
        if (this.checked) {
            this._folderManager.setupFolders();
            this._startMonitoring();
        } else {
            this._folderManager.clearFolders();
            this._stopMonitoring();
        }
    }

    _startMonitoring() {
        console.log('App-Grid-Wizard: Started monitoring for app changes');

        if (this._monitorId) return;

        const appSystem = Shell.AppSystem.get_default();
        this._monitorId = appSystem.connect('installed-changed', () => {
            console.log('App-Grid-Wizard: Detected app installation/removal');
            GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, () => {
                this._folderManager.setupFolders();
                return GLib.SOURCE_REMOVE;
            });
        });
    }

    _stopMonitoring() {
        if (this._monitorId) {
            Shell.AppSystem.get_default().disconnect(this._monitorId);
            this._monitorId = null;
            console.log('App-Grid-Wizard: Stopped monitoring');
        }
    }

    destroy() {
        this._stopMonitoring();
        super.destroy();
    }
});

const WizardIndicator = GObject.registerClass(
class WizardIndicator extends SystemIndicator {
    _init() {
        super._init();

        const toggle = new WizardToggle();
        
        if (SHOW_INDICATOR) {
            this._indicator = this._addIndicator();
            this._indicator.iconName = 'view-grid-symbolic';

            toggle.bind_property('checked', this._indicator, 'visible', GObject.BindingFlags.SYNC_CREATE);
        }

        this.quickSettingsItems.push(toggle);
    }
});

export default class WizardManagerExtension extends Extension {
    enable() {
        this._indicator = new WizardIndicator();
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        this._indicator.quickSettingsItems.forEach(item => item.destroy());
        this._indicator.destroy();
	this._indicator = null;
    }
}
