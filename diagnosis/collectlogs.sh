#!/bin/bash

collectContainerdMetadata()
{
    CONTAINERD_VERSION=$(containerd --version | xargs)
    CONTAINERD_LOG_FILE=${LOGDIRECTORY}/daemons/k8s-containerd.log
    
    echo "== BEGIN HEADER =="               > ${CONTAINERD_LOG_FILE}
    echo "Type: Daemon"                     >> ${CONTAINERD_LOG_FILE}
    echo "TenantId: ${TENANT_ID}"           >> ${CONTAINERD_LOG_FILE}
    echo "Name: containerd"                 >> ${CONTAINERD_LOG_FILE}
    echo "Version: ${CONTAINERD_VERSION}"   >> ${CONTAINERD_LOG_FILE}
    echo "SubscriptionID: ${SUB_ID}"        >> ${CONTAINERD_LOG_FILE}
    echo "ResourceGroup: ${RESOURCE_GROUP}" >> ${CONTAINERD_LOG_FILE}
    echo "== END HEADER =="                 >> ${CONTAINERD_LOG_FILE}
}

collectKubeletMetadata()
{
    KUBELET_VERSION=$(kubelet --version | xargs)
    KUBELET_VERBOSITY=$(grep -e '--v=[0-9]' -oh /etc/systemd/system/kubelet.service | grep -e '[0-9]' -oh /etc/systemd/system/kubelet.service | head -n 1)
    KUBELET_LOG_FILE=${LOGDIRECTORY}/daemons/k8s-kubelet.log
    
    echo "== BEGIN HEADER =="               > ${KUBELET_LOG_FILE}
    echo "Type: Daemon"                     >> ${KUBELET_LOG_FILE}
    echo "TenantId: ${TENANT_ID}"           >> ${KUBELET_LOG_FILE}
    echo "Name: kubelet"                    >> ${KUBELET_LOG_FILE}
    echo "Version: ${KUBELET_VERSION}"      >> ${KUBELET_LOG_FILE}
    echo "Verbosity: ${KUBELET_VERBOSITY}"  >> ${KUBELET_LOG_FILE}
    echo "SubscriptionID: ${SUB_ID}"        >> ${KUBELET_LOG_FILE}
    echo "ResourceGroup: ${RESOURCE_GROUP}" >> ${KUBELET_LOG_FILE}
    echo "== END HEADER =="                 >> ${KUBELET_LOG_FILE}
}

collectDockerMetadata()
{
    DOCKER_VERSION=$(sudo docker version | grep -A 20 "Server:" | grep "Version:" | head -n 1 | cut -d ":" -f 2 | xargs)
    DOCKER_LOG_FILE=${LOGDIRECTORY}/daemons/k8s-docker.log
    
    echo "== BEGIN HEADER =="               > ${DOCKER_LOG_FILE}
    echo "Type: Daemon"                     >> ${DOCKER_LOG_FILE}
    echo "TenantId: ${TENANT_ID}"           >> ${DOCKER_LOG_FILE}
    echo "Name: docker"                     >> ${DOCKER_LOG_FILE}
    echo "Version: ${DOCKER_VERSION}"       >> ${DOCKER_LOG_FILE}
    echo "SubscriptionID: ${SUB_ID}"        >> ${DOCKER_LOG_FILE}
    echo "ResourceGroup: ${RESOURCE_GROUP}" >> ${DOCKER_LOG_FILE}
    echo "== END HEADER =="                 >> ${DOCKER_LOG_FILE}
}

collectEtcdMetadata()
{
    ETCD_VERSION=$(/usr/bin/etcd --version | grep "etcd Version:" | cut -d ":" -f 2 | xargs)
    ETCD_LOG_FILE=${LOGDIRECTORY}/daemons/k8s-etcd.log
    
    echo "== BEGIN HEADER =="               > ${ETCD_LOG_FILE}
    echo "Type: Daemon"                     >> ${ETCD_LOG_FILE}
    echo "TenantId: ${TENANT_ID}"           >> ${ETCD_LOG_FILE}
    echo "Name: etcd"                       >> ${ETCD_LOG_FILE}
    echo "Version: ${ETCD_VERSION}"         >> ${ETCD_LOG_FILE}
    echo "SubscriptionID: ${SUB_ID}"        >> ${ETCD_LOG_FILE}
    echo "ResourceGroup: ${RESOURCE_GROUP}" >> ${ETCD_LOG_FILE}
    echo "== END HEADER =="                 >> ${ETCD_LOG_FILE}
}

