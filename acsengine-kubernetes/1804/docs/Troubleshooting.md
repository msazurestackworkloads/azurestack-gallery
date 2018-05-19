Troubleshooting:
This deployment runs in two stages. 

a) First is that we deploy a DVM. If you hit any issues with DVM deployment first thing to check is: 
	
Login to the deployment VM with name "vmd-(resource group name)" using Putty/SSH and read the following logs:
		
/var/log/azure/acsengine-kubernetes-dvm.log

The last error in the file usually reflects the issue. If it's user error please fix it and try redeployment.
	
b) Second it runs Kubernetes cluster deployment, if you hit any issues with kubernetes cluster deployment then [TBA].


FAQ
===
1) 	Ensure that the input tenant ARM endpoint is of correct format. 
	This is the ARM endpoint to connect to create the resoure group for the Kubernetes cluster. 
	Remove any trailing slash. e.g. https://management.regionname.ext-my.masd.stbtest.microsoft.com (multi-node) or https://management.local.azurestack.external (one-node).

