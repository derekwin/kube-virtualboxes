iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
systemctl stop kubelet
systemctl stop docker
rm -rf /var/lib/cni/*
rm -rf /var/lib/kubelet/*
rm -rf /etc/cni/*
ifconfig cni0 down
ifconfig flannel.1 down
ifconfig docker0 down
ip link delete cni0
ip link delete flannel.1
sudo systemctl daemon-reload
systemctl start kubelet
systemctl start docker