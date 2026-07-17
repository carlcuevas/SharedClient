# Runbook - Preparación y Defensa

Guía de comandos en orden. Sigue esto tal cual, de arriba hacia abajo.

## FASE 0 — Una sola vez (semana 17, con calma)

### 0.1 Iniciar el Learner Lab y obtener credenciales
1. Entra a AWS Academy → tu curso → **Start Lab** (espera el punto verde).
2. Click en **AWS Details** → **Show** junto a "AWS CLI".
3. Copia las 3 líneas (`aws_access_key_id`, `aws_secret_access_key`,
   `aws_session_token`). Duran ~4 horas o hasta que reinicies el lab.
4. En "AWS Details" también verás el **Account ID** (12 dígitos). Anótalo.

### 0.2 Editar el archivo del clúster
En `eksctl-cluster.yaml`, reemplaza `<ACCOUNT_ID>` por tu Account ID real
(dos ocurrencias).

### 0.3 Instalar herramientas locales (una vez, en tu máquina)
```bash
# aws cli, eksctl, kubectl - instala los que falten
aws --version
eksctl version
kubectl version --client
```

### 0.4 Exportar credenciales localmente (para crear el clúster desde tu máquina)
```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
export AWS_DEFAULT_REGION="us-east-1"
```

### 0.5 Crear el clúster EKS (tarda 15-20 min, hazlo con tiempo)
```bash
eksctl create cluster -f eksctl-cluster.yaml
aws eks update-kubeconfig --name techmarket-eks --region us-east-1
kubectl get nodes    # deben verse 2 nodos en estado Ready
```

### 0.6 Aplicar el Service público inicial (una sola vez)
```bash
kubectl apply -f k8s/service-public.yaml
```

### 0.7 Configurar los Secrets del repo en GitHub
GitHub → tu repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Valor |
|---|---|
| `AWS_ACCESS_KEY_ID` | el de tu sesión actual |
| `AWS_SECRET_ACCESS_KEY` | el de tu sesión actual |
| `AWS_SESSION_TOKEN` | el de tu sesión actual |

> Estas credenciales expiran. Tendrás que **repetir este paso 0.7** cada vez
> que reinicies el Learner Lab, incluyendo la mañana de la defensa.

### 0.8 Primer despliegue manual de referencia (versión "blue" inicial)
Antes de depender del pipeline, deja corriendo manualmente una primera
versión estable para tener algo que comparar:
```bash
export COLOR=blue
export IMAGE="<tu_cuenta_ecr>.dkr.ecr.us-east-1.amazonaws.com/techmarket-orders:inicial"
export NAMESPACE=default
# (build y push manual de esa imagen si es necesario, o deja que el primer
#  run del pipeline la genere y luego aplica switch-traffic a blue)
```
Lo más simple: corre el pipeline (`git push` a `main`) dos veces seguidas al
principio, así terminas con `blue` desplegado y activo, y `green` listo para
la segunda iteración durante la demo.

---

## FASE 1 — La noche/mañana antes de la defensa

```bash
# 1. Reinicia el Learner Lab si estaba apagado, espera el punto verde
# 2. Copia las nuevas credenciales (AWS Details -> Show)
# 3. Actualízalas en GitHub Secrets (paso 0.7)
# 4. Verifica que el clúster sigue vivo:
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
aws eks update-kubeconfig --name techmarket-eks --region us-east-1
kubectl get nodes
kubectl get pods -o wide
kubectl get service orders-public

# 5. Corre el pipeline una vez para confirmar que build -> deploy -> health -> switch
#    funciona de punta a punta con las credenciales nuevas.

# 6. Deja preparado (sin ejecutar) el comando de falla real que vas a necesitar
#    si TÚ tienes que provocar el error (o si el docente te pide reproducirlo
#    de nuevo después de que el suyo se resuelva):
#      kubectl set image deployment/orders-<color-activo> orders=alpine:latest -n default
#      kubectl scale deployment orders-<color-activo> --replicas=1 -n default
```

