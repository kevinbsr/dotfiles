#!/usr/bin/env python3
import time
import os
import subprocess

# ACPI Paths and Commands for Dell G15 5515
ACPI_PATH = "/proc/acpi/call"
WMAX_PATH = "\\_SB.AMW3.WMAX"

def acpi_call(cmd):
    try:
        with open(ACPI_PATH, "w") as f:
            f.write(cmd)
        with open(ACPI_PATH, "r") as f:
            res = f.read().strip('\x00')
        return res
    except Exception as e:
        return None

def set_manual_mode():
    # Set power mode to Manual (0x0)
    acpi_call(f"{WMAX_PATH} 0 0x15 {{0x01, 0x00, 0x00, 0x00}}")

def set_fan_boost(fan_id, level):
    # fan_id: 0x32 (CPU), 0x33 (GPU)
    # level: 0x00 - 0xff
    acpi_call(f"{WMAX_PATH} 0 0x15 {{0x02, {fan_id}, {hex(level)}, 0x00}}")

def get_cpu_temp():
    # Using ACPI for temperature as it's what the BIOS sees
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
    print("Starting G15 Automatic Fan Control...")
    last_boost = -1
    
    while True:
        cpu_temp = get_cpu_temp()
        gpu_temp = get_gpu_temp()
        max_temp = max(cpu_temp, gpu_temp)
        
        # Automatic curve logic
        if max_temp < 50:
            boost = 0x00
        elif max_temp < 60:
            boost = 0x40 # ~25%
        elif max_temp < 70:
            boost = 0x80 # ~50%
        elif max_temp < 80:
            boost = 0xc0 # ~75%
        else:
            boost = 0xff # 100%
            
        if boost != last_boost:
            print(f"Temp: {max_temp}C -> Setting Fan Boost to {hex(boost)}")
            set_manual_mode()
            set_fan_boost(0x32, boost) # CPU Fan
            set_fan_boost(0x33, boost) # GPU Fan
            last_boost = boost
            
        time.sleep(5)

if __name__ == "__main__":
    if not os.path.exists(ACPI_PATH):
        print(f"Error: {ACPI_PATH} not found. Is acpi_call module loaded?")
        exit(1)
    main()
