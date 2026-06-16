#!/usr/bin/env python3
import json
import os
import sys
import time
import subprocess

STATE_PATH = os.path.expanduser("~/.config/waybar/scripts/pomodoro_state.json")
CONFIG_PATH = os.path.expanduser("~/.config/waybar/scripts/pomodoro_config.json")

# Nerd Font Icons
ICON_WORK = "󰔛"      # Timer/Focus
ICON_BREAK = "󰔚"     # Coffee Cup/Break
ICON_PAUSED = "󰏤"    # Pause
ICON_STOPPED = ""   # Clock/Stopped

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

def load_state():
    if os.path.exists(STATE_PATH):
        try:
            with open(STATE_PATH, 'r', encoding='utf-8') as f:
                state = json.load(f)
                # Ensure all fields are present
                state.setdefault("status", "stopped")
                state.setdefault("target_time", 0)
                state.setdefault("paused_remaining", 0)
                state.setdefault("mode", "work")
                state.setdefault("completed_cycles", 0)
                return state
        except Exception:
            pass
    return {
        "status": "stopped",
        "target_time": 0,
        "paused_remaining": 0,
        "mode": "work",
        "completed_cycles": 0
    }

def save_state(state):
    try:
        with open(STATE_PATH, 'w', encoding='utf-8') as f:
            json.dump(state, f, ensure_ascii=False, indent=2)
    except Exception:
        pass

def send_notification(summary, body, urgency="normal"):
    try:
        # Send desktop notification
        subprocess.run([
            "notify-send",
            "-u", urgency,
            "-i", "alarm-symbolic",
            summary,
            body
        ], check=False)
    except Exception:
        pass

def toggle_timer(state):
    config = load_config()
    duration_work = config["work_duration"] * 60
    duration_break = config["break_duration"] * 60
    duration_long_break = config["long_break_duration"] * 60
    cycles_before_long_break = config["cycles_before_long_break"]
    
    current_time = int(time.time())
    status = state["status"]
    mode = state["mode"]
    
    if status == "stopped":
        state["status"] = mode
        if mode == "work":
            state["target_time"] = current_time + duration_work
            send_notification("Focus Session Started", f"Let's focus for {config['work_duration']} minutes!")
        else:
            cycles = state["completed_cycles"]
            if cycles > 0 and cycles % cycles_before_long_break == 0:
                state["target_time"] = current_time + duration_long_break
                send_notification("Break Started", f"Time for a Long Break ({config['long_break_duration']} min).")
            else:
                state["target_time"] = current_time + duration_break
                send_notification("Break Started", f"Time for a Short Break ({config['break_duration']} min).")
        state["paused_remaining"] = 0
    elif status in ("work", "break"):
        state["paused_remaining"] = max(0, state["target_time"] - current_time)
        state["status"] = "paused"
        send_notification("Pomodoro Paused", "Timer has been paused.")
    elif status == "paused":
        state["status"] = mode
        state["target_time"] = current_time + state["paused_remaining"]
        state["paused_remaining"] = 0
        send_notification("Pomodoro Resumed", f"Back to {mode} session.")
        
    save_state(state)

def reset_timer(state):
    state["status"] = "stopped"
    state["mode"] = "work"
    state["target_time"] = 0
    state["paused_remaining"] = 0
    send_notification("Pomodoro Reset", "The timer has been reset.")
    save_state(state)

def skip_timer(state):
    config = load_config()
    duration_work = config["work_duration"] * 60
    duration_break = config["break_duration"] * 60
    duration_long_break = config["long_break_duration"] * 60
    cycles_before_long_break = config["cycles_before_long_break"]
    
    current_time = int(time.time())
    status = state["status"]
    
    if state["mode"] == "work":
        state["mode"] = "break"
        cycles = state["completed_cycles"] + 1
        state["completed_cycles"] = cycles
        
        if status in ("work", "break", "paused"):
            if cycles % cycles_before_long_break == 0:
                duration = duration_long_break
                send_notification("Session Skipped", f"Skipping to Long Break ({config['long_break_duration']} min).")
            else:
                duration = duration_break
                send_notification("Session Skipped", f"Skipping to Short Break ({config['break_duration']} min).")
            
            if status == "paused":
                state["paused_remaining"] = duration
            else:
                state["status"] = "break"
                state["target_time"] = current_time + duration
        else:
            send_notification("Session Skipped", "Skipped Focus. Ready for Break.")
    else:
        state["mode"] = "work"
        if status in ("work", "break", "paused"):
            duration = duration_work
            send_notification("Session Skipped", f"Skipping back to Focus Session ({config['work_duration']} min).")
            
            if status == "paused":
                state["paused_remaining"] = duration
            else:
                state["status"] = "work"
                state["target_time"] = current_time + duration
        else:
            send_notification("Session Skipped", "Skipped Break. Ready to Focus.")
            
    save_state(state)

