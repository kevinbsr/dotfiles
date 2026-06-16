#!/usr/bin/env python3
import json
import os
import sys

CONFIG_PATH = os.path.expanduser("~/.config/waybar/scripts/pomodoro_config.json")
STATE_PATH = os.path.expanduser("~/.config/waybar/scripts/pomodoro_state.json")

# ANSI Color Codes
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"

def load_config():
    defaults = {
        "work_duration": 25,
        "break_duration": 5,
        "long_break_duration": 15,
        "cycles_before_long_break": 4
    }
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
                loaded = json.load(f)
                for k, v in defaults.items():
                    loaded.setdefault(k, v)
                return loaded
        except Exception:
            pass
    return defaults

def save_config(config):
    try:
        with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
            json.dump(config, f, ensure_ascii=False, indent=2)
        return True
    except Exception as e:
        print(f"{RED}Error saving config: {e}{RESET}")
        return False

def load_state():
    if os.path.exists(STATE_PATH):
        try:
            with open(STATE_PATH, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def save_state(state):
    try:
        with open(STATE_PATH, 'w', encoding='utf-8') as f:
            json.dump(state, f, ensure_ascii=False, indent=2)
    except Exception:
        pass

def get_int_input(prompt, current_val, min_val=1, max_val=180):
    while True:
        try:
            user_input = input(f"{prompt} [{current_val}]: ").strip()
            if not user_input:
                return current_val
            val = int(user_input)
            if min_val <= val <= max_val:
                return val
            else:
                print(f"{RED}Please enter a number between {min_val} and {max_val}.{RESET}")
        except ValueError:
            print(f"{RED}Invalid input. Please enter an integer.{RESET}")

def main():
    config = load_config()
    
    while True:
        state = load_state()
        completed = state.get("completed_cycles", 0)
        
        os.system("clear")
        print(f"{BOLD}{CYAN}┌──────────────────────────────────────────────┐{RESET}")
        print(f"{BOLD}{CYAN}│      🍅 Waybar Pomodoro Configurator         │{RESET}")
        print(f"{BOLD}{CYAN}└──────────────────────────────────────────────┘{RESET}")
        print()
        print(f"Current Settings:")
        print(f"  {BOLD}1.{RESET} Focus/Work duration       : {GREEN}{config['work_duration']} min{RESET}")
        print(f"  {BOLD}2.{RESET} Short Break duration      : {GREEN}{config['break_duration']} min{RESET}")
        print(f"  {BOLD}3.{RESET} Long Break duration       : {GREEN}{config['long_break_duration']} min{RESET}")
        print(f"  {BOLD}4.{RESET} Cycles before Long Break  : {GREEN}{config['cycles_before_long_break']} cycles{RESET}")
        print()
        print(f"Statistics:")
        print(f"  {BOLD}5.{RESET} Completed cycles          : {YELLOW}{completed}{RESET} (Select to Reset)")
        print()
        print(f"  {BOLD}6. Save & Exit{RESET}")
        print(f"  {BOLD}7. Cancel & Exit{RESET}")
        print()
        
        choice = input(f"{BOLD}Select an option (1-7): {RESET}").strip()
        
        if choice == "1":
            config["work_duration"] = get_int_input("Enter Work duration (min)", config["work_duration"])
        elif choice == "2":
            config["break_duration"] = get_int_input("Enter Short Break duration (min)", config["break_duration"])
        elif choice == "3":
            config["long_break_duration"] = get_int_input("Enter Long Break duration (min)", config["long_break_duration"])
        elif choice == "4":
            config["cycles_before_long_break"] = get_int_input("Enter cycles before Long Break", config["cycles_before_long_break"], min_val=1, max_val=20)
        elif choice == "5":
            confirm = input(f"{YELLOW}Reset completed cycles to 0? (y/N): {RESET}").strip().lower()
            if confirm == "y":
                state["completed_cycles"] = 0
                save_state(state)
                print(f"{GREEN}Cycles reset successfully.{RESET}")
                input("\nPress Enter to continue...")
        elif choice == "6":
            if save_config(config):
                print(f"\n{GREEN}Configuration saved successfully!{RESET}")
                # Send a notification to inform the user
                os.system("notify-send -i timer-symbolic 'Pomodoro Config' 'Settings updated successfully.'")
                time_sleep = 1
                sys.exit(0)
        elif choice == "7":
            print(f"\n{YELLOW}Changes discarded.{RESET}")
            sys.exit(0)
        else:
            print(f"{RED}Invalid choice. Select a number between 1 and 7.{RESET}")
            import time
            time.sleep(1)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{YELLOW}Exiting...{RESET}")
        sys.exit(0)
