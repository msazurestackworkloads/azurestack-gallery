Troubleshooting:
This deployment runs in two stages. 

a) First is that we deploy a DVM. If you hit any issues with DVM deployment first thing to check is: 
	
Login to the deployment VM with name "vmd-(resource group name)" using Putty/SSH and read the following logs:
		
/var/log/azure/acsengine-kubernetes-dvm.log

The last error in the file usually reflects the issue. If it's user error please fix it and try redeployment.
	
b) Second it runs Kubernetes cluster deployment, if you hit any issues with kubernetes cluster deployment then TBA.
	 

