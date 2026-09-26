$ErrorActionPreference = 'Stop'
$temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path "$temp/scripts", "$temp/config" | Out-Null
Copy-Item "$PSScriptRoot/../phase2/scripts/common.ps1", "$PSScriptRoot/../phase2/scripts/00-preflight.ps1" "$temp/scripts"
@'
$AwsRegion = 'ap-southeast-1'
$MachineCidr = '10.40.0.0/16'
$PublicSubnetId = 'subnet-public'
$PrivateSubnetId = 'subnet-private'
'@ | Set-Content "$temp/config/phase2.config.ps1"

function global:rosa {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'verify' -and $args[1] -eq 'permissions') { throw 'Do not run non-STS permission verification for HCP.' }
    if (($global:Scenario -eq 'authentication' -and $args[0] -eq 'whoami') -or
        ($global:Scenario -eq 'quota' -and $args[1] -eq 'quota')) {
        $global:LASTEXITCODE = 17
    }
}
function global:aws {
    $global:LASTEXITCODE = 0
    if ($args -notcontains '--region' -or $args -notcontains 'ap-southeast-1') { throw 'Missing configured AWS region.' }
    if ($global:Scenario -eq 'aws-failure') { $global:LASTEXITCODE = 12; return }
    if ($args[0] -eq 'sts') { return '{}' }
    switch ($args[1]) {
        'describe-subnets' {
            $public = @{SubnetId='subnet-public';VpcId='vpc-test';AvailabilityZone='ap-southeast-1a';State='available';MapPublicIpOnLaunch=$true}
            $private = @{SubnetId='subnet-private';VpcId='vpc-test';AvailabilityZone='ap-southeast-1a';State='available';MapPublicIpOnLaunch=$false}
            if ($global:Scenario -eq 'different-vpc') { $private.VpcId = 'vpc-other' }
            if ($global:Scenario -eq 'different-az') { $private.AvailabilityZone = 'ap-southeast-1b' }
            if ($global:Scenario -eq 'private-public-ip') { $private.MapPublicIpOnLaunch = $true }
            @{Subnets=@($public,$private)} | ConvertTo-Json -Depth 8
        }
        'describe-vpcs' {
            $cidr = '10.40.0.0/16'
            if ($global:Scenario -eq 'machine-cidr') { $cidr = '10.99.0.0/16' }
            @{Vpcs=@(@{CidrBlock=$cidr})} | ConvertTo-Json -Depth 8
        }
        'describe-vpc-attribute' {
            @{EnableDnsSupport=@{Value=($global:Scenario -ne 'dns')};EnableDnsHostnames=@{Value=$true}} | ConvertTo-Json -Depth 8
        }
        'describe-route-tables' {
            $publicRoute = @{DestinationCidrBlock='0.0.0.0/0';State='active';GatewayId='igw-test'}
            $privateRoute = @{DestinationCidrBlock='0.0.0.0/0';State='active';NatGatewayId='nat-test'}
            if ($global:Scenario -eq 'blackhole') { $privateRoute.State = 'blackhole' }
            $privateRoutes = @($privateRoute)
            if ($global:Scenario -eq 'no-egress') { $privateRoutes = @() }
            $publicRoutes = @($publicRoute)
            if ($global:Scenario -eq 'no-igw') { $publicRoutes = @() }
            $privateAssociations = @(@{SubnetId='subnet-private'})
            if ($global:Scenario -eq 'main-fallback') { $privateAssociations = @(@{Main=$true}) }
            @{RouteTables=@(
                @{Associations=@(@{SubnetId='subnet-public'});Routes=$publicRoutes},
                @{Associations=$privateAssociations;Routes=$privateRoutes}
            )} | ConvertTo-Json -Depth 8
        }
        'describe-internet-gateways' {
            $vpc = 'vpc-test'
            if ($global:Scenario -eq 'detached-igw') { $vpc = 'vpc-other' }
            @{InternetGateways=@(@{Attachments=@(@{VpcId=$vpc;State='available'})})} | ConvertTo-Json -Depth 8
        }
        'describe-nat-gateways' {
            $nat = @{State='available';VpcId='vpc-test';ConnectivityType='public';SubnetId='subnet-public'}
            if ($global:Scenario -eq 'nat-pending') { $nat.State = 'pending' }
            if ($global:Scenario -eq 'nat-private') { $nat.ConnectivityType = 'private' }
            @{NatGateways=@($nat)} | ConvertTo-Json -Depth 8
        }
        default { throw "Unexpected AWS command: $args" }
    }
}
try {
    $cases = [ordered]@{
        valid = $null
        'main-fallback' = $null
        'aws-failure' = 'exit code 12'
        authentication = 'exit code 17'
        quota = 'exit code 17'
        'different-vpc' = 'same VPC and Availability Zone'
        'different-az' = 'same VPC and Availability Zone'
        'private-public-ip' = 'must not auto-assign'
        'machine-cidr' = 'MachineCidr must match'
        dns = 'enableDnsSupport must be enabled'
        'no-egress' = 'default route to a NAT'
        blackhole = 'default route to a NAT'
        'no-igw' = 'default route to an internet gateway'
        'detached-igw' = 'not attached'
        'nat-pending' = 'available public NAT'
        'nat-private' = 'available public NAT'
    }
    foreach ($case in $cases.GetEnumerator()) {
        $global:Scenario = $case.Key
        $failure = $null
        try { & "$temp/scripts/00-preflight.ps1" | Out-Null } catch { $failure = $_.Exception.Message }
        if ($null -eq $case.Value -and $null -ne $failure) { throw "$($case.Key): $failure" }
        if ($null -ne $case.Value -and ($null -eq $failure -or $failure -notlike "*$($case.Value)*")) {
            throw "$($case.Key): expected '$($case.Value)', got '$failure'"
        }
        Write-Host "PASS $($case.Key)"
    }
} finally {
    Remove-Item -Recurse -Force $temp
    Remove-Item Function:\aws, Function:\rosa
}
