# Laboratorio KEDA con GitOps (ApplicationSets)

Mismo laboratorio de KEDA (un consumer de RabbitMQ que escala de 0 a 10 réplicas), pero desplegado
**como en producción**: el repositorio Git es la fuente de verdad y Argo CD lo sincroniza. La
estructura sigue la de `argocd-deploy`: `bootstrap/`, `app-manager/` y `platform/`.

La teoría de KEDA (activación, HPA, parámetros, fases) está en el README del laboratorio `keda`.
Aquí el foco es **cómo se declara y se despliega con Git**.

## Qué cambia respecto al laboratorio `keda`

| | Laboratorio `keda` | Este laboratorio |
|---|---|---|
| Dónde viven los YAML | Dentro de cada `Application`, en `valuesObject.resources` | **Archivos YAML normales**, uno por recurso, en `platform/manifests/<carpeta>/` |
| Cómo llega un cambio al clúster | Editar y ejecutar `04-desplegar-lab.ps1`, que reempaqueta todo | `git push` y **Refresh** en Argo CD |
| Quién crea las Applications | Una raíz con las hijas incrustadas | **ApplicationSets** que descubren carpetas por su `platform.yaml` |
| Orden de despliegue | sync-waves entre Applications | **Reintentos con backoff** (los ApplicationSets no ordenan) |
| Fuente de la verdad | La `Application` dentro del clúster | El repositorio en GitHub |

## Estructura

```
lab_keda/
├── bootstrap/                      # lo que se ejecuta a mano, una vez
│   ├── root-app.yaml               # única Application "a mano": apunta a app-manager/
│   └── 01..07, 99, refrescar, observar (.ps1)
├── app-manager/                    # lo que Argo CD gestiona sobre sí mismo
│   ├── appproject-lab.yaml         # permisos: repos, namespaces y CRDs permitidos
│   ├── appset-charts.yaml          # una Application por platform/charts/*/platform.yaml
│   └── appset-manifests.yaml       # una Application por platform/manifests/*/platform.yaml
├── platform/
│   ├── charts/keda/                # chart "envoltorio": Chart.yaml + Chart.lock + values
│   └── manifests/
│       ├── rabbitmq/               # Secret, Deployment, Service, Job que declara la cola
│       └── keda-demo/              # Secret, TriggerAuthentication, Deployment, ScaledObject
├── app/                            # consumer/producer (se construye en minikube)
└── helm-values/argocd-values.yaml  # valores de Helm para instalar Argo CD
```

## Cómo se genera todo

```mermaid
flowchart TB
    ROOT["root-app-manager<br/>bootstrap/root-app.yaml"] --> AM["app-manager/"]
    AM --> PROJ[AppProject lab]
    AM --> AS1[ApplicationSet lab-charts]
    AM --> AS2[ApplicationSet lab-manifests]
    AS1 -->|"platform/charts/*/platform.yaml"| K[Application lab-keda]
    AS2 -->|"platform/manifests/*/platform.yaml"| R[Application lab-rabbitmq]
    AS2 -->|"platform/manifests/*/platform.yaml"| D[Application lab-keda-demo]
    K --> K1["operator, metrics-apiserver, webhooks, CRDs"]
    R --> R1["Deployment, Service, Secret, Job de la cola"]
    D --> D1["consumer, TriggerAuthentication, ScaledObject"]
```

1. Tú aplicas **una sola** Application (`root-app-manager`). Sincroniza la carpeta `app-manager/`.
2. Ahí están el `AppProject` y los dos `ApplicationSet`s.
3. Cada `ApplicationSet` busca en Git los archivos `platform.yaml` y **genera una Application por cada uno**.

### La convención `platform.yaml`

Cada carpeta declara sus datos en un `platform.yaml` (no es un manifiesto de Kubernetes):

```yaml
name: keda-demo        # nombre de la Application generada: lab-keda-demo
enabled: "true"        # "false" = se da de baja
namespace: keda-demo   # namespace de destino
```

| Dato | Para qué lo usa el ApplicationSet |
|---|---|
| `name` | Nombre de la Application (`lab-<name>`) y carpeta de origen (`path: platform/manifests/<name>`) |
| `enabled` | Filtro: sólo se generan las que tienen `"true"` (entre comillas: se compara como texto) |
| `namespace` | `destination.namespace`. Los manifiestos **no** declaran namespace: caen aquí |

