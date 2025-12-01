#!/bin/bash

USERID=$(id -u)
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

LOGS_FOLDER="/var/log/shell-roboshop"
# Use the script filename (without extension) as log name
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

# VALIDATE takes two args:
#   $1 -> exit code (typically pass $? to it)
#   $2 -> message to print
VALIDATE() {
    if [ "$1" -ne 0 ]; then
        echo -e " $2 ... $R FAILURE $N" | tee -a "$LOG_FILE"
        exit 1
    else
        echo -e " $2 ... $G SUCCESS $N" | tee -a "$LOG_FILE"
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
    echo -e " user already exists ... $Y SKIPPING $N" | tee -a "$LOG_FILE"
fi

# Ensure /app directory exists and owned by roboshop
mkdir -p /app
VALIDATE $? "Creating /app directory"

chown roboshop:roboshop /app -R &>>"$LOG_FILE"
VALIDATE $? "Setting ownership of /app"

# Download the user app zip
curl -sL -o /tmp/user.zip "https://roboshop-artifacts.s3.amazonaws.com/user-v3.zip" &>>"$LOG_FILE"
VALIDATE $? "Downloading user application"

cd /app
VALIDATE $? "Changing to /app directory"

# Remove old app contents safely (but keep dotfiles if needed)
rm -rf /app/* /app/.[!.]* 2>/dev/null || true
VALIDATE $? "Removing existing code"

# Unzip (overwrite) into /app
unzip -o /tmp/user.zip -d /app &>>"$LOG_FILE"
VALIDATE $? "Unzip user application"

# Install node dependencies as roboshop user
# Use npm --production to avoid dev deps if needed; change as required.
sudo -u roboshop bash -c "cd /app && npm install --silent" &>>"$LOG_FILE"
VALIDATE $? "Install dependencies"

# Copy the correct systemd service file. (Ensure service file present in script dir.)
# NOTE: earlier you had catalogue.service copied but the app is 'user' — keep names consistent.
if [ -f "$SCRIPT_DIR/user.service" ]; then
    cp "$SCRIPT_DIR/user.service" /etc/systemd/system/user.service
    VALIDATE $? "Copy systemd service file (user.service)"
else
    echo -e " user.service not found in script directory ($SCRIPT_DIR). $R FAILURE $N" | tee -a "$LOG_FILE"
    exit 1
fi

systemctl daemon-reload &>>"$LOG_FILE"
VALIDATE $? "systemd daemon-reload"

systemctl enable user &>>"$LOG_FILE"
VALIDATE $? "Enable user service"

systemctl restart user &>>"$LOG_FILE"
VALIDATE $? "Restart user service"

echo -e "\nAll steps completed successfully." | tee -a "$LOG_FILE"