collectContainerMetadata()
{
    local cid=$1
    local pname=$2
    local cname=$3
    local image=$4

    CLOG_FILE=${LOGDIRECTORY}/containers/k8s-${pname}-${cname}-${cid}.log
    
    echo "== BEGIN HEADER =="               > ${CLOG_FILE}
    echo "Type: Container"                  >> ${CLOG_FILE}
    echo "TenantId: ${TENANT_ID}"           >> ${CLOG_FILE}
    echo "Name: ${cname}"                   >> ${CLOG_FILE}
    echo "Hostname: ${HOSTNAME}"            >> ${CLOG_FILE}
    echo "ContainerID: ${cid}"              >> ${CLOG_FILE}
    echo "Image: ${image}"                  >> ${CLOG_FILE}
    echo "SubscriptionID: ${SUB_ID}"        >> ${CLOG_FILE}
    echo "ResourceGroup: ${RESOURCE_GROUP}" >> ${CLOG_FILE}
    echo "== END HEADER =="                 >> ${CLOG_FILE}
}

compressLogsDirectory()
{
    sync
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Compressing logs and cleaning up temp files"
    CURRENTUSER=$(whoami)
    LOGFILENAME="${HOSTNAME}.zip"
    sudo rm -f ${LOGFILENAME}
    
    sudo chown -R ${CURRENTUSER} ${LOGDIRECTORY}
    # TODO This wont work on a disconnected scenario
    (cd $TMP && zip -q -r ~/${LOGFILENAME} ${HOSTNAME})
    sudo chown ${CURRENTUSER} ~/${LOGFILENAME}
    sudo rm -f -r $TMP
}

collectCloudProviderJson() {
    if [ -f /etc/kubernetes/azure.json ]; then
        sudo jq . /etc/kubernetes/azure.json | sudo grep -v aadClient > ${LOGDIRECTORY}/etc/kubernetes/azure.json
    fi
    if [ -f /etc/kubernetes/azurestackcloud.json ]; then
        sudo jq . /etc/kubernetes/azurestackcloud.json > ${LOGDIRECTORY}/etc/kubernetes/azurestackcloud.json
    fi
    if [ -f /etc/kubernetes/network_interfaces.json ]; then
        cp /etc/kubernetes/network_interfaces.json ${LOGDIRECTORY}/etc/kubernetes/network_interfaces.json
    fi
    if [ -f /etc/kubernetes/interfaces.json ]; then
        cp /etc/kubernetes/interfaces.json ${LOGDIRECTORY}/etc/kubernetes/interfaces.json
    fi
    if [ -f /opt/azure/vhd-install.complete ]; then
        mkdir -p ${LOGDIRECTORY}/opt/azure
        cp /opt/azure/vhd-install.complete ${LOGDIRECTORY}/opt/azure
    fi
}

