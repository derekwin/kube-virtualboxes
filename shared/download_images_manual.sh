KUBE_VER=1.28.0

ALI_REGISTRY=registry.cn-hangzhou.aliyuncs.com/google_containers
COREDNS_REGISTRY=k8s-gcr.m.daocloud.io
sudo kubeadm config images list --kubernetes-version v$KUBE_VER > /shared/images.list

for line in $(cat /shared/images.list)
do
    ifcoredns=$(echo $line | grep "coredns")
    ifregistryk8s=$(echo $line | grep "registry.k8s")
    ifk8sgcr=$(echo $line | grep "k8s.gcr")
    if [[ "$ifregistryk8s" != "" ]]; then
        if [[ "$ifcoredns" != "" ]]
        then
            image=$(echo "$line" | sed "s#registry.k8s.io#$COREDNS_REGISTRY#g")
        else
            image=$(echo "$line" | sed "s#registry.k8s.io#$ALI_REGISTRY#g")
        fi
    fi
    if [[ "$ifk8sgcr" != "" ]]; then
        if [[ "$ifcoredns" != "" ]]
        then
            image=$(echo "$line" | sed "s#k8s.gcr.io#$COREDNS_REGISTRY#g")
        else
            image=$(echo "$line" | sed "s#k8s.gcr.io#$ALI_REGISTRY#g")
        fi
    fi
    echo $image
    sudo ctr -n=k8s.io image pull $image
    sudo ctr -n=k8s.io image tag $image $line
done