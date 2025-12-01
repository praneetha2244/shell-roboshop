#!/bin/bash
# cart.sh - robust installer for roboshop cart service
# Usage: sudo ./cart.sh
# - Downloads /tmp/cart.zip, verifies it, unpacks to /app
# - Installs nodejs (module stream), npm deps as 'roboshop' user
# - Installs unzip if missing
# - Copies cart.service from script dir to /etc/systemd/system/cart.service
# - Enables & restarts the service

# --- safety / strictness (avoid set -e to keep VALIDATE behavior predictable)
set -u
shopt -s nullglob

USERID=$(id -u)
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

LOGS_FOLDER="/var/log/shell-roboshop"
SCRIPT_NAME=$(basename "$0" | cut -d"." -f1)
SCRIPT_DIR="$PWD"
MONGODB_HOST="mongodb.hhrp.life"
LOG_FILE="$LOGS_FOLDER/$SCRIPT_NAME.log"
APP_DIR="/app"
ZIP_TMP="/tmp/cart.zip"
ZIP_URL="https://roboshop-artifacts.s3.amazonaws.com/cart-v3.zip"
SERVICE_NAME="cart"
SERVICE_FILE="${SERVICE_NAME}.service"

mkdir -p "$LOGS_FOLDER"
touch "$LOG_FILE"
echo "script started executed at: $(date)" | tee -a "$LOG_FILE"

# Trap to print last lines on any error and exit non-zero
failure_trap() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    echo -e "${R}Script failed (exit $rc). Last 100 log lines:${N}" | tee -a "$LOG_FILE"
    tail -n 100 "$LOG_FILE" | sed 's/^/  /' | tee -a "$LOG_FILE"
  fi
  exit $rc
}
trap failure_trap EXIT

if [ "$USERID" -ne 0 ]; then
    echo -e "ERROR:: Please run this script with root privilege" | tee -a "$LOG_FILE"
    exit 1
fi

# VALIDATE: $1 -> exit code, $2 -> message
VALIDATE() {
    if [ "$1" -ne 0 ]; then
        echo -e " $2 ... ${R}FAILURE${N}" | tee -a "$LOG_FILE"
        return 1
    else
        echo -e " $2 ... ${G}SUCCESS${N}" | tee -a "$LOG_FILE"
        return 0
    fi
}

# Helper: ensure command is present, install if possible
ensure_cmd() {
  local cmd="$1"
  local pkg="$2" # optional package name
  if command -v "$cmd" &>/dev/null; then
    echo "$cmd found" >>"$LOG_FILE"
    return 0
  fi
  echo "$cmd not found — attempting to install" | tee -a "$LOG_FILE"
  if command -v dnf &>/dev/null; then
    dnf install -y "${pkg:-$cmd}" &>>"$LOG_FILE"
    VALIDATE $? "Installing $pkg (dnf)"
    return $?
  elif command -v yum &>/dev/null; then
    yum install -y "${pkg:-$cmd}" &>>"$LOG_FILE"
    VALIDATE $? "Installing $pkg (yum)"
    return $?
  else
    echo "No package manager found to install $cmd" | tee -a "$LOG_FILE"
    return 1
  fi
}

#### NodeJS install (dnf module stream approach)
dnf module disable nodejs -y &>>"$LOG_FILE"
VALIDATE $? "Disabling NodeJS"

dnf module enable nodejs:20 -y &>>"$LOG_FILE"
VALIDATE $? "Enabling NodeJS 20"

dnf install nodejs -y &>>"$LOG_FILE"
VALIDATE $? "Installing NodeJS"

# Create roboshop system user if not present
id roboshop &>>"$LOG_FILE"
if [ $? -ne 0 ]; then
    useradd --system --home "$APP_DIR" --shell /sbin/nologin --comment "roboshop system user" roboshop &>>"$LOG_FILE"
    VALIDATE $? "Creating system user 'roboshop'"
else
    echo -e " user already exists ... ${Y}SKIPPING${N}" | tee -a "$LOG_FILE"
fi

# Ensure /app directory exists and owned by roboshop
mkdir -p "$APP_DIR"
VALIDATE $? "Creating $APP_DIR directory"

