# Paso 1: crea (o arranca) el clúster minikube del laboratorio.
#
# Contempla dos fallas conocidas de minikube con el driver docker:
#   a) El perfil existe pero su contenedor desapareció (docker rm, reset de
#      Rancher/Docker Desktop...). minikube intenta "reiniciar" un clúster que ya
#      no existe y el kubelet queda sin /etc/kubernetes/bootstrap-kubelet.conf.
#      -> Se detecta ANTES de arrancar y se borra el perfil huérfano.
#   b) 'minikube start' termina "bien" pero kubelet/apiserver no corren.
#      -> Se detecta DESPUÉS de arrancar, se recrea el perfil y se reintenta una vez.
param(
    [int]$Cpus = 4,
    [int]$MemoryMb = 6144,
    [string]$Driver = ''   # vacío = el driver por defecto de minikube (docker, hyperv...)
)
. "$PSScriptRoot\_comun.ps1"

function Get-ProfileDriver {
    $mkHome = if ($env:MINIKUBE_HOME) { $env:MINIKUBE_HOME } else { Join-Path $HOME '.minikube' }
    $cfg = Join-Path $mkHome "profiles\$MinikubeProfile\config.json"
    if (-not (Test-Path $cfg)) { return $null }
    (Get-Content $cfg -Raw | ConvertFrom-Json).Driver
}

function Test-ContainerExists {
    $ErrorActionPreference = 'Continue'
    docker container inspect $MinikubeProfile *> $null
    $LASTEXITCODE -eq 0
}

function Get-ControlPlaneStatus {
    $ErrorActionPreference = 'Continue'
    minikube -p $MinikubeProfile status --format '{{.Kubelet}}/{{.APIServer}}' 2>$null
}

# Espera a que kubelet y apiserver estén Running (pueden tardar unos segundos tras el start).
function Wait-ControlPlane([int]$TimeoutSeconds = 90) {
    $limit = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $status = Get-ControlPlaneStatus
        if ($status -eq 'Running/Running') { return $true }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $limit)
    Write-Host "Estado del control plane: $status" -ForegroundColor Red
    return $false
}

function Remove-Profile([string]$Reason) {
    Write-Host "$Reason -> se borra el perfil '$MinikubeProfile' para crearlo de cero" -ForegroundColor Yellow
    Invoke-Native 'minikube delete' { minikube delete -p $MinikubeProfile }
}

# --- a) Perfil huérfano ---------------------------------------------------------
$existingDriver = Get-ProfileDriver
if ($existingDriver -eq 'docker' -and -not (Test-ContainerExists)) {
    Remove-Profile 'El perfil existe pero su contenedor Docker no'
}

# --- Arranque con un reintento -----------------------------------------------------
$startArgs = @('start', '-p', $MinikubeProfile, "--cpus=$Cpus", "--memory=$MemoryMb")
if ($Driver) { $startArgs += "--driver=$Driver" }

$ok = $false
foreach ($attempt in 1..2) {
    Write-Step "Iniciando minikube (perfil '$MinikubeProfile', $Cpus CPU, $MemoryMb MB) - intento $attempt"
    $ErrorActionPreference = 'Continue'
    minikube @startArgs
    $ErrorActionPreference = 'Stop'

    Write-Step 'Verificando que kubelet y apiserver estén corriendo'
    if (Wait-ControlPlane) { $ok = $true; break }

    # --- b) Control plane roto ---
    if ($attempt -eq 1) { Remove-Profile 'El control plane no arrancó' }
}

if (-not $ok) {
    Write-Host "`nEl clúster no arrancó tras recrearlo. Diagnóstico:" -ForegroundColor Red
    Write-Host "  minikube -p $MinikubeProfile ssh -- sudo journalctl -u kubelet -n 30"
    Write-Host "  minikube -p $MinikubeProfile logs --problems"
    exit 1
}

# Se habilita DESPUÉS de verificar el apiserver: si se activa antes, minikube intenta
# aplicarlo mientras el apiserver arranca y falla con 'connection refused'.
Write-Step 'Habilitando metrics-server (para kubectl top)'
Invoke-Native 'addon metrics-server' { minikube -p $MinikubeProfile addons enable metrics-server }

Write-Step 'Esperando a que el nodo esté Ready'
Invoke-Native 'nodo Ready' { kubectl wait --for=condition=Ready "node/$MinikubeProfile" --timeout=120s }
kubectl get nodes
