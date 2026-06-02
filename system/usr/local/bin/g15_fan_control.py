#!/usr/bin/env python3
import time
import os
from collections import deque

# ACPI Paths and Commands for Dell G15 5515
ACPI_PATH = "/proc/acpi/call"
WMAX_PATH = "\\_SB.AMW3.WMAX"

# Balanced & Silent Thresholds with Hysteresis
# Focus: Silence during light work, aggressive cooling only when needed
# Format: (up_threshold, down_threshold, boost_value)
LEVELS = [
    (85, 80, 0xff), # Level 7: 100% - Critical
    (75, 70, 0xcc), # Level 6: ~80%  - Heavy Load
    (65, 60, 0xa6), # Level 5: ~65%  - Active Usage
    (60, 55, 0x80), # Level 4: 50%   - Warmer
    (55, 50, 0x59), # Level 3: ~35%  - Transition
    (50, 45, 0x33), # Level 2: ~20%  - Light Work (Very Quiet)
    (40, 35, 0x1a), # Level 1: ~10%  - Proactive (Silent Airflow)
    (0,  0,  0x00), # Level 0: 0%    - Cold
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
    print("Starting G15 Ultra-Silent & Smooth Fan Control...")
    current_level_idx = len(LEVELS) - 1
    last_boost = -1
    
    # Store the last 10 readings (50 seconds of data at 5s interval)
    # A longer window prevents rapid changes from short spikes
    temp_history = deque(maxlen=10)
    
    while True:
        cpu_temp = get_cpu_temp()
        gpu_temp = get_gpu_temp()
        raw_max = max(cpu_temp, gpu_temp)
        
        if raw_max > 0:
            temp_history.append(raw_max)
        
        if not temp_history:
            time.sleep(5)
            continue
            
        # Average temperature to smooth out the curve
        avg_temp = sum(temp_history) / len(temp_history)
        
        new_level_idx = current_level_idx
        
        # UP logic
        for i in range(current_level_idx):
            if avg_temp >= LEVELS[i][0]:
                new_level_idx = i
                break
        
        # DOWN logic
        if avg_temp < LEVELS[current_level_idx][1]:
            for i in range(current_level_idx + 1, len(LEVELS)):
                if avg_temp >= LEVELS[i][0] or i == len(LEVELS) - 1:
                    new_level_idx = i
                    break

        boost = LEVELS[new_level_idx][2]
            
        if boost != last_boost:
            print(f"Raw: {raw_max}C | Avg: {avg_temp:.1f}C -> Level {len(LEVELS)-1-new_level_idx} (Boost: {hex(boost)})")
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
