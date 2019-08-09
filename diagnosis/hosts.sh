#!/bin/bash

###
#   <summary>
#       Find nodes on the network using the `ping` command instead of `kubectl get nodes`.
#       This approach should still give us back results even if the Kubernetes API is having problems.
#   </summary>
###

WD=$1
mkdir -p $WD
TMP=$(mktemp -d)

HOSTLIST=$WD/host.list
rm -f $HOSTLIST

echo "[$(date +%Y%m%d%H%M%S)][INFO] Searching for cluster nodes"
#If the node count increases ip ranges needs to be modified 
for ip in 10.240.0.{4..100};
do
    ping -c 1 -W 1 $ip | grep "64 bytes" | cut -d " " -f 4 | cut -d ":" -f 1 >> $HOSTLIST
done
for ip in 10.240.255.{5..100};
do
    ping -c 1 -W 1 $ip | grep "64 bytes" | cut -d " " -f 4 | cut -d ":" -f 1 >> $HOSTLIST
done

echo "[$(date +%Y%m%d%H%M%S)][INFO] Collecting cluster snapshot"
kubectl cluster-info dump --output-directory ${TMP} &> /dev/null
cp ${TMP}/*.json ${TMP}/kube-system/*.json ${WD}

TENANT_ID=$(sudo jq -r '.tenantId' /etc/kubernetes/azure.json)
PODS=$(find ${TMP}/kube-system -mindepth 1 -maxdepth 1 -type d -printf '%f\n')

for pod in ${PODS}
do
    jq --arg name "${pod}" --arg tenant "${TENANT_ID}"  '.items[] | select (.metadata.name == $name) | {
            Name: .metadata.name,
            Type: "Container",
            TenantId: $tenant,
            Hostname: .spec.nodeName,
            Image: .spec.containers[0].image,
            ContainerID: .status.containerStatuses[0].containerID,
            Verbosity: (.spec.containers[0].args[-1] // "") }' ${WD}/pods.json | \
    sed 's/docker:\/\///g' | \
sed s/--v=//g | \
sed s/--.*\"$/\"/g | \
    sed 's/"\/.*"$/\"\"/g' > ${WD}/${pod}.meta
    # TODO the sed command above a hack to clean up data, need to get rid of them
done

tar -zcf ${WD}.tar.gz ${WD} 
rm -rf ${WD}
