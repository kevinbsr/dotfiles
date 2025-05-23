import Gio from "gi://Gio";
import Gtk from "gi://Gtk";
export function createCheckboxInput(settings, id, label) {
    const check = new Gtk.CheckButton({
        label: label,
        visible: true,
    });
    settings.bind(id, check, "active", Gio.SettingsBindFlags.DEFAULT);
    return check;
}
