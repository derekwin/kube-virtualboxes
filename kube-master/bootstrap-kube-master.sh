#!/bin/bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install ca-certificates software-properties-common apt-transport-https curl gnupg lsb-release -y

sudo hostnamectl set-hostname "$(hostname -I | awk '{print $2}')"
sudo swapoff -a && sudo sed -i 's/\/swap/#\/swap/g' /etc/fstab

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

sudo apt-get update
sudo apt-get install -y docker.io
sudo apt-mark hold docker.io

sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

sudo mkdir -p /etc/systemd/system/docker.service.d
sudo systemctl daemon-reload
sudo systemctl restart docker

sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address 192.168.33.10 | tee /kubeadm.log

mkdir -p /root/.kube
sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
sudo chown "$(id -u):$(id -g)" /root/.kube/config

echo "net.bridge.bridge-nf-call-iptables=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

sudo rm -rf /root/.kube

# Config for vagrant user
mkdir -p /home/vagrant/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo chown -R "vagrant:vagrant" /home/vagrant/.kube/