**Agregar una app nueva = crear una carpeta con YAML y un `platform.yaml`.** Sin tocar ningún ApplicationSet.

### Por qué hay dos ApplicationSets

| | `lab-charts` (Helm) | `lab-manifests` (YAML plano) |
|---|---|---|
| Para | KEDA | RabbitMQ y la demo |
| Qué lee | Un chart envoltorio con la dependencia oficial **y su versión fija** (`Chart.lock`) | Una carpeta de YAML (excluye `platform.yaml`) |
| Al borrar la carpeta | **Conserva** los recursos (`preserveResourcesOnDeletion`): borrar KEDA borraría sus CRDs y con ellas todos los `ScaledObject` | **Elimina** los recursos (finalizer): dar de baja una demo la limpia entera |
| `ignoreDifferences` | `caBundle` del `APIService` y del webhook (KEDA lo escribe en runtime) | `spec.replicas` de los Deployments (lo escribe el HPA de KEDA) |

## Cómo se enlazan los recursos de `keda-demo`

Todo se enlaza **por nombre**, dentro del mismo namespace:

```
scaledobject.yaml          consumer-scaler
 ├─ scaleTargetRef.name: consumer ──────────► deployment-consumer.yaml        (Deployment "consumer")
 └─ authenticationRef.name: rabbitmq-auth ──► triggerauthentication.yaml      (rabbitmq-auth)
                                               └─ secretTargetRef:
                                                  name: keda-rabbitmq-host ─► secret-keda-host.yaml
                                                  key: host                    └─ la URL de RabbitMQ
```

- La URL (`http://demo:demo123@rabbitmq.keda-demo.svc.cluster.local:15672/`) debe coincidir con el
  Service `rabbitmq` ([service.yaml](platform/manifests/rabbitmq/service.yaml)), su namespace y su puerto.
- `queueName: tareas` (ScaledObject) y `QUEUE_NAME: tareas` (consumer) **no se sincronizan solos**: si cambias uno, cambia el otro.
- KEDA consulta por HTTP (15672) y el consumer trabaja por AMQP (5672): son dos conexiones distintas.
- Los comentarios de cada archivo indican a quién apunta cada referencia.

## Publicar el repositorio

Argo CD clona el repositorio desde dentro del clúster, así que **tiene que estar en GitHub**. El
laboratorio asume `https://github.com/rijmjada/lab_keda.git` (cámbialo en `bootstrap\_comun.ps1`,
`bootstrap\root-app.yaml` y `app-manager\*.yaml` si usas otro nombre).

```powershell
cd C:\Users\diego\OneDrive\Escritorio\lab_keda
git init -b main
git add .
git commit -m "Laboratorio KEDA con GitOps"
git remote add origin https://github.com/rijmjada/lab_keda.git
git push -u origin main
```

(Crea antes el repositorio vacío en GitHub.) Si es **privado**, define `$env:GH_TOKEN` antes del
paso 02: el script crea el mismo `repo-creds-github` que usa `argocd-deploy`.

> **Cuidado con los secretos:** el laboratorio sube contraseñas de demostración (`demo123`) en texto
> plano. Hazlo sólo con credenciales de laboratorio. En un entorno real irían con Sealed Secrets,
> SOPS o External Secrets.

## Paso a paso

```powershell
.\bootstrap\01-iniciar-minikube.ps1   # clúster 'lab-keda' (recupera solo un perfil huérfano)
.\bootstrap\02-instalar-argocd.ps1    # Helm: Argo CD
.\bootstrap\03-construir-imagen.ps1   # imagen del consumer dentro de minikube
.\bootstrap\04-desplegar-lab.ps1      # aplica la raíz y espera a que todo quede Synced/Healthy
.\bootstrap\05-abrir-uis.ps1          # Argo CD :8090 y RabbitMQ :15673
```

Si no hay recursos suficientes, detén antes los otros laboratorios (`minikube stop -p keda-lab`, etc.).
Resultado esperado: cuatro Applications: `root-app-manager`, `lab-keda`, `lab-rabbitmq` y `lab-keda-demo`.
`lab-keda-demo` puede fallar sus primeros intentos hasta que KEDA instale sus CRDs: reintenta solo.

## El ciclo de trabajo: editar, subir y Refresh

