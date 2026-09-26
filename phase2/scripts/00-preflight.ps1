. "$PSScriptRoot\common.ps1"
Require-Command aws
Require-Command rosa
Require-ConfiguredValue "AwsRegion" $AwsRegion
Require-ConfiguredValue "MachineCidr" $MachineCidr
Require-ConfiguredValue "PublicSubnetId" $PublicSubnetId
Require-ConfiguredValue "PrivateSubnetId" $PrivateSubnetId

Invoke-CheckedNative aws @('sts', 'get-caller-identity', '--region', $AwsRegion, '--no-cli-pager')
Invoke-CheckedNative rosa @('version')
Invoke-CheckedNative rosa @('verify', 'permissions', '--region', $AwsRegion)
Invoke-CheckedNative rosa @('verify', 'quota', '--region', $AwsRegion)
Invoke-CheckedNative rosa @('whoami')

function Read-Ec2Json {
    param([string[]]$Arguments)
    $raw = Invoke-CheckedNative aws (@('ec2') + $Arguments + @('--region', $AwsRegion, '--output', 'json', '--no-cli-pager'))
    return ($raw -join "`n" | ConvertFrom-Json)
}

$subnets = @( (Read-Ec2Json @('describe-subnets', '--subnet-ids', $PublicSubnetId, $PrivateSubnetId)).Subnets )
$public = @($subnets | Where-Object { $_.SubnetId -eq $PublicSubnetId })
$private = @($subnets | Where-Object { $_.SubnetId -eq $PrivateSubnetId })
if ($PublicSubnetId -eq $PrivateSubnetId -or $public.Count -ne 1 -or $private.Count -ne 1) {
    throw 'Expected two distinct, existing public/private subnet IDs.'
}
$public = $public[0]
$private = $private[0]
if ($public.VpcId -ne $private.VpcId -or $public.AvailabilityZone -ne $private.AvailabilityZone) {
    throw 'The Single-AZ lab requires both subnets in the same VPC and Availability Zone.'
}
if ($public.State -ne 'available' -or $private.State -ne 'available') {
    throw 'Both subnets must be available.'
}
if ($private.MapPublicIpOnLaunch) { throw 'The private subnet must not auto-assign public IPv4 addresses.' }

$vpcId = $public.VpcId
$vpcs = @( (Read-Ec2Json @('describe-vpcs', '--vpc-ids', $vpcId)).Vpcs )
if ($vpcs.Count -ne 1 -or $vpcs[0].CidrBlock -ne $MachineCidr) {
    throw 'MachineCidr must match the lab VPC primary CIDR.'
}
foreach ($attribute in @('enableDnsSupport', 'enableDnsHostnames')) {
    $result = Read-Ec2Json @('describe-vpc-attribute', '--vpc-id', $vpcId, '--attribute', $attribute)
    $property = $attribute.Substring(0, 1).ToUpper() + $attribute.Substring(1)
    if (-not $result.$property.Value) { throw "VPC $attribute must be enabled." }
}

$routeTables = @( (Read-Ec2Json @('describe-route-tables', '--filters', "Name=vpc-id,Values=$vpcId")).RouteTables )
function Get-EffectiveRouteTable {
    param([string]$SubnetId)
    $matches = @($routeTables | Where-Object { @($_.Associations | Where-Object { $_.SubnetId -eq $SubnetId }).Count -gt 0 })
    if ($matches.Count -eq 0) {
        $matches = @($routeTables | Where-Object { @($_.Associations | Where-Object { $_.Main -eq $true }).Count -gt 0 })
    }
    if ($matches.Count -ne 1) { throw "Cannot resolve exactly one effective route table for $SubnetId." }
    return $matches[0]
}
function Require-InternetRoute {
    param([string]$SubnetId)
    $table = Get-EffectiveRouteTable $SubnetId
    $routes = @($table.Routes | Where-Object { $_.DestinationCidrBlock -eq '0.0.0.0/0' -and $_.State -eq 'active' -and $_.GatewayId -like 'igw-*' })
    if ($routes.Count -ne 1) { throw "Subnet $SubnetId needs an active default route to an internet gateway." }
    $gateways = @( (Read-Ec2Json @('describe-internet-gateways', '--internet-gateway-ids', $routes[0].GatewayId)).InternetGateways )
    if (@($gateways.Attachments | Where-Object { $_.VpcId -eq $vpcId -and $_.State -eq 'available' }).Count -ne 1) {
        throw 'Internet gateway is not attached to the selected VPC.'
    }
}
Require-InternetRoute $PublicSubnetId
$privateTable = Get-EffectiveRouteTable $PrivateSubnetId
$natRoutes = @($privateTable.Routes | Where-Object { $_.DestinationCidrBlock -eq '0.0.0.0/0' -and $_.State -eq 'active' -and $_.NatGatewayId -like 'nat-*' })
if ($natRoutes.Count -ne 1) { throw 'Private subnet needs an active default route to a NAT gateway for this lab.' }
$natGateways = @( (Read-Ec2Json @('describe-nat-gateways', '--nat-gateway-ids', $natRoutes[0].NatGatewayId)).NatGateways )
if ($natGateways.Count -ne 1 -or $natGateways[0].State -ne 'available' -or $natGateways[0].VpcId -ne $vpcId -or $natGateways[0].ConnectivityType -ne 'public') {
    throw 'The private route must target an available public NAT gateway in the same VPC.'
}
# The shared NAT may be in another AZ; check its actual subnet as well.
Require-InternetRoute $natGateways[0].SubnetId
Write-Host 'Preflight passed: CLI prerequisites and the lab NAT routing checks passed.'
Write-Host 'This does not verify security groups, NACLs, endpoint reachability, available IP capacity, or cluster installation health.'
