#!/usr/bin/env python3
import time
import os
import glob
import subprocess
import threading
from collections import deque
import evdev, select

ACPI_PATH = "/proc/acpi/call"
WMAX_PATH = "\\_SB.AMW3.WMAX"
INTERVAL = 1
AC_ONLINE_PATH = "/sys/class/power_supply/ACAD/online"
GMODE_FILE = "/run/g15-fan-control/gmode_override"
GMODE_DEBOUNCE_SECONDS = 2.0

# Override pelo pico bruto, COM histerese: entra em 86 C, so sai em 80 C.
# Sem histerese isto era avaliado 1x/s contra um sensor da EC que oscila ~6 C
# entre leituras consecutivas, e a EC ficava alternando entre G-Mode e modo
# normal a cada segundo em volta do limiar.
RAW_OVERRIDE_ON = 86
RAW_OVERRIDE_OFF = 80

LEVELS = [
    (88, 83, 0xff), # Level 7: 100% - Critical (G-Mode)
    (81, 75, 0xb0), # Level 6: ~69% - Heavy Load
    (74, 68, 0x80), # Level 5: 50%  - Active Usage
    (67, 61, 0x50), # Level 4: ~31% - Warmer
    (60, 54, 0x2e), # Level 3: ~18% - Transition
    (53, 47, 0x18), # Level 2: ~9%  - Light Work
    (45, 39, 0x0d), # Level 1: ~5%  - Proactive
    (0,  0,  0x00), # Level 0: 0%   - Cold
]

def acpi_call(cmd):
    try:
        with open(ACPI_PATH, "w") as f:
            f.write(cmd)
        with open(ACPI_PATH, "r") as f:
            res = f.read().strip("\x00")
        return res
    except Exception:
        return None

def set_mode(gmode=False):
    if gmode:
        acpi_call(f"{WMAX_PATH} 0 0x15 {{0x01, 0xab, 0x00, 0x00}}")
    else:
        acpi_call(f"{WMAX_PATH} 0 0x15 {{0x01, 0x00, 0x00, 0x00}}")

def set_fan_boost(fan_id, level):
    acpi_call(f"{WMAX_PATH} 0 0x15 {{0x02, {fan_id}, {hex(level)}, 0x00}}")

def write_sysfs_boost(level):
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        name_file = os.path.join(h, "name")
        if os.path.exists(name_file):
            try:
                with open(name_file) as f:
                    if "alienware_wmi" in f.read():
                        for fan_node in ("fan1_boost", "fan2_boost"):
                            p = os.path.join(h, fan_node)
                            if os.path.exists(p):
                                with open(p, "w") as fw:
                                    fw.write(str(level))
            except Exception:
                pass

def uptime():
    return time.clock_gettime(time.CLOCK_BOOTTIME)

def read_ac_online():
    try:
        with open(AC_ONLINE_PATH) as f:
            return f.read().strip()
    except Exception:
        return None

def read_gmode_override():
    if os.path.exists(GMODE_FILE):
        try:
            with open(GMODE_FILE) as f:
                return f.read().strip() == "1"
        except Exception:
            pass
    return False

def write_gmode_override(is_on):
    try:
        with open(GMODE_FILE, "w") as f:
            f.write("1" if is_on else "0")
    except Exception:
        pass

def send_notification(is_on):
    try:
        title = "G-Mode ATIVADO" if is_on else "G-Mode DESATIVADO"
        body = "Perfil de Alta Performance & Ventoinhas a 100%" if is_on else "Perfil Equilibrado e Controle Automático de Ventoinhas"
        icon = "applications-games-symbolic" if is_on else "power-profile-balanced-symbolic"
        target_profile = "performance" if is_on else "balanced"
        
        subprocess.run(["powerprofilesctl", "set", target_profile], check=False)
        cmd = f"sudo -u kevin DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send -u low -t 2000 -i {icon} \"{title}\" \"{body}\""
        subprocess.run(cmd, shell=True, check=False)
    except Exception as e:
        print("Notification error:", e)

def toggle_gmode():
    current = read_gmode_override()
    new_state = not current
    write_gmode_override(new_state)
    send_notification(new_state)
    print(f"[HARDWARE KEY] G-Mode Toggled -> {new_state}")

