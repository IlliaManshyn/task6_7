#!bin/bash

dir="$(cd "$(dirname "$0")" && pwd)"

source $dir/vm2.conf

ifconfig $INTERNAL_IF $INTERNAL_IP
route add default gw $GW_IP

ip link add link $INTERNAL_IF name  $INTERNAL_IF.$VLAN type vlan id $VLAN
ifconfig $INTERNAL_IF.$VLAN $APACHE_VLAN_IP

route add -net 0.0.0.0 netmask 0.0.0.0 gw $GW_IP $INTERNAL_IF
echo "nameserver 8.8.8.8" > /etc/resolv.conf

sysctl -w net.ipv4.ip_forward=1

CHECK=$(dpkg -s apache2 | grep -o "install ok installed")
TEXT="install ok installed"

if [ "$CHECK" != "$TEXT" ]
then
apt-get install apache2 -y
fi

APACHE_IP=$(echo $APACHE_VLAN_IP | cut -d '/' -f1 )

cat $dir/apache2.conf | grep -v "#" | sed 's/APACHE_VLAN_IP/'$APACHE_IP'/' > /etc/apache2/apache2.conf

cat $dir/site1_apache.conf | sed 's/SERVER_NAME/'$HOSTNAME'/' | sed 's/VLAN_IP/'$APACHE_IP'/' > /etc/apache2/sites-available/site1.conf

a2ensite site1.conf

service apache2 restart

