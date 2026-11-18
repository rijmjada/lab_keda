# Abre port-forwards en segundo plano hacia la UI de Argo CD y la de RabbitMQ,
# espera a que respondan y recién entonces abre el navegador.
#   Argo CD  -> http://localhost:8090   (admin / password del paso 2)
#   RabbitMQ -> http://localhost:15673  (demo / demo123)
. "$PSScriptRoot\_comun.ps1"

# Siempre se parte limpio: cierra port-forwards previos (incluidos huérfanos).
& "$PSScriptRoot\07-cerrar-uis.ps1" *> $null

$forwards = @(
    @{ Name = 'RabbitMQ'; Ns = $DemoNamespace; Svc = 'svc/rabbitmq';      Port = $RabbitPort; TargetPort = 15672; Path = '/#/queues' },
    @{ Name = 'Argo CD';  Ns = $ArgoNamespace; Svc = 'svc/argocd-server'; Port = $ArgoPort;   TargetPort = 80;    Path = '/applications?view=tree' }
)

Write-Step 'Abriendo port-forwards'
$started = @()
$pids = foreach ($f in $forwards) {
    $ErrorActionPreference = 'Continue'
    kubectl -n $f.Ns get $f.Svc *> $null
    if ($LASTEXITCODE -ne 0) { Write-Host "  $($f.Name): el Service todavía no existe, se omite" -ForegroundColor Yellow; continue }
    $ErrorActionPreference = 'Stop'
    $started += $f
    $p = Start-Process kubectl -WindowStyle Hidden -PassThru `
        -ArgumentList @('-n', $f.Ns, 'port-forward', $f.Svc, "$($f.Port):$($f.TargetPort)")
    $p.Id
}
$pids | Set-Content $PidFile

# Listo = devuelve CUALQUIER respuesta HTTP (un 4xx/5xx también cuenta).
function Wait-Http([string]$Url, [int]$TimeoutSeconds = 60) {
    $limit = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $limit) {
        try { Invoke-WebRequest $Url -UseBasicParsing -TimeoutSec 3 | Out-Null; return $true }
        catch { if ($_.Exception.Response) { return $true } }
        Start-Sleep -Seconds 1
    }
    return $false
}

Write-Step 'Esperando a que las UIs respondan'
$ready = @{}
foreach ($f in $started) {
    $ready[$f.Name] = Wait-Http "http://localhost:$($f.Port)/"
    Write-Host ("  {0,-9} :{1,-6} {2}" -f $f.Name, $f.Port, $(if ($ready[$f.Name]) { 'OK' } else { 'NO RESPONDE' }))
}

# Argo CD al final para que quede como pestaña activa.
foreach ($f in $started) {
    if ($ready[$f.Name]) { Start-Process "http://localhost:$($f.Port)$($f.Path)" }
}

# Resumen al final de todo, para que sea lo último visible en la consola.
Write-Host ''
Write-Host '==============================================================' -ForegroundColor Green
Write-Host "  Argo CD : http://localhost:$ArgoPort    admin / $(Get-ArgoPassword)" -ForegroundColor Green
Write-Host "  RabbitMQ: http://localhost:$RabbitPort   demo / demo123" -ForegroundColor Green
Write-Host '  Cerrar  : .\bootstrap\07-cerrar-uis.ps1' -ForegroundColor Green
Write-Host '==============================================================' -ForegroundColor Green
if ($ready.Values -contains $false) {
    Write-Host 'Alguna UI no respondió. Revisa: kubectl -n argocd get pods ; kubectl -n keda-demo get pods' -ForegroundColor Yellow
    exit 1
}
