# TechMarket Orders - Operación Resiliencia

Evaluación Final Transversal - AUY1104 Ciclo de Vida del Software II

## 1. Arquitectura en EKS

El microservicio `orders` (Node.js/Express) se despliega en un clúster **Amazon EKS**
(`techmarket-eks`, creado con `eksctl` sobre AWS Academy usando el rol precreado
`LabRole`, ver `eksctl-cluster.yaml`).

La imagen se construye con Docker y se publica en **Amazon ECR** (repositorio
`techmarket-orders`). El pipeline de CI/CD vive en `.github/workflows/` y está
compuesto por:

- **Plantillas reutilizables**:
  - `build-push-ecr.yml`: construye y publica la imagen en ECR. Recibe como
    parámetros el nombre del repositorio, el tag de imagen y la región — nada
    queda hardcodeado.
  - `deploy-eks.yml`: aplica el Deployment y el Service de previsualización de
    una variante (blue o green) en el clúster, inyectando dinámicamente color,
    imagen y namespace vía `envsubst`.
- **Orquestador** (`cd-pipeline.yaml`): decide qué color desplegar, invoca las
  plantillas, corre la validación de salud y ejecuta el cutover o el rollback.

### Actions oficiales vs. scripts propios

Las plantillas usan Actions oficiales de terceros de confianza en vez de
reimplementar esa lógica a mano:

- `aws-actions/configure-aws-credentials@v4`: configura las credenciales
  temporales de AWS Academy de forma segura, sin dejarlas expuestas en logs
  ni tener que exportarlas manualmente en cada job.
- `aws-actions/amazon-ecr-login@v2`: resuelve el login contra ECR y expone la
  URL del registry como output, evitando manejar tokens de Docker a mano.
- `actions/checkout@v4`: estándar para traer el código al runner.

Se usan Actions oficiales (mantenidas por AWS/GitHub, versionadas con tag fijo)
en vez de scripts propios de autenticación porque reducen superficie de error
humano, están auditadas públicamente, y se actualizan con parches de seguridad
sin que el equipo tenga que mantenerlas. La lógica de negocio específica del
proyecto (build parametrizado, envsubst, health checks, blue-green) sí se
implementó a mano en los `run:` de las plantillas, porque es lógica única del
caso "Orders" que ninguna Action de terceros cubre.

## 2. Estrategias de despliegue: comparación y elección

Antes de implementar, se evaluaron las cuatro estrategias vistas en el
semestre en función del contexto del caso (servicio crítico, tolerancia cero
a downtime, necesidad de rollback rápido):

| Estrategia | Uptime durante release | Costo (recursos) | Velocidad de rollback | Velocidad de entrega |
|---|---|---|---|---|
| **All-in-once** | Downtime garantizado (se reemplaza todo de golpe) | Bajo (1 sola versión corriendo a la vez) | Lento (hay que redesplegar la versión anterior desde cero) | Muy rápida |
| **Rolling Update** | Alto, pero con ventana de tráfico mixto (pods viejos y nuevos conviven) | Bajo-medio (réplicas parciales de ambas versiones) | Lento (`rollout undo`, tarda varios ciclos de reemplazo) | Rápida |
| **Canary** | Alto, riesgo acotado a un % de usuarios | Medio (corren ambas versiones, aunque el canary a baja escala) | Rápido (se reduce el % del canary a 0) | Media (requiere pasos incrementales) |
| **Blue-Green** (elegida) | Máximo — el cutover es atómico, sin ventana de tráfico mixto | Alto (dos ambientes completos corren en paralelo durante el release) | Instantáneo (un solo `kubectl patch` revierte el selector) | Rápida |

**Elegimos Blue-Green** por tres razones, en el contexto de un servicio
crítico como "Orders":

1. **Cutover atómico**: el cambio de tráfico es un solo `kubectl patch` sobre
   el selector del Service. No hay estados intermedios de tráfico mixto (como
   sí ocurre en Rolling Update o Canary) que compliquen el diagnóstico durante
   un incidente en vivo.
2. **Rollback instantáneo**: la versión anterior (el color que deja de recibir
   tráfico) NO se elimina inmediatamente. Sigue corriendo, lista para recibir
   tráfico de vuelta en segundos si algo falla después del corte — a
   diferencia de All-in-once, donde revertir implica volver a desplegar desde
   cero.
3. **Simplicidad de validación**: podemos probar el 100% del comportamiento
   de la nueva versión contra un Service de previsualización interno
   (`orders-preview-<color>`) antes de exponerla a usuarios reales, algo que
   Canary logra de forma más gradual pero más lenta de operar.

