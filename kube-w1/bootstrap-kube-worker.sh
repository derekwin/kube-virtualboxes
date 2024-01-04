#!/bin/bash
whoami
KUBE_VER=$1
HOSTNAME=$2
sudo hostnamectl set-hostname $HOSTNAME
HOST_PRIVATE_IP=$(hostname -I | cut -d ' ' -f2)
printf "Installing K8=$KUBE_VER-00 on $HOSTNAME with IP: $HOST_PRIVATE_IP\n"

# set dns
echo "nameserver 114.114.114.114" | sudo tee /etc/resolv.conf > /dev/null


# add host
### 修改每个机器对应的host ###
echo "192.168.33.10 kube-master" | sudo tee -a /etc/hosts
echo "192.168.33.11 kube-w1" | sudo tee -a /etc/hosts
echo "192.168.33.12 kube-w2" | sudo tee -a /etc/hosts


# install
sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get -y install net-tools iputils-ping ca-certificates software-properties-common apt-transport-https curl gnupg lsb-release
ifconfig


# install docker : https://docs.docker.com/engine/install/ubuntu/
# Add Docker's official GPG key:
sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
# Docker version 24.0.7, build afdd53b

# without this 
sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": ["https://h89hplon.mirror.aliyuncs.com"]
}
EOF

sudo systemctl restart docker
sudo systemctl enable docker


# close firewall
# ubuntu 22 default status of ufw is inactive, so we don't need
# sudo ufw disable

# close selinux
# ubuntu 22 didn't installed selinux, so we don't need close it

# close swap
sudo swapoff -a && sudo sed -i 's/\/swap/#\/swap/g' /etc/fstab


# install kubenetes
curl https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb http://mirrors.aliyun.com/kubernetes/apt kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

sudo apt-get update && sudo apt-get install -y kubelet=$KUBE_VER-00 kubeadm=$KUBE_VER-00 kubectl=$KUBE_VER-00
sudo apt-mark hold kubelet kubeadm kubectl
echo "KUBELET_EXTRA_ARGS=--node-ip=$HOST_PRIVATE_IP" | sudo tee /etc/default/kubelet > /dev/null
sudo systemctl enable kubelet


# install cri-docker from https://github.com/Mirantis/cri-dockerd/releases, 本脚本将下载好的deb包放置到了贡献目录/shared下
sudo apt install -y /shared/cri-dockerd.deb
sudo systemctl daemon-reload
sudo systemctl enable --now cri-docker.socket


# set
sudo modprobe br_netfilter
echo "net.bridge.bridge-nf-call-ip6tables = 1" | sudo tee -a /etc/sysctl.conf
echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
echo "vm.swappiness=0" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p


# 影响kubeadm不能启动的一个关键原因 ：需要指定cri-docker的参数使用 [config/images] Pulled registry.aliyuncs.com/google_containers/pause:3.9 （此版本为拉取镜像时候对应适配的版本）
# /lib/systemd/system/cri-docker.service  if cri-docker isn't enabled， change this file
# /etc/systemd/system/multi-user.target.wants/cri-docker.service  if cri-docker is enabled， change this file
# 脚本修改
sudo kubeadm config images list --image-repository registry.aliyuncs.com/google_containers --kubernetes-version v$KUBE_VER > /shared/images.list
for line in $(cat /shared/images.list)
do
  ifpause=$(echo $line | grep "pause")
  if [[ "$ifpause" != "" ]]; then
    pattern="ExecStart=\/usr\/bin\/cri-dockerd --container-runtime-endpoint fd:\/\/"
    ifhasset=$(cat /etc/systemd/system/multi-user.target.wants/cri-docker.service | grep "pause")
    if [[ "$ifhasset" == "" ]]; then
      append_string="  --pod-infra-container-image=$line"
      sudo sed -i "s|$pattern|$pattern$append_string|" /etc/systemd/system/multi-user.target.wants/cri-docker.service
    fi
  fi
done
# 手动修改
# sudo vim /etc/systemd/system/multi-user.target.wants/cri-docker.service， 在ExecStart=/usr/bin/cri-dockerd --container-runtime-endpoint fd:后添加
# --pod-infra-container-image=registry.aliyuncs.com/google_containers/pause:3.9  # 对应/shared/images.list中pause的版本
sudo systemctl daemon-reload
sudo systemctl restart cri-docker


# kubeadm join