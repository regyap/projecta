. "$PSScriptRoot\common.ps1"
Require-Command rosa
Require-ConfiguredValue "PublicSubnetId" $PublicSubnetId
Require-ConfiguredValue "PrivateSubnetId" $PrivateSubnetId
Require-ConfiguredValue "OidcConfigId" $OidcConfigId
Write-Host "This creates a billable ROSA HCP cluster."
if ((Read-Host "Type CREATE to continue") -ne "CREATE") { throw "Cancelled." }
rosa create cluster --cluster-name $ClusterName --region $AwsRegion --sts --mode auto --hosted-cp --operator-roles-prefix $OperatorRolesPrefix --oidc-config-id $OidcConfigId --subnet-ids "$PublicSubnetId,$PrivateSubnetId" --machine-cidr $MachineCidr --yes
rosa describe cluster --cluster $ClusterName
