# Borra el laboratorio: elimina el clúster minikube completo (minikube delete, NUNCA docker rm).
# El repositorio Git no se toca.
. "$PSScriptRoot\_comun.ps1"

& "$PSScriptRoot\07-cerrar-uis.ps1"

Write-Step "Eliminando el clúster minikube '$MinikubeProfile'"
Invoke-Native 'minikube delete' { minikube delete -p $MinikubeProfile }