chown roboshop:roboshop "$APP_DIR" -R &>>"$LOG_FILE"
VALIDATE $? "Setting ownership of $APP_DIR"

# Ensure dependencies for download/unpack exist
ensure_cmd curl curl || exit 1
ensure_cmd unzip unzip || exit 1
ensure_cmd sudo sudo || true  # sudo may already be present; not fatal if missing

# Download with retries
download_zip() {
  local tries=0
  local max_tries=3
  rm -f "$ZIP_TMP"
  while [ $tries -lt $max_tries ]; do
    tries=$((tries+1))
    echo "Attempt $tries to download $ZIP_URL" | tee -a "$LOG_FILE"
    curl -sSL --retry 2 --retry-delay 3 -o "$ZIP_TMP" "$ZIP_URL" &>>"$LOG_FILE"
    if [ -s "$ZIP_TMP" ]; then
      echo "Download succeeded on try $tries" >>"$LOG_FILE"
      return 0
    fi
    echo "Download failed on try $tries" | tee -a "$LOG_FILE"
    sleep 2
  done
  return 1
}

download_zip
VALIDATE $? "Downloading cart application"

# Validate zip file
if [ ! -s "$ZIP_TMP" ]; then
  echo -e " $ZIP_TMP is missing or empty. ${R}FAILURE${N}" | tee -a "$LOG_FILE"
  ls -lh "$ZIP_TMP" >>"$LOG_FILE" 2>&1 || true
  file "$ZIP_TMP" >>"$LOG_FILE" 2>&1 || true
  exit 1
fi

unzip -t "$ZIP_TMP" &>>"$LOG_FILE"
if [ $? -ne 0 ]; then
  echo -e " $ZIP_TMP failed integrity test. ${R}FAILURE${N}" | tee -a "$LOG_FILE"
  file "$ZIP_TMP" >>"$LOG_FILE" 2>&1 || true
  exit 1
fi
VALIDATE $? "Zip integrity test"

# Move to app dir and clean safely
cd "$APP_DIR" || exit 1
VALIDATE $? "Changing to app directory ($APP_DIR)"

# Remove existing files safely but avoid deleting important system files by mistake
# This removes all non-hidden and hidden files (careful in production)
rm -rf "$APP_DIR"/* "$APP_DIR"/.[!.]* 2>/dev/null || true
VALIDATE $? "Removing existing code in $APP_DIR"

# Unpack zip into /app
unzip -o "$ZIP_TMP" -d "$APP_DIR" &>>"$LOG_FILE"
VALIDATE $? "Unzip cart application"

# Ensure ownership of unpacked content
chown -R roboshop:roboshop "$APP_DIR" &>>"$LOG_FILE"
VALIDATE $? "Set ownership for unpacked files"

# Install node modules as roboshop user
if id roboshop &>/dev/null; then
  sudo -u roboshop bash -c "cd '$APP_DIR' && npm install --silent" &>>"$LOG_FILE"
  VALIDATE $? "Install npm dependencies as roboshop"
else
  npm --prefix "$APP_DIR" install --silent &>>"$LOG_FILE"
  VALIDATE $? "Install npm dependencies (fallback)"
fi

# Copy systemd service file (expect cart.service present in script dir)
if [ -f "$SCRIPT_DIR/$SERVICE_FILE" ]; then
  cp "$SCRIPT_DIR/$SERVICE_FILE" "/etc/systemd/system/$SERVICE_FILE"
  VALIDATE $? "Copy systemd service file ($SERVICE_FILE)"
else
  echo -e " $SCRIPT_DIR/$SERVICE_FILE not found. ${R}FAILURE${N}" | tee -a "$LOG_FILE"
  exit 1
fi

systemctl daemon-reload &>>"$LOG_FILE"
VALIDATE $? "systemd daemon-reload"

systemctl enable "$SERVICE_NAME" &>>"$LOG_FILE"
VALIDATE $? "Enable $SERVICE_NAME service"

systemctl restart "$SERVICE_NAME" &>>"$LOG_FILE"
VALIDATE $? "Restart $SERVICE_NAME service"

echo -e "\nAll steps completed successfully." | tee -a "$LOG_FILE"

# clear trap and exit 0
trap - EXIT
exit 0
