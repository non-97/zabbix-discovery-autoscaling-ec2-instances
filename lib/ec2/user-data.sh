#!/bin/bash

set -ue

# Redirect /var/log/user-data.log and /dev/console
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

declare -r max_retry_interval=8
declare -r max_retries=16
declare -r hostname_prefix=web-
declare -r hostname_domain=corp.non-97.net
declare -r filter_tag_key=aws:autoscaling:groupName
declare -r filter_tag_value=asg

# Get my instance ID
token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
instance_id=$(curl -s -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254/latest/meta-data/instance-id")

for i in $(seq 1 $max_retries); do
  echo "======================================================="

  hostname_list=($(aws ec2 describe-instances \
    --filters Name=tag:$filter_tag_key,Values=$filter_tag_value \
      Name=instance-state-code,Values=0,16 \
    --query "Reservations[].Instances[].[Tags[?Key=='HostName'].Value][]" \
    --output text \
    | grep $hostname_prefix \
    | sort -n
  ))

  # Initialize the expected next number to 1
  candidate_hostname_number="1"
  
  for hostname in "${hostname_list[@]}"; do
    hostname_number=$(echo $hostname | grep -o -E '[0-9]+$')
    
    echo "--------------------------------------------------"
    echo candidate_hostname_number : $candidate_hostname_number
    echo hostname : $hostname
    echo hostname_number : $hostname_number
  
    if [[ $((10#$hostname_number)) -ne $candidate_hostname_number ]]; then
      break
    fi
    candidate_hostname_number=$(($candidate_hostname_number+1))
  done
  
  candidate_hostname=$(printf "%s%02d" $hostname_prefix $candidate_hostname_number)
  echo "--------------------------------------------------"
  echo candidate_hostname : $candidate_hostname

  # Set HostName tag
  aws ec2 create-tags \
    --resources $instance_id \
    --tags Key=HostName,Value=$candidate_hostname

  # Get sorted instance IDs with HostName tag
  instance_ids=($(aws ec2 describe-instances \
    --filters Name=tag:$filter_tag_key,Values=$filter_tag_value \
      Name=tag:HostName,Values=$candidate_hostname \
      Name=instance-state-code,Values=0,16 \
    --query "Reservations[].Instances[].[InstanceId]" \
    --output text
  ))
  
  echo "--------------------------------------------------"

  # Check if the instance itself is the only one holding the hostname
  if [[ "${instance_ids[0]}" == "$instance_id" && "${#instance_ids[@]}" == 1 ]]; then
    # Set OS hostname and break the loop
    echo "Set HostName ${candidate_hostname}.${hostname_domain}"
    hostnamectl set-hostname "${candidate_hostname}.${hostname_domain}"
    
    echo "hostnamectl :
      $(hostnamectl)"
    break
  else
    # Remove the HostName tag and retry
    aws ec2 delete-tags \
      --resources $instance_id \
      --tags Key=HostName

    retry_interval=$(($RANDOM % $max_retry_interval))

    echo "Failed to allocate hostname $candidate_hostname, retrying in $retry_interval seconds..."
    sleep $retry_interval
  fi
done

# If the loop exhausted retries, fail and suggest manual assignment
if [[ $i == $max_retries ]]; then
  echo "Failed to allocate a unique hostname after $max_retries retries. Please manually assign a hostname."
fi