El trade-off consciente: Blue-Green consume el doble de recursos durante el
release (dos Deployments completos corriendo en paralelo). Para un servicio
crítico como "Orders", priorizamos cero downtime y rollback instantáneo por
sobre el ahorro de cómputo — el costo extra es temporal (solo durante el
release) y acotado, mientras que el costo de una caída del servicio de
pedidos es mayor y afecta directamente al negocio.

Funcionamiento:

```
                     ┌────────────────────┐
 usuarios ────────▶  │  orders-public      │  (selector: color=blue|green)
                     └─────────┬──────────┘
                               │ apunta SIEMPRE a un solo color
             ┌─────────────────┴─────────────────┐
             ▼                                     ▼
     orders-blue (Deployment)              orders-green (Deployment)
     orders-preview-blue (Service)         orders-preview-green (Service)
```

1. Se despliega la nueva versión en el color inactivo (ej. green), sin tocar
   `orders-public`.
2. El job **"Validación de Salud"** prueba `orders-preview-green` (health
   check HTTP repetido) sin afectar tráfico real.
3. Si pasa → `switch-traffic` mueve `orders-public` a `color=green` (100% del
   tráfico de una sola vez).
4. Si falla → `rollback-pre-cutover` elimina el Deployment defectuoso; el
   tráfico público nunca se movió de la versión estable.

## 3. Remediación automática

### Flujo de remediación (Detección → Acción → Notificación)

```
 ┌───────────────┐     ┌────────────────────┐     ┌──────────────────────┐
 │   DETECCIÓN   │────▶│      ACCIÓN         │────▶│    NOTIFICACIÓN       │
 │               │     │                     │     │                       │
 │ watchdog cada │     │ kubectl patch       │     │ log con timestamp,    │
 │ 3s vía curl al│     │ service selector    │     │ color anterior/nuevo, │
 │ LoadBalancer  │     │ -> color anterior   │     │ impreso en consola    │
 │ público       │     │ (rollback atómico)  │     │ (evidencia para       │
 │ /health       │     │                     │     │ auditoría/demo)       │
 └───────────────┘     └────────────────────┘     └──────────────────────┘
        │                                                    ▲
        │ 3 fallas consecutivas                              │
        └─────────────── umbral alcanzado ───────────────────┘
```

Hay dos mecanismos de remediación, para dos momentos distintos:

- **Pre-cutover** (dentro del pipeline): si la Validación de Salud falla antes
  de mover tráfico, el job `rollback-pre-cutover` borra la variante nueva
  automáticamente. Cero impacto a usuarios.
- **Post-cutover / en vivo** (`scripts/watchdog-auto-rollback.sh`): monitorea
  cada 3 segundos el `/health` de la variante activa contra la URL pública del
  LoadBalancer. Si detecta 3 fallas consecutivas (HTTP distinto de 200), el
  watchdog:
  1. **Detecta**: cuenta fallas consecutivas del endpoint público.
  2. **Actúa**: al llegar al umbral, ejecuta automáticamente
     ```
     kubectl patch service orders-public -n default \
       -p '{"spec":{"selector":{"app":"orders","color":"<color-anterior>"}}}'
     ```
     revirtiendo el tráfico al color anterior, que nunca dejó de correr.
  3. **Notifica**: imprime en consola cada falla y el resultado del rollback
     con timestamp, dejando un log auditable de todo el incidente.

  Este es el mecanismo que responde a la "Prueba de Fuego": un error
  inyectado en vivo se detecta y se corrige sin intervención manual.

### Impacto medido (evidencia real)

Durante el ensayo del 17-07-2026 se forzó una falla real (`CrashLoopBackOff`
en `orders-blue`, imagen inválida) con cero réplicas sanas de respaldo. El
watchdog:

- Detectó la falla en el primer chequeo (`HTTP 000`, sin respuesta).
- Alcanzó el umbral de 3 fallas consecutivas en **10 segundos** (intervalo de
  chequeo de 3s).
- Ejecutó el `kubectl patch` y restauró el servicio a `HTTP 200` de forma
  inmediata.

**MTTR (Mean Time To Recovery) medido: ~10 segundos**, sin intervención
humana. Ver evidencia completa en `docs/evidencia-rollback-log.txt` y
`docs/evidencia-rollback-verificacion.webp`.

