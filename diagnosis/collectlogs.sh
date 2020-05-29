#!/bin/bash

collectKubeletMetadata()
{
    KUBELET_REPOSITORY=$(docker images --format '{{.Repository}}' | grep hyperkube)
    KUBELET_TAG=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep hyperkube | cut -d ":" -f 2)
    KUBELET_VERBOSITY=$(cat /etc/systemd/system/kubelet.service | grep -e '--v=[0-9]' -oh | grep -e [0-9] -oh | head -n 1)
    KUBELET_LOG_FILE=${LOGDIRECTORY}/daemons/k8s-kubelet.log
    
    echo "== BEGIN HEADER =="               > ${KUBELET_LOG_FILE}
    echo "Type: Daemon"                     >> ${KUBELET_LOG_FILE}
    echo "TenantId: ${TENANT_ID}"           >> ${KUBELET_LOG_FILE}
    echo "Name: kubelet"                    >> ${KUBELET_LOG_FILE}
    echo "Version: ${KUBELET_TAG}"          >> ${KUBELET_LOG_FILE}
    echo "Verbosity: ${KUBELET_VERBOSITY}"  >> ${KUBELET_LOG_FILE}
    echo "Image: ${KUBELET_REPOSITORY}"     >> ${KUBELET_LOG_FILE}
    echo "SubscriptionID: ${SUB_ID}"        >> ${KUBELET_LOG_FILE}
    echo "ResourceGroup: ${RESOURCE_GROUP}" >> ${KUBELET_LOG_FILE}
    echo "== END HEADER =="                 >> ${KUBELET_LOG_FILE}
}

collectMobyMetadata()
{
    DOCKER_VERSION=$(docker version | grep -A 20 "Server:" | grep "Version:" | head -n 1 | cut -d ":" -f 2 | xargs)
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
    
    CVERBOSITY=$(docker inspect ${cid} | grep -e "--v=[0-9]" -oh | grep -e [0-9] -oh | head -n 1)
    IMAGE_SHA=$(docker inspect ${cid} | grep Image | grep -e "sha256:[[:alnum:]]*" -oh | head -n 1 | cut -d ':' -f 2)
    IMAGE=$(docker image inspect ${IMAGE_SHA} | jq -r '.[] | .RepoTags | @tsv' | xargs)
    CLOG_FILE=${LOGDIRECTORY}/containers/k8s-${pname}-${cname}.log
    
    echo "== BEGIN HEADER =="               > ${CLOG_FILE}
    echo "Type: Container"                  >> ${CLOG_FILE}
    echo "TenantId: ${TENANT_ID}"           >> ${CLOG_FILE}
    echo "Name: ${cname}"                   >> ${CLOG_FILE}
    echo "Hostname: ${HOSTNAME}"            >> ${CLOG_FILE}
    echo "ContainerID: ${cid}"              >> ${CLOG_FILE}
    echo "Image: ${IMAGE}"                  >> ${CLOG_FILE}
    echo "Verbosity: ${CVERBOSITY}"         >> ${CLOG_FILE}
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
}

collectCloudProviderJson() {
    if [ -f /etc/kubernetes/azure.json ]; then
        sudo jq . /etc/kubernetes/azure.json | sudo grep -v aadClient > ${LOGDIRECTORY}/etc/kubernetes/azure.json
    fi
    if [ -f /etc/kubernetes/azurestackcloud.json ]; then
        sudo jq . /etc/kubernetes/azurestackcloud.json > ${LOGDIRECTORY}/etc/kubernetes/azurestackcloud.json
    fi
    if [ -f /opt/azure/vhd-install.complete ]; then
        mkdir -p ${LOGDIRECTORY}/opt/azure
        cp /opt/azure/vhd-install.complete ${LOGDIRECTORY}/opt/azure
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
test -n "${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting logs from pods in these namespaces: $NAMESPACES"
mkdir -p ${LOGDIRECTORY}/containers

TENANT_ID=$(sudo jq -r '.tenantId' /etc/kubernetes/azure.json)
SUB_ID=$(sudo jq -r '.subscriptionId' /etc/kubernetes/azure.json)
RESOURCE_GROUP=$(sudo jq -r '.resourceGroup' /etc/kubernetes/azure.json)

if [ "${TENANT_ID}" == "adfs" ]
then
    TENANT_ID=$(sudo jq -r '.serviceManagementEndpoint' /etc/kubernetes/azurestackcloud.json | cut -d / -f4)
fi

for cid in $(docker ps -a -q --no-trunc)
do
    cns=$(docker inspect --format='{{ index .Config.Labels "io.kubernetes.pod.namespace" }}' ${cid})
    
    # if NAMESPACES not set, then collect everything
    if [ -z "${NAMESPACES}" ] || (echo $NAMESPACES | grep -qw $cns);
    then
        # Ignore the Pause container
        if docker inspect --format='{{ .Config.Image }}' ${cid} | grep -q -v pause-amd64;
        then
            pname=$(docker inspect --format='{{ index .Config.Labels "io.kubernetes.pod.name" }}' ${cid})
            cname=$(docker inspect --format='{{ index .Config.Labels "io.kubernetes.container.name" }}' ${cid})
            clog=$(docker inspect --format='{{ .LogPath }}' ${cid})
            
            collectContainerMetadata ${cid} ${pname} ${cname}
            sudo docker inspect ${cid} &> ${LOGDIRECTORY}/containers/k8s-${pname}-${cname}.json
            sudo cat $clog >> ${LOGDIRECTORY}/containers/k8s-${pname}-${cname}.log
        fi
    fi
done

test -n "${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting daemon logs"
mkdir -p ${LOGDIRECTORY}/daemons

# TODO use --until --since --lines to limit size
if systemctl list-units | grep -q kubelet.service; then
    collectKubeletMetadata
    sudo journalctl -n 10000 --utc -o short-iso -u kubelet &>> ${LOGDIRECTORY}/daemons/k8s-kubelet.log
fi

if systemctl list-units | grep -q etcd.service; then
    collectEtcdMetadata
    sudo journalctl -n 10000 --utc -o short-iso -u etcd &>> ${LOGDIRECTORY}/daemons/k8s-etcd.log
fi

if systemctl list-units | grep -q docker.service; then
    collectMobyMetadata
    sudo journalctl -n 10000 --utc -o short-iso -u docker &>> ${LOGDIRECTORY}/daemons/k8s-docker.log
fi

collectCloudProviderJson

test -n "${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Basic networking test"
checkNetworking

compressLogsDirectory
