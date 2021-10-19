# Learn more on https://docs.microsoft.com/en-us/azure/app-service/manage-create-arc-environment?tabs=bash

# Install CLI extensions
az extension add --upgrade --yes --name connectedk8s
az extension add --upgrade --yes --name k8s-extension
az extension add --upgrade --yes --name customlocation
az provider register --namespace Microsoft.ExtendedLocation --wait
az provider register --namespace Microsoft.Web --wait
az provider register --namespace Microsoft.KubernetesConfiguration --wait
az extension remove --name appservice-kube
az extension add --yes --source "https://aka.ms/appsvc/appservice_kube-latest-py2.py3-none-any.whl"

# Define variables
$resourceGroupName="codit-cloud-native-demystified-azure-arc"
$remoteClusterName="codit-cloud-native-demystified-self-hosted-cluster"
$aksPublicIPName="cloud-native-anywhere-public-ip"
$aksClusterResourceGroupName="MC_codit-cloud-native-demystified-azure-arc_cloud-native-anywhere_westeurope"

# Create public IP address
az network public-ip create --resource-group $aksClusterResourceGroupName --name $aksPublicIPName --sku STANDARD
$staticClusterIp=$(az network public-ip show --resource-group $aksClusterResourceGroupName --name $aksPublicIPName --output tsv --query ipAddress)

# Connect Kind cluster to Azure with Azure Arc
az connectedk8s connect --resource-group $resourceGroupName --name $remoteClusterName
az connectedk8s show --resource-group $resourceGroupName --name $remoteClusterName

# Create Log Analytics namespace
$workspaceName="codit-cloud-native-demystified-logs"
az monitor log-analytics workspace create --resource-group $resourceGroupName --workspace-name $workspaceName

# Get Log Analytics info
$logAnalyticsWorkspaceId=$(az monitor log-analytics workspace show --resource-group $resourceGroupName --workspace-name $workspaceName --query customerId --output tsv)
$logAnalyticsWorkspaceIdEnc=[Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($logAnalyticsWorkspaceId))
$logAnalyticsKey=$(az monitor log-analytics workspace get-shared-keys --resource-group $resourceGroupName --workspace-name $workspaceName --query primarySharedKey --output tsv)
$logAnalyticsKeyEnc=[Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($logAnalyticsKey))

# Create App Service extension on remote cluster
# Name of the App Service extension
$extensionName="appservice-on-kubernetes"
# Namespace in your cluster to install the extension and provision resources
$namespace="appservice-system"
# Name of the App Service Kubernetes environment resource
$kubeEnvironmentName="codit-cloud-native-demystified-app-service-on-kube"
az k8s-extension create --resource-group $resourceGroupName --name $extensionName --cluster-type connectedClusters --cluster-name $remoteClusterName --extension-type 'Microsoft.Web.Appservice' --release-train stable --auto-upgrade-minor-version true --scope cluster --release-namespace $namespace --configuration-settings "Microsoft.CustomLocation.ServiceAccount=default" --configuration-settings "appsNamespace=${namespace}" --configuration-settings "clusterName=${kubeEnvironmentName}" --configuration-settings "loadBalancerIp=${staticClusterIp}" --configuration-settings "keda.enabled=true" --configuration-settings "buildService.storageClassName=default" --configuration-settings "buildService.storageAccessMode=ReadWriteOnce" --configuration-settings "customConfigMap=${namespace}/kube-environment-config" --configuration-settings "envoy.annotations.service.beta.kubernetes.io/azure-load-balancer-resource-group=${aksClusterResourceGroupName}" --configuration-settings "logProcessor.appLogs.destination=log-analytics" --configuration-protected-settings "logProcessor.appLogs.logAnalyticsConfig.customerId=${logAnalyticsWorkspaceIdEnc}" --configuration-protected-settings "logProcessor.appLogs.logAnalyticsConfig.sharedKey=${logAnalyticsKeyEnc}"

# Get ID of the cluster extension & wait for completion
$clusterExtensionId=$(az k8s-extension show --cluster-type connectedClusters --cluster-name $remoteClusterName --resource-group $resourceGroupName --name $extensionName --query id --output tsv)
az resource wait --ids $clusterExtensionId --custom "properties.installState!='Pending'" --api-version "2020-07-01-preview"

# Creating a custom location to deploy to
$customLocationName="codito-HQ"
$connectedClusterId=$(az connectedk8s show --resource-group $resourceGroupName --name $remoteClusterName --query id --output tsv)
az customlocation create --resource-group $resourceGroupName --name $customLocationName --host-resource-id $connectedClusterId --namespace $namespace --cluster-extension-ids $clusterExtensionId
az customlocation show --resource-group $resourceGroupName --name $customLocationName
$customLocationId=$(az customlocation show --resource-group $resourceGroupName --name $customLocationName --query id --output tsv)

# Create the App Service Kubernetes environment
az appservice kube create --resource-group $resourceGroupName --name $kubeEnvironmentName --custom-location $customLocationId --static-ip $staticClusterIp