collectKubeletConfigFiles() {
    echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting Kubelet config files"
    if sudo [ -f /etc/kubernetes/kubeadm-config.yaml ]; then
        sudo cp /etc/kubernetes/kubeadm-config.yaml ${LOGDIRECTORY}/etc/kubernetes/kubeadm-config.yaml
    fi
    
    kubeletFolder="${LOGDIRECTORY}/etc/kubernetes/kubelet"
    mkdir -p ${kubeletFolder}
    if sudo [ -f /etc/default/kubelet ]; then
        sudo cp /etc/default/kubelet ${kubeletFolder}
    fi
    if sudo [ -f /etc/systemd/system/kubelet.service ]; then
        sudo cp /etc/systemd/system/kubelet.service ${kubeletFolder}
    fi
    if sudo [ -f /etc/kubernetes/kubelet.conf ]; then
        sudo cp /etc/kubernetes/kubelet.conf ${kubeletFolder}
    fi
    if sudo [ -f /var/lib/kubelet/config.yaml ]; then
        sudo cp /var/lib/kubelet/config.yaml ${kubeletFolder}
    fi
    if sudo [ -f /var/lib/kubelet/kubeadm-flags.env ]; then
        sudo cp /var/lib/kubelet/kubeadm-flags.env ${kubeletFolder}
    fi

    containerdFolder="${LOGDIRECTORY}/etc/containerd"
    mkdir -p ${containerdFolder}
    if sudo [ -f /etc/systemd/system/containerd.service ]; then
        sudo cp /etc/systemd/system/containerd.service ${containerdFolder}
    fi
    if sudo [ -f /etc/containerd/config.toml ]; then
        sudo cp /etc/containerd/config.toml ${containerdFolder}
    fi
    if sudo [ -f /etc/containerd/kubenet_template.conf ]; then
        sudo cp /etc/containerd/kubenet_template.conf ${containerdFolder}
    fi

    mkdir -p ${LOGDIRECTORY}/etc/cni
    if sudo [ -d /etc/cni/net.d ]; then
        sudo cp -r /etc/cni/net.d ${LOGDIRECTORY}/etc/cni
    fi

    sysctlFolder="${LOGDIRECTORY}/etc/sysctl"
    mkdir -p ${sysctlFolder}
    if sudo [ -f /etc/sysctl.d/11-containerd.conf ]; then
        sudo cp /etc/sysctl.d/11-containerd.conf ${sysctlFolder}
    fi
    if sudo [ -f /etc/sysctl.d/999-sysctl-aks.conf ]; then
        sudo cp /etc/sysctl.d/999-sysctl-aks.conf ${sysctlFolder}
    fi
}

checkNetworking() {
    local DIR=${LOGDIRECTORY}/network
    mkdir -p ${DIR}
    ping ${HOSTNAME} -c 3 &> ${DIR}/ping.txt
}

TMP=$(mktemp -d)
LOGDIRECTORY=${TMP}/${HOSTNAME}
mkdir -p ${LOGDIRECTORY}

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting azure logs"
mkdir -p ${LOGDIRECTORY}/var/log/azure
cd /var/log/azure
for f in *.log
do
    sudo cp "$f" ${LOGDIRECTORY}/var/log/azure/k8s-"${f%}" || :
done

cd /var/log
for f in cloud-init*.log
do
    sudo cp "$f" ${LOGDIRECTORY}/var/log/k8s-"${f%}" || :
done

if [ -d /var/log/kubeaudit ]; then
    cd /var/log/kubeaudit
    for f in *.log
    do
        sudo cp "$f" ${LOGDIRECTORY}/var/log/k8s-"${f%}" || :
    done
fi

sudo cp /var/log/waagent.log ${LOGDIRECTORY}/var/log/k8s-waagent.log || :

