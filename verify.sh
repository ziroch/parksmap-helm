#!/bin/bash
# ============================================
# Script de Verificación - Parksmap Helm Chart
# ============================================

set -e

NAMESPACE=${1:-parksmap-dev}
RELEASE_NAME=${2:-parksmap}

echo "=========================================="
echo "🔍 Verificando Parksmap Helm en: $NAMESPACE"
echo "   Release: $RELEASE_NAME"
echo "=========================================="

echo -e "\n📦 1. Helm Release status:"
helm status $RELEASE_NAME -n $NAMESPACE 2>/dev/null || echo "   (No instalado via Helm CLI - OK si es ArgoCD)"

echo -e "\n🟢 2. Pods running:"
oc get pods -n $NAMESPACE -l app.kubernetes.io/name=parksmap

echo -e "\n🔌 3. Services:"
oc get svc -n $NAMESPACE -l app.kubernetes.io/name=parksmap

echo -e "\n🌐 4. Routes:"
oc get route -n $NAMESPACE -l app.kubernetes.io/name=parksmap

echo -e "\n📜 5. ConfigMaps:"
oc get configmap -n $NAMESPACE -l app.kubernetes.io/name=parksmap 2>/dev/null || echo "   (No hay configmaps adicionales)"

echo -e "\n🔐 6. Secrets:"
oc get secret -n $NAMESPACE | grep nationalparks || true

echo -e "\n👤 7. RBAC (RoleBindings):"
oc get rolebinding -n $NAMESPACE | grep view || true

echo -e "\n📈 8. HPA (si aplica):"
oc get hpa -n $NAMESPACE 2>/dev/null || echo "   (No HPA configurado)"

echo -e "\n🧪 9. Probar Frontend:"
FRONTEND_ROUTE=$(oc get route -n $NAMESPACE -l app.kubernetes.io/component=parksmap -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
if [ -n "$FRONTEND_ROUTE" ]; then
    echo "   URL: https://$FRONTEND_ROUTE"
    curl -sk https://${FRONTEND_ROUTE} | head -20 || echo "   (App aún iniciando...)"
else
    echo "   ⚠️ No se encontró route del frontend"
fi

echo -e "\n🧪 10. Probar Backend Health:"
BACKEND_ROUTE=$(oc get route -n $NAMESPACE -l app.kubernetes.io/component=nationalparks -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
if [ -n "$BACKEND_ROUTE" ]; then
    echo "   URL: https://$BACKEND_ROUTE/ws/healthz"
    curl -sk https://${BACKEND_ROUTE}/ws/healthz || echo "   (Backend aún iniciando...)"
    echo -e "\n   Datos de parques:"
    curl -sk https://${BACKEND_ROUTE}/ws/data/all | head -30 || echo "   (Backend aún iniciando...)"
else
    echo "   ⚠️ No se encontró route del backend"
fi

echo -e "\n✅ Verificación completada"
