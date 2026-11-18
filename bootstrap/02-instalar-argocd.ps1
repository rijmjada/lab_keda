# Paso 2: instala Argo CD con Helm.
#
# Si el repositorio es PRIVADO, define antes el token y este script crea las credenciales
# (mismo mecanismo que repo-creds-github en argocd-deploy):
#   $env:GH_TOKEN = 'github_pat_...'     # permiso Contents: Read
. "$PSScriptRoot\_comun.ps1"

Write-Step 'Agregando repositorio Helm de Argo'
Invoke-Native 'helm repo add argo' { helm repo add argo https://argoproj.github.io/argo-helm --force-update }
Invoke-Native 'helm repo update' { helm repo update argo }

Write-Step "Instalando argo/argo-cd $ArgoChartVersion en el namespace '$ArgoNamespace'"
Invoke-Native 'helm upgrade argocd' {
    helm upgrade --install argocd argo/argo-cd `
        --version $ArgoChartVersion `
        --namespace $ArgoNamespace --create-namespace `
        -f (Join-Path $ProjectRoot 'helm-values\argocd-values.yaml') `
        --wait --timeout 10m
}

if ($env:GH_TOKEN) {
    Write-Step 'Repositorio privado: creando las credenciales de Argo CD (GH_TOKEN)'
    # repo-creds = plantilla de credenciales: vale para TODOS los repos de la organización.
    $orgUrl = $RepoUrl -replace '^(https://github\.com/[^/]+)/.*$', '$1'
    $secret = @"
apiVersion: v1
kind: Secret
metadata:
  name: repo-creds-github
  namespace: $ArgoNamespace
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  type: git
  url: $orgUrl
  username: x-access-token
  password: $($env:GH_TOKEN)
"@
    # Por stdin: el token no se escribe en ningún archivo temporal.
    $secret | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear repo-creds-github' }
} else {
    Write-Host "`n(Sin GH_TOKEN: se asume un repositorio público.)" -ForegroundColor DarkGray
}

Write-Step 'Pods de Argo CD'
kubectl -n $ArgoNamespace get pods

Write-Host "`nUsuario: admin" -ForegroundColor Green
Write-Host "Password: $(Get-ArgoPassword)" -ForegroundColor Green
Write-Host '(La UI se abre con bootstrap\05-abrir-uis.ps1)'
