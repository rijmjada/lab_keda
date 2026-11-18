# Equivale a pulsar "Refresh" en la UI de Argo CD, para todas las Applications y ApplicationSets.
# Úsalo justo después de un "git push" para no esperar el ciclo de sondeo de Argo CD (unos 3 minutos).
#
#   Applications     -> releen su carpeta del repo (cambios en los YAML de platform/)
#   ApplicationSets  -> vuelven a leer los platform.yaml (cambios de enabled / namespace / carpetas nuevas)
. "$PSScriptRoot\_comun.ps1"

Write-Step 'Refrescando los ApplicationSets (¿carpetas nuevas o enabled cambiado?)'
kubectl -n $ArgoNamespace annotate applicationsets --all argocd.argoproj.io/application-set-refresh=true --overwrite

Write-Step 'Refrescando las Applications (hard: ignora la caché del repo)'
kubectl -n $ArgoNamespace annotate applications --all argocd.argoproj.io/refresh=hard --overwrite

Write-Host "`nListo. Estado:" -ForegroundColor Green
Start-Sleep -Seconds 5
kubectl -n $ArgoNamespace get applications
