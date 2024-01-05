
# 使用vagrant快速搭建某个版本的k8s
1. 安装virtualbox与vagrant
2. vagrant需要基础vbox镜像，国内网络可以通过清华源下载vagrant box镜像
    - vagrant box add ubuntu/focal64 https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cloud-images/focal/current/focal-server-cloudimg-amd64-vagrant.box
    - vagrant box add ubuntu/jammy64 https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cloud-images/jammy/current/jammy-server-cloudimg-amd64-vagrant.box

## 本文采用cri-docker和docker来安装k8s
1.24之后的k8s，需要cri-docker, 下载cri-dockerd的安装包放到对应的shared目录下
`wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.7/cri-dockerd_0.3.7.3-0.ubuntu-jammy_amd64.deb`


在配置1.28版本k8s的过程中，使用flannel cni，在加入节点时候，会pull registry.k8s.io/pause:3.6导致节点加入不成功，目前不知道原因，
所以在主从节点均手动下载好该镜像(脚本中已经自带)


```
sudo docker pull registry.aliyuncs.com/google_containers/pause:3.6
sudo docker tag registry.aliyuncs.com/google_containers/pause:3.6 registry.k8s.io/pause:3.6
```

## 配置
修改相关文件内的设备配置，如ip，设备名等(用 ###注释### 的地方)

如果使用calico 修改 calico custom-resources.yaml中cidr 10.244.0.0/16

如果是flannel 不需要修改

## 启动
进入kube-master/kube-w1/kube-w2目录，执行`vagrant up`

## 说明
本仓库脚本使用cri-docker和docker方案，所以kubeadm命令需要手动指定 --cri-socket /run/cri-dockerd.sock

- sudo kubeadm reset --cri-socket /run/cri-dockerd.sock
- kubeadm init --kubernetes-version=v1.28.0 --pod-network-cidr=10.244.0.0/16 --cri-socket /run/cri-dockerd.sock
- kubeadm join --cri-socket /run/cri-dockerd.sock ...

## 常用指令
### 启动master节点
```
sudo kubeadm init --v=5 --cri-socket unix:///var/run/cri-dockerd.sock --kubernetes-version v1.28.0 --image-repository registry.aliyuncs.com/google_containers --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address 192.168.33.20 | tee /shared/kubeadm.log
sudo cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
```

### 重置master节点
```
sudo kubeadm reset --cri-socket unix:///var/run/cri-dockerd.sock
# 重置flannel
kubectl delete -f /shared/flannel.yaml
sudo bash /shared/reflash-flannel.sh
```

### 加入节点
```
sudo kubeadm join 192.168.33.20:6443 --cri-socket /run/cri-dockerd.sock --token ev4mk5.egzxdqzi5nvgo648 --discovery-token-ca-cert-hash sha256:41072d05203374e79827ce49d93dbc6d9ad22e875637fff3546b6bec7e7a913b
```