#!/usr/bin/env bash
# =============================================================================
#  backup.sh — Automated Backup Script
#  Usage: bash backup.sh [OPTIONS]
#
#  Options:
#    -s, --source   <path>          Source directory to back up
#    -d, --dest     <path>          Destination directory for backups
#    -f, --formats  <ext1,ext2,...> File extensions (e.g. txt,py,jpg)
#    -n, --days     <N>             Delete backups older than N days
#    -e, --encrypt                  Encrypt the backup archive (requires gpg)
#    -p, --password <passphrase>    Passphrase for encryption
#    --email        <address>       Email address for notifications
#    --cron         <schedule>      Install cron job (e.g. "0 2 * * *")
#    -h, --help                     Show this help message
#
#  Examples:
#    bash backup.sh -s ~/Documents -d ~/backups -f "txt,pdf,py" -n 7
#    bash backup.sh -s ~/code -d /mnt/backup -f py -n 14 -e -p "MyPass"
#    bash backup.sh -s ~/data -d ~/backups -f csv --cron "0 3 * * *"
# =============================================================================

set -uo pipefail

# ─── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ─── Global state (set via args / prompts) ────────────────────────────────────
SOURCE_DIR=""
DEST_DIR=""
FILE_FORMATS=""
RETENTION_DAYS=""
ENCRYPT=false
PASSPHRASE=""
EMAIL=""
CRON_SCHEDULE=""

# ─── Runtime globals filled during main() ────────────────────────────────────
TIMESTAMP=""
BACKUP_WORK_DIR=""
MANIFEST_FILE=""
ARCHIVE_FILE=""

# ─── Logging helpers ─────────────────────────────────────────────────────────
_log() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${RESET} $*"; }
_ok()  { echo -e "${GREEN}[✔️]${RESET} $*"; }
_warn(){ echo -e "${YELLOW}[⚠]${RESET} $*"; }
_err() { echo -e "${RED}[✘]${RESET} $*" >&2; }
_die() { _err "$*"; exit 1; }

banner() {
  echo -e "${BOLD}${CYAN}"
  echo "  ╔══════════════════════════════════════╗"
  echo "  ║       🗄  Automated Backup Tool       ║"
  echo "  ╚══════════════════════════════════════╝"
  echo -e "${RESET}"
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -s|--source)   SOURCE_DIR="$2";      shift 2 ;;
      -d|--dest)     DEST_DIR="$2";        shift 2 ;;
      -f|--formats)  FILE_FORMATS="$2";    shift 2 ;;
      -n|--days)     RETENTION_DAYS="$2";  shift 2 ;;
      -e|--encrypt)  ENCRYPT=true;         shift   ;;
      -p|--password) PASSPHRASE="$2";      shift 2 ;;
      --email)       EMAIL="$2";           shift 2 ;;
      --cron)        CRON_SCHEDULE="$2";   shift 2 ;;
      -h|--help)
        grep '^#  ' "$0" | sed 's/^#  //'
        exit 0 ;;
      *) _die "Unknown option: $1" ;;
    esac
  done
}

# ─── Interactive Prompts ──────────────────────────────────────────────────────
prompt_missing() {
  if [[ -z "$SOURCE_DIR" ]]; then
    printf "${BOLD}📁 Source directory path: ${RESET}"
    read -r SOURCE_DIR
  fi
  if [[ -z "$DEST_DIR" ]]; then
    printf "${BOLD}💾 Backup destination directory: ${RESET}"
    read -r DEST_DIR
  fi
  if [[ -z "$FILE_FORMATS" ]]; then
    printf "${BOLD}🔍 File formats (comma-separated, e.g. txt,py,log): ${RESET}"
    read -r FILE_FORMATS
  fi
  if [[ -z "$RETENTION_DAYS" ]]; then
    printf "${BOLD}🗑  Delete backups older than N days? [7]: ${RESET}"
    read -r RETENTION_DAYS
    RETENTION_DAYS="${RETENTION_DAYS:-7}"
  fi
  if [[ "$ENCRYPT" == false ]]; then
    printf "${BOLD}🔒 Encrypt backup archive? (y/N): ${RESET}"
    read -r enc_answer
    if [[ "$enc_answer" =~ ^[Yy]$ ]]; then
      ENCRYPT=true
      if [[ -z "$PASSPHRASE" ]]; then
        printf "${BOLD}   Enter passphrase: ${RESET}"
        read -rs PASSPHRASE
        echo
      fi
    fi
  fi
}

