#!/bin/bash

set -u

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

mkdir -p "$LOGS_FOLDER"
echo "script started executed at: $(date)" | tee -a "$LOG_FILE"

if [ "$USERID" -ne 0 ]; then
    echo -e "ERROR:: Please run this script with root privilege" | tee -a "$LOG_FILE"
    exit 1
fi

# VALIDATE: $1 -> exit code, $2 -> message
VALIDATE() {
    if [ "$1" -ne 0 ]; then
        echo -e " $2 ... ${R}FAILURE${N}" | tee -a "$LOG_FILE"
        exit 1
    else
        echo -e " $2 ... ${G}SUCCESS${N}" | tee -a "$LOG_FILE"
    fi
}

#### Node JS ###

dnf module disable nodejs -y &>>"$LOG_FILE"
VALIDATE $? "Disabling NodeJS"

dnf module enable nodejs:20 -y &>>"$LOG_FILE"
VALIDATE $? "Enabling NodeJS 20"

dnf install nodejs -y &>>"$LOG_FILE"
VALIDATE $? "Installing NodeJS"

# Create roboshop system user if not present
id roboshop &>>"$LOG_FILE"
if [ $? -ne 0 ]; then
    useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop &>>"$LOG_FILE"
    VALIDATE $? "Creating system user 'roboshop'"
else
    echo -e " user already exists ... ${Y}SKIPPING${N}" | tee -a "$LOG_FILE"
fi

# Ensure /app exists and owned by roboshop
mkdir -p /app
VALIDATE $? "Creating /app directory"

chown roboshop:roboshop /app -R &>>"$LOG_FILE"
VALIDATE $? "Set ownership of /app"

# Download cart application zip
curl -sL -o /tmp/cart.zip "https://roboshop-artifacts.s3.amazonaws.com/cart-v3.zip" &>>"$LOG_FILE"
VALIDATE $? "Downloading cart application"

cd /app
VALIDATE $? "Changing to /app directory"

# Remove existing code (careful: this deletes files in /app)
rm -rf /app/* /app/.[!.]* 2>/dev/null || true
VALIDATE $? "Removing existing code"

# Unpack cart.zip into /app
unzip -o /tmp/cart.zip -d /app &>>"$LOG_FILE"
VALIDATE $? "Unzip cart application"

# Install node modules as roboshop user
sudo -u roboshop bash -c "cd /app && npm install --silent" &>>"$LOG_FILE"
VALIDATE $? "Install dependencies"

# Copy systemd service file (expect cart.service in script dir)
if [ -f "$SCRIPT_DIR/cart.service" ]; then
    cp "$SCRIPT_DIR/cart.service" /etc/systemd/system/cart.service
    VALIDATE $? "Copy systemd service file (cart.service)"
else
    echo -e " cart.service not found in $SCRIPT_DIR ... ${R}FAILURE${N}" | tee -a "$LOG_FILE"
    exit 1
fi

systemctl daemon-reload &>>"$LOG_FILE"
VALIDATE $? "systemd daemon-reload"

systemctl enable cart &>>"$LOG_FILE"
VALIDATE $? "Enable cart service"

systemctl restart cart &>>"$LOG_FILE"
VALIDATE $? "Restart cart service"

echo -e "\nAll steps completed successfully." | tee -a "$LOG_FILE"
