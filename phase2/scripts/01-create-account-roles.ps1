. "$PSScriptRoot\common.ps1"
Require-Command rosa
rosa create account-roles --hosted-cp --prefix $AccountRolesPrefix --mode auto --yes
rosa list account-roles
