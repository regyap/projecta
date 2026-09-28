# Developer push, GitLab, identity and deployment

GitHub remains the review/source location for this change. Import or mirror the
whole repository into your GitLab project to run the root `.gitlab-ci.yml`.
Do not mirror secrets. Developers push feature branches to GitLab from their IDE;
merge requests run Python tests, source/secret scans, rootless image builds and image
scans. Maintainers merge to a protected default branch. A blocking manual dev deploy
uses the exact commit tag; verification checks the rollout and HTTPS responses.
The existing custom webhook/EventBridge/FIFO prototype is not the deployment trigger.

## One-time configuration (not applied by this PR)

1. Protect the default branch and disable direct developer pushes. Require successful
   pipelines and reviewers; approval enforcement features vary by GitLab tier.
   Enable MFA, disable public sign-up, use private projects and review PAT scopes.
2. Use disposable isolated runners for image builds. The rootless BuildKit template
   uses `--oci-worker-no-process-sandbox` per GitLab's documented pattern; this is
   not a sandbox for hostile jobs. Do not put builds on production nodes or mount
   a host Docker socket. Configure runner user namespaces/AppArmor appropriately;
   do not make production app pods privileged to fix build-runner compatibility.
3. Separate protected deployment runners from untrusted merge-request runners.
   Set the deploy jobs' tags to your protected runner tag; enforce that setting on
   the GitLab runner. Runtime credentials must be masked, protected and dev-scoped.
4. Bootstrap the dedicated `gitlab-platform` namespace and the application resources
   once as an administrator using a built, scanned application image. Apply
   `gitlab/deployer-rbac.yaml`. The deployer intentionally cannot create namespaces,
   Secrets, roles or new resources; it patches only the named existing resources.
   Do not place other privileged service accounts or sensitive workloads in this
   namespace. Deployment-edit permission can alter pod specs: namespace separation
   and OpenShift SCC enforcement remain essential boundaries.
5. Configure `OPENSHIFT_SERVER` (exact API URL), `OPENSHIFT_TOKEN` (short-lived token
   for `gitlab-deployer`), and file-type variables `OPENSHIFT_CA_FILE` and
   `APPLICATION_CA_FILE` with trusted CA bundles. Arrange issuance/rotation through
   your chosen identity integration. There is no long-lived token creation here;
   AWS OIDC does not automatically authenticate a job to OpenShift.
6. If the GitLab image registry is private, bootstrap a read-only registry pull
   Secret and link it to the app's service account (`default` in this lab). Use a
   deploy token with `read_registry`, not an expiring CI job password. Do not put
   the value in YAML or grant the deployer Secret permissions. If using another
   application name/namespace, update the RBAC allowlist too.
7. Pipeline image tags are explicit; verify availability in your environment and
   pin approved image digests as part of your release policy. Keep scanner images
   and databases updated. The scans gate HIGH/CRITICAL findings, including unfixed
   findings; failing builds require investigation, not disabling the gate.

## AWS identity

Set Terraform `gitlab_oidc` only after an administrator configures and verifies the
AWS IAM OIDC provider, issuer discovery/JWKS and audience `sts.amazonaws.com`:

```hcl
gitlab_oidc = {
  provider_arn = "arn:aws:iam::123456789012:oidc-provider/gitlab.example.com"
  issuer       = "https://gitlab.example.com"
  project_path = "platform/projecta"
  branch       = "main"
}
```

Use the resulting role only with `artifact-publish.job.yml.example`. Its trust
requires an exact audience and project/branch subject; no wildcard trust or static
AWS keys. Match any customized GitLab subject claims to this trust explicitly.
Private/self-managed GitLab discovery must be accessible to AWS; don't publish
private configuration or use broad trust to bypass reachability. The role cannot
run Terraform, administer IAM, deploy ROSA, access media or delete artifacts.
ROSA account/operator roles, application AWS roles, CI artifact writing, Kubernetes
RBAC and LDAP user authentication are separate permissions domains.

## LDAP / Active Directory

Reference deployment: an existing **self-managed Linux-package GitLab server**,
with ROSA hosting the application. The PR does not install GitLab, Runner or AD.
Do not paste the Linux-package fragment into a GitLab Helm deployment; translate
using the chart's documented LDAP and secret settings if hosting GitLab on ROSA.
GitLab.com cannot use this self-managed LDAP configuration.

Render `ansible/ldap-config.yml`, review it, then include the fragment from your
existing `/etc/gitlab/gitlab.rb` with `from_file '/etc/gitlab/gitlab-ldap.rb'`.
Install the AD CA chain at the configured path and provision the bind password via
your secret manager into the configured root-owned `0600` file. Never commit it.
Back up the existing configuration and retain a tested local break-glass admin.
Run `gitlab-ctl reconfigure`, then `gitlab-rake gitlab:ldap:check` during an approved
change window. Check LDAPS reachability, DNS/hostname certificate matching, bind DN,
base DN and the group filter before approving newly created accounts.

The template uses LDAPS 636, `simple_tls`, certificate verification, a read-only
bind account and an explicit GitLab-Users AD group filter. It blocks automatic user
activation. It does not grant GitLab maintainer/admin rights based on LDAP login.
Nested AD groups need a deliberate recursive filter; the sample matches direct
membership. GitLab group synchronization depends on tier; this sample assumes
manual GitLab project/group role assignment. AD users must not be able to rewrite
the email attributes used to link identities. LDAPS alone is not MFA; configure
MFA/SSO according to your authentication policy. Permit AD access only from GitLab
through the private network/VPN; never expose LDAP to the internet.

Sources:
- https://docs.gitlab.com/ci/docker/using_buildkit/
- https://docs.gitlab.com/ci/cloud_services/aws/
- https://docs.gitlab.com/administration/auth/ldap/