def print_status(state):
    config = load_config()
    duration_work = config["work_duration"] * 60
    duration_break = config["break_duration"] * 60
    duration_long_break = config["long_break_duration"] * 60
    cycles_before_long_break = config["cycles_before_long_break"]

    current_time = int(time.time())
    status = state["status"]
    mode = state["mode"]
    completed = state["completed_cycles"]
    
    # Check for transition in active states
    if status in ("work", "break"):
        remaining = int(state["target_time"] - current_time)
        if remaining <= 0:
            # Time's up! Transition mode, but stop and wait for click
            if mode == "work":
                completed += 1
                state["completed_cycles"] = completed
                state["mode"] = "break"
                state["status"] = "stopped"
                state["target_time"] = 0
                state["paused_remaining"] = 0
                
                if completed % cycles_before_long_break == 0:
                    send_notification(
                        "Focus Session Completed!", 
                        f"Great job! Click the widget to start your Long Break ({config['long_break_duration']} min).", 
                        urgency="critical"
                    )
                else:
                    send_notification(
                        "Focus Session Completed!", 
                        f"Time for a Short Break ({config['break_duration']} min). Click the widget to start.", 
                        urgency="critical"
                    )
            else:
                state["mode"] = "work"
                state["status"] = "stopped"
                state["target_time"] = 0
                state["paused_remaining"] = 0
                send_notification(
                    "Break Completed!", 
                    "Time to get back to work. Click the widget to start focusing.", 
                    urgency="critical"
                )
            
            save_state(state)
            # Re-read status/mode for output
            status = state["status"]
            mode = state["mode"]
            
    if status in ("work", "break"):
        remaining = int(state["target_time"] - current_time)
        mins = remaining // 60
        secs = remaining % 60
        time_str = f"{mins:02d}:{secs:02d}"
        
        if mode == "work":
            text = f"{ICON_WORK} {time_str}"
            tooltip = f"Focus Session (Work)\nRemaining: {mins}m {secs}s\nCompleted cycles: {completed}"
            css_class = "work"
            total = duration_work
        else:
            text = f"{ICON_BREAK} {time_str}"
            tooltip = f"Break Session (Rest)\nRemaining: {mins}m {secs}s\nCompleted cycles: {completed}"
            css_class = "break"
            total = duration_long_break if completed % cycles_before_long_break == 0 else duration_break
            
        percentage = int((remaining / total) * 100)
        
    elif status == "paused":
        remaining = state["paused_remaining"]
        mins = remaining // 60
        secs = remaining % 60
        time_str = f"{mins:02d}:{secs:02d}"
        
        text = f"{ICON_PAUSED} {time_str}"
        tooltip = f"Paused ({mode.capitalize()})\nRemaining: {mins}m {secs}s\nCompleted cycles: {completed}"
        css_class = "paused"
        
        if mode == "work":
            total = duration_work
        else:
            total = duration_long_break if completed % cycles_before_long_break == 0 else duration_break
        percentage = int((remaining / total) * 100)
        
    else:  # stopped
        if mode == "break":
            text = f"{ICON_BREAK}"
            duration = config["long_break_duration"] if completed > 0 and completed % cycles_before_long_break == 0 else config["break_duration"]
            tooltip = f"Break Pending ({duration}m)\nClick to start break session.\nCompleted cycles: {completed}"
        else:
            text = f"{ICON_STOPPED}"
            tooltip = f"Ready to Focus ({config['work_duration']}m)\nClick to start focus session.\nCompleted cycles: {completed}"
        
        css_class = "stopped"
        percentage = 100

    output = {
        "text": text,
        "tooltip": tooltip,
        "class": css_class,
        "percentage": percentage
    }
    print(json.dumps(output))

def main():
    state = load_state()
    
    if len(sys.argv) > 1:
        action = sys.argv[1]
        if action == "--toggle":
            toggle_timer(state)
        elif action == "--reset":
            reset_timer(state)
        elif action == "--skip":
            skip_timer(state)
        elif action == "--help":
            print("Usage: pomodoro.py [--toggle | --reset | --skip]")
    else:
        print_status(state)

if __name__ == "__main__":
    main()
