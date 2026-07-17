#!/usr/bin/env bash
# health-check.sh
# Verifica el estado de salud de la variante activa expuesta por
# orders-public. Uso: ./scripts/health-check.sh
#
# Requiere: kubectl configurado contra el clúster EKS (aws eks update-kubeconfig).

set -euo pipefail

NAMESPACE="default"
SERVICE="orders-public"

ACTIVE_COLOR=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.selector.color}')
echo "Variante activa: $ACTIVE_COLOR"

kubectl port-forward "svc/$SERVICE" 8081:80 -n "$NAMESPACE" >/tmp/pf.log 2>&1 &
PF_PID=$!
sleep 3

STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/health || echo "000")
kill $PF_PID 2>/dev/null || true

if [ "$STATUS" == "200" ]; then
  echo "OK: el servicio responde 200 en /health"
  exit 0
else
  echo "FALLO: el servicio respondió HTTP $STATUS en /health"
  exit 1
fi
