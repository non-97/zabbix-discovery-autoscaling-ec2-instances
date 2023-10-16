#!/bin/bash

set -xue

# Redirect /var/log/user-data.log and /dev/console
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# Install SSM Agent
token=$(curl \
  -s \
  -X PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
  "http://169.254.169.254/latest/api/token"
)
region_name=$(curl \
  -s \
  -H "X-aws-ec2-metadata-token: $token" \
  "http://169.254.169.254/latest/meta-data/placement/availability-zone" \
  | sed -e 's/.$//'
)

dnf install -y "https://s3.${region_name}.amazonaws.com/amazon-ssm-${region_name}/latest/linux_amd64/amazon-ssm-agent.rpm"
systemctl enable --now amazon-ssm-agent

# Install Zabbix Server
rpm -Uvh https://repo.zabbix.com/zabbix/6.4/rhel/9/x86_64/zabbix-release-6.4-1.el9.noarch.rpm
dnf clean all
dnf install -y \
  zabbix-server-pgsql \
  zabbix-web-pgsql \
  zabbix-nginx-conf \
  zabbix-sql-scripts \
  zabbix-selinux-policy \
  zabbix-agent

# Install PostgreSQL
dnf module install -y postgresql:15/server

# Setting PostgreSQL
postgresql-setup --initdb
sed -i '/^host.*all.*all.*ident$/s/ident/scram-sha-256/' /var/lib/pgsql/data/pg_hba.conf

systemctl enable --now postgresql

cd /tmp/
sudo -u postgres psql -c "CREATE USER zabbix WITH PASSWORD 'zabbixDbP@ssw0rd';"
sudo -u postgres createdb -O zabbix zabbix

zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz \
  | sudo -u zabbix psql zabbix \
  > /dev/null

# Zabbix Server DB Password
sed -i 's/^# DBPassword=.*/DBPassword=zabbixDbP@ssw0rd/' /etc/zabbix/zabbix_server.conf

# Setting Nginx
sed -i 's/#\(.*listen.*8080;\)/\1/' /etc/nginx/conf.d/zabbix.conf
sed -i 's/#\(.*server_name\).*/\1\tzabbix.non-97.net;/' /etc/nginx/conf.d/zabbix.conf

systemctl enable --now \
  zabbix-server \
  zabbix-agent \
  nginx php-fpm