Este MTTR bajo es el argumento de negocio central de la solución: en un
servicio de pedidos, cada minuto de caída se traduce directamente en ventas
perdidas y pedidos no procesados. Pasar de un rollback manual (que depende de
que alguien esté mirando un dashboard, minutos de reacción humana) a uno
automático de ~10 segundos reduce el impacto financiero de un incidente a una
fracción, y libera al equipo de tener que hacer guardia activa para reaccionar
a caídas.

## 4. Escenarios de error identificados

Escenarios de falla contemplados y cómo se manifiestan en EKS/Kubernetes:

| Escenario | Cómo se manifiesta | Estrategia asociada | Detectado por |
|---|---|---|---|
| **Imagen defectuosa / binario que crashea al iniciar** | Pods en `CrashLoopBackOff`, contenedor reinicia en loop | Blue-Green: el color roto nunca recibe tráfico si falla la validación pre-cutover; si falla post-cutover, el watchdog revierte | Watchdog (`/health` sin respuesta, HTTP 000) — **reproducido en vivo durante el desarrollo** |
| **Fallo de Liveness/Readiness probe** | Pod no pasa a `Ready`, el Service no le enruta tráfico | Rolling Update tradicional dejaría tráfico mixto degradado; Blue-Green evita exponerlo hasta pasar la Validación de Salud | Job `health-validation` del pipeline (5 intentos de `curl` contra el Service de preview) |
| **Latencia alta / error 500 en la nueva versión** | La app responde pero fuera de SLA o con errores de aplicación | La Validación de Salud (`health-validation`) corta el cutover antes de exponer al 100% de usuarios | Job `health-validation`, umbral de HTTP distinto de 200 |
| **Error de configuración del Deployment (recursos insuficientes, imagen inexistente)** | Pod en `ImagePullBackOff` o `Pending` indefinido | El `rollout status --timeout=120s` del job de deploy falla, el pipeline no avanza a validación | Paso `Esperar a que el rollout esté listo` de `deploy-eks.yml` |
| **Error "desconocido" inyectado en vivo (prueba de fuego)** | Cualquiera de los anteriores, sin aviso previo | El watchdog no depende de conocer la causa — solo mide el síntoma (`/health` no responde con 200) | Watchdog, agnóstico a la causa raíz |

Este último punto es intencional: el watchdog **no intenta diagnosticar la
causa** de la falla, solo mide el síntoma observable desde afuera (el
endpoint público deja de responder correctamente). Esto es lo que permite que
el sistema reaccione igual de bien ante un error conocido que ante uno
completamente nuevo introducido en la defensa — no hace falta anticipar cada
causa posible, solo el efecto que todas comparten.

Un caso real de este comportamiento ocurrió durante el desarrollo: un
`CrashLoopBackOff` provocado deliberadamente en `orders-blue` fue detectado y
remediado por el watchdog sin que el sistema supiera de antemano que la causa
era una imagen incompatible (`alpine:latest` sin el binario de la app) — solo
detectó que el health check dejó de responder.

## 5. Cómo se activa cada cosa

| Acción | Comando / disparador |
|---|---|
| Correr el pipeline completo | `git push` a `main`, o `workflow_dispatch` manual en GitHub Actions |
| Ver color activo actual | `kubectl get service orders-public -o jsonpath='{.spec.selector.color}'` |
| Monitoreo en vivo + auto-rollback | `./scripts/watchdog-auto-rollback.sh` (dejar corriendo durante la defensa) |
| Chequeo de salud puntual | `./scripts/health-check.sh` |
| Rollback manual de emergencia | `kubectl patch service orders-public -p '{"spec":{"selector":{"color":"blue"}}}'` |

## 6. Citas y referencias (APA)

Amazon Web Services. (2025). *Amazon EKS User Guide*. AWS Documentation. https://docs.aws.amazon.com/eks/

Amazon Web Services. (2025). *Amazon ECR User Guide*. AWS Documentation. https://docs.aws.amazon.com/AmazonECR/latest/userguide/

The Kubernetes Authors. (2025). *Services*. Kubernetes Documentation. https://kubernetes.io/docs/concepts/services-networking/service/

The Kubernetes Authors. (2025). *Deployments*. Kubernetes Documentation. https://kubernetes.io/docs/concepts/workloads/controllers/deployment/

GitHub, Inc. (2025). *Reusing workflows*. GitHub Docs. https://docs.github.com/en/actions/using-workflows/reusing-workflows

## 7. Declaración de uso de IA

Ver `DECLARACION-USO-IA.md`.
