. "$PSScriptRoot\common.ps1"
rosa describe cluster --cluster $ClusterName
oc get clusteroperators
oc get nodes -o wide
oc get all -n $ProjectName
oc get hpa -n $ProjectName
$HostName = oc get route $ApplicationName -n $ProjectName -o jsonpath='{.spec.host}'
Write-Host "https://$HostName"
