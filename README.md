# ROSA GitLab Platform - Phase 1

Contents:

- `ROSA_GitLab_Platform_Phase_1.docx` - architecture and implementation plan
- `terraform/` - deployable AWS event foundation
- `lambda/` - signed webhook validator with DynamoDB idempotency
- `diagrams/` - architecture source and PNG

This is intentionally the first controlled milestone, not the entire platform.


## Architecture extension

See [architecture v2](docs/architecture-v2.md) for developer delivery, IAM boundaries,
S3/SQS controls, optional Rekognition and consented geolocation, GitLab/LDAP setup,
and the moderate Ansible container baseline. The document distinguishes implemented
code from pending integrations and explains the existing webhook prototype's limits.

- [GitLab and LDAP setup](gitlab/README.md)
- [Ansible baseline](ansible/README.md)
- [Optional media worker](services/media/README.md)
