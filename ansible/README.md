# Moderate, application-scoped container baseline

Run on a controller with Python, ansible-core and the Kubernetes Python client.
Install the collection: `ansible-galaxy collection install -r ansible/requirements.yml`.
Preview locally: `ansible-playbook ansible/container-baseline.yml`.
This writes `.rendered/container-patch.yaml` and contacts no cluster by default.

After inspecting the patch, authenticate to the intended cluster and set its exact
HTTPS API endpoint explicitly:

```sh
ansible-playbook ansible/container-baseline.yml \
  -e apply_changes=true -e expected_api_server=https://api.example.com:6443
```

Use `--check --diff` with the same variables for a server-connected preview first.
Scope is one named container in one Deployment, not the whole cluster. The patch
preserves images, probes and resource requests. It disables token automount,
privilege escalation and capabilities, uses RuntimeDefault seccomp and a read-only
root, and adds writable `/tmp` for Gunicorn. It leaves OpenShift's assigned UID
alone. Set `read_only_root=false` for a documented compatibility exception; mount
specific writable paths instead when possible. Do not apply this to GitLab itself,
build runners, privileged infrastructure components or an app that needs API tokens
without adapting the baseline. No host sysctls, SELinux changes, package removal,
or full CIS/STIG compliance is claimed. Keep the source Deployment aligned with
this patch so a later CI deployment does not undo it.

## LDAP template

`ansible-playbook ansible/ldap-config.yml` renders a **Linux-package GitLab** fragment.
Override sample values using `-e @your.local.yml` (gitignored). It does not install
GitLab/AD, copy secrets, restart services or alter a live directory. See
[GitLab identity setup](../gitlab/README.md) for activation and verification.
