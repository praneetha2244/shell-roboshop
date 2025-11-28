!/bin/bash

USERID=$(id -u)
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

LOGS_FOLDER="/var/log/shell-roboshop"
SCRIPT_NAME=$( echo $0 | cut -d "." -f1 )
LOG_FILE="$LOGS_FOLDER/$SCRIPT_NAME.log"
START_TIME=(date +%s)
mkdir -p $LOGS_FOLDER
SCRIPT_DIR=$(PWD)
echo "script started executed at: $(date)" | tee -a $LOG_FILE

if [ $USERID -ne 0 ]; then
    echo "ERROR:: Please run this script with root privelege"
    exit 1 # failure is other than 0    
fi

VALIDATE(){ # functions receive inputs through args just like shell script args}

if [ $? -ne 0 ]; then
    echo -e " $2 ... $R FAILURE $N" | tee -a $LOG_FILE
    exit 1
    
else
    echo -e " $2 ... $G is SUCCESS $N" | tee -a $LOG_FILE
fi   
} 

cp $SCRIPT_DIR/rabbitmq.repo /etc/yum.repos.d/rabbitmq.repo
VALIDATE $? "Adding RabbitMQ repo"
dnf install rabbitmq-server -y
VALIDATE $? "Installing RabbitMQ Server"
systemctl enable rabbitmq-server
VALIDATE $? "Eanableing RabbitMQ Server"
systemctl start rabbitmq-server
VALIDATE $? "Starting RabbitMQ"
rabbitmqctl add_user roboshop roboshop123
rabbitmqctl set_permissions -p / roboshop ".*" ".*" ".*"
VALIDATE $? "Setting up permissions"



END_TIME=(date +%s)
TOTAL_TIME=$(( $END_TIME -$START_TIME))
echo -e "Script executed in: $Y $TOTAL_TIME seconds $N"