## FASE 2 — Guion de la defensa (minuto a minuto)

Duración estimada total: 12-15 min. Cada bloque cita el/los indicador(es) del
rubric de Presentación que cubre, para que sepas qué es lo que se está
evaluando en cada momento y no lo des por sentado.

### Preparación inmediata antes de empezar (no cronometrado)
Terminal 1, visible todo el tiempo, arranca el watchdog **antes** de saludar
al docente:
```bash
cd ~/SharedClient
chmod +x scripts/watchdog-auto-rollback.sh
./scripts/watchdog-auto-rollback.sh
```
Terminal 2: para navegar el repo y ejecutar comandos.
Navegador: repo de GitHub abierto en la pestaña de Actions y en la de código.

---

**[0:00 - 1:00] Apertura — contexto del caso**
_(No hay indicador puntual aquí, pero marca el tono técnico de todo lo que sigue)_

Explica en 3-4 frases: "TechMarket Orders" corría con un pipeline
RollingUpdate sin validaciones, causaba caídas. El encargo fue transformarlo
en Blue-Green con validación de salud y rollback automático sobre EKS.
Muestra el diagrama de arquitectura del README (sección 1-2).

---

**[1:00 - 4:00] Plantillas reutilizables**
_Cubre indicadores 1, 2, 3, 4 (32% de la nota de Presentación)_

1. Abre `.github/workflows/build-push-ecr.yml` y `deploy-eks.yml` en GitHub.
2. Señala el bloque `on: workflow_call:` y sus `inputs:` — explica que esto
   es lo que las hace reutilizables, no scripts copiados y pegados.
3. Muestra dónde `cd-pipeline.yaml` las invoca con `uses: ./.github/workflows/...`
   y pasa `with:` — así se ve la inyección de variables dinámicas
   (`image-tag: ${{ github.sha }}`, `color`, etc.) en vivo.
4. Explica **por qué** usas `aws-actions/configure-aws-credentials` y
   `amazon-ecr-login` en vez de scripts propios de autenticación (README
   sección 1, subsección "Actions oficiales vs. scripts propios"): son
   Actions oficiales versionadas y auditadas, reducen superficie de error
   humano frente a manejar tokens a mano.
5. Cierra con el valor de negocio: estas plantillas permiten desplegar
   cualquier microservicio nuevo del equipo reusando el mismo build/deploy,
   sin reescribir YAML desde cero cada vez — eso es lo que reduce tiempo de
   entrega y errores de configuración manual.

---

**[4:00 - 7:00] Estrategia Blue-Green**
_Cubre indicadores 5, 6, 7 (24% de la nota de Presentación)_

1. Muestra el diagrama de `orders-public` apuntando a un solo color
   (README sección 2).
2. Explica **las 4 estrategias** brevemente y por qué NO elegiste las otras
   tres — usa la tabla comparativa del README (uptime/costo/rollback/velocidad):
   - All-in-once: rápido pero con downtime garantizado, inaceptable para un
     servicio de pedidos.
   - Rolling Update: es lo que había antes y fallaba — ventana de tráfico
     mixto sin control.
   - Canary: válido, pero más lento de operar y de diagnosticar en un
     incidente en vivo (por el tráfico dividido).
   - Blue-Green (elegida): cutover atómico, rollback instantáneo, cuesta más
     recursos temporalmente pero es el costo correcto para un servicio
     crítico.
3. Muestra en `cd-pipeline.yaml` los jobs `determine-target-color`,
   `deploy-target`, `health-validation`, `switch-traffic` en orden — narra
   el flujo mientras señalas cada uno.

---

**[7:00 - 11:00] Live demo — pipeline funcionando**
_Cubre indicador 8 (10% de la nota, uno de los dos más pesados)_

