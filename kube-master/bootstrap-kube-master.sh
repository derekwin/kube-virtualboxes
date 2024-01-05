KUBE_VER=$1
HOSTNAME=$2

# set dns
# echo "nameserver 114.114.114.114" | sudo tee /etc/resolv.conf > /dev/null
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null

sudo hostnamectl set-hostname $HOSTNAME  #
HOST_PRIVATE_IP=$(hostname -I | cut -d ' ' -f2)
printf "Installing K8=$KUBE_VER-00 on $HOSTNAME with IP: $HOST_PRIVATE_IP\n"

# add host
### 修改每个机器对应的host ###
echo "$HOST_PRIVATE_IP kube-master" | sudo tee -a /etc/hosts
echo "192.168.33.11 kube-w1" | sudo tee -a /etc/hosts
echo "192.168.33.12 kube-w2" | sudo tee -a /etc/hosts


# install docker : https://docs.docker.com/engine/install/ubuntu/
# Add Docker's official GPG key:
sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg net-tools
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
# 脚本修改：脚本修改的配置文件会出现无法正常启动kubeadm的情况，下面的写法有问题
# sudo kubeadm config images list --image-repository registry.aliyuncs.com/google_containers --kubernetes-version v$KUBE_VER > /shared/images.list
# for line in $(cat /shared/images.list)
# do
#   ifpause=$(echo $line | grep "pause")
#   if [[ "$ifpause" != "" ]]; then
#     pattern="ExecStart=\/usr\/bin\/cri-dockerd --container-runtime-endpoint fd:\/\/"
#     ifhasset=$(cat /etc/systemd/system/multi-user.target.wants/cri-docker.service | grep "pause")
#     if [[ "$ifhasset" == "" ]]; then
#       append_string=" --pod-infra-container-image=$line"
#       sudo sed -i "s|$pattern|$pattern$append_string|" /etc/systemd/system/multi-user.target.wants/cri-docker.service
#     fi
#   fi
# done
# 直接指定行，进行命令追加
escaped_string_to_add=$(sed 's/[&/\]/\\&/g' <<< " --pod-infra-container-image=registry.aliyuncs.com/google_containers/pause:3.9")
sudo sed -i '10s/$/'"$escaped_string_to_add"'/' /etc/systemd/system/multi-user.target.wants/cri-docker.service
# 手动修改
# sudo vim /etc/systemd/system/multi-user.target.wants/cri-docker.service， 在ExecStart=/usr/bin/cri-dockerd --container-runtime-endpoint fd:后添加
# --pod-infra-container-image=registry.aliyuncs.com/google_containers/pause:3.9  # 对应/shared/images.list中pause的版本
sudo systemctl daemon-reload
sudo systemctl restart cri-docker


# up
# 指定 criSocket unix:///var/run/cri-dockerd.sock
sudo kubeadm config images pull --cri-socket unix:///var/run/cri-dockerd.sock --kubernetes-version v$KUBE_VER --image-repository registry.aliyuncs.com/google_containers
# 注意修改api ip为对应本vm的ip #
sudo kubeadm init --v=5 --cri-socket unix:///var/run/cri-dockerd.sock --kubernetes-version v$KUBE_VER --image-repository registry.aliyuncs.com/google_containers --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address $HOST_PRIVATE_IP | tee /shared/kubeadm.log
# --v=5 --skip-phases=preflight
# sudo kubeadm reset --cri-socket unix:///var/run/cri-dockerd.sock


# 配置当前用户的操作权限
sudo rm -rf /root/.kube
mkdir -p /home/vagrant/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo chown -R "vagrant:vagrant" /home/vagrant/.kube/


# 安装CNI
# calico始终无法成功，应该是镜像的问题
# # calico: https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart
# # kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
# # kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml
# # 如果网络问题手动下载然后指定本地yaml路径
# kubectl create -f /shared/tigera-operator.yaml  # kubectl delete -f /shared/tigera-operator.yaml
# kubectl create -f /shared/custom-resources.yaml

# # waiting
# kubectl taint nodes --all node-role.kubernetes.io/control-plane-
# kubectl taint nodes --all node-role.kubernetes.io/master-

# 改用flannel
# kube-flannel：https://blog.csdn.net/chen_haoren/article/details/108580338
# docker pull flannel/flannel:v0.24.0, docker save flannel/flannel > flannel.tar先手动下载镜像到本地然后
sudo docker load < /shared/flannel.tar
# 在外网服务器下载到docker pull flannel/flannel-cni-plugin:v1.2.0，导出 docker save flannel/flannel-cni-plugin > flannel-plugin.tar
sudo docker load < /shared/flannel-plugin.tar
# kube-flannel: https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
kubectl create -f /shared/flannel.yaml  # kubectl delete -f /shared/flannel.yaml

# 在配置1.28版本k8s的过程中，使用flannel cni，在加入节点时候，会pull registry.k8s.io/pause:3.6导致节点加入不成功，目前不知道原因，
# 所以在主从节点均手动下载好该镜像
sudo docker pull registry.aliyuncs.com/google_containers/pause:3.6
sudo docker tag registry.aliyuncs.com/google_containers/pause:3.6 registry.k8s.io/pause:3.6

# kubectl get pods -A
# kubectl describe pods kube-flannel-ds-xm7tq -n kube-flannel
# kubectl describe pods coredns-66f779496c-k7z78 -n kube-system
kubectl get nodes -o wide