if [ -f /var/log/azure/deploy-script-dvm.log ]
then
    sudo apt install zip -y
    compressLogsDirectory
    exit
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting static pod manifests"
mkdir -p ${LOGDIRECTORY}/etc/kubernetes/manifests
sudo cp /etc/kubernetes/manifests/* ${LOGDIRECTORY}/etc/kubernetes/manifests 2>/dev/null
mkdir -p ${LOGDIRECTORY}/etc/kubernetes/addons
sudo cp /etc/kubernetes/addons/* ${LOGDIRECTORY}/etc/kubernetes/addons 2>/dev/null

test $# -gt 0 && NAMESPACES=$@
test -z "${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting logs from pods in all namespaces"
test -n "${NAMESPACES}" && NAMESPACES="kube-system${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting logs from pods in these namespaces: $NAMESPACES"
mkdir -p ${LOGDIRECTORY}/containers

TENANT_ID=$(sudo jq -r '.tenantId' /etc/kubernetes/azure.json)
SUB_ID=$(sudo jq -r '.subscriptionId' /etc/kubernetes/azure.json)
RESOURCE_GROUP=$(sudo jq -r '.resourceGroup' /etc/kubernetes/azure.json)

if [ "${TENANT_ID}" == "adfs" ]
then
    TENANT_ID=$(sudo jq -r '.serviceManagementEndpoint' /etc/kubernetes/azurestackcloud.json | cut -d / -f4)
fi

if systemctl is-active --quiet docker; then
    for cid in $(sudo docker ps -a -q --no-trunc)
    do
        cns=$(sudo docker inspect --format='{{ index .Config.Labels "io.kubernetes.pod.namespace" }}' ${cid})
        
        # if NAMESPACES not set, then collect everything
        if [ -z "${NAMESPACES}" ] || (echo $NAMESPACES | grep -qw $cns);
        then
            image_sha=$(sudo docker inspect ${cid} | jq -r '.[].Image' | grep -e "sha256:[[:alnum:]]*" -oh | head -n 1 | cut -d ':' -f 2)
            image=$(sudo docker image inspect ${image_sha} | jq -r '.[] | .RepoTags | @tsv' | xargs)
            # Ignore the Pause container
            if echo ${image} | grep -q -v pause;
            then
                pname=$(sudo docker inspect --format='{{ index .Config.Labels "io.kubernetes.pod.name" }}' ${cid})
                cname=$(sudo docker inspect --format='{{ index .Config.Labels "io.kubernetes.container.name" }}' ${cid})
                clog=$(sudo docker inspect --format='{{ .LogPath }}' ${cid})

                if [ -z "${pname}" ]; then pname=unknown; fi
                if [ -z "${cname}" ]; then cname=unknown; fi

                collectContainerMetadata ${cid} ${pname} ${cname} ${image}
                sudo docker inspect ${cid} &> ${LOGDIRECTORY}/containers/k8s-${pname}-${cname}-${cid}.json
                sudo cat $clog >> ${LOGDIRECTORY}/containers/k8s-${pname}-${cname}-${cid}.log
            fi
        fi
    done
fi

if command -v crictl &> /dev/null; then
    for cid in $(sudo crictl ps -a -q --no-trunc)
    do
        cinfo=$(sudo crictl inspect ${cid})
        cns=$(echo ${cinfo} | jq -r '.status.labels."io.kubernetes.pod.namespace"')
        
        # if NAMESPACES not set, then collect everything
        if [ -z "${NAMESPACES}" ] || (echo $NAMESPACES | grep -qw $cns);
        then
            image=$(echo ${cinfo} | jq -r '.status.image.image')
            # Ignore the Pause container
            if echo ${image} | grep -q -v pause;
            then
                pname=$(echo ${cinfo} | jq -r '.status.labels."io.kubernetes.pod.name"')
                cname=$(echo ${cinfo} | jq -r '.status.labels."io.kubernetes.container.name"')
                clog=$(echo ${cinfo} | jq -r '.status.logPath')
                
                collectContainerMetadata ${cid} ${pname} ${cname} ${image}
                echo ${cinfo} &> ${LOGDIRECTORY}/containers/k8s-${pname}-${cname}-${cid}.json
                sudo cat $clog >> ${LOGDIRECTORY}/containers/k8s-${pname}-${cname}-${cid}.log
            fi
        fi
    done
fi

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting daemon logs"
mkdir -p ${LOGDIRECTORY}/daemons

# TODO use --until --since --lines to limit size
if systemctl list-units | grep -q kubelet.service; then
    collectKubeletMetadata
    sudo journalctl -n 10000 --utc -o short-iso -r -u kubelet &>> ${LOGDIRECTORY}/daemons/k8s-kubelet.log
fi

if systemctl list-units | grep -q etcd.service; then
    collectEtcdMetadata
    sudo journalctl -n 10000 --utc -o short-iso -r -u etcd &>> ${LOGDIRECTORY}/daemons/k8s-etcd.log
fi

if systemctl list-units | grep -q docker.service; then
    collectDockerMetadata
    sudo journalctl -n 10000 --utc -o short-iso -r -u docker &>> ${LOGDIRECTORY}/daemons/k8s-docker.log
fi

if systemctl list-units | grep -q containerd.service; then
    collectContainerdMetadata
    sudo journalctl -n 10000 --utc -o short-iso -r -u containerd &>> ${LOGDIRECTORY}/daemons/k8s-containerd.log
fi

collectCloudProviderJson
collectKubeletConfigFiles

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Basic networking test"
checkNetworking

compressLogsDirectory
