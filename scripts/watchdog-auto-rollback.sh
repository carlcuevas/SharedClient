#!/bin/bash

# ===================================================================
#  WATCHDOG - Monitoreo continuo de orders-public (vía LoadBalancer)
#  Intervalo: 3s | Umbral de fallas: 3
# ===================================================================

SERVICE="orders-public"
NAMESPACE="default"
THRESHOLD=3
INTERVAL=3
HEALTH_PATH="/health"

FAIL_COUNT=0

echo "==================================================================="
echo "  WATCHDOG - Monitoreo continuo de $SERVICE"
echo "  Intervalo: ${INTERVAL}s | Umbral de fallas: ${THRESHOLD}"
echo "==================================================================="

LB_HOST=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$LB_HOST" ]; then
  echo "[ERROR] No se pudo obtener el hostname del LoadBalancer. ¿Está provisionado?"
  exit 1
fi

URL="http://${LB_HOST}${HEALTH_PATH}"
echo "[INFO] Monitoreando: $URL"
echo ""

while true; do
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "$URL")

  if [ "$HTTP_CODE" == "200" ]; then
    if [ "$FAIL_COUNT" -gt 0 ]; then
      echo "[$TIMESTAMP] OK - Recuperado (código $HTTP_CODE)"
    fi
    FAIL_COUNT=0
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "[$TIMESTAMP] FALLA #$FAIL_COUNT - código: ${HTTP_CODE:-sin respuesta}"

    if [ "$FAIL_COUNT" -ge "$THRESHOLD" ]; then
      echo "[$TIMESTAMP] >>> UMBRAL ALCANZADO. Ejecutando rollback automático..."

      CURRENT_COLOR=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.selector.color}')

      if [ "$CURRENT_COLOR" == "blue" ]; then
        TARGET_COLOR="green"
      else
        TARGET_COLOR="blue"
      fi

      echo "[$TIMESTAMP] Color activo con falla: $CURRENT_COLOR -> Rollback a: $TARGET_COLOR"
      kubectl patch service "$SERVICE" -n "$NAMESPACE" -p "{\"spec\":{\"selector\":{\"color\":\"${TARGET_COLOR}\"}}}"

      echo "[$TIMESTAMP] Rollback ejecutado. Reiniciando contador de fallas."
      FAIL_COUNT=0

      sleep 5
    fi
  fi

  sleep "$INTERVAL"
done