1. Haz un cambio real y visible en el código (ej. un `console.log` nuevo en
   `index.js`, o un mensaje en el endpoint), commitea y push a `main`:
   ```bash
   git add -A
   git commit -m "demo: cambio visible para la defensa"
   git push
   ```
2. Ve a la pestaña **Actions** de GitHub, abre el run en curso.
3. **Narra en voz alta mientras corren los jobs** (esto es lo que pide
   explícitamente el indicador 8 — no te quedes en silencio viendo la
   pantalla):
   - "Ahora está en `tests`, corriendo los tests unitarios..."
   - "Pasó a `build`, está construyendo la imagen Docker y subiéndola a ECR
     con el SHA del commit como tag..."
   - "`determine-target-color` decidió que el color inactivo es X, así que
     desplegará ahí sin tocar el tráfico real..."
   - "Ahora `health-validation` está probando el Service de preview
     internamente, 5 intentos con 2 segundos de espera..."
   - "Pasó, así que `switch-traffic` está moviendo el 100% del tráfico
     público al nuevo color con un solo `kubectl patch`..."
4. Verifica en vivo con el navegador o `curl` contra la URL del LoadBalancer
   que el cambio nuevo ya está sirviendo.

---

**[11:00 - final abierto] Prueba de fuego — error inyectado por el docente**
_Cubre indicadores 9 y 12 (18% de la nota, el otro indicador más pesado)_

1. Cuando el docente inyecte el error, **no lo arregles tú manualmente**.
2. Señala la Terminal 1 (el watchdog) y **verbaliza lo que ves en tiempo
   real**, esto es literalmente lo que pide el indicador 9:
   - "Vemos que el watchdog empieza a reportar `FALLA #1`, código HTTP..."
   - Si alcanzas a ver el estado del pod: "y si miro `kubectl get pods`,
     está en `CrashLoopBackOff` / `ImagePullBackOff` / lo que sea — eso
     significa que [causa probable]."
   - Mantén la calma aunque no reconozcas la causa exacta — el punto del
     diseño es que el watchdog no necesita saber la causa, solo mide el
     síntoma. Puedes decir esto explícitamente, es un punto a tu favor.
3. Cuando se alcance el umbral (3 fallas, ~10s), el watchdog ejecuta el
   `kubectl patch` solo. Señálalo: "aquí está actuando el mecanismo de
   remediación, sin que yo intervenga."
4. Confirma verbal y visualmente que el servicio volvió a responder 200:
   ```bash
   kubectl get service orders-public -o jsonpath='{.spec.selector.color}'
   curl -s -o /dev/null -w "HTTP: %{http_code}\n" http://<tu-lb-hostname>/health
   ```
5. Cierra explicando el impacto medido (README sección 3, "Impacto medido"):
   MTTR de ~10 segundos, sin intervención humana, y por qué eso importa para
   el negocio (menos ventas perdidas, no requiere guardia activa 24/7).

---

## FASE 3 — Al terminar (para no gastar créditos de Academy)
```bash
eksctl delete cluster -f eksctl-cluster.yaml
```

---

## Banco de preguntas típicas del evaluador (respuestas cortas, sin leer)

**¿Por qué Blue-Green y no Canary?**
Porque el caso pide alta disponibilidad y bajo riesgo para un servicio
crítico de pedidos. Canary reduce el radio de impacto de forma gradual, pero
el cutover de Blue-Green es atómico y el rollback es instantáneo —
priorizamos velocidad de reacción sobre ahorro incremental de recursos.

**¿Qué pasa si `health-validation` falla?**
El job `rollback-pre-cutover` borra el Deployment de la variante nueva
automáticamente. El tráfico público nunca se movió de la versión estable, así
que el impacto a usuarios es cero.

**¿Cómo sabe el watchdog a qué color revertir?**
Lee el selector actual del Service (`kubectl get service ... -o jsonpath`),
y calcula el color contrario. No asume, lo consulta en cada ciclo.

