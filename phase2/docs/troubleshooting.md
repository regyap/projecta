# Troubleshooting

- Enable ROSA in the AWS ROSA console before creating a cluster.
- `rosa verify permissions` validates non-STS installations and is not an HCP/STS IAM readiness check. Verify the HCP account/operator roles and trust relationships during role setup.
- Authenticate with `rosa login --use-auth-code` before preflight; after creating the cluster admin, run the printed `oc login` command before deploying.
- For this Single-AZ example, the public and private subnets must belong to the same VPC and Availability Zone.
- The VPC CIDR must match `MachineCidr`.
- Phase 1 now supports NAT egress (`enable_nat_gateway = true`). Apply it with the original Terraform state, then run `scripts/00-preflight.ps1`. See [network setup](../../terraform/README.md#rosa-network-egress).
- A missing private default route is a configuration suspect, not proof of a live cluster failure. Inspect `rosa describe cluster --cluster rosa-gitlab-dev` and `rosa logs install --cluster rosa-gitlab-dev` before recreating anything.
- Preflight rejects failed native commands, mismatched subnet VPC/AZ, disabled VPC DNS, and missing/inactive NAT/IGW routes. All AWS queries use the configured region.
- Inspect actual routes with `aws ec2 describe-route-tables --region ap-southeast-1 --filters "Name=vpc-id,Values=<actual-vpc-id>"`. Account for any manually managed networking.
- Use `rosa describe cluster -c <name> --debug` for cluster creation failures.

