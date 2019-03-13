# Monitoring Kubernetes Clusters

While Kubernetes does not include a full monitoring experience out-of-the-box, there are a number of reliable proprietary and community-supported open source options to collect, aggregate, visualize, and alert on metrics and logs.

The AKS Engine's contributors put together a [list of solutions](https://github.com/Azure/aks-engine/blob/master/docs/topics/monitoring.md) validated against clusters running on Azure's public cloud. Most of the information on this guide should be applicable to clusters running on Azure Stack.

Differences between Azure and Azure Stack, or required extra steps, are listed below when applicable.

## Azure Monitor for containers

Support for [Azure Monitor for containers](https://docs.microsoft.com/en-us/azure/azure-monitor/insights/container-insights-overview) is close to be completed.

Work is being done to allow Kubernetes clusters running on Azure Stack to ship metrics and logs to a [Log Analytics](https://docs.microsoft.com/en-us/azure/azure-monitor/log-query/log-query-overview) workspace resources on Azure's public cloud.

## Kubernetes dashboard

AKS Engine deploys the [Kubernetes dashboard](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/) as part of the cluster deployment process.

Take into account that remote connections to the Kubernetes dashboard will be refused if your host is not trusted by your Kubernetes API. Make sure you [import the required certificates](https://aka.ms/AzsK8sDashboard) if you face this issue.

## Prometheus-Grafana Extension

AKS Engine provides an [extension](https://github.com/Azure/aks-engine/blob/master/docs/topics/extensions.md) that simplifies the deployment and basic configuration of [Prometheus](https://prometheus.io/) and [Grafana](https://grafana.com/) as part of your Kubernetes cluster creation.

When deploying to Azure's public cloud, this is achieved by modifying your cluster definition as indicated in [here](https://github.com/Azure/aks-engine/tree/master/extensions/prometheus-grafana-k8s). On Azure Stack private clouds, this process temporarily requires manual intervention until AKS Engine's CLI is officially supported as a deployment mechanism.

The required steps are listed below. These commands should to executed from any of the master nodes.

```
#!/bin/bash

# Download install script 
curl -O https://raw.githubusercontent.com/Azure/aks-engine/master/extensions/prometheus-grafana-k8s/v1/prometheus-grafana-k8s.sh

# Make it executable
chmod +x prometheus-grafana-k8s.sh

# Set environment variables (this is a required step)
# Update values if defaults do not work for you
NAMESPACE=default
RAW_PROMETHEUS_CHART_VALS="https://raw.githubusercontent.com/Azure/aks-engine/master/extensions/prometheus-grafana-k8s/v1/prometheus_values.yaml"
CADVISOR_CONFIG_URL="https://raw.githubusercontent.com/Azure/aks-engine/master/extensions/prometheus-grafana-k8s/v1/cadvisor_daemonset.yml"

# Execute script
./prometheus-grafana-k8s.sh "$NAMESPACE;$RAW_PROMETHEUS_CHART_VALS;$CADVISOR_CONFIG_URL"

```

The install script performs this high level steps:

- Install and configure [Helm](https://helm.sh/)
- Install a [cAdvisor](https://github.com/google/cadvisor) DaemonSet (see [CADVISOR_CONFIG_URL](https://raw.githubusercontent.com/Azure/aks-engine/master/extensions/prometheus-grafana-k8s/v1/prometheus_values.yaml))
- Install [Prometheus's chart](https://github.com/helm/charts/tree/master/stable/prometheus) from Helm's stable repository (see [RAW_PROMETHEUS_CHART_VALS](https://raw.githubusercontent.com/Azure/aks-engine/master/extensions/prometheus-grafana-k8s/v1/cadvisor_daemonset.yml))
- Install [Grafana's chart](https://github.com/helm/charts/tree/master/stable/grafana) from Helm's stable repository
- Create Prometheus data source for Grafana
- Install Grafana's [Kubernetes dashboard](https://grafana.com/dashboards/3119)