**¿Qué pasa si las dos variantes fallan al mismo tiempo?**
El watchdog seguiría oscilando entre ambas sin estabilizarse (algo que de
hecho reprodujimos durante el desarrollo por un bug de falsos positivos).
Es una limitación real del diseño actual: no hay un tercer estado de
"detener todo tráfico" si ambas fallan. Mejora futura: agregar un modo de
"mantenimiento" que saque el Service de circulación en vez de seguir
alternando entre dos versiones rotas.

**¿Por qué usaste EKS real y no K3s si el profesor dijo que era opcional?**
Porque ya lo tenía andando de trabajos anteriores del curso, y quise que la
evidencia de la defensa fuera sobre la misma infraestructura administrada
que describe el caso de negocio del encargo (Amazon EKS real).

**¿Cuánto tiempo tardó en detectarse y corregirse la falla?**
~10 segundos: 3 chequeos consecutivos cada 3 segundos hasta alcanzar el
umbral, más el tiempo de aplicar el patch. Está documentado con evidencia en
`docs/evidencia-rollback-log.txt`.

**¿Por qué el intervalo de chequeo es de 3 segundos y el umbral de 3 fallas?**
Es un balance: un intervalo muy corto genera falsos positivos por latencia
de red normal hacia el LoadBalancer; uno muy largo retrasa la detección. 3
fallas consecutivas evita reaccionar a un timeout aislado, pero sigue siendo
rápido (~10s) frente a un fallo sostenido real.

---

## Plan de contingencia — qué hacer si algo falla en vivo

**Si el pipeline de GitHub Actions falla por credenciales expiradas:**
Las credenciales de AWS Academy duran ~4h. Ten a mano el paso 0.7 (Secrets
de GitHub) y actualízalos ahí mismo si es necesario, en menos de un minuto.

**Si el watchdog no detecta la falla en el tiempo esperado:**
No entres en pánico ni lo reinicies de inmediato. Verbaliza lo que estás
observando ("todavía no alcanza el umbral de 3 fallas, esperemos unos
segundos más") — la rúbrica valora que mantengas la calma y expliques el
proceso, no solo que ocurra instantáneamente.

**Si el LoadBalancer de AWS tarda en propagar DNS (raro, pero posible tras
recrear el clúster):**
Ten igual un `kubectl port-forward svc/orders-public 8080:80` como respaldo
para mostrar el `/health` localmente mientras se resuelve, explicando la
diferencia entre el chequeo interno y el público.

**Si accidentalmente rompes algo tú mismo antes de que el docente inyecte su
error:**
Puedes decirlo abiertamente y usarlo como demo adicional del mecanismo — de
hecho es literalmente lo que hiciste durante el desarrollo para probar el
sistema. No es un fallo tuyo, es evidencia de que el sistema reacciona igual
sin importar el origen de la falla.

---

## Checklist de ensayo (hazlo al menos una vez completo antes del día real)
- [ ] Clúster EKS creado y `kubectl get nodes` muestra nodos Ready
- [ ] Secrets de GitHub actualizados con credenciales vigentes
- [ ] Pipeline corre de punta a punta sin intervención manual
- [ ] `orders-public` apunta a un color y responde 200 en `/health`
- [ ] Provocaste una falla real tú mismo (ej. desplegar una imagen que
      crashea) y confirmaste que el watchdog revierte solo en <15s
- [ ] Sabes explicar, sin leer, por qué Blue-Green y no Canary/Rolling para
      este caso
- [ ] Practicaste narrar en voz alta mientras el pipeline corre (indicador 8)
- [ ] Practicaste el banco de preguntas típicas al menos una vez en voz alta
- [ ] README y `DECLARACION-USO-IA.md` completos y commiteados
- [ ] Decidiste qué hacer con `deploy-k3s.yaml` (eliminarlo o documentarlo
      como versión anterior reemplazada)
