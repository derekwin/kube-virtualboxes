
# 使用vagrant快速搭建某个版本的k8s
1. 安装virtualbox与vagrant
2. vagrant需要基础vbox镜像，国内网络可以通过清华源下载vagrant box镜像
    - vagrant box add ubuntu/focal64 https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cloud-images/focal/current/focal-server-cloudimg-amd64-vagrant.box
    - vagrant box add ubuntu/jammy64 https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cloud-images/jammy/current/jammy-server-cloudimg-amd64-vagrant.box

## 本文采用cri-docker和docker来安装k8s
1.24之后的k8s，需要cri-docker, 下载cri-dockerd的安装包放到对应的shared目录下
`wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.7/cri-dockerd_0.3.7.3-0.ubuntu-jammy_amd64.deb`

## 配置
修改相关文件内的设备配置，如ip，设备名等(用 ###注释###的地方)

## 启动
进入kube-master/kube-w1/kube-w2目录，执行`vagrant up`

## 说明
本仓库脚本使用cri-docker和docker方案，所以kubeadm命令需要手动指定 --cri-socket /run/cri-dockerd.sock

- sudo kubeadm reset --cri-socket /run/cri-dockerd.sock
- kubeadm init --kubernetes-version=v1.28.0 --pod-network-cidr=10.244.0.0/16 --cri-socket /run/cri-dockerd.sock
- kubeadm join --cri-socket /run/cri-dockerd.sock ...


### refs:
https://www.jjworld.fr/kubernetes-installation/