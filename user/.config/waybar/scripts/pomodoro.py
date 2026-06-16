#!/usr/bin/env python3
import json
import os
import sys
import time
import subprocess

STATE_PATH = os.path.expanduser("~/.config/waybar/scripts/pomodoro_state.json")

# Nerd Font Icons
ICON_WORK = "󰔛"      # Timer/Focus
ICON_BREAK = "󰔚"     # Coffee Cup/Break
ICON_PAUSED = "󰏤"    # Pause
ICON_STOPPED = ""   # Clock/Stopped

# Durations in seconds
DURATION_WORK = 25 * 60
DURATION_BREAK = 5 * 60
DURATION_LONG_BREAK = 15 * 60

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
    current_time = int(time.time())
    status = state["status"]
    
    if status == "stopped":
        state["status"] = "work"
        state["mode"] = "work"
        state["target_time"] = current_time + DURATION_WORK
        state["paused_remaining"] = 0
        state["completed_cycles"] = 0
        send_notification("Pomodoro Started", "Let's focus for 25 minutes!")
    elif status in ("work", "break"):
        state["paused_remaining"] = max(0, state["target_time"] - current_time)
        state["status"] = "paused"
        send_notification("Pomodoro Paused", "Timer has been paused.")
    elif status == "paused":
        state["status"] = state["mode"]
        state["target_time"] = current_time + state["paused_remaining"]
        state["paused_remaining"] = 0
        send_notification("Pomodoro Resumed", f"Back to {state['mode']} session.")
        
    save_state(state)

def reset_timer(state):
    state["status"] = "stopped"
    state["mode"] = "work"
    state["target_time"] = 0
    state["paused_remaining"] = 0
    send_notification("Pomodoro Reset", "The timer has been reset.")
    save_state(state)

def skip_timer(state):
    current_time = int(time.time())
    status = state["status"]
    
    if status == "stopped":
        return
        
    if state["mode"] == "work":
        state["mode"] = "break"
        state["status"] = "break"
        cycles = state["completed_cycles"] + 1
        state["completed_cycles"] = cycles
        
        if cycles % 4 == 0:
            state["target_time"] = current_time + DURATION_LONG_BREAK
            send_notification("Session Skipped", "Skipping to Long Break (15 min).")
        else:
            state["target_time"] = current_time + DURATION_BREAK
            send_notification("Session Skipped", "Skipping to Short Break (5 min).")
    else:
        state["mode"] = "work"
        state["status"] = "work"
        state["target_time"] = current_time + DURATION_WORK
        send_notification("Session Skipped", "Skipping back to Focus Session (25 min).")
        
    state["paused_remaining"] = 0
    save_state(state)

def print_status(state):
    current_time = int(time.time())
    status = state["status"]
    mode = state["mode"]
    completed = state["completed_cycles"]
    
    # Check for transition in active states
    if status in ("work", "break"):
        remaining = int(state["target_time"] - current_time)
        if remaining <= 0:
            # Time's up! Transition state.
            if mode == "work":
                completed += 1
                state["completed_cycles"] = completed
                state["mode"] = "break"
                state["status"] = "break"
                
                if completed % 4 == 0:
                    state["target_time"] = current_time + DURATION_LONG_BREAK
                    send_notification(
                        "Focus Session Completed!", 
                        "Great job! Time for a Long Break (15 min).", 
                        urgency="critical"
                    )
                else:
                    state["target_time"] = current_time + DURATION_BREAK
                    send_notification(
                        "Focus Session Completed!", 
                        "Time to take a Short Break (5 min).", 
                        urgency="critical"
                    )
            else:
                state["mode"] = "work"
                state["status"] = "work"
                state["target_time"] = current_time + DURATION_WORK
                send_notification(
                    "Break Completed!", 
                    "Time to get back to work. Focus!", 
                    urgency="critical"
                )
            
            save_state(state)
            # Re-read remaining for print
            remaining = int(state["target_time"] - current_time)
            status = state["status"]
            mode = state["mode"]
            
        mins = remaining // 60
        secs = remaining % 60
        time_str = f"{mins:02d}:{secs:02d}"
        
        if mode == "work":
            text = f"{ICON_WORK} {time_str}"
            tooltip = f"Focus Session (Work)\nRemaining: {mins}m {secs}s\nCompleted cycles: {completed}"
            css_class = "work"
            total = DURATION_WORK
        else:
            text = f"{ICON_BREAK} {time_str}"
            tooltip = f"Break Session (Rest)\nRemaining: {mins}m {secs}s\nCompleted cycles: {completed}"
            css_class = "break"
            total = DURATION_LONG_BREAK if completed % 4 == 0 else DURATION_BREAK
            
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
            total = DURATION_WORK
        else:
            total = DURATION_LONG_BREAK if completed % 4 == 0 else DURATION_BREAK
        percentage = int((remaining / total) * 100)
        
    else:  # stopped
        text = f"{ICON_STOPPED} Pomodoro"
        tooltip = "Pomodoro Timer\n\nClick to start a 25-minute focus session.\nRight-click to reset."
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
