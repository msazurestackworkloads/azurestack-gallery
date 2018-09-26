# Service Fabric Gallery Item 
================================================================================
This gallery item deploys a Service Fabric Cluster on Azure Stack based on Azure Stack resoureces. It includs following scenarios:

* Deploy new Service Fabric cluster
  * Deploy single node type cluster
  * Deploy multi node type cluster
* Scale out node (within node type)

For scale out, you just scale out the VM scale set. For scale down or scale out on node type, you have to do extra work to update the service fabric configuration. Please see the appendix to see the related links.

================================================================================

## Development Guid
1) Source File Contents:
   
   ### a) DSC
      Service Fabric Cluster is deployed through DSC. The DSC actually do following things: 
	  1. Prepare enviroment. Including grant certificate access, set firewall rules etc.
	  2. Download Service Fabric package and prepare service fabric configuration file.
	  3. Deploy Service Fabric
	  4. Add a new node (Scale out)
     
	  DSC/DeploySFCluster.ps1 
	  
	      This is the configuration of DSC.		  
	  
	  DSC/xServiceFabricSecureCluster/DSCResources/xServiceFabricSecureClusterDeployment/xServiceFabricSecureClusterDeployment.psm1
	      
		  The main logic of DSC.
		  
	  DSC/xServiceFabricSecureCluster/DSCResources/xServiceFabricSecureClusterDeployment/xServiceFabricSecureClusterDeployment.schema.mof 	  
		  
		  The contract of DSC (schema).
		  
      **If you need to modify the parameters, you must update in the above three files.** 
		  
   ### b) Microsoft.ServiceFabricCluster
	  This the Gallery item template, including UI definition and deployment template. 
     
	  Microsoft.ServiceFabricCluster\DeploymentTemplates\ClusterConfig.X509.MultiMachine.json
	    
		This is the initial configuration file used to generate cluster configuration file.
		
	  Microsoft.ServiceFabricCluster\DeploymentTemplates\MainTemplate.json
	  
        This is the start template of deploy Azure Resources.
      
	  Microsoft.ServiceFabricCluster\DeploymentTemplates\vmssProvision.json
		
		This is the sub template for creating VM scale set for each node type. 
      
	  Microsoft.ServiceFabricCluster\DeploymentTemplates\DeploySFCluster.zip
	  
        This is the DSC package. **Whenever you update the DSC logic, you must make a new DSC package to replace the old one.** Make sure to use the latest DSC package before making gallery package.
		
2) How to make gallery item package and push in market place: 

      https://docs.microsoft.com/en-us/azure/azure-stack/azure-stack-create-and-publish-marketplace-item

================================================================================

## Useful links:
1) Service Fabric on Azure Stack Deployment steps:

   https://docs.microsoft.com/en-us/azure/azure-stack/user/azure-stack-solution-template-service-fabric-cluster

2) Standalone service fabric: 

   https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-creation-for-windows-server
   
3) Standalone service fabric security configuration:

   https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-windows-cluster-x509-security
   
4) Service Fabric Scale In/Out

   https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-windows-server-add-remove-nodes


