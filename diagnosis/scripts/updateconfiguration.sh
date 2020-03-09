#!/bin/bash -e

agentScript() {
    cat <<EOF > agent.sh
#!/bin/bash -e

# cloud provider
sudo cp /etc/kubernetes/azure.json /etc/kubernetes/azure.bak
sudo jq '.cloudProviderRatelimit = true | .cloudProviderRateLimitQPS = 3 | .cloudProviderRateLimitBucket = 10 | .cloudProviderBackoffRetries = 1 | .cloudProviderBackoffDuration = 30' /etc/kubernetes/azure.bak | sudo dd status=none of=/etc/kubernetes/azure.json

# kubelet
sudo cp /etc/default/kubelet /etc/default/kubelet.bak
sudo sed -i -e 's/--node-status-update-frequency=[0-9]*[a-z]/--node-status-update-frequency=1m/' /etc/default/kubelet

# restart
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo "=> azure.json updates"
sudo grep -E 'cloudProviderRatelimit"|cloudProviderRateLimitQPS"|cloudProviderRateLimitBucket"|cloudProviderBackoffRetries"|cloudProviderBackoffDuration"' /etc/kubernetes/azure.json
echo "=> kubelet restarted"
systemctl status kubelet --no-pager -l
EOF
if [ ! -f agent.sh ]; then
    echo "[ERR] Error generating script: agent.sh"
    return 1
fi
}

masterScript() {
    cat <<EOF > master.sh
#!/bin/bash -e

# cloud provider
sudo cp /etc/kubernetes/azure.json /etc/kubernetes/azure.bak
sudo jq '.cloudProviderRatelimit = false | .cloudProviderRateLimitQPS = 3 | .cloudProviderRateLimitBucket = 10 | .cloudProviderBackoffRetries = 1 | .cloudProviderBackoffDuration = 30' /etc/kubernetes/azure.bak | sudo dd status=none of=/etc/kubernetes/azure.json

# kubelet
sudo cp /etc/default/kubelet /etc/default/kubelet.bak
sudo sed -i -e 's/--node-status-update-frequency=[0-9]*[a-z]/--node-status-update-frequency=1m/' /etc/default/kubelet

# kube-controller-manager
sudo cp /etc/kubernetes/manifests/kube-controller-manager.yaml /etc/kubernetes/manifests/kube-controller-manager.bak
sudo sed -i -e 's/--route-reconciliation-period=[0-9]*[a-z]/route-reconciliation-period=1m/' /etc/kubernetes/manifests/kube-controller-manager.yaml
sudo sed -i -e 's/--node-monitor-grace-period=[0-9]*[a-z]/--node-monitor-grace-period=5m/' /etc/kubernetes/manifests/kube-controller-manager.yaml
sudo sed -i -e 's/--pod-eviction-timeout=[0-9]*[a-z]/--pod-eviction-timeout=5m/' /etc/kubernetes/manifests/kube-controller-manager.yaml

# restart
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo "=> controller-manager updates"
grep -o -E 'route-reconciliation-period=[0-9a-zA-Z]*' /etc/kubernetes/manifests/kube-controller-manager.yaml
grep -o -E 'node-monitor-grace-period=[0-9a-zA-Z]*' /etc/kubernetes/manifests/kube-controller-manager.yaml
grep -o -E 'pod-eviction-timeout=[0-9a-zA-Z]*' /etc/kubernetes/manifests/kube-controller-manager.yaml
echo "=> azure.json updates"
sudo grep -E 'cloudProviderRatelimit"|cloudProviderRateLimitQPS"|cloudProviderRateLimitBucket"|cloudProviderBackoffRetries"|cloudProviderBackoffDuration"' /etc/kubernetes/azure.json
echo "=> kubelet restarted"
systemctl status kubelet --no-pager -l
EOF
if [ ! -f master.sh ]; then
    echo "[ERR] Error generating script: master.sh"
    return 1
fi
}

processHost() {
    HOST=$1
    SCRIPT=$2

    if [[ "$HOST" == "$HOSTNAME" ]]; then
        sudo chmod +x ${SCRIPT};
        ./${SCRIPT};
    else
        KNOWN_HOSTS_OPTIONS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR'
        PROXY_CMD="ssh ${KNOWN_HOSTS_OPTIONS} ${USER}@${HOSTNAME} -W %h:%p"
        SSH_FLAGS="-q -t ${KNOWN_HOSTS_OPTIONS}"
        SCP_FLAGS="-q ${KNOWN_HOSTS_OPTIONS}"

        scp ${SCP_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${SCRIPT} ${USER}@${HOST}:${SCRIPT}
        ssh ${SSH_FLAGS} -o ProxyCommand="${PROXY_CMD}" ${USER}@${HOST} "sudo chmod +x ${SCRIPT}; ./${SCRIPT}; rm ${SCRIPT};"
    fi
}

printUsage()
{
    echo "$0 updates Kubernetes clusters configuration on agent and master nodes."
    echo "Usage:"
    echo "  $0 [flags]"
    echo ""
    echo "Flags:"
    echo "  --agents                        Update configuration on all Kubernetes agent nodes"
    echo "  --masters                       Update configuration on all Kubernetes master nodes"
    echo ""
    echo "Examples:"
    echo "  $0 --agents"
    echo "  $0 --masters"
    echo "  $0 --masters --agents"
    exit 1
}

if [ "$#" -eq 0 ]
then
    printUsage
fi

DOMASTERS=1
DOAGENTS=1
while [[ "$#" -gt 0 ]]
do
    case $1 in
        --masters)
            DOMASTERS=0
            shift
        ;;
        --agents)
            DOAGENTS=0
            shift
        ;;
        -h|--help)
            printUsage
        ;;
        *)
            echo ""
            echo "[ERR] Unexpected flag $1"
            printUsage
        ;;
    esac
done

## NODES
if [ $DOAGENTS -eq 0 ]; then
    agentScript
    AGENTS=$(kubectl get nodes -o custom-columns=CONTAINER:.metadata.name | tail -n +2 | grep -v k8s-master | xargs)
    for AGENT in ${AGENTS}; do
        echo ""
        echo "==> PROCESSING AGENT $AGENT"
        processHost ${AGENT} agent.sh
    done
    rm agent.sh
fi

# MASTERS
if [ $DOMASTERS -eq 0 ]; then
    masterScript
    MASTERS=$(kubectl get nodes -o custom-columns=CONTAINER:.metadata.name | tail -n +2 | grep k8s-master | xargs)
    for MASTER in ${MASTERS}; do
        echo ""
        echo "==> PROCESSING MASTER $MASTER"
        processHost ${MASTER} master.sh
    done
    rm master.sh
fi
