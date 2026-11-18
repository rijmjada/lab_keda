# Publica N mensajes en la cola "tareas" usando un pod efímero con el producer.
#   .\bootstrap\06-generar-carga.ps1 -Mensajes 300
param([int]$Mensajes = 300)
. "$PSScriptRoot\_comun.ps1"

function Get-SecretValue([string]$Key) {
    $b64 = kubectl -n $DemoNamespace get secret rabbitmq-credentials -o "jsonpath={.data.$Key}"
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
}
$user = Get-SecretValue 'username'
$pass = Get-SecretValue 'password'

$expected = [math]::Min(10, [math]::Ceiling($Mensajes / 10))
Write-Step "Publicando $Mensajes mensajes (con value=10 y max=10, KEDA debería pedir ~$expected réplicas)"
$podName = "producer-$(Get-Date -Format 'HHmmss')"
Invoke-Native 'producer' {
    kubectl -n $DemoNamespace run $podName --rm -i --restart=Never `
        --image=$WorkerImage --image-pull-policy=Never `
        --env="RABBITMQ_HOST=rabbitmq" --env="RABBITMQ_USER=$user" --env="RABBITMQ_PASSWORD=$pass" `
        -- python producer.py $Mensajes
}
Write-Host 'Observa el escalado con bootstrap\observar.ps1 o en la UI de Argo CD.' -ForegroundColor Green
