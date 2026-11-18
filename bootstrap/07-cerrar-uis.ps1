# Cierra los port-forwards del laboratorio.
#
# kubectl instalado con Chocolatey es un "shim" que lanza el kubectl real como proceso hijo:
# matar sólo el PID guardado deja vivo al hijo ocupando el puerto. Se mata el árbol completo
# (taskkill /T) y además se buscan huérfanos por línea de comando.
. "$PSScriptRoot\_comun.ps1"
$ErrorActionPreference = 'Continue'

$closed = 0
if (Test-Path $PidFile) {
    foreach ($id in Get-Content $PidFile) {
        if (Get-Process -Id ([int]$id) -ErrorAction SilentlyContinue) {
            taskkill /PID $id /T /F *> $null
            $closed++
        }
    }
    Remove-Item $PidFile
}

$orphans = Get-CimInstance Win32_Process -Filter "Name='kubectl.exe'" |
    Where-Object { $_.CommandLine -match "port-forward\s+svc/(argocd-server|rabbitmq)\s+($ArgoPort|$RabbitPort):" }
foreach ($p in $orphans) {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    $closed++
}

Write-Host "Port-forwards cerrados: $closed" -ForegroundColor Green
