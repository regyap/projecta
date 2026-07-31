# Phase 1 Terraform Foundation

This deploys only the low-risk foundation: VPC/subnets, encrypted S3, DynamoDB idempotency table, EventBridge, SQS FIFO/DLQ, API Gateway and a webhook Lambda.

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
