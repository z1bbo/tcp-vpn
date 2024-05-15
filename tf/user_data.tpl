#!/bin/bash
echo "Installing OpenVPN, AWS CLI, and Easy-RSA..."
apt-get update
apt-get install -y openvpn awscli easy-rsa

if [ $? -ne 0 ]; then
  echo "Failed to install OpenVPN, AWS CLI, and Easy-RSA."
  exit 1
fi

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
if [ -z "$INSTANCE_ID" ]; then
 echo "Failed to retrieve instance ID."
 exit 1
fi

echo "Exporting AWS_DEFAULT_REGION=${aws_region}"
export AWS_DEFAULT_REGION=${aws_region}
echo "Associating Elastic IP with instance ID: $INSTANCE_ID..."
aws ec2 associate-address --instance-id $INSTANCE_ID --public-ip ${eip_public_ip}

if [ $? -ne 0 ]; then
 echo "Failed to associate Elastic IP."
 exit 1
fi

CERT_DIR="/etc/openvpn"
echo "Checking if the certificates exist in Secrets Manager..."
if aws secretsmanager describe-secret --secret-id vpn_certs > /dev/null 2>&1; then
  echo "Certificates exist in Secrets Manager. Retrieving them..."
  aws secretsmanager get-secret-value --secret-id vpn_certs --query SecretBinary --output text | base64 --decode | tar -xz -C /etc/openvpn/
else
  echo "Certificates do not exist in Secrets Manager. Generating and storing them..."
  # Create a temporary directory for Easy-RSA
  EASY_RSA_DIR=$(mktemp -d --dry-run)
  make-cadir $EASY_RSA_DIR
  cd $EASY_RSA_DIR

  # Initialize the PKI
  ./easyrsa init-pki

  # Build the CA
  ./easyrsa --batch build-ca nopass

  # Generate server and client certificates and keys
  ./easyrsa --batch build-server-full server nopass
  ./easyrsa --batch build-client-full client nopass

  # Move certificates to the required location
  mkdir -p $CERT_DIR
  cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/issued/client.crt pki/private/client.key $CERT_DIR
  
	cd $CERT_DIR
  # tls-crypt.key to encrypt the handshake
  openvpn --genkey secret /etc/openvpn/tls-crypt.key

  # Bundle certificates and keys into a tar archive
  tar -czf vpn_certs.tar.gz -C $CERT_DIR ca.crt server.crt server.key client.crt client.key tls-crypt.key

  # Store the bundled certificates and keys in AWS Secrets Manager
  aws secretsmanager create-secret --name vpn_certs --secret-binary fileb://vpn_certs.tar.gz

  # Clean up
  rm -rf $EASY_RSA_DIR vpn_certs.tar.gz

  echo "Certificates generated and stored in Secrets Manager."
fi

# grant capability to bind to privileged ports & call on reboot
setcap CAP_NET_BIND_SERVICE=+eip /usr/sbin/openvpn
echo "setcap CAP_NET_BIND_SERVICE=+eip /usr/sbin/openvpn" >> /etc/rc.local

# block ipv6
echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf

# block ipv6 DNS
ip6tables -A OUTPUT -p tcp --dport 53 -j DROP
ip6tables -A OUTPUT -p udp --dport 53 -j DROP

# enable ip forwarding
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

# Masquerade the client IP with the server IP
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# setup dnsmasq to serve DNS queries
echo "listen-address=10.8.0.1" >> /etc/dnsmasq.conf
echo "port=5353" >> /etc/dnsmasq.conf
DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dnsmasq

# route DNS traffic to port 5353 where dnsmasq runs
iptables -t nat -A PREROUTING -i tun0 -p udp --dport 53 -j REDIRECT --to-port 5353
iptables -t nat -A PREROUTING -i tun0 -p tcp --dport 53 -j REDIRECT --to-port 5353

# forward server ip instead of client ip
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf

# store and apply on reboot
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent netfilter-persistent

netfilter-persistent save
ip6tables-save > /etc/iptables/rules.v6

# old way:
# mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4
# echo "iptables-restore < /etc/iptables/rules.v4" >> /etc/rc.local

echo "Creating server configuration file..."
echo "
port 443
proto tcp-server
server 10.8.0.0 255.255.255.0
dev tun
ca /etc/openvpn/ca.crt
cert /etc/openvpn/server.crt
key /etc/openvpn/server.key
dh none
tls-crypt /etc/openvpn/tls-crypt.key
cipher AES-256-CBC
data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC
keepalive 15 120
ping-timer-rem
persist-tun
persist-key
user ubuntu
group ubuntu
push \"dhcp-option DNS 10.8.0.1\"
push \"redirect-gateway def1\"
keepalive 10 120
daemon" > /etc/openvpn/server.conf

echo "Enabling and starting OpenVPN service..."
systemctl enable openvpn@server
systemctl start openvpn@server

if [ $? -ne 0 ]; then
  echo "Failed to start OpenVPN service."
  exit 1
fi

# Apply sysctl changes
sysctl -p

# Let's run a script every minute to make sure the service is up
echo '#!/bin/bash
service_status=$(systemctl is-active openvpn@server)
port_status=$(ss -tuln | grep ^tcp.*:443)
if [[ "$service_status" != "active" ]] || [[ -z "$port_status" ]]; then
  systemctl start openvpn@server
fi' > /usr/local/bin/check_openvpn.sh

chmod +x /usr/local/bin/check_openvpn.sh

# start cron 2 minutes after startup
(
  sleep 120
  echo "* * * * * root /usr/local/bin/check_openvpn.sh" >> /etc/crontab
  systemctl restart cron
) &

echo "Script execution completed successfully."

