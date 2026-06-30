# 🗄️ Automated Backup Script

> A powerful, simple Bash script for automated backups of files and folders — with compression, encryption, email notifications, and scheduled execution.

[![Bash](https://img.shields.io/badge/Bash-4.0%2B-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20WSL-orange)](#)

---

## 📖 About the Project

This script solves a simple but important problem: **how do you automatically and securely back up your important files?**

`backup.sh` recursively scans your directories, finds files matching the formats you specify, compresses them (and optionally encrypts them), generates a full report of the operation, cleans up old backups, and can even schedule itself for recurring runs.

### ✨ Key Features

| Feature | Description |
|---|---|
| 🔍 **Recursive Scan** | Searches all subdirectories for files matching given extensions |
| 📝 **Auto Manifest** | Logs the absolute path of every matched file in `backup_manifest.txt` |
| 🗜️ **Dual Compression** | Each file gzipped individually, then bundled into a final `tar.gz` |
| 🔐 **AES-256 Encryption** | Protects the final archive using `gpg` |
| 📊 **Full Reporting** | Log includes status, size, duration, and file counts |
| 🗑️ **Auto Cleanup** | Deletes backups older than N days |
| ⏰ **Cron Scheduling** | Automatically installs a cron job for recurring backups |
| 📧 **Email Notifications** | Sends the result of each backup via `msmtp` |

---

## 🧰 Prerequisites

Tested on **Linux** (Debian/Ubuntu/Kali) and **WSL**.

### Required tools (usually pre-installed)

```bash
bash      # version 4.0+
find      # file search
gzip      # compression
tar       # archiving
```

### Optional tools (depending on which features you use)

| Tool | Needed for | Install |
|---|---|---|
| `gpg` | Archive encryption | `sudo apt install gnupg` |
| `msmtp` + `msmtp-mta` | Email notifications | `sudo apt install msmtp msmtp-mta` |
| `cron` | Scheduled execution | `sudo apt install cron` |

### Check what's installed

```bash
command -v gzip tar find gpg msmtp crontab
```

---

## 📥 Installation

```bash
# Clone the repository
git clone https://github.com/Ox50R0U5H/backup-script.git
cd backup-script

# Make the script executable
chmod +x backup.sh
```

---

## 🚀 Usage

### Interactive mode (easiest)

Run without arguments — the script will prompt you for everything:

```bash
./backup.sh
```

```
📁 Source directory path: /home/user/documents
💾 Backup destination directory: /home/user/backups
🔍 File formats (comma-separated, e.g. txt,py,log): txt,pdf,py
🗑  Delete backups older than N days? [7]: 7
🔒 Encrypt backup archive? (y/N): n
```

### Command-line mode (for scripting and cron)

```bash
./backup.sh -s <source> -d <destination> -f <formats> -n <days> [options]
```

### Parameters

| Flag | Short | Description | Required |
|---|---|---|---|
| `--source` | `-s` | Source directory path | ✅ |
| `--dest` | `-d` | Backup destination path | ✅ |
| `--formats` | `-f` | Comma-separated extensions (e.g. `txt,py,pdf`) | ✅ |
| `--days` | `-n` | Delete backups older than N days | ✅ |
| `--encrypt` | `-e` | Enable AES-256 encryption | ❌ |
| `--password` | `-p` | Passphrase (used with `-e`) | ❌ |
| `--email` | — | Email address for notifications | ❌ |
| `--cron` | — | Cron schedule (crontab format) | ❌ |
| `--help` | `-h` | Show help | ❌ |

---

## 💡 Examples

### Basic backup

```bash
./backup.sh -s ~/Documents -d ~/backups -f "txt,pdf,docx" -n 7
```

### Encrypted backup

```bash
./backup.sh -s ~/code -d /mnt/backup -f "py,js" -n 14 -e -p "MyStrongPass123"
```

> ⚠️ **Security warning:** Passing a password in plain text on the command line stores it in your shell history (`~/.bash_history`). For automated scripts, read the password from a file or environment variable instead (see [Security Notes](#-security-notes)).

### Backup with email notification

```bash
./backup.sh -s ~/data -d ~/backups -f csv -n 7 --email you@example.com
```

See [Email Setup](#-email-setup-with-msmtp) for configuration.

### Daily scheduled backup (2 AM)

```bash
./backup.sh -s ~/Documents -d ~/backups -f txt -n 7 --cron "0 2 * * *"
```

### Weekly scheduled backup (every Sunday at 3 AM)

```bash
./backup.sh -s ~/projects -d ~/backups -f py -n 30 --cron "0 3 * * 0"
```

### All features combined

```bash
./backup.sh \
  -s ~/important-files \
  -d ~/secure-backups \
  -f "txt,pdf,docx,xlsx" \
  -n 14 \
  -e -p "MySecurePass" \
  --email admin@company.com \
  --cron "0 2 * * *"
```

---

## 📂 Output Structure

Each run creates a `backup_<timestamp>` folder inside the destination path:

```
~/backups/
└── backup_2026_06_28_13_47_08/
    ├── backup_manifest.txt              # absolute paths of matched files
    ├── backup_2026_06_28_13_47_08.tar.gz(.gpg)  # final archive (encrypted if -e)
    ├── backup.log                       # full operation report
    └── *.gz                             # individually compressed files
```

### Sample `backup_manifest.txt`

```
/home/user/documents/notes.txt
/home/user/documents/reports/q1.pdf
/home/user/documents/code/main.py
```

### Sample `backup.log`

```
═══════════════════════════════════════════════════════
  Backup Report — 2026-06-28 13:47:08
═══════════════════════════════════════════════════════
  Status          : SUCCESS
  Source          : /home/user/documents
  Formats         : txt,pdf,py
  Archive         : .../backup_2026_06_28_13_47_08.tar.gz
  Archive Size    : 4.2M
  Files Backed Up : 27
  Files Failed    : 0
  Start Time      : 2026-06-28 13:47:08
  Duration        : 3 seconds
  Encrypted       : false
  Retention Days  : 7
═══════════════════════════════════════════════════════
```

---

## 📧 Email Setup with msmtp

To enable email notifications, `msmtp` must be installed and configured.

### 1. Install

```bash
sudo apt update
sudo apt install msmtp msmtp-mta
```

### 2. Create a Gmail App Password

1. Go to [Google Account Security](https://myaccount.google.com/security)
2. Enable **2-Step Verification**
3. Go to [App Passwords](https://myaccount.google.com/apppasswords) and create one for Mail

### 3. Create the config file

```bash
nano ~/.msmtprc
```

```ini
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account        gmail
host           smtp.gmail.com
port           587
from           your-email@gmail.com
user           your-email@gmail.com
password       YOUR_16_DIGIT_APP_PASSWORD

account default : gmail
```

```bash
chmod 600 ~/.msmtprc
```

### 4. Test it

```bash
echo "Test message" | msmtp your-email@gmail.com
```

---

## ⏰ Cron Setup

### Check if the cron service is running

```bash
# systemd-based systems
sudo systemctl status cron

# WSL (no systemd)
sudo service cron start
```

### View installed cron jobs

```bash
crontab -l
```

### Cron schedule format

```
*  *  *  *  *
│  │  │  │  └── day of week (0-6, Sunday=0)
│  │  │  └───── month (1-12)
│  │  └──────── day of month (1-31)
│  └─────────── hour (0-23)
└────────────── minute (0-59)
```

| Example | Meaning |
|---|---|
| `0 2 * * *` | Every night at 2 AM |
| `*/15 * * * *` | Every 15 minutes |
| `0 8 * * 1` | Every Monday at 8 AM |
| `0 0 1 * *` | First of every month at midnight |

---

## 🔐 Security Notes

> ⚠️ Read this before using in production.

- **Passwords on the command line**: Passing `-p "password"` stores the password in `~/.bash_history` and in `crontab -l`. For serious use:
  - Use `-e` without `-p` to have the script prompt interactively and securely (`read -s`).
  - Or store the password in a file with `600` permissions and extend the script to read from it.
- **`.msmtprc` file**: Always `chmod 600` it so only you can read it.
- **Encrypted archive (`.gpg`)**: Uses `AES-256` symmetric encryption; keep the passphrase safe — losing it means losing access to the backup.
- This repository includes a `.gitignore` that prevents logs, encrypted archives, and sensitive config files from being committed.

---

## 🛠️ Troubleshooting

<details>
<summary><strong>Cron doesn't run</strong></summary>

On WSL, systemd is usually not active. Instead of:
```bash
sudo systemctl start cron
```
use:
```bash
sudo service cron start
```
</details>

<details>
<summary><strong>"mail command not found" error</strong></summary>

You need to install `msmtp` and `msmtp-mta` — see [Email Setup](#-email-setup-with-msmtp).
</details>

<details>
<summary><strong>gpg error during encryption</strong></summary>

Make sure gpg is installed:
```bash
sudo apt install gnupg
```
</details>

<details>
<summary><strong>404 error during apt install (on Kali)</strong></summary>

The mirror is broken; update or retry with `--fix-missing`:
```bash
sudo apt update --fix-missing
sudo apt install <package> --fix-missing
```
</details>

---

## 🗺️ Roadmap

- [ ] Support reading password from a file or environment variable
- [ ] Add an incremental backup flag
- [ ] Support cloud upload (S3 / Google Drive)
- [ ] Add automated tests (bats-core)

---

## 🤝 Contributing

Pull requests and issues are welcome! For major changes, please open an issue first.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

---

## 👤 Author

**Soroush Bieranvand**

Built with ❤️ and Bash — 2026
