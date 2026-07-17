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
```

## FASE 2 — Durante la defensa

1. Abre una terminal y déjala visible: **corre el watchdog**
   ```bash
   chmod +x scripts/watchdog-auto-rollback.sh
   ./scripts/watchdog-auto-rollback.sh
   ```
2. En otra pestaña, muestra el repo y explica las plantillas (indicadores 1-4
   de la Presentación).
3. Haz un cambio pequeño en `index.js`, commitea, push a `main` → el docente
   ve el pipeline correr en vivo (build, deploy green, validación, cutover).
   Narra cada paso mientras corre (indicador 8, live demo).
4. Cuando el docente inyecte el error real: **no lo arregles tú manualmente**.
   Señálalo en la terminal del watchdog ("aquí se detectan las fallas
   consecutivas...") y explica qué está pasando mientras el watchdog revierte
   solo (indicadores 9 y 12).
5. Confirma verbal y visualmente que el servicio volvió a responder 200:
   ```bash
   ./scripts/health-check.sh
   ```

## FASE 3 — Al terminar (para no gastar créditos de Academy)
```bash
eksctl delete cluster -f eksctl-cluster.yaml
```

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
- [ ] README y `DECLARACION-USO-IA.md` completos y commiteados
