# Paso 4: construye la imagen del consumer/producer DENTRO de minikube
# (no hace falta registry: los pods usan imagePullPolicy: Never).
. "$PSScriptRoot\_comun.ps1"

Write-Step "Construyendo $WorkerImage dentro de minikube"
Invoke-Native 'minikube image build' {
    minikube -p $MinikubeProfile image build -t $WorkerImage (Join-Path $ProjectRoot 'app')
}

Write-Step 'Imagen disponible en el nodo'
minikube -p $MinikubeProfile image ls | Select-String 'keda-demo-worker'
