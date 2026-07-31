. "$PSScriptRoot\common.ps1"
Require-Command rosa
rosa create oidc-config --mode auto --yes
rosa list oidc-config
$OidcId = Read-Host "Paste the OIDC configuration ID created above"
if ([string]::IsNullOrWhiteSpace($OidcId)) { throw "OIDC ID cannot be blank." }
rosa create operator-roles --hosted-cp --prefix $OperatorRolesPrefix --oidc-config-id $OidcId --mode auto --yes
rosa list operator-roles
Write-Host "Save in config\phase2.config.ps1: `$OidcConfigId = `"$OidcId`""