def listen_keyboard_events():
    def worker():
        target_devs = []
        for dev_path in glob.glob("/dev/input/event*"):
            try:
                dev = evdev.InputDevice(dev_path)
                if "Dell" in dev.name or "AT Translated" in dev.name:
                    target_devs.append(dev)
            except Exception:
                pass
        
        if not target_devs:
            print("No Dell keyboard devices found for hardware listening.")
            return

        print(f"G-Key Listener attached to {[d.name for d in target_devs]}")
        # Keycodes for G-Mode on Dell G15 laptops:
        # 701: KEY_PERFORMANCE (current kernel); remaining codes support older kernels.
        G_CODES = {148, 187, 194, 202, 240, 248, 701}
        last_gmode_press = 0.0

        while True:
            try:
                r, w, x = select.select(target_devs, [], [], 1.0)
                for dev in r:
                    for ev in dev.read():
                        if ev.type == evdev.ecodes.EV_KEY and ev.value == 1:
                            if ev.code in G_CODES:
                                now = time.monotonic()
                                if now - last_gmode_press < GMODE_DEBOUNCE_SECONDS:
                                    continue
                                last_gmode_press = now
                                print(f"Hardware G-Key pressed on {dev.name} (Code: {ev.code})!")
                                toggle_gmode()
            except Exception:
                time.sleep(1)

    t = threading.Thread(target=worker, daemon=True)
    t.start()

def get_cpu_temp():
    res = acpi_call(f"{WMAX_PATH} 0 0x14 {{0x04, 0x01, 0x00, 0x00}}")
    if res and res.startswith("0x"):
        return int(res, 16)
    return 0

def get_gpu_temp():
    res = acpi_call(f"{WMAX_PATH} 0 0x14 {{0x04, 0x06, 0x00, 0x00}}")
    if res and res.startswith("0x"):
        return int(res, 16)
    return 0

def main():
    print("Starting G15 High-Performance Fan Control Service with Direct Hardware G-Key Interception...")
    listen_keyboard_events()

    current_level_idx = len(LEVELS) - 1
    last_boost = -1
    last_ac = read_ac_online()
    last_gmode_state = None
    raw_override = False
    loop_start = uptime()

    # 7 amostras a INTERVAL=1s = janela de 7s. Filtra o ruido de ~6 C do
    # sensor da EC sem voltar aos 35s da versao de 2026-08-09, que atrasava
    # a subida em 25s+.
    temp_history = deque(maxlen=7)

    while True:
        gmode_override = read_gmode_override()

        cpu_temp = get_cpu_temp()
        gpu_temp = get_gpu_temp()
        raw_max = max(cpu_temp, gpu_temp)

        if raw_max > 0:
            temp_history.append(raw_max)

        avg_temp = sum(temp_history) / len(temp_history) if temp_history else raw_max

        if raw_max >= RAW_OVERRIDE_ON:
            raw_override = True
        elif raw_max < RAW_OVERRIDE_OFF:
            raw_override = False

        if gmode_override:
            new_level_idx = 0
            boost = 0xff
        elif raw_override:
            new_level_idx = 0
            boost = 0xff
        else:
            new_level_idx = current_level_idx
            for i in range(current_level_idx):
                if avg_temp >= LEVELS[i][0]:
                    new_level_idx = i
                    break

            if avg_temp < LEVELS[current_level_idx][1]:
                for i in range(current_level_idx + 1, len(LEVELS)):
                    if avg_temp >= LEVELS[i][0] or i == len(LEVELS) - 1:
                        new_level_idx = i
                        break
            boost = LEVELS[new_level_idx][2]

        now = uptime()
        ac_now = read_ac_online()
        slept = now - loop_start

        # Reaplicar SO em evento real. Reemitir os comandos com o nivel
        # inalterado faz a EC reiniciar a rampa e a ventoinha pulsa: medido
        # oscilando 0 <-> 2200 RPM com Tctl travado em 45 C, em ciclos de ~15s
        # -- exatamente o heartbeat "now - last_apply_time >= 15" que estava
        # aqui. O "or boost == 0xff" era pior: reaplicava 1x/s sob carga.
        # A versao de 2026-08-09 ja documentava este bug; a reescrita de
        # 2026-08-18 o reintroduziu. Nao voltar a reaplicar por tempo.
        resumed = slept > 10  # so suspend/resume: o ciclo normal e de 1s

        if boost != last_boost or gmode_override != last_gmode_state or ac_now != last_ac or resumed:
            if boost != last_boost or gmode_override != last_gmode_state:
                print(f"GModeOverride: {gmode_override} | Raw: {raw_max}C | Avg: {avg_temp:.1f}C -> Level {len(LEVELS)-1-new_level_idx} (Boost: {hex(boost)})")

            gmode_active = (gmode_override or boost == 0xff)
            set_mode(gmode=gmode_active)
            set_fan_boost(0x32, boost)
            set_fan_boost(0x33, boost)
            write_sysfs_boost(boost)

            last_boost = boost
            last_ac = ac_now
            last_gmode_state = gmode_override
            current_level_idx = new_level_idx

        loop_start = uptime()
        time.sleep(INTERVAL)

if __name__ == "__main__":
    if not os.path.exists(ACPI_PATH):
        print(f"Error: {ACPI_PATH} not found.")
        exit(1)
    main()
