. "$PSScriptRoot\common.ps1"
Write-Host "This permanently deletes the ROSA cluster."
if ((Read-Host "Type $ClusterName to continue") -ne $ClusterName) { throw "Cancelled." }
rosa delete cluster --cluster $ClusterName --yes
Write-Host "Wait for deletion to finish before deleting OIDC or IAM roles."
