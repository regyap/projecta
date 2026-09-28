# ROSA GitLab Platform — Phase 2

Phase 2 provisions a ROSA with Hosted Control Planes (HCP) cluster using the ROSA CLI, then deploys a sample application to OpenShift.

## Cost warning
ROSA creates billable AWS and Red Hat resources. Review pricing and quotas before cluster creation, and delete the cluster when the lab is finished.

## Start
```powershell
Copy-Item .\config\phase2.config.example.ps1 .\config\phase2.config.ps1
notepad .\config\phase2.config.ps1
rosa login --use-auth-code
.\scripts\00-preflight.ps1
.\scripts\01-create-account-roles.ps1
.\scripts\02-create-oidc-and-operator-roles.ps1
.\scripts\03-create-cluster.ps1
.\scripts\04-watch-cluster.ps1
.\scripts\05-create-admin.ps1
# Run the oc login command printed above and wait for login to succeed.
.\scripts\06-deploy-app.ps1
.\scripts\07-verify.ps1
```

Cleanup:
```powershell
.\scripts\99-delete-cluster.ps1
```


Before creating the cluster, [apply and verify Phase 1 NAT egress](../terraform/README.md#rosa-network-egress), select a matched subnet pair, and run `scripts/00-preflight.ps1`.
