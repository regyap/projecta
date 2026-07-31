. "$PSScriptRoot\common.ps1"
Require-Command aws
Require-Command rosa
aws sts get-caller-identity
rosa version
rosa verify permissions
rosa verify quota
rosa whoami
Require-ConfiguredValue "PublicSubnetId" $PublicSubnetId
Require-ConfiguredValue "PrivateSubnetId" $PrivateSubnetId
aws ec2 describe-subnets --subnet-ids $PublicSubnetId $PrivateSubnetId --query "Subnets[].{SubnetId:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,VpcId:VpcId,PublicIP:MapPublicIpOnLaunch}"
Write-Host "Confirm both subnets are in the same VPC and AZ for this Single-AZ lab."
