# 🗺️ Parksmap App - Helm Chart para OpenShift GitOps

Helm Chart completo y parametrizado para desplegar la **Parksmap App** (National Parks Explorer) en OpenShift con ArgoCD / OpenShift GitOps.

## Arquitectura

```
┌─────────────────┐      HTTPS     ┌──────────────────┐
│   Parksmap      │ ◄───────────── │   Usuario        │
│   (Frontend)    │                │                  │
│  quay.io/...    │                └──────────────────┘
└────────┬────────┘
         │ Descubre backends vía OpenShift API (requiere SA + rol 'view')
         ▼
┌─────────────────┐      HTTP      ┌──────────────────┐
│  Nationalparks  │ ◄───────────── │   Parksmap       │
│   (Backend)     │                │   (Frontend)     │
│  Python/Flask   │                │                  │
│   Port: 8080    │                └──────────────────┘
└────────┬────────┘
         │ MongoDB queries
         ▼
┌─────────────────┐
│     MongoDB     │
│   Port: 27017   │
└─────────────────┘
```

## Estructura del Chart

```
parksmap-helm/
├── Chart.yaml                      # Metadatos del chart
├── values.yaml                     # Valores por defecto
├── values-dev.yaml                 # Override: Desarrollo
├── values-staging.yaml             # Override: Staging
├── values-prod.yaml                # Override: Producción
├── argocd-application-dev.yaml     # Application ArgoCD - DEV
├── argocd-application-staging.yaml # Application ArgoCD - STAGING
├── argocd-application-prod.yaml    # Application ArgoCD - PROD
├── verify.sh                       # Script de verificación
└── templates/
    ├── _helpers.tpl                # Funciones reutilizables de Helm
    ├── secrets.yaml                # Secret de MongoDB
    ├── serviceaccount.yaml         # SA para frontend
    ├── rolebinding.yaml            # RBAC (rol 'view')
    ├── frontend-deployment.yaml    # Deployment Parksmap
    ├── frontend-service.yaml       # Service Parksmap
    ├── frontend-route.yaml         # Route Parksmap
    ├── backend-deployment.yaml     # Deployment Nationalparks
    ├── backend-service.yaml        # Service Nationalparks
    ├── backend-route.yaml          # Route Nationalparks
    ├── mongodb-deployment.yaml     # Deployment MongoDB
    ├── mongodb-service.yaml        # Service MongoDB
    ├── mongodb-pvc.yaml            # PVC MongoDB (condicional)
    └── hpa.yaml                    # HorizontalPodAutoscaler (condicional)
```

## Cambios Realizados vs Archivos Originales

| Problema Original | Solución Aplicada |
|-------------------|-------------------|
| `values.yaml` solo tenía config del frontend | ✅ Valores completos para frontend, backend, mongodb, secrets, rbac, hpa |
| Imágenes hardcodeadas en templates | ✅ Todas las imágenes parametrizadas via `values.yaml` |
| `replicas: 1` hardcodeado | ✅ `{{ .Values.frontend.replicaCount }}` etc. |
| `secrets.yaml` con base64 hardcodeado | ✅ Usa `stringData` con valores de `values.yaml` |
| Sin ServiceAccount dedicado | ✅ SA `parksmap-sa` con anotaciones configurables |
| Sin probes de salud | ✅ Liveness y Readiness probes parametrizadas |
| Sin recursos (CPU/memoria) | ✅ `resources` configurables por componente |
| Sin HPA | ✅ HPA condicional solo para producción |
| Sin persistencia para MongoDB | ✅ PVC condicional (emptyDir para dev, PVC para prod) |
| Sin `values` por entorno | ✅ `values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml` |

## Procedimiento de Despliegue

### Paso 0: Preparar Entorno

