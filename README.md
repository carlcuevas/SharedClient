# TechMarket Orders - Operación Resiliencia

Evaluación Final Transversal - AUY1104 Ciclo de Vida del Software II

## 1. Arquitectura en EKS

El microservicio `orders` (Node.js/Express) se despliega en un clúster **Amazon EKS**
(`techmarket-eks`, creado con `eksctl` sobre AWS Academy usando el rol precreado
`LabRole`, ver `eksctl-cluster.yaml`).

La imagen se construye con Docker y se publica en **Amazon ECR** (repositorio
`techmarket-orders`). El pipeline de CI/CD vive en `.github/workflows/` y está
compuesto por:

- **Plantillas reutilizables** (`.github/workflows/templates/`):
  - `build-push-ecr.yml`: construye y publica la imagen en ECR. Recibe como
    parámetros el nombre del repositorio, el tag de imagen y la región — nada
    queda hardcodeado.
  - `deploy-eks.yml`: aplica el Deployment y el Service de previsualización de
    una variante (blue o green) en el clúster, inyectando dinámicamente color,
    imagen y namespace vía `envsubst`.
- **Orquestador** (`cd-pipeline.yaml`): decide qué color desplegar, invoca las
  plantillas, corre la validación de salud y ejecuta el cutover o el rollback.

## 2. Estrategia de despliegue: Blue-Green

Elegimos **Blue-Green** (no Canary) por tres razones, en el contexto de un
servicio crítico como "Orders":

1. **Cutover atómico**: el cambio de tráfico es un solo `kubectl patch` sobre
   el selector del Service. No hay estados intermedios de tráfico mixto que
   compliquen el diagnóstico durante un incidente en vivo.
2. **Rollback instantáneo**: la versión anterior (el color que deja de recibir
   tráfico) NO se elimina inmediatamente. Sigue corriendo, lista para recibir
   tráfico de vuelta en segundos si algo falla después del corte.
3. **Simplicidad de validación**: podemos probar el 100% del comportamiento
   de la nueva versión contra un Service de previsualización interno
   (`orders-preview-<color>`) antes de exponerla a usuarios reales.

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

Hay dos mecanismos de remediación, para dos momentos distintos:

- **Pre-cutover** (dentro del pipeline): si la Validación de Salud falla antes
  de mover tráfico, el job `rollback-pre-cutover` borra la variante nueva
  automáticamente. Cero impacto a usuarios.
- **Post-cutover / en vivo** (`scripts/watchdog-auto-rollback.sh`): monitorea
  cada 3 segundos el `/health` de la variante activa y el estado de sus pods.
  Si detecta 3 fallas consecutivas (HTTP distinto de 200 o pods en
  `CrashLoopBackOff`/`Error`), ejecuta automáticamente:
  ```
  kubectl patch service orders-public -n default \
    -p '{"spec":{"selector":{"app":"orders","color":"<color-anterior>"}}}'
  ```
  revirtiendo el tráfico al color anterior, que nunca dejó de correr. Este es
  el mecanismo que responde a la "Prueba de Fuego": un error inyectado en vivo
  se detecta y se corrige sin intervención manual.

## 4. Cómo se activa cada cosa

| Acción | Comando / disparador |
|---|---|
| Correr el pipeline completo | `git push` a `main`, o `workflow_dispatch` manual en GitHub Actions |
| Ver color activo actual | `kubectl get service orders-public -o jsonpath='{.spec.selector.color}'` |
| Monitoreo en vivo + auto-rollback | `./scripts/watchdog-auto-rollback.sh` (dejar corriendo durante la defensa) |
| Chequeo de salud puntual | `./scripts/health-check.sh` |
| Rollback manual de emergencia | `kubectl patch service orders-public -p '{"spec":{"selector":{"color":"blue"}}}'` |

## 5. Citas y referencias (APA)

_Pendiente completar según las fuentes que efectivamente uses (documentación
oficial de AWS EKS, Kubernetes, GitHub Actions, etc.). Ejemplo de formato:_

> Amazon Web Services. (2025). *Amazon EKS User Guide*. AWS Documentation. https://docs.aws.amazon.com/eks/

## 6. Declaración de uso de IA

_Ver `DECLARACION-USO-IA.md` — completar con el detalle real de qué partes se
generaron/apoyaron con IA y cuáles fueron desarrolladas o adaptadas manualmente._
