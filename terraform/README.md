# Phase 1 Terraform Foundation

This deploys the foundation: VPC/subnets, optional billable NAT egress, encrypted S3, DynamoDB idempotency table, EventBridge, SQS FIFO/DLQ, API Gateway and a webhook Lambda.

It deliberately does **not** create ROSA, RDS, ElastiCache or GitLab yet. Those are later milestones after account prerequisites, quotas, cost controls and design validation are complete.

## Prerequisites

- Terraform 1.8+
- AWS CLI configured for `ap-southeast-1`
- An AWS identity permitted to create the listed resources

## Commands

```powershell
cd terraform\environments\dev
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

## Safe cleanup

```powershell
terraform destroy
```

The S3 bucket has `force_destroy = false`; empty it before destroy if it contains objects.


## ROSA network egress

The existing VPC and public/private subnet pairs are reused. DNS support and
hostnames are enabled. Public subnets route `0.0.0.0/0` to the internet gateway;
private subnets now route `0.0.0.0/0` through one public NAT gateway with an Elastic
IP in the first configured AZ. The existing VPC, subnet and shared private route
table resource addresses are retained. No state migration is required by this change.

`enable_nat_gateway = true` is the default. Applying this configuration adds ongoing
NAT gateway, data processing and public IPv4 charges. For Phase 1 without ROSA,
set it to `false` to omit NAT and the private default route. Do not disable it while
ROSA depends on that egress. A single shared NAT is a development cost tradeoff:
it is an AZ dependency and traffic from another AZ can incur cross-AZ charges.
Production needs a separate design with per-AZ NAT gateways and private route tables.

The network pattern follows the [AWS ROSA HCP VPC guide](https://docs.aws.amazon.com/rosa/latest/userguide/getting-started-hcp.html).
NAT does not prove ROSA readiness: also check subnet capacity, quotas, IAM, security
groups, NACLs and required outbound destinations. The existing `/24` subnet sizes
are preserved; size them against the intended cluster before installing.

### Update an existing Phase 1 deployment

Use the original state/backend, workspace and variable values. Do not create a
fresh state or change existing CIDRs/AZs to add egress. Inspect any manually created
NAT/default route first and reconcile/import it rather than creating a conflicting
route. Then, from `terraform/environments/dev`:

```powershell
terraform init
terraform validate
terraform plan -out=network.tfplan
# Review: VPC/subnets should not be replaced. Investigate any replacement or deletion.
terraform apply network.tfplan
terraform output -json foundation
```

Use `foundation.subnets_by_az` to copy a matched public/private pair into
`phase2/config/phase2.config.ps1`, preferably from the first configured AZ where
NAT lives for this Single-AZ lab. Set `AwsRegion` and `MachineCidr` to the matching
values. Run `phase2/scripts/00-preflight.ps1` from the repository root after apply.
The output also exposes `nat_gateway_id` and `private_route_table_id` for inspection.
Do not recreate an existing cluster just to add its missing default route.

Preflight checks effective route tables (including the main-table fallback), the
public internet route, the private NAT route, NAT availability and its public
subnet's internet route. It stops on nonzero AWS/ROSA CLI exits. It expects this
lab's direct NAT architecture; proxy/transit-gateway/egress-zero designs require
different checks. Successful preflight is not an end-to-end connectivity test.

Before destroying Phase 1, remove dependent ROSA resources first. Deleting the
cluster alone leaves the Phase 1 NAT gateway billable until separately removed.

### Repository verification

The `Network checks` workflow initializes providers and runs `terraform validate`
and mocked Terraform network tests without AWS credentials, parses PowerShell, and exercises 16 mocked preflight
success/failure cases. Run the same PowerShell cases locally with:

```powershell
pwsh -NoProfile -File tests/preflight.Tests.ps1
```

These checks do not run `terraform apply` or inspect a live AWS account.
