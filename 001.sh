#!/bin/bash
set -euo pipefail

AMI_ID="ami-09c813fb71547fc4f"
SG_ID="sg-037ea79c954371756"
FRONTEND_SG="sg-07c8acf3fa6b923fa"
REGION="us-east-1"

if [ $# -eq 0 ]; then
  echo "Usage: $0 component [component ...]"
  exit 1
fi

for instance in "$@"; do
  # choose SG for frontend vs others
  if [ "$instance" = "frontend" ]; then
    USE_SG="$FRONTEND_SG"
  else
    USE_SG="$SG_ID"
  fi

  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type t3.micro \
    --security-group-ids "$USE_SG" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance}]" \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$REGION")

  echo "Launched $instance -> $INSTANCE_ID"

  # wait until running, then get IP
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
  IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text \
    --region "$REGION")

  echo "$instance: $IP"
done