```powershell
# 1. Edita un YAML, por ejemplo platform\manifests\keda-demo\scaledobject.yaml
git add -A; git commit -m "maxReplicaCount a 5"; git push
# 2. Refresh en la UI de Argo CD (botón en la Application), o:
.\bootstrap\refrescar.ps1
```

Si no haces Refresh, Argo CD sondea Git por su cuenta (por defecto cada ~3 minutos).

| Qué cambiaste | Qué refrescar |
|---|---|
| Un YAML dentro de una carpeta de `platform/` | La Application de esa carpeta (Refresh) |
| `platform.yaml` (`enabled`, `namespace`) o una carpeta nueva | El **ApplicationSet** (`refrescar.ps1` lo hace; en la UI espera su sondeo) |
| `app-manager/` | `root-app-manager` |

Genera carga con `.\bootstrap\06-generar-carga.ps1 -Mensajes 300` y míralo con `.\bootstrap\observar.ps1`.

## Experimentos

1. **Cambiar la regla.** En `scaledobject.yaml`, `maxReplicaCount: 10` → `3` y `value: "10"` → `"50"`. Push, Refresh y genera carga: verás menos réplicas.
2. **Pausar el escalado.** Descomenta el bloque `annotations` del `ScaledObject` (va en `metadata`, **no** en `spec`). Push y Refresh: `kubectl -n keda-demo get scaledobject` muestra `PAUSED=True` y el consumer queda fijo en 0 aunque haya mensajes.
3. **selfHeal.** Cambia algo a mano: `kubectl -n keda-demo edit scaledobject consumer-scaler`. Argo CD lo devuelve al valor de Git. **Git manda.**
4. **Dar de baja una demo.** En `platform/manifests/keda-demo/platform.yaml` pon `enabled: "false"`. Push y refresca el ApplicationSet: la Application `lab-keda-demo` y todos sus recursos desaparecen. Vuelve a `"true"` para recuperarla.
5. **Una app nueva.** Copia `keda-demo` a otra carpeta, cambia sus nombres y su `platform.yaml`. Push: aparece una Application nueva **sin tocar ningún ApplicationSet**.
6. **Rollback.** `git revert HEAD` y push: el clúster vuelve al estado anterior. Es la gran ventaja frente al laboratorio `keda`.

## Diferencias con `argocd-deploy`

| | `argocd-deploy` | `lab_keda` |
|---|---|---|
| Bootstrap | `entorno.py` en Python (instala Argo CD con `install.yaml`) | Scripts PowerShell (instalan Argo CD con Helm) |
| Repos | Tres: despliegue, `<app>-conf` y la app | Uno solo |
| Apps de negocio | `apps/prod/*.yaml` apunta a un repo `-conf` con un chart | La demo vive en `platform/manifests/keda-demo` |
| AppProject | `platform` | `lab` |
| `ignoreDifferences` | No hacen falta | Hacen falta por KEDA (ver arriba) |

## Solución de problemas

| Síntoma | Causa y solución |
|---|---|
| `04` dice que no puede leer la rama `main` | El repositorio no existe, está vacío o es privado sin acceso. Ver "Publicar el repositorio". |
| Las Applications no aparecen | Revisa `kubectl -n argocd get applicationset` y los logs: `kubectl -n argocd logs deploy/argocd-applicationset-controller --tail=20` |
| `lab-keda-demo` en `OutOfSync` con error de CRD | KEDA todavía no terminó de instalarse: reintenta solo (hasta 10 veces, con espera creciente). |
| `ScaledObject` con `Ready=False` y `404` en los logs de KEDA | La cola `tareas` no existe: `kubectl -n keda-demo logs job/declarar-cola-tareas` |
| El cambio no se ve tras el push | Falta el Refresh (ver la tabla del ciclo de trabajo). |
| `lab-keda` en `OutOfSync` por el `APIService` | Falta el `ignoreDifferences` de `appset-charts.yaml`. |
| Pod del consumer en `ErrImageNeverPull` | La imagen no está en el nodo: ejecuta `03-construir-imagen.ps1` (se pierde si se recrea el perfil). |
| Errores `connection refused` al arrancar minikube | Perfil huérfano: `01` lo detecta y lo recrea. Borra siempre con `minikube delete -p lab-keda`, no con `docker rm`. |
