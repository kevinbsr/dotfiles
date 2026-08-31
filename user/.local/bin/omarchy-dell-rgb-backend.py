#!/usr/bin/python3
import sys
import usb.core
import usb.util

# ELC Constants
ELC_QUERY = 0x20
USER_ANIMATION = 0x21
START_SERIES = 0x23
ADD_ACTION = 0x24
SET_COLOR = 0x27
DIMMING = 0x26
START_NEW = 0x01
FINISH_SAVE = 0x02
SET_DEFAULT = 0x06
AC_CHARGING = 0x5d
AC_CHARGED = 0x5c
DC_ON = 0x5f
COLOR = 0x00

VID = 0x187C
PID = 0x0550 # G15 5515

def build_report(fragment):
    report = bytearray.fromhex("03" + fragment)
    report += bytearray(33 - len(report))
    return report

def send_report(dev, fragment):
    report = build_report(fragment)
    dev.ctrl_transfer(0x21, 9, 0x200, 0, report)

def set_static(dev, r, g, b):
    zones = [0, 1, 2, 3]
    zonestring = "".join(format(x, '02x') for x in zones)
    
    # Simple set color command (Direct)
    # fragment = format(SET_COLOR, '02x') + format(r, '02x') + format(g, '02x') + format(b, '02x') + format(len(zones), '04x') + zonestring
    # send_report(dev, fragment)

    # Formal Animation set (as in awelc.py)
    for anim in [AC_CHARGING, AC_CHARGED, DC_ON]:
        # Start new
        send_report(dev, format(USER_ANIMATION, '02x') + format(START_NEW, '04x') + format(anim, "04x"))
        # Start series
        send_report(dev, format(START_SERIES, '02x') + format(0x01, "02x") + format(len(zones), "04x") + zonestring)
        # Add action (Static color)
        # Action fragment: effect(1) duration(2) tempo(2) R(1) G(1) B(1) = 7 bytes
        # Duration max: ffff, Tempo min: 01
        action = format(COLOR, '02x') + "ffff" + "01" + format(r, '02x') + format(g, '02x') + format(b, '02x')
        send_report(dev, format(ADD_ACTION, '02x') + action)
        # Finish save
        send_report(dev, format(USER_ANIMATION, '02x') + format(FINISH_SAVE, '04x') + format(anim, "04x"))
        # Set default
        send_report(dev, format(USER_ANIMATION, '02x') + format(SET_DEFAULT, '04x') + format(anim, "04x"))

def main():
    if len(sys.argv) < 4:
        return
    
    r, g, b = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
    
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if not dev:
        # Try 0551 as well
        dev = usb.core.find(idVendor=VID, idProduct=0x0551)
        
    if not dev:
        print("Device not found")
        sys.exit(1)

    try:
        if dev.is_kernel_driver_active(0):
            dev.detach_kernel_driver(0)
    except:
        pass

    try:
        set_static(dev, r, g, b)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
