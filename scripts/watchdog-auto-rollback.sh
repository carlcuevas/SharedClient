#!/usr/bin/env bash
# watchdog-auto-rollback.sh
#
# Este es el script que corres EN VIVO durante la defensa ("Prueba de Fuego").
# Monitorea continuamente la variante activa de orders-public. Si detecta
# fallas consecutivas (HTTP != 200, o pods en CrashLoopBackOff/Error),
# revierte automáticamente el tráfico a la variante anterior estable
# (que sigue corriendo en paralelo, sin tráfico) mediante "kubectl patch".
#
# No requiere que se vuelva a correr el pipeline de GitHub Actions: la
# recuperación ocurre localmente, en segundos, apuntando al mismo clúster.
#
# Uso:
#   chmod +x scripts/watchdog-auto-rollback.sh
#   ./scripts/watchdog-auto-rollback.sh
#
# Déjalo corriendo en una terminal visible durante toda la defensa.

set -uo pipefail

NAMESPACE="default"
SERVICE="orders-public"
INTERVAL_SECONDS=3
MAX_FALLAS_CONSECUTIVAS=3

fallas=0

color_opuesto() {
  if [ "$1" == "blue" ]; then echo "green"; else echo "blue"; fi
}

echo "==================================================================="
echo "  WATCHDOG - Monitoreo continuo de orders-public"
echo "  Intervalo: ${INTERVAL_SECONDS}s | Umbral de fallas: ${MAX_FALLAS_CONSECUTIVAS}"
echo "==================================================================="

while true; do
  ACTIVE_COLOR=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.selector.color}' 2>/dev/null)

  # Chequeo 1: estado de los pods de la variante activa (detecta CrashLoopBackOff, etc.)
  POD_ESTADO=$(kubectl get pods -n "$NAMESPACE" -l app=orders,color="$ACTIVE_COLOR" \
    -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' 2>/dev/null)

  # Chequeo 2: HTTP real vía port-forward
  kubectl port-forward "svc/$SERVICE" 8082:80 -n "$NAMESPACE" >/tmp/watchdog-pf.log 2>&1 &
  PF_PID=$!
  sleep 1
  HTTP_STATUS=$(curl -s -m 2 -o /dev/null -w "%{http_code}" http://localhost:8082/health 2>/dev/null || echo "000")
  kill $PF_PID 2>/dev/null || true
  wait $PF_PID 2>/dev/null

  TIMESTAMP=$(date '+%H:%M:%S')

  if [ "$HTTP_STATUS" == "200" ] && [ -z "$POD_ESTADO" ]; then
    if [ "$fallas" -gt 0 ]; then
      echo "[$TIMESTAMP] Recuperado. Variante activa: $ACTIVE_COLOR (HTTP 200)"
    fi
    fallas=0
  else
    fallas=$((fallas + 1))
    echo "[$TIMESTAMP] FALLA DETECTADA #$fallas - Variante: $ACTIVE_COLOR | HTTP: $HTTP_STATUS | Estado pods: ${POD_ESTADO:-N/A}"
  fi

  if [ "$fallas" -ge "$MAX_FALLAS_CONSECUTIVAS" ]; then
    ANTERIOR=$(color_opuesto "$ACTIVE_COLOR")
    echo "==================================================================="
    echo "[$TIMESTAMP] UMBRAL SUPERADO -> Ejecutando ROLLBACK AUTOMATICO"
    echo "  De: $ACTIVE_COLOR   Hacia: $ANTERIOR"
    echo "==================================================================="

    kubectl patch service "$SERVICE" -n "$NAMESPACE" \
      -p "{\"spec\":{\"selector\":{\"app\":\"orders\",\"color\":\"$ANTERIOR\"}}}"

    echo "[$TIMESTAMP] Rollback aplicado. Tráfico ahora en: $ANTERIOR"
    echo "[$TIMESTAMP] Reiniciando contador de fallas y continuando monitoreo..."
    fallas=0
  fi

  sleep "$INTERVAL_SECONDS"
done
