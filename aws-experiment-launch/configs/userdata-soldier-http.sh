#!/bin/bash

mkdir -p /home/ec2-user
cd /home/ec2-user

BUCKET=unique-bucket-bin
FOLDER=leo/

TESTBIN=( txgen soldier benchmark commander go-commander.sh )

for bin in "${TESTBIN[@]}"; do
   curl http://${BUCKET}.s3.amazonaws.com/${FOLDER}${bin} -o ${bin}
   chmod +x ${bin}
done

sysctl -w net.core.somaxconn=1024
sysctl -w net.core.netdev_max_backlog=65536
sysctl -w net.ipv4.tcp_tw_reuse=1
sysctl -w net.ipv4.tcp_rmem='4096 65536 16777216'
sysctl -w net.ipv4.tcp_wmem='4096 65536 16777216'
sysctl -w net.ipv4.tcp_mem='65536 131072 262144'

echo "* soft     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "* hard     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "* soft     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "* hard     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "root soft     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "root hard     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "root soft     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "root hard     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "session required pam_limits.so" | sudo tee -a /etc/pam.d/common-session

get_vm_flavor() {
	local resp
	if \
		resp=$(curl -s -H 'Metadata-Flavor: Google' -o /dev/null -w '%{http_code}' 'http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip') && \
		[ "X${resp}" = "X200" ]
	then
		echo "gcp"
	elif
		resp=$(curl -s -I http://169.254.169.254/latest/meta-data/instance-type -o /dev/null -w "%{http_code}") && \
		[ "X${resp}" = "X200" ]
	then
		echo "aws"
	elif
		resp=$(curl -s -H Metadata:true -o /dev/null -w "%{http_code}" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-04-02&format=text") && \
		[ "X${resp}" = "X200" ]
	then
		echo "azure"
	fi
}

case $(get_vm_flavor) in
aws)
	PUB_IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
	;;
azure)
	PUB_IP=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-04-02&format=text")
	;;
gcp)
	PUB_IP=$(curl -s -H 'Metadata-Flavor: Google' 'http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip')
	yum install -y psmisc	# for fuser
	;;
*)
	echo "ERROR: unknown VM flavor.  Instance is unusable."
	exit
	;;
esac

NODE_PORT=9000
SOLDIER_PORT=1$NODE_PORT

# Kill existing soldier/node
fuser -k -n tcp $SOLDIER_PORT
fuser -k -n tcp $NODE_PORT

# Run soldier
./soldier -ip $PUB_IP -port $NODE_PORT -http > soldier-${PUB_IP}.log 2>&1 &