```bash
# Login al cluster
oc login --token=<tu-token> --server=https://api.<cluster>.openshift.com:6443

# Verificar OpenShift GitOps
oc get csv -n openshift-gitops-operator | grep gitops

# Obtener credenciales ArgoCD
ARGOCD_URL=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')
ARGOCD_PASS=$(oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d)
argocd login ${ARGOCD_URL} --username admin --password ${ARGOCD_PASS} --insecure

# Clonar repo
git clone https://github.com/workshop-gitops/cap12-labs.git
cd cap12-labs
```

### Paso 1: Validar Chart Localmente

```bash
cd parksmap-helm

# Validar sintaxis del chart
helm lint .

# Renderizar templates para ver el output
helm template parksmap-dev . --values values.yaml --values values-dev.yaml

# Validar contra API de Kubernetes (dry-run)
helm install parksmap-dev . --values values.yaml --values values-dev.yaml   --namespace parksmap-dev --dry-run --create-namespace

# Comparar outputs entre entornos
helm template parksmap-dev . --values values.yaml --values values-dev.yaml > /tmp/dev.yaml
helm template parksmap-staging . --values values.yaml --values values-staging.yaml > /tmp/staging.yaml
helm template parksmap-prod . --values values.yaml --values values-prod.yaml > /tmp/prod.yaml

diff /tmp/dev.yaml /tmp/staging.yaml | head -50
diff /tmp/staging.yaml /tmp/prod.yaml | head -50
```

### Paso 2: Desplegar con ArgoCD (Modo GitOps)

```bash
# Aplicar Application de ArgoCD para DEV
oc apply -f argocd-application-dev.yaml

# Verificar estado
argocd app get parksmap-helm-dev
argocd app wait parksmap-helm-dev --sync --health --timeout 300

# Ver recursos desplegados
argocd app resources parksmap-helm-dev
```

### Paso 3: Verificar Despliegue

```bash
# Usar script de verificación
./verify.sh parksmap-dev

# O manualmente:
oc get pods -n parksmap-dev
oc get route -n parksmap-dev

# Probar frontend
FRONTEND=$(oc get route -n parksmap-dev -l app.kubernetes.io/component=parksmap   -o jsonpath='{.items[0].spec.host}')
curl -sk https://${FRONTEND}

# Probar backend health
BACKEND=$(oc get route -n parksmap-dev -l app.kubernetes.io/component=nationalparks   -o jsonpath='{.items[0].spec.host}')
curl -sk https://${BACKEND}/ws/healthz
curl -sk https://${BACKEND}/ws/data/all | head -30
```

### Paso 4: Verificar Manifiestos Renderizados por ArgoCD

```bash
# Ver manifiestos que ArgoCD aplicó
argocd app manifests parksmap-helm-dev

# Ver solo el Deployment del frontend
argocd app manifests parksmap-helm-dev | grep -A 50 "kind: Deployment" | head -60

# Verificar que el Secret tiene los valores correctos
argocd app manifests parksmap-helm-dev | grep -A 15 "kind: Secret"

# Ver el diff
argocd app diff parksmap-helm-dev
```

### Paso 5: Demostración de Auto-Heal

```bash
# Simular cambio manual no autorizado
oc patch deployment parksmap-frontend -n parksmap-dev   --type merge -p '{"spec":{"replicas":5}}'

# Verificar cambio
oc get deployment parksmap-frontend -n parksmap-dev -o jsonpath='{.spec.replicas}'
# Muestra: 5

# Esperar ~30-40 segundos (selfHeal lo restaura)
sleep 40

# Verificar restauración
oc get deployment parksmap-frontend -n parksmap-dev -o jsonpath='{.spec.replicas}'
# Muestra: 1 (valor de values-dev.yaml)

# Ver evento en ArgoCD
argocd app get parksmap-helm-dev --show-operation
```

### Paso 6: Promoción de Imagen (Flujo CI/CD)

