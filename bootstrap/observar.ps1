# Panel en consola: mensajes en cola vs réplicas del consumer, refrescado cada N segundos.
# Ejecútalo en una terminal aparte mientras generas carga. Ctrl+C para salir.
param([int]$IntervalSeconds = 3)
. "$PSScriptRoot\_comun.ps1"
$ErrorActionPreference = 'Continue'

while ($true) {
    $queue = kubectl -n $DemoNamespace exec deploy/rabbitmq -- `
        rabbitmqctl -q list_queues name messages_ready messages_unacknowledged 2>$null |
        Select-String '^tareas'
    $ready = 0; $unacked = 0
    if ($queue) {
        $parts = ($queue.Line -split '\s+')
        $ready = [int]$parts[1]; $unacked = [int]$parts[2]
    }
    $desired = kubectl -n $DemoNamespace get deploy consumer -o 'jsonpath={.spec.replicas}' 2>$null
    $readyPods = kubectl -n $DemoNamespace get deploy consumer -o 'jsonpath={.status.readyReplicas}' 2>$null
    if (-not $desired) { $desired = 0 }
    if (-not $readyPods) { $readyPods = 0 }
    $active = kubectl -n $DemoNamespace get scaledobject consumer-scaler `
        -o 'jsonpath={.status.conditions[?(@.type==''Active'')].status}' 2>$null   # comillas simples: las dobles se pierden en PS 5.1

    Clear-Host
    Write-Host ("KEDA lab  {0}" -f (Get-Date -Format 'HH:mm:ss')) -ForegroundColor Cyan
    Write-Host ("Cola 'tareas'   ready={0,-5} unacked={1,-5} total={2}" -f $ready, $unacked, ($ready + $unacked))
    Write-Host ("ScaledObject    Active={0}" -f $active)
    Write-Host ("Consumer        deseadas={0,-3} listas={1,-3} " -f $desired, $readyPods) -NoNewline
    Write-Host ('#' * [int]$readyPods) -ForegroundColor Green
    Write-Host ''
    kubectl -n $DemoNamespace get hpa 2>$null
    Write-Host ''
    kubectl -n $DemoNamespace get pods -l app=consumer 2>$null
    Start-Sleep -Seconds $IntervalSeconds
}
