. "$PSScriptRoot\common.ps1"
Require-Command oc
$ManifestPath = Join-Path $ProjectRoot "openshift"
oc whoami
oc new-project $ProjectName 2>$null
if ($LASTEXITCODE -ne 0) { oc project $ProjectName }
(Get-Content (Join-Path $ManifestPath "deployment.yaml") -Raw) -replace "__APPLICATION_IMAGE__",$ApplicationImage -replace "__APPLICATION_NAME__",$ApplicationName | oc apply -f -
foreach($f in @("service.yaml","route.yaml","hpa.yaml","networkpolicy.yaml")) { (Get-Content (Join-Path $ManifestPath $f) -Raw) -replace "__APPLICATION_NAME__",$ApplicationName | oc apply -f - }
oc rollout status "deployment/$ApplicationName" --timeout=5m
oc get route $ApplicationName