```bash
# Simular que el pipeline CI actualiza la imagen en staging
# Modificar values-staging.yaml
sed -i 's/tag: "v1.2.0"/tag: "v1.3.0"/' values-staging.yaml

# Validar
helm template parksmap-staging . --values values.yaml --values values-staging.yaml | grep "image:"

# Commit y push (GitOps)
git add values-staging.yaml
git commit -m "ci: promote parksmap to v1.3.0 in staging [workshop-lab-c]"
git push origin main

# ArgoCD detecta automáticamente
argocd app get parksmap-helm-staging --hard-refresh
argocd app wait parksmap-helm-staging --sync --health --timeout 300
```

### Paso 7: Desplegar Producción con HPA

```bash
# Aplicar Application de producción
oc apply -f argocd-application-prod.yaml

# Esperar sync
argocd app wait parksmap-helm-prod --sync --health --timeout 300

# Verificar HPA
oc get hpa -n parksmap-prod
oc describe hpa parksmap-helm-prod-frontend-hpa -n parksmap-prod

# Verificar persistencia de MongoDB
oc get pvc -n parksmap-prod
```

## Tabla Comparativa por Entorno

| Aspecto | DEV | STAGING | PROD |
|---------|-----|---------|------|
| **Réplicas** | 1 | 2 | 3 |
| **Tag Imagen** | `latest` | `v1.2.0` | `v1.2.0` |
| **Recursos** | Mínimos | Medios | Grandes |
| **HPA** | ❌ | ❌ | ✅ |
| **Persistencia MongoDB** | emptyDir | PVC 2Gi | PVC 10Gi |
| **Log Level** | debug | info | warn |
| **App Name** | "... - DEV" | "... - STAGING" | "National Parks Explorer" |

## Comandos de Referencia Rápida

```bash
# Helm
helm lint .                                    # Validar chart
helm template <release> . --values values.yaml --values values-dev.yaml  # Renderizar
helm install <release> . --values values.yaml --values values-dev.yaml   # Instalar
helm upgrade <release> . --values values.yaml --values values-dev.yaml   # Actualizar
helm uninstall <release> -n <namespace>          # Desinstalar

# ArgoCD
argocd app get parksmap-helm-dev               # Estado de la app
argocd app manifests parksmap-helm-dev           # Ver manifiestos
argocd app diff parksmap-helm-dev              # Diff Git vs cluster
argocd app sync parksmap-helm-dev --force       # Forzar sync
argocd app history parksmap-helm-dev           # Historial de syncs
argocd app rollback parksmap-helm-dev <id>      # Rollback

# Verificación
./verify.sh parksmap-dev                         # Script completo
oc get all -n parksmap-dev                       # Todos los recursos
oc logs -n parksmap-dev -l app.kubernetes.io/component=parksmap  # Logs frontend
```

## Notas Importantes

1. **RBAC Crítico**: El frontend `parksmap` requiere el rol `view` en el ServiceAccount para descubrir automáticamente los backends. El servicio `nationalparks` DEBE tener el label `type: parksmap-backend`.

2. **MongoDB**: En producción real, considerar usar MongoDB Atlas o un operator de MongoDB en lugar del contenedor standalone.

3. **Imágenes**: Las imágenes `latest` se usan solo en dev. En staging/prod se usan tags semver para reproducibilidad.

4. **HPA**: Requiere que el cluster tenga habilitado el metrics-server o similar para OpenShift.

5. **Persistencia**: El PVC requiere un StorageClass válido en el cluster. Ajustar `storageClass` en `values-prod.yaml`.

## Troubleshooting

| Problema | Causa | Solución |
|----------|-------|----------|
| Frontend no muestra parques | Falta label `type: parksmap-backend` en servicio backend | Verificar `backend.service.labels` en values |
| Frontend no descubre backend | Falta RoleBinding con rol `view` | Verificar `rbac.enabled: true` |
| MongoDB no inicia | Credenciales incorrectas | Verificar `secrets.data` en values |
| HPA no escala | metrics-server no disponible | Verificar `oc get --raw /apis/metrics.k8s.io/v1beta1` |
| Route no genera TLS | Cert-manager no instalado | Usar `tls.enabled: false` o instalar cert-manager |
