#!/bin/bash

# Colors
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

LOGS_FOLDER="/var/log/shell-roboshop"
SCRIPT_NAME=$(basename "$0" .sh)
SCRIPT_DIR=$(dirname "$(realpath "$0")")
MONGODB_HOST="mongodb.hhrp.life"   # fixed variable name (no trailing underscore)
LOG_FILE="$LOGS_FOLDER/${SCRIPT_NAME}.log"

mkdir -p "$LOGS_FOLDER"
echo -e "script started executed at: $(date)" | tee -a "$LOG_FILE"

# must run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${R}ERROR:: Please run this script with root privilege${N}" | tee -a "$LOG_FILE"
    exit 1
fi

# Validation helper: pass exit code as $1 and description as $2
VALIDATE() {
    if [ "$1" -ne 0 ]; then
        echo -e " $2 ... ${R}FAILURE${N}" | tee -a "$LOG_FILE"
        exit 1
    else
        echo -e " $2 ... ${G}SUCCESS${N}" | tee -a "$LOG_FILE"
    fi
}

# Ensure unzip is present (used later)
dnf install -y unzip &>>"$LOG_FILE"
VALIDATE $? "Install unzip (prerequisite)"

# NodeJS setup
dnf module disable nodejs -y &>>"$LOG_FILE"
VALIDATE $? "Disabling NodeJS"
dnf module enable nodejs:20 -y &>>"$LOG_FILE"
VALIDATE $? "Enabling NodeJS 20"
dnf install -y nodejs &>>"$LOG_FILE"
VALIDATE $? "Installing NodeJS"

# Create system user if not exists
if ! id roboshop &>/dev/null; then
    useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop &>>"$LOG_FILE"
    VALIDATE $? "Creating system user"
else
    echo "system user 'roboshop' already exists" | tee -a "$LOG_FILE"
fi

# App dir
mkdir -p /app
VALIDATE $? "Creating app directory"

# Download & unpack app
curl -s -o /tmp/catalogue.zip "https://roboshop-artifacts.s3.amazonaws.com/catalogue-v3.zip" &>>"$LOG_FILE"
VALIDATE $? "Downloading catalogue application"

cd /app || { echo "Failed to cd /app" | tee -a "$LOG_FILE"; exit 1; }
VALIDATE $? "Changing to app directory"

unzip -o /tmp/catalogue.zip &>>"$LOG_FILE"
VALIDATE $? "Unzip catalogue"

# Install node deps
npm install --prefix /app &>>"$LOG_FILE"
VALIDATE $? "Install dependencies"

# Copy systemd service (ensure path)
if [ -f "$SCRIPT_DIR/catalogue.service" ]; then
    cp "$SCRIPT_DIR/catalogue.service" /etc/systemd/system/catalogue.service &>>"$LOG_FILE"
    VALIDATE $? "Copy systemctl service"
else
    echo "WARN: $SCRIPT_DIR/catalogue.service not found" | tee -a "$LOG_FILE"
fi

systemctl daemon-reload &>>"$LOG_FILE"
systemctl enable catalogue &>>"$LOG_FILE"
VALIDATE $? "Enable catalogue"

# MongoDB repo & client
if [ -f "$SCRIPT_DIR/mongo.repo" ]; then
    cp "$SCRIPT_DIR/mongo.repo" /etc/yum.repos.d/mongo.repo &>>"$LOG_FILE"
    VALIDATE $? "copy mongo repo"
else
    echo "WARN: $SCRIPT_DIR/mongo.repo not found; skipping repo copy" | tee -a "$LOG_FILE"
fi

dnf install -y mongodb-mongosh &>>"$LOG_FILE"
VALIDATE $? "Install MongoDB client"

# Load DB data (ensure file exists)
if [ -f /app/db/master-data.js ]; then
    mongosh --host "$MONGODB_HOST" </app/db/master-data.js &>>"$LOG_FILE"
    VALIDATE $? "Load catalogue products"
else
    echo "WARN: /app/db/master-data.js not found; skipping DB load" | tee -a "$LOG_FILE"
fi

systemctl restart catalogue &>>"$LOG_FILE"
VALIDATE $? "Restarted catalogue"

echo -e "${G}Script completed at: $(date)${N}" | tee -a "$LOG_FILE"
