#!/usr/bin/env python3
import time
import os

# ACPI Paths and Commands for Dell G15 5515
ACPI_PATH = "/proc/acpi/call"
WMAX_PATH = "\\_SB.AMW3.WMAX"

# Granular Thresholds with Hysteresis for Smooth Transitions
# Format: (up_threshold, down_threshold, boost_value)
LEVELS = [
    (85, 80, 0xff), # Level 7: 100% - Extreme
    (75, 70, 0xcc), # Level 6: ~80%  - Very Heavy
    (65, 60, 0xa6), # Level 5: ~65%  - Heavy Load
    (55, 50, 0x80), # Level 4: 50%   - Active Usage
    (50, 45, 0x59), # Level 3: ~35%  - Moderate (Smooth Transition)
    (45, 40, 0x40), # Level 2: 25%   - Light Usage
    (40, 35, 0x26), # Level 1: ~15%  - Proactive (Near-silent)
    (0,  0,  0x00), # Level 0: 0%    - Silence
]

def acpi_call(cmd):
    try:
        with open(ACPI_PATH, "w") as f:
            f.write(cmd)
        with open(ACPI_PATH, "r") as f:
            res = f.read().strip('\x00')
        return res
    except Exception:
        return None

def set_manual_mode():
    acpi_call(f"{WMAX_PATH} 0 0x15 {{0x01, 0x00, 0x00, 0x00}}")

def set_fan_boost(fan_id, level):
    acpi_call(f"{WMAX_PATH} 0 0x15 {{0x02, {fan_id}, {hex(level)}, 0x00}}")

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
    print("Starting G15 Granular & Smooth Fan Control...")
    current_level_idx = len(LEVELS) - 1
    last_boost = LEVELS[current_level_idx][2]
    
    while True:
        cpu_temp = get_cpu_temp()
        gpu_temp = get_gpu_temp()
        max_temp = max(cpu_temp, gpu_temp)
        
        new_level_idx = current_level_idx
        
        # Check if we should go UP
        for i in range(current_level_idx):
            if max_temp >= LEVELS[i][0]:
                new_level_idx = i
                break
        
        # Check if we should go DOWN
        if max_temp < LEVELS[current_level_idx][1]:
            for i in range(current_level_idx + 1, len(LEVELS)):
                if max_temp >= LEVELS[i][0] or i == len(LEVELS) - 1:
                    new_level_idx = i
                    break

        boost = LEVELS[new_level_idx][2]
            
        if boost != last_boost:
            print(f"Temp: {max_temp}C -> Level {len(LEVELS)-1-new_level_idx} (Boost: {hex(boost)})")
            set_manual_mode()
            set_fan_boost(0x32, boost)
            set_fan_boost(0x33, boost)
            last_boost = boost
            current_level_idx = new_level_idx
            
        time.sleep(5)

if __name__ == "__main__":
    if not os.path.exists(ACPI_PATH):
        print(f"Error: {ACPI_PATH} not found.")
        exit(1)
    main()
