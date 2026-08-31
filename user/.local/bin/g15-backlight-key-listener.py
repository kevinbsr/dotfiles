#!/usr/bin/env python3

"""Handle the Dell G15 keyboard-backlight hotkey outside the compositor."""

import glob
import os
import select
import subprocess
import time

from evdev import InputDevice, ecodes


HOTKEY_CODE = ecodes.KEY_F18
DEBOUNCE_SECONDS = 0.25
BRIGHTNESS_COMMAND = [
    os.path.expanduser("~/.local/bin/omarchy-brightness-keyboard-dell-g15"),
    "cycle",
]


def find_hotkey_devices():
    devices = []
    for path in sorted(glob.glob("/dev/input/event*")):
        try:
            device = InputDevice(path)
            key_codes = device.capabilities().get(ecodes.EV_KEY, [])
            if HOTKEY_CODE in key_codes:
                devices.append(device)
            else:
                device.close()
        except (OSError, PermissionError):
            continue
    return devices


def close_devices(devices):
    for device in devices:
        try:
            device.close()
        except OSError:
            pass


def main():
    last_press = 0.0

    while True:
        devices = find_hotkey_devices()
        if not devices:
            print("No input device exposing KEY_F18; retrying", flush=True)
            time.sleep(3)
            continue

        print(
            "Listening for KEY_F18 on "
            + ", ".join(f"{device.path} ({device.name})" for device in devices),
            flush=True,
        )

        try:
            while True:
                readable, _, _ = select.select(devices, [], [], 5)
                for device in readable:
                    for event in device.read():
                        if (
                            event.type == ecodes.EV_KEY
                            and event.code == HOTKEY_CODE
                            and event.value == 1
                        ):
                            now = time.monotonic()
                            if now - last_press < DEBOUNCE_SECONDS:
                                continue
                            last_press = now
                            result = subprocess.run(BRIGHTNESS_COMMAND, check=False)
                            print(
                                f"KEY_F18 pressed; brightness command exited {result.returncode}",
                                flush=True,
                            )
        except (OSError, ValueError) as error:
            print(f"Input device changed ({error}); rescanning", flush=True)
        finally:
            close_devices(devices)


if __name__ == "__main__":
    main()
