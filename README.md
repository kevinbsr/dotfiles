# ⚡ My Workstation Dotfiles
Infrastructure as Code (IaC) repository for the automated provisioning of my workstation - **Dell G15 Ryzen Edition** - running **[Omarchy](https://omarchy.org/) (Arch Linux)**.
This repository's architecture strictly separates user-level configurations from system binaries and hardware rules, adhering to the principle of least privilege.
## ✨ Key Features
* **Event-Driven Power Management:** Custom ACPI/udev rules combined with a dynamic power manager script to automatically switch between 165Hz/Performance mode (AC/Gaming) and 60Hz/Power-Saver mode (Battery).
* **Idempotent Deployment:** The bootstrap script can be safely executed multiple times to enforce system state without duplicating data or breaking configurations.
* **Zero-Trust Privilege Handling:** Automatically drops root privileges to safely install AUR packages (via `yay`) and link user-space configs (via `stow`).
## 🏗️ Architecture
The dotfiles management is split into two isolated domains to prevent privilege escalation and maintain OS integrity:
* **User Space (`/user`):** Managed via [GNU Stow](https://www.gnu.org/software/stow/). Contains user-level configurations. Using symlinks allows changes to instantly reflect in version control without manual synchronization.
* **System Space (`/system`):** Managed via a strict bootstrap script. Files in this domain are injected using physical copies (`cp`) with hardcoded `root:root` ownership, preventing malicious scripts in the user session from altering system behavior.
## ⚙️ Deployment / Installation
The bootstrap script is idempotent. It can be safely executed multiple times to apply new system rule updates.
> **Security Note:** The installation script requires `sudo` strictly to inject rules into `/etc/udev/` and binaries into `/usr/local/bin/`. All user-space operations drop these privileges automatically.
```bash
git clone https://github.com/kevinbsr/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
chmod +x install.sh
sudo ./install.sh
```
---

