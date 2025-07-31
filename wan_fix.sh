#!/bin/bash
# ------------------------------------------------------------------------------
#     ______           __  _             __     
#    / ____/___  _____/ /_(_)___ _____ _/ /____ 
#   / /_  / __ \/ ___/ __/ / __ \`/ __ \`/ __/ '\
#  / __/ / /_/ / /  / /_/ / /_/ / /_/ / /_/  __/
# /_/    \____/_/   \__/_/\__, /\__,_/\__/\___/ 
#                        /____/                
# WAN fixer – Automated Internet Recovery
# ------------------------------------------------------------------------------

# This script requires a configuration file named 'wan_fix.conf' in the same directory.
# The configuration file must define the following variables:

# monitored_ip_1="<IP address>"
# monitored_ip_2="<IP address>"
# fortigate_fw="<FortiGate IP>"
# fw_user="<username>"
# fw_password="<password>"
# telegram_bot_token="<Telegram Bot Token>"
# telegram_chat_id="<Telegram Chat ID>"

# Optional custom paths:
# last_fix_file="/var/tmp/wan1_last_fix.timestamp"
# lockfile="/var/tmp/wan1_fix.lock"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/wan_fix.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo "Error: Configuration file '$CONF_FILE' not found. Aborting."
    exit 1
fi

source "$CONF_FILE"

last_fix_file="${last_fix_file:-/var/tmp/wan1_last_fix.timestamp}"
lockfile="${lockfile:-/var/tmp/wan1_fix.lock}"

dry_run=false
if [[ ${1:-} == "--dry-run" ]]; then
    dry_run=true
    echo "Dry-run mode activated – SSH commands will not be executed."
fi

log() {
    echo "$1"
    logger -t ping_check_script "$1"
}

send_telegram() {
    message="$1"
    if ! curl -s --max-time 10 -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" \
         -d chat_id="$telegram_chat_id" \
         -d text="$message" > /dev/null; then
        log "Warning: Failed to send Telegram message."
    fi
}

check_dependencies() {
    for cmd in sshpass ping curl logger stat; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            echo "Error: Required command '$cmd' not found. Aborting."
            exit 1
        fi
    done
}
check_dependencies

# Advanced lockfile handling with PID, boot ID, and script validation
current_boot_id=$(cat /proc/sys/kernel/random/boot_id)

if [ -f "$lockfile" ]; then
    read -r old_pid old_boot_id < "$lockfile"
    if [ "$old_boot_id" = "$current_boot_id" ] && kill -0 "$old_pid" 2>/dev/null; then
        if grep -q "wan_fix.sh" "/proc/$old_pid/cmdline" 2>/dev/null; then
            log "Another instance (PID $old_pid) is still running. Exiting."
            exit 1
        else
            log "Stale lockfile found (PID reused by another process). Removing and continuing."
            rm -f "$lockfile"
        fi
    else
        log "Stale lockfile from previous boot or dead process. Removing and continuing."
        rm -f "$lockfile"
    fi
fi

echo "$$ $current_boot_id" > "$lockfile"
cleanup() { rm -f "$lockfile"; }
trap cleanup EXIT

ping_test() {
    local ip=$1
    for i in {1..3}; do
        ping -c 1 -W 2 "$ip" > /dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

if [ -f "$last_fix_file" ]; then
    last_fix_time=$(stat -c %Y "$last_fix_file")
    now=$(date +%s)
    diff=$((now - last_fix_time))
    if [ $diff -lt 1800 ]; then
        log "Previous fix was less than 30 minutes ago. Skipping fix attempt."
        exit 0
    fi
fi

if ping_test "$monitored_ip_1"; then
    log "$monitored_ip_1 responded. Exiting."
    exit 0
fi

if ping_test "$monitored_ip_2"; then
    log "$monitored_ip_2 responded. Exiting."
    exit 0
fi

if ping_test "$fortigate_fw"; then
    log "FortiGate ($fortigate_fw) is reachable. Attempting automated fix."
    touch "$last_fix_file"

    if $dry_run; then
        sshpass -p "$fw_password" ssh -o StrictHostKeyChecking=no "$fw_user@$fortigate_fw" "get system status" || log "Dry-run: SSH test failed (WAN1 down simulation)"
    else
        if ! sshpass -p "$fw_password" ssh -o StrictHostKeyChecking=no "$fw_user@$fortigate_fw" << EOF
config global
config system interface
edit wan1
set status down
next
end
EOF
        then
            log "Error: SSH command failed while bringing WAN1 down."
            exit 1
        fi
    fi

    log "WAN1 brought down. Waiting 15 seconds..."
    sleep 15

    if $dry_run; then
        sshpass -p "$fw_password" ssh -o StrictHostKeyChecking=no "$fw_user@$fortigate_fw" "get system status" || log "Dry-run: SSH test failed (WAN1 up simulation)"
    else
        if ! sshpass -p "$fw_password" ssh -o StrictHostKeyChecking=no "$fw_user@$fortigate_fw" << EOF
config global
config system interface
edit wan1
set status up
next
end
EOF
        then
            log "Error: SSH command failed while bringing WAN1 back up."
            exit 1
        fi
    fi

    log "WAN1 brought back up. Waiting 15 seconds..."
    sleep 15

    if ping_test "$monitored_ip_1" || ping_test "$monitored_ip_2"; then
        log "Automatic fix succeeded. Connectivity restored."
        send_telegram "⚙️ Automatic fix succeeded. Internet connectivity issue was detected and resolved by restarting WAN1 on FortiGate."
        rm -f "$last_fix_file"
    else
        log "Automatic fix failed. Internet still not reachable."
    fi

    exit 0
else
    log "FortiGate ($fortigate_fw) is unreachable. Skipping SSH commands."
fi

log "No IP responded. FortiGate may be offline or isolated."
