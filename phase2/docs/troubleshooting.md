# Troubleshooting

- Enable ROSA in the AWS ROSA console before creating a cluster.
- `rosa verify permissions` must pass for automatic IAM creation.
- For this Single-AZ example, the public and private subnets must belong to the same VPC and Availability Zone.
- The VPC CIDR must match `MachineCidr`.
- The Phase 1 demo VPC may require NAT/outbound routing and other ROSA-specific networking changes.
- Use `rosa describe cluster -c <name> --debug` for cluster creation failures.
