$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $ProjectRoot "config\phase2.config.ps1"
if (-not (Test-Path $ConfigPath)) { throw "Missing $ConfigPath. Copy phase2.config.example.ps1 to phase2.config.ps1 and edit it." }
. $ConfigPath
function Require-Command { param([string]$Name); if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Required command '$Name' is not installed or not in PATH." } }
function Require-ConfiguredValue { param([string]$Name,[string]$Value); if ([string]::IsNullOrWhiteSpace($Value) -or $Value -match "REPLACE") { throw "Set '$Name' in config\phase2.config.ps1." } }
