#!/usr/bin/env python3
"""Read and write MX Master settings for the Omarchy bar plugin.

Reads go through the logitech_receiver library so one HID++ session returns
battery and every setting at once. Writes shell out to `solaar config`, which
owns the persistence path (device write + ~/.config/solaar/config.yaml) that
reapplies settings when the mouse reconnects.
"""

import argparse
import contextlib
import io
import json
import os
import subprocess
import sys
import time

CACHE = os.path.expanduser("~/.cache/omarchy-mxmaster.json")

# Settings the panel exposes, in display order.
EXPOSED = [
    "dpi",
    "smart-shift",
    "scroll-ratchet",
    "hires-smooth-invert",
    "hires-smooth-resolution",
    "thumb-scroll-invert",
    "change-host",
]

# Only mice are interesting here; matched against the HID++ device name.
NAME_HINTS = ("MX Master", "MX Anywhere", "MX Vertical")


def _candidates():
    """Yield every reachable HID++ device.

    Covers both connection styles: `receivers_and_devices` reports Unifying/Bolt
    receivers (whose paired devices are reached by iterating the receiver) and
    devices attached directly over Bluetooth or a USB cable, which have no
    receiver to walk.
    """
    from logitech_receiver import base
    from logitech_receiver import device as device_mod
    from logitech_receiver import receiver as receiver_mod

    for dev_info in base.receivers_and_devices():
        try:
            if getattr(dev_info, "isDevice", False):
                dev = device_mod.create_device(base, dev_info)
                if dev is not None:
                    yield dev
                continue
            rcv = receiver_mod.create_receiver(base, dev_info)
            if rcv is None:
                continue
            for dev in rcv:
                if dev is not None:
                    yield dev
        except Exception:
            continue


def _find_device():
    """Return the best connected Logitech mouse, or None.

    Solaar's import chatter and receiver probe errors go to stdout, which would
    corrupt our JSON, so everything up to the return is captured.
    """
    fallback = None
    for dev in _candidates():
        try:
            # ping() answers False (not None) for a paired-but-asleep device;
            # treating that as present would report a connected mouse whose
            # settings all read back empty.
            if not dev.ping():
                continue
        except Exception:
            continue
        name = dev.name or ""
        if any(hint in name for hint in NAME_HINTS):
            return dev
        # Keep any other mouse in reserve so a non-MX model still works, but
        # let a named MX win even if it enumerates later.
        if fallback is None and str(dev.kind) == "mouse":
            fallback = dev
    return fallback


def _choice_index(choices, value):
    """Locate value among choices, matching either the name or the raw int."""
    for i, choice in enumerate(choices):
        if str(choice) == str(value):
            return i
    try:
        target = int(value)
    except (TypeError, ValueError):
        return -1
    for i, choice in enumerate(choices):
        try:
            if int(choice) == target:
                return i
        except (TypeError, ValueError):
            continue
    return -1


def _setting_payload(setting):
    """Describe one setting as {value, plus range or choices} for the QML side."""
    from logitech_receiver import settings as settings_mod

    try:
        value = setting.read()
    except Exception:
        return None
    if value is None:
        return None

    out = {}
    kind = setting.kind

    if kind == settings_mod.Kind.CHOICE:
        choices = [str(c) for c in (setting.choices or [])]
        out["value"] = str(value)
        # DPI has 157 choices; send bounds instead of the whole list.
        if setting.name == "dpi":
            ints = [int(c) for c in choices if str(c).isdigit()]
            out["value"] = int(value)
            out["min"] = min(ints) if ints else 200
            out["max"] = max(ints) if ints else 8000
            out["step"] = (ints[1] - ints[0]) if len(ints) > 1 else 50
        else:
            # Some settings read back as the raw int behind the choice
            # (scroll-ratchet -> 2) rather than its name, so match on both.
            out["choices"] = choices
            out["index"] = _choice_index(setting.choices or [], value)
            if out["index"] >= 0:
                out["value"] = choices[out["index"]]

    elif kind == settings_mod.Kind.RANGE:
        out["value"] = int(value)
        out["min"] = int(getattr(setting, "min_value", 1))
        out["max"] = int(getattr(setting, "max_value", 50))

    elif kind == settings_mod.Kind.TOGGLE:
        out["value"] = bool(value)

    else:
        out["value"] = str(value)

    return out


def _cli_selector(dev):
    """Identifier `solaar config` can match this device by.

    Solaar matches its argument against serial, codename, kind or a substring of
    the name — never the unit id. Over Bluetooth the serial comes back empty
    while the unit id is populated, so passing the unit id fails with "no online
    device found" even though the mouse is plainly connected.
    """
    for candidate in (dev.serial, dev.codename, dev.name):
        if candidate:
            return str(candidate)
    return str(dev.number)


