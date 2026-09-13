#!/bin/bash
# Bootstrap script of my workstation
# Author: Kevin Benevides

set -euo pipefail

# Finds from where the script is running to use absolute paths
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure that is running as root to modify the system
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] This script needs to be run as root. Use: sudo ./install.sh"
  exit 1
fi

# Identify the real user behind sudo
REAL_USER=${SUDO_USER:-$(logname)}
USER_HOME=$(eval echo "~$REAL_USER")
USER_UID=$(id -u "$REAL_USER")

# dependencies list
OFFICIAL_PACKAGES=(
  "gamemode"
  "lib32-gamemode"
  "jq"
  "power-profiles-daemon"
  "powertop"
  "stow"
)

AUR_PACKAGES=(
  "envycontrol"
  "ryzenadj-git"
)

echo "==> Initializing infrastructure provisioning from $REPO_DIR..."

# Resolving dependencies
echo "-> [DEPENDENCIES] Synchronizing official packages from Arch..."
pacman -S --needed --noconfirm "${OFFICIAL_PACKAGES[@]}"

echo "-> [DEPENDENCIES] Provisioning AUR packages..."
if command -v yay &> /dev/null; then
  # dropping privilegies to use yay
  sudo -u "$REAL_USER" yay -S --needed --noconfirm "${AUR_PACKAGES[@]}"
else
  echo "[ERROR] 'yay' AUR helper is missing. Install it first."
  exit 1
fi

# Deploy user configs
echo "-> [USER] Executing GNU Stow for the user $REAL_USER..."
# uses sudo to run stow as user not root
sudo -u "$REAL_USER" mkdir -p "$USER_HOME/.config"
sudo -u "$REAL_USER" stow --restow --target="$USER_HOME" --dir="$REPO_DIR" user

# Deploy fan control
echo "-> [SYSTEM] Provisioning Dell G15 fan control..."
cp "$REPO_DIR/system/usr/local/bin/g15_fan_control.py" /usr/local/bin/
chown root:root /usr/local/bin/g15_fan_control.py
chmod 755 /usr/local/bin/g15_fan_control.py

cp "$REPO_DIR/system/etc/systemd/system/g15-fan-control.service" /etc/systemd/system/
chown root:root /etc/systemd/system/g15-fan-control.service
chmod 644 /etc/systemd/system/g15-fan-control.service

systemctl daemon-reload
systemctl enable --now g15-fan-control.service

# Deploy ryzenadj power limits
echo "-> [SYSTEM] Provisioning RyzenAdj power limit services..."
cp "$REPO_DIR/system/etc/systemd/system/ryzenadj.service" /etc/systemd/system/
cp "$REPO_DIR/system/etc/systemd/system/ryzenadj-resume.service" /etc/systemd/system/
chown root:root /etc/systemd/system/ryzenadj.service /etc/systemd/system/ryzenadj-resume.service
chmod 644 /etc/systemd/system/ryzenadj.service /etc/systemd/system/ryzenadj-resume.service

systemctl daemon-reload
systemctl enable --now ryzenadj.service
systemctl enable ryzenadj-resume.service

# Deploy CPU frequency cap
# Caps scaling_max_freq below the boost ceiling. The top few hundred MHz cost
# far more heat than they return in throughput, and heat is what the fan
# answers. Re-applied on resume because the governor restores its own maximum.
echo "-> [SYSTEM] Provisioning CPU frequency cap..."
cp "$REPO_DIR/system/etc/systemd/system/cpu-max-freq.service" /etc/systemd/system/
chown root:root /etc/systemd/system/cpu-max-freq.service
chmod 644 /etc/systemd/system/cpu-max-freq.service

systemctl daemon-reload
systemctl enable --now cpu-max-freq.service

# Deploy DisplayPort wake recovery
# The link to the ASUS on DP-1 can come back dead from suspend with nothing
# reporting it. MUST be a system unit: the user manager has no suspend.target,
# so a user unit wanting it never fires.
echo "-> [SYSTEM] Provisioning DisplayPort wake recovery..."
cp "$REPO_DIR/system/etc/systemd/system/dp-wake-recover.service" /etc/systemd/system/
chown root:root /etc/systemd/system/dp-wake-recover.service
chmod 644 /etc/systemd/system/dp-wake-recover.service

systemctl daemon-reload
systemctl enable dp-wake-recover.service

# Same recovery for the DPMS path: Hyprland emits no DPMS event, so the user
# unit polls for it.
sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$USER_UID" \
  systemctl --user enable --now dp-dpms-watch.service || true

# EasyEffects as a service rather than an XDG autostart entry. It aborts when
# PipeWire restarts and does not come back on its own; an autostart entry runs
# once at login and has no answer to that. The audio then keeps playing, just
# with no EQ and no limiter, and nothing says so.
echo "-> [USER] Enabling EasyEffects audio processing..."
sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$USER_UID" \
  systemctl --user enable --now easyeffects.service || true

# Deploy custom binaries
echo "-> [SYSTEM] Provisioning custom binaries..."
mkdir -p /usr/local/bin
cp "$REPO_DIR/system/usr/local/bin/omarchy-power-manager" /usr/local/bin/
chown root:root /usr/local/bin/omarchy-power-manager
chmod 755 /usr/local/bin/omarchy-power-manager

# Deploy the omarchy patch reapplier
# omarchy-dev follows the quattro branch, so every upgrade replaces the whole
# installed tree and takes any locally applied patch with it -- without saying
# so. This pacman hook puts them back after the transaction.
echo "-> [SYSTEM] Provisioning omarchy patch reapplier..."
install -Dm755 "$REPO_DIR/system/usr/local/bin/omarchy-reapply-patches" \
  /usr/local/bin/omarchy-reapply-patches
install -Dm644 "$REPO_DIR/system/etc/pacman.d/hooks/95-omarchy-reapply-patches.hook" \
  /etc/pacman.d/hooks/95-omarchy-reapply-patches.hook

mkdir -p /usr/local/share/omarchy-patches
for patch_file in "$REPO_DIR"/system/usr/local/share/omarchy-patches/*.patch; do
  [[ -e $patch_file ]] || continue
  install -Dm644 "$patch_file" "/usr/local/share/omarchy-patches/$(basename "$patch_file")"
done

/usr/local/bin/omarchy-reapply-patches || true

# Deploy udev rules
mkdir -p /etc/udev/rules.d
echo "-> [SYSTEM] Provisioning kernel rules (udev)..."
cp "$REPO_DIR/system/etc/udev/rules.d/99-display-power.rules" /etc/udev/rules.d/
chown root:root /etc/udev/rules.d/99-display-power.rules
chmod 644 /etc/udev/rules.d/99-display-power.rules

echo "-> [SYSTEM] Reloading udev subsystem..."
udevadm control --reload-rules && udevadm trigger

echo "-> [SYSTEM] Enabling on-boot energy daemon..."
systemctl enable --now power-profiles-daemon.service

echo "-> [SYSTEM] Registering gamemode daemon on session bus..."
# the injection of var XDG_RUNTIME_DIR is mandatory when root tries to enable user space services
sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$USER_UID" systemctl --user enable --now gamemoded.service || true

echo "==> Provisioning successfully concluded!"
