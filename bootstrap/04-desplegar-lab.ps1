# Paso 4: arranca el GitOps. Aplica UNA sola Application (la raíz) y Argo CD hace el resto:
#
#   root-app-manager  ->  app-manager/ : AppProject "lab" + ApplicationSets
#     lab-charts      ->  platform/charts/*/platform.yaml     ->  lab-keda
#     lab-manifests   ->  platform/manifests/*/platform.yaml  ->  lab-rabbitmq, lab-keda-demo
#
# Los repositorios Git son la fuente de verdad: el repo tiene que estar publicado en GitHub ANTES
# de ejecutar este script (ver README, "Publicar el repositorio").
param([int]$TimeoutMinutes = 12)
. "$PSScriptRoot\_comun.ps1"

Write-Step "Comprobando que Argo CD podrá leer $RepoUrl"
if (-not (Test-RepoReachable)) {
    Write-Host "No puedo leer la rama 'main' de $RepoUrl" -ForegroundColor Red
    Write-Host '  - ¿Está creado el repositorio y subido el contenido de lab_keda? (README: "Publicar el repositorio")'
    Write-Host '  - Si es privado: configura tu acceso a GitHub y define $env:GH_TOKEN antes del paso 02.'
    exit 1
}
Write-Host '  OK' -ForegroundColor DarkGray

Write-Step 'Aplicando la Application raíz (bootstrap\root-app.yaml)'
Invoke-Native 'apply root-app' { kubectl apply -f (Join-Path $PSScriptRoot 'root-app.yaml') }

Write-Step 'Esperando a que Argo CD cree y sincronice las Applications'
Write-Host '  (lab-keda-demo puede fallar sus primeros intentos hasta que existan las CRDs de KEDA: reintenta solo)' -ForegroundColor DarkGray
# Una línea sólo cuando cambia el estado: no se pierde la salida de los pasos anteriores.
$template = '{range .items[*]}{.metadata.name}={.status.sync.status}/{.status.health.status}  {end}'
$limit = (Get-Date).AddMinutes($TimeoutMinutes)
$ErrorActionPreference = 'Continue'
$last = ''
do {
    Start-Sleep -Seconds 5
    $state = (kubectl -n $ArgoNamespace get applications -o "jsonpath=$template" 2>$null)
    if ($state -and $state -ne $last) {
        Write-Host ("  {0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $state.Trim())
        $last = $state
    }
    $items = @(($state -split '\s{2,}') | Where-Object { $_ -match '=' })
    # root-app-manager + lab-keda + lab-rabbitmq + lab-keda-demo
    $done = ($items.Count -ge 4) -and (@($items | Where-Object { $_ -notmatch '=Synced/Healthy$' }).Count -eq 0)
} until ($done -or (Get-Date) -gt $limit)

if (-not $done) {
    Write-Host "`nNo terminó en $TimeoutMinutes minutos. Recursos que no están Healthy:" -ForegroundColor Yellow
    foreach ($app in 'root-app-manager', 'lab-keda', 'lab-rabbitmq', 'lab-keda-demo') {
        $json = kubectl -n $ArgoNamespace get application $app -o json 2>$null
        if (-not $json) { Write-Host "  [$app] no existe todavía"; continue }
        $a = $json -join "`n" | ConvertFrom-Json
        if ($a.status.operationState.phase -eq 'Failed' -or $a.status.operationState.phase -eq 'Error') {
            Write-Host "  [$app] sync: $($a.status.operationState.message)"
        }
        $a.status.resources | Where-Object { $_.health -and $_.health.status -ne 'Healthy' } |
            ForEach-Object { Write-Host "  [$app] $($_.kind)/$($_.name): $($_.health.status) $($_.health.message)" }
    }
    Write-Host '  Más detalle: kubectl -n argocd describe application <nombre>'
    exit 1
}

Write-Step 'Laboratorio listo'
kubectl -n $KedaNamespace get deployments
kubectl -n $DemoNamespace get scaledobject,hpa,deployment