def read_status():
    buf = io.StringIO()
    dev = None
    try:
        # Suppress library chatter so stdout carries JSON only.
        with contextlib.redirect_stdout(buf):
            dev = _find_device()
    except Exception as exc:
        return {"ok": False, "connected": False, "error": str(exc), "ts": int(time.time())}

    if dev is None:
        return {"ok": True, "connected": False, "ts": int(time.time())}

    status = {
        "ok": True,
        "connected": True,
        "name": dev.name,
        "id": dev.unitId or dev.serial or str(dev.number),
        "selector": _cli_selector(dev),
        "settings": {},
        "ts": int(time.time()),
    }

    with contextlib.redirect_stdout(buf):
        try:
            battery = dev.battery()
            if battery is not None:
                state = str(getattr(battery, "status", "")).split(".")[-1].lower()
                status["battery"] = {
                    "level": battery.level if isinstance(battery.level, int) else None,
                    "status": state,
                    "charging": "charg" in state and "dis" not in state,
                }
        except Exception:
            pass

        by_name = {s.name: s for s in dev.settings}
        for name in EXPOSED:
            setting = by_name.get(name)
            if setting is None:
                continue
            payload = _setting_payload(setting)
            if payload is not None:
                status["settings"][name] = payload

    return status


def write_cache(status):
    try:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        tmp = CACHE + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(status, fh)
        os.replace(tmp, CACHE)
    except Exception:
        pass


def read_cache():
    try:
        with open(CACHE) as fh:
            return json.load(fh)
    except Exception:
        return None


def _selector(cached):
    """Identifier for `solaar config`, preferring the cache to avoid a probe.

    Enumerating costs ~2s, and solaar re-enumerates internally anyway, so
    reusing the cached selector keeps a write down to a single probe.
    """
    if cached and cached.get("selector"):
        return cached["selector"]
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        dev = _find_device()
    if dev is None:
        return None
    return _cli_selector(dev)


def _run_config(selector, name, value):
    return subprocess.run(
        ["solaar", "config", selector, name, str(value)],
        capture_output=True,
        text=True,
        timeout=30,
    )


def apply_setting(name, value):
    """Delegate the write to `solaar config`, which also persists it."""
    if name not in EXPOSED:
        return {"ok": False, "error": f"unknown setting: {name}"}

    cached = read_cache()
    selector = _selector(cached)
    if selector is None:
        return {"ok": False, "connected": False, "error": "no device"}

    proc = _run_config(selector, name, value)
    if proc.returncode != 0:
        # The cached selector goes stale when the mouse moves between the
        # receiver and Bluetooth, so re-probe once before giving up. Bounded to
        # a single extra attempt — never recurse, or a permanently bad selector
        # would loop.
        fresh = _selector(None) if cached and cached.get("selector") else None
        if fresh and fresh != selector:
            selector = fresh
            proc = _run_config(selector, name, value)
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip().splitlines()
        return {"ok": False, "error": detail[-1] if detail else "solaar config failed"}

    # Patch the cache so the panel reflects the change without a full re-read.
    if cached and cached.get("settings", {}).get(name) is not None:
        entry = cached["settings"][name]
        if isinstance(entry.get("value"), bool):
            entry["value"] = str(value).lower() in ("true", "yes", "on", "1")
        elif isinstance(entry.get("value"), int):
            try:
                entry["value"] = int(value)
            except ValueError:
                entry["value"] = value
        else:
            entry["value"] = str(value)
            if entry.get("choices"):
                entry["index"] = _choice_index(entry["choices"], value)
        write_cache(cached)
        return {"ok": True, "status": cached}

    return {"ok": True}


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="action", required=True)

    sub.add_parser("status")
    sub.add_parser("cached")

    p_set = sub.add_parser("set")
    p_set.add_argument("name")
    p_set.add_argument("value")

    args = parser.parse_args()

    if args.action == "cached":
        cached = read_cache()
        print(json.dumps(cached if cached else {"ok": True, "connected": False, "stale": True}))
        return 0

    if args.action == "status":
        status = read_status()
        write_cache(status)
        print(json.dumps(status))
        return 0

    if args.action == "set":
        result = apply_setting(args.name, args.value)
        if not result.get("ok"):
            print(json.dumps(result))
            return 1
        status = result.get("status")
        if status is None:
            status = read_status()
            write_cache(status)
        print(json.dumps(status))
        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
