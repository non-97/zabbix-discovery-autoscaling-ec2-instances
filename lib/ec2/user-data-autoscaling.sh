#!/bin/bash

set -u

# Redirect /var/log/user-data.log and /dev/console
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

declare -r max_retry_interval=8
declare -r max_retries=16
declare -r hostname_prefix=__hostname_prefix__
declare -r hostname_domain=__hostname_domain__
declare -r filter_tag_key=__filter_tag_key__
declare -r filter_tag_value=__filter_tag_value__
declare -r hosted_zone_id=__hosted_zone_id__
declare -r zabbix_server_ip=__zabbix_server_ip__

# Get my instance ID
token=$(curl \
  -s \
  -X PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
  "http://169.254.169.254/latest/api/token"
)
instance_id=$(curl \
  -s \
  -H "X-aws-ec2-metadata-token: $token" \
  "http://169.254.169.254/latest/meta-data/instance-id"
)

ip_address=$(curl \
  -s \
  -H "X-aws-ec2-metadata-token: $token" \
  "http://169.254.169.254/latest/meta-data/local-ipv4"
)

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
    hostname="${candidate_hostname}.${hostname_domain}"
    echo "Set HostName ${hostname}"
    hostnamectl set-hostname ${hostname}
    
    echo "hostnamectl :
      $(hostnamectl)"

    rrset_exists=$(dig $hostname +short)

    # Route 53 RRset
    rrset_action=""
    if [[ -z $rrset_exists ]]; then
      rrset_action=CREATE
    else
      rrset_action=UPSERT
    fi

    change_resource_record_sets_input=$(cat <<EOF
    {
      "Changes": [
        {
          "Action": "$rrset_action",
          "ResourceRecordSet": {
            "Name": "${hostname}",
            "Type": "A",
            "TTL": 300,
            "ResourceRecords": [
              {
                "Value": "$ip_address"
              }
            ]
          }
        }
      ]
    }
EOF
)

    aws route53 change-resource-record-sets \
      --hosted-zone-id "$hosted_zone_id" \
      --change-batch "$change_resource_record_sets_input"
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

# Install Zabbix Agent
for i in $(seq 1 $max_retries); do
  rpm -Uvh https://repo.zabbix.com/zabbix/6.4/rhel/9/x86_64/zabbix-release-6.4-1.el9.noarch.rpm
  dnf clean all
  dnf install -y zabbix-agent2

  if [[ $? == 0 ]]; then
    sed -i "s/Server=127.0.0.1/Server=$zabbix_server_ip/g" /etc/zabbix/zabbix_agent2.conf
    systemctl enable --now zabbix-agent2

    break
  else
    retry_interval=$(($RANDOM % $max_retry_interval))

    echo "Failed to install Zabbix Agent, retrying in $retry_interval seconds..."
    sleep $retry_interval
  fi
done

if [[ $i == $max_retries ]]; then
  echo "Failed to install Zabbix Agent after $max_retries retries. Please manually install Zabbix Agent."
fi

