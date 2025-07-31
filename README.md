# 📡 WAN Fixer – Automated Internet Recovery for FortiGate

**`wan_fix.sh`** is an automated monitoring and recovery script that checks internet connectivity and attempts to fix issues by toggling the WAN1 interface on a FortiGate firewall.

## 🧩 Features

- ✅ Monitors two external IP addresses (e.g., 8.8.8.8 and 1.1.1.1)
- ✅ Verifies FortiGate reachability before attempting recovery
- ✅ Uses SSH to bring FortiGate's WAN1 down and back up
- ✅ Sends success notifications to a Telegram channel
- ✅ Avoids excessive fix attempts (enforces 30-minute cooldown)
- ✅ Lockfile mechanism prevents concurrent runs and handles stale locks
- ✅ Dry-run mode for safe testing without changing firewall state

## 🛠️ Requirements

- `bash`
- `sshpass`
- `ping`
- `curl`
- `logger`
- `stat`

Install `sshpass` if needed:
```bash
sudo apt install sshpass  # For Debian/Ubuntu
```

## 🔧 Configuration

Create a file named `wan_fix.conf` in the same directory as the script:

```bash
monitored_ip_1="<First IP>"
monitored_ip_2="<Second IP>"
fortigate_fw="<FortiGate IP>"
fw_user="<username>"
fw_password="<password>"
telegram_bot_token="<token>"
telegram_chat_id="<chat>"

# Optional (defaults are used if omitted)
last_fix_file="/var/tmp/wan1_last_fix.timestamp"
lockfile="/var/tmp/wan1_fix.lock"
```

⚠️ Keep this file secure — it contains credentials.

## 🚀 Usage

Run normally:
```bash
./wan_fix.sh
```

Test with dry-run:
```bash
./wan_fix.sh --dry-run
```

This will perform checks and SSH connections, but will only run `get system status` on the firewall.

## ⏰ Cron Scheduling

Add this to crontab to run every 5 minutes:
```cron
*/5 * * * * /path/to/wan_fix.sh > /dev/null 2>&1
```

Adjust the path to match your environment.

## 🧪 Testing

Use dry-run mode to simulate fixes without making changes. You can also manually edit the lockfile or manipulate ping behavior to simulate various scenarios.

## 📁 Logging

All events are logged to syslog under the tag `ping_check_script`:

```bash
journalctl -t ping_check_script
# or
grep ping_check_script /var/log/syslog
```

## 🛡️ Security

- Lockfile includes PID and boot ID to handle reboots safely
- SSH password is not exposed via command line arguments
- Dry-run mode supports non-invasive diagnostics

## 📬 Telegram Notifications

A message is sent to your Telegram channel only if automatic recovery is successful. Failures are logged but not notified.

## 📌 Author

Designed for FortiGate environments to ensure automated, robust internet recovery in monitored systems.
