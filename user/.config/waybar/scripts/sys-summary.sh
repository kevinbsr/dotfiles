#!/bin/bash

# --- CPU USAGE ---
# Using awk for safer math and handling fast samples
cpu_usage=$(awk '{
    if ($1 == "cpu") {
        total = $2+$3+$4+$5+$6+$7+$8+$9;
        idle = $5+$6;
        print total " " idle;
        exit;
    }
}' /proc/stat)

sleep 0.1

cpu_usage_now=$(awk '{
    if ($1 == "cpu") {
        total = $2+$3+$4+$5+$6+$7+$8+$9;
        idle = $5+$6;
        print total " " idle;
        exit;
    }
}' /proc/stat)

cpu_total=$(echo "$cpu_usage $cpu_usage_now" | awk '{
    diff_total = $3 - $1;
    diff_idle = $4 - $2;
    if (diff_total > 0) {
        print int(100 * (diff_total - diff_idle) / diff_total);
    } else {
        print 0;
    }
}')
cpu_total="${cpu_total}%"

# --- CPU TEMP ---
cpu_temp=$(sensors | grep -E 'Tctl|CPU:' | head -n1 | awk '{print $2}' | tr -d '+')

# --- RAM ---
ram_used=$(free -h | awk '/Mem:/ {print $3}')
ram_total=$(free -h | awk '/Mem:/ {print $2}')
ram_perc=$(free | awk '/Mem:/ {printf "%.0f%%", $3/$2*100}')

# --- GPU (NVIDIA) ---
gpu_active=true
if command -v supergfxctl >/dev/null; then
    gfx_mode=$(supergfxctl -g 2>/dev/null)
    if [ "$gfx_mode" = "Integrated" ] || [ "$gfx_mode" = "Vfio" ]; then
        gpu_active=false
    fi
fi

if [ "$gpu_active" = "true" ]; then
    if pgrep -x nvidia-smi >/dev/null; then
        gpu_line="󰢮  GPU:         [Locked/Busy]"
    else
        gpu_info=$(timeout -k 1 1.5 nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$gpu_info" ]; then
            gpu_load=$(echo "$gpu_info" | awk -F', ' '{print $1"%"}')
            gpu_mem_used=$(echo "$gpu_info" | awk -F', ' '{printf "%.1fGi", $2/1024}')
            gpu_mem_total=$(echo "$gpu_info" | awk -F', ' '{printf "%.1fGi", $3/1024}')
            gpu_temp=$(echo "$gpu_info" | awk -F', ' '{print $4"°C"}')
            gpu_line="󰢮  GPU:         $gpu_load ($gpu_mem_used / $gpu_mem_total) @ $gpu_temp"
        else
            gpu_line=""
        fi
    fi
else
    gpu_line=""
fi

# --- DISKS ---
get_disk_info() {
    df -h "$1" | awk 'NR==2 {printf "%s / %s (%s)", $3, $2, $5}'
}
disk_root=$(get_disk_info /)
disk_home=$(get_disk_info /home)

# --- NETWORK ---
interface=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
[ -z "$interface" ] && interface=$(ip link show | grep 'state UP' | awk -F': ' '{print $2}' | head -n1)

if [ -n "$interface" ]; then
    R1=$(cat /sys/class/net/"$interface"/statistics/rx_bytes)
    T1=$(cat /sys/class/net/"$interface"/statistics/tx_bytes)
    sleep 0.1
    R2=$(cat /sys/class/net/"$interface"/statistics/rx_bytes)
    T2=$(cat /sys/class/net/"$interface"/statistics/tx_bytes)
    
    rx_speed=$(( (R2 - R1) * 10 ))
    tx_speed=$(( (T2 - T1) * 10 ))
    
    format_speed() {
        if [ "$1" -gt 1048576 ]; then
            echo "$1" | awk '{printf "%.1f Mb/s", $1/1048576}'
        else
            echo "$1" | awk '{printf "%.1f Kb/s", $1/1024}'
        fi
    }
    net_down=$(format_speed "$rx_speed")
    net_up=$(format_speed "$tx_speed")
    net_line="󰀂  Net:         󰇚 $net_down  󰕒 $net_up"
else
    net_line="󰀂  Net:         Disconnected"
fi

# --- TOOLTIP CONSTRUCTION ---
tooltip="<b>System Overview</b>
------------------------------------------
  CPU Total:   $cpu_total @ $cpu_temp
󰘚  RAM:         $ram_used / $ram_total ($ram_perc)"

[ -n "$gpu_line" ] && tooltip="$tooltip
$gpu_line"

tooltip="$tooltip
------------------------------------------
󰋊  Root (/):    $disk_root
󰒋  Home (/h):   $disk_home
------------------------------------------
$net_line"

# Output JSON
jq -nc --arg text "󰍛" --arg tooltip "$tooltip" '{"text": $text, "tooltip": $tooltip}'
