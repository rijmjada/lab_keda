# Configuración compartida. Se carga desde los demás scripts con: . "$PSScriptRoot\_comun.ps1"
$ErrorActionPreference = 'Stop'

$MinikubeProfile  = 'lab-keda'
$ArgoNamespace    = 'argocd'
$ArgoChartVersion = '10.18.0'
$KedaNamespace    = 'keda'
$DemoNamespace    = 'keda-demo'
$WorkerImage      = 'keda-demo-worker:1.0'

# Repositorio que vigila Argo CD. Es el MISMO valor que hay en bootstrap\root-app.yaml y en
# app-manager\*.yaml (si cambias de organización o de nombre, cámbialo en los cuatro sitios).
$RepoUrl          = 'https://github.com/diegodevopsorg/lab-keda.git'

# Puertos distintos a los de los otros labs (KEDA 8080/15672, VPA 8081-8082, Knative 8083-8084,
# Prometheus 8085-8087).
$ArgoPort         = 8090
$RabbitPort       = 15673

$ProjectRoot      = Split-Path -Parent $PSScriptRoot
$PidFile          = Join-Path $ProjectRoot '.port-forward.pids'

function Write-Step([string]$Text) {
    Write-Host "`n==> $Text" -ForegroundColor Cyan
}

# Ejecuta un comando externo y corta el script si falla.
function Invoke-Native([string]$Description, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Falló: $Description (exit code $LASTEXITCODE)" }
}

function Get-ArgoPassword {
    $encoded = kubectl -n $ArgoNamespace get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
}

# ¿Existe el repo y tiene la rama main? Sin prompts: si pide credenciales, falla en vez de colgarse.
function Test-RepoReachable {
    $ErrorActionPreference = 'Continue'
    $env:GIT_TERMINAL_PROMPT = '0'
    git ls-remote --exit-code $RepoUrl main *> $null
    $LASTEXITCODE -eq 0
}