# ─── Validation ───────────────────────────────────────────────────────────────
validate_inputs() {
  [[ -d "$SOURCE_DIR" ]]      || _die "Source directory not found: $SOURCE_DIR"
  [[ -n "$FILE_FORMATS" ]]    || _die "No file formats specified."
  [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || _die "Retention days must be a positive integer."
  if $ENCRYPT; then
    command -v gpg &>/dev/null || _die "gpg is not installed. Cannot encrypt."
    [[ -n "$PASSPHRASE" ]]    || _die "Encryption requested but no passphrase provided (-p)."
  fi
  mkdir -p "$DEST_DIR"        || _die "Cannot create destination: $DEST_DIR"
}

# ─── Build manifest ───────────────────────────────────────────────────────────
build_manifest() {
  _log "Scanning '${SOURCE_DIR}' for formats: ${FILE_FORMATS}"

  local find_args=()
  local first=true
  IFS=',' read -ra exts <<< "$FILE_FORMATS"
  for ext in "${exts[@]}"; do
    ext="${ext// /}"; ext="${ext#.}"
    if $first; then
      find_args+=( -name "*.${ext}" ); first=false
    else
      find_args+=( -o -name "*.${ext}" )
    fi
  done

  find "$SOURCE_DIR" -type f \( "${find_args[@]}" \) | sort > "$MANIFEST_FILE"
  local count; count=$(wc -l < "$MANIFEST_FILE")
  _ok "Manifest saved: ${MANIFEST_FILE}  (${count} file(s) found)"
}

# ─── Compress files ───────────────────────────────────────────────────────────
SUCCESS_COUNT=0
FAIL_COUNT=0

compress_files() {
  _log "Compressing individual files …"
  SUCCESS_COUNT=0; FAIL_COUNT=0

  while IFS= read -r filepath; do
    [[ -z "$filepath" ]] && continue
    local safe_name
    safe_name=$(echo "$filepath" | sed 's|^/||; s|/|__|g')
    local gz_out="${BACKUP_WORK_DIR}/${safe_name}.gz"
    if gzip -c "$filepath" > "$gz_out" 2>/dev/null; then
      (( SUCCESS_COUNT++ )) || true
    else
      _warn "Failed to compress: $filepath"
      echo "$filepath" >> "${BACKUP_WORK_DIR}/failed_files.txt"
      (( FAIL_COUNT++ )) || true
    fi
  done < "$MANIFEST_FILE"

  _ok "Compressed: ${SUCCESS_COUNT} file(s)  |  Failed: ${FAIL_COUNT} file(s)"

  _log "Bundling all compressed files into: ${ARCHIVE_FILE}"
  tar -czf "$ARCHIVE_FILE" \
      -C "$BACKUP_WORK_DIR" \
      --exclude="$(basename "$ARCHIVE_FILE")" \
      . 2>/dev/null || true
  _ok "Archive created: ${ARCHIVE_FILE}"
}

# ─── Encrypt archive ──────────────────────────────────────────────────────────
encrypt_archive() {
  local encrypted="${ARCHIVE_FILE}.gpg"
  _log "Encrypting archive with AES-256 …"
  echo "$PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 \
    --symmetric --cipher-algo AES256 -o "$encrypted" "$ARCHIVE_FILE"
  rm -f "$ARCHIVE_FILE"
  ARCHIVE_FILE="$encrypted"
  _ok "Encrypted archive: ${ARCHIVE_FILE}"
}

# ─── Write log report ─────────────────────────────────────────────────────────
write_log() {
  local log_file="$1"
  local status="$2"
  local start_time="$3"
  local duration="$4"
  local archive_size="N/A"
  [[ -f "$ARCHIVE_FILE" ]] && archive_size=$(du -sh "$ARCHIVE_FILE" | cut -f1)

  cat >> "$log_file" <<EOF
═══════════════════════════════════════════════════════
  Backup Report — $(date '+%Y-%m-%d %H:%M:%S')
═══════════════════════════════════════════════════════
  Status          : ${status}
  Source          : ${SOURCE_DIR}
  Formats         : ${FILE_FORMATS}
  Archive         : ${ARCHIVE_FILE}
  Archive Size    : ${archive_size}
  Files Backed Up : ${SUCCESS_COUNT}
  Files Failed    : ${FAIL_COUNT}
  Start Time      : ${start_time}
  Duration        : ${duration} seconds
  Encrypted       : ${ENCRYPT}
  Retention Days  : ${RETENTION_DAYS}
═══════════════════════════════════════════════════════

EOF
  _ok "Log written: ${log_file}"
}

# ─── Cleanup old backups ──────────────────────────────────────────────────────
cleanup_old_backups() {
  _log "Removing backups older than ${RETENTION_DAYS} days from '${DEST_DIR}' …"
  local removed=0
  while IFS= read -r -d '' old_dir; do
    _warn "Removing old backup: ${old_dir}"
    rm -rf "$old_dir"
    (( removed++ )) || true
  done < <(find "$DEST_DIR" -maxdepth 1 -type d -name "backup_*" \
             -mtime "+${RETENTION_DAYS}" -print0 2>/dev/null)
  _ok "Removed ${removed} old backup(s)."
}

# ─── Send notification ────────────────────────────────────────────────────────
send_notification() {
  local status="$1"
  [[ -z "$EMAIL" ]] && return

  if command -v msmtp &>/dev/null; then
    local subject="[Backup] ${status} — $(hostname) $(date '+%Y-%m-%d')"
    local body="Backup ${status}\nFiles: ${SUCCESS_COUNT} ok / ${FAIL_COUNT} failed\nArchive: ${ARCHIVE_FILE}"
    printf "Subject: %s\n\n%b" "$subject" "$body" | msmtp "$EMAIL"
    _ok "Email sent to: ${EMAIL}"
  else
    _warn "No mail command found. Install msmtp: sudo apt install msmtp"
  fi
}

# ─── Install cron ─────────────────────────────────────────────────────────────
install_cron() {
  [[ -z "$CRON_SCHEDULE" ]] && return
  local script_path; script_path="$(realpath "$0")"
  local cron_args="-s '${SOURCE_DIR}' -d '${DEST_DIR}' -f '${FILE_FORMATS}' -n '${RETENTION_DAYS}'"
  $ENCRYPT && cron_args+=" -e -p '${PASSPHRASE}'"
  [[ -n "$EMAIL" ]] && cron_args+=" --email '${EMAIL}'"
  local cron_line="${CRON_SCHEDULE} bash ${script_path} ${cron_args} >> /tmp/backup_cron.log 2>&1"
  ( crontab -l 2>/dev/null | grep -v "$script_path"; echo "$cron_line" ) | crontab -
  _ok "Cron job installed: ${cron_line}"
}

# ═════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═════════════════════════════════════════════════════════════════════════════
main() {
  banner
  parse_args "$@"
  prompt_missing
  validate_inputs

  # Initialise runtime globals
  TIMESTAMP=$(date +"%Y_%m_%d_%H_%M_%S")
  BACKUP_WORK_DIR="${DEST_DIR}/backup_${TIMESTAMP}"
  MANIFEST_FILE="${BACKUP_WORK_DIR}/backup_manifest.txt"
  ARCHIVE_FILE="${BACKUP_WORK_DIR}/backup_${TIMESTAMP}.tar.gz"

  mkdir -p "$BACKUP_WORK_DIR"
  _log "Backup working directory: ${BACKUP_WORK_DIR}"

  local log_file="${BACKUP_WORK_DIR}/backup.log"
  local start_epoch; start_epoch=$(date +%s)
  local start_time;  start_time=$(date '+%Y-%m-%d %H:%M:%S')

  # 1. Build manifest
  build_manifest

  # 2. Compress files
  compress_files

  # 3. Optional encryption
  $ENCRYPT && encrypt_archive

  # 4. Write report
  local end_epoch; end_epoch=$(date +%s)
  local duration=$(( end_epoch - start_epoch ))
  local status="SUCCESS"
  [[ "$FAIL_COUNT" -gt 0 ]] && status="PARTIAL (${FAIL_COUNT} file(s) failed)"
  write_log "$log_file" "$status" "$start_time" "$duration"

  # 5. Cleanup old backups
  cleanup_old_backups

  # 6. Notifications
  send_notification "$status"

  # 7. Install cron if requested
  install_cron

  echo
  echo -e "${BOLD}${GREEN}══════════════════════════════════════════${RESET}"
  echo -e "${BOLD}${GREEN}  ✅ Backup complete in ${duration}s              ${RESET}"
  echo -e "${BOLD}${GREEN}  📦 Archive : ${ARCHIVE_FILE}${RESET}"
  echo -e "${BOLD}${GREEN}  📋 Log     : ${log_file}${RESET}"
  echo -e "${BOLD}${GREEN}══════════════════════════════════════════${RESET}"
}

main "$@"

