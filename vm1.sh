#!bin/bash

dir="$(cd "$(dirname "$0")" && pwd)"
source $dir/vm1.conf
if  [[ $EXT_IP -eq "DHCP" ]]
then
dhclient "$EXTERNAL_IF"
else
ifconfig $EXTERNAL_IF  $EXT_IP
route add default gw $EXT_GW
echo "nameserver 8.8.8.8" > /etc/resolv.conf
fi

ifconfig $INTERNAL_IF $INT_IP

ip link add link $INTERNAL_IF name $INTERNAL_IF.$VLAN type vlan id $VLAN

ifconfig $INTERNAL_IF.$VLAN $VLAN_IP

sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -o $EXTERNAL_IF -j MASQUERADE
iptables -A FORWARD -i $EXTERNAL_IF -o $INTERNAL_IF -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $INTERNAL_IF -o $EXTERNAL_IF -j ACCEPT

CHECK=$(dpkg -s nginx | grep -o "install ok installed")
TEXT="install ok installed"

if [ "$CHECK" != "$TEXT" ]
then
apt-get install nginx -y
fi

EXTERNAL_INT_IP=$(ip -br address show $EXTERNAL_IF | sed 's/\s\+/,/g' | cut -d ',' -f3 | cut -d '/' -f1)

cd /etc/ssl/certs
openssl req -newkey rsa:2048 -nodes -keyout privateCA.key \
-subj /C=UA/O=Mirantis/CN=$HOSTNAME/emailAddress=. -out CA_csr.csr
cd /etc/ssl/certs
openssl x509 -signkey privateCA.key -in CA_csr.csr \
-req -days 365 -out root-ca.crt
cd /etc/ssl/certs
openssl genrsa -out nginx.web.key 2048
cd /etc/ssl/certs
openssl req -new -key nginx.web.key \
-subj /C=UA/O=Mirantis/CN=$HOSTNAME/emailAddress=.  -out nginx.web.csr
if [ "$EXT_IP" == DHCP ]
then
cd /etc/ssl/certs
openssl x509 -req \
-extfile <(printf "subjectAltName=IP:$EXTERNAL_INT_IP,DNS:$HOSTNAME") -days 365\
 -in nginx.web.csr -CA root-ca.crt\
 -CAkey privateCA.key -CAcreateserial -out web.crt
else
cd /etc/ssl/certs
openssl x509 -req \
-extfile <(printf "subjectAltName=IP:$EXT_IP,DNS:$HOSTNAME") -days 365\
 -in nginx.web.csr -CA root-ca.crt\
 -CAkey privateCA.key -CAcreateserial -out web.crt
fi
cat /etc/ssl/certs/web.crt /etc/ssl/certs/root-ca.crt > /etc/ssl/certs/web.pem

cat $dir/site1.conf | sed 's/SERVER_NAME/'$HOSTNAME'/'| sed 's/APACHE_VLAN_IP/'$APACHE_VLAN_IP'/g'| sed 's/NGINX_PORT/'$NGINX_PORT'/' | sed 's/EXTERNAL_INT_IP/'$EXTERNAL_INT_IP'/g' | sed 's/SERVER_NAME/'$HOSTNAME'/' > /etc/nginx/conf.d/site1.conf

service nginx restart

