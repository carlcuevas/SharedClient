# Declaración de Uso de Inteligencia Artificial

**Asignatura:** AUY1104 - Ciclo de Vida del Software II
**Evaluación:** Evaluación Final Transversal

## Herramienta utilizada
Claude (Anthropic).

## Partes del trabajo apoyadas con IA
- [x] Estructura inicial de los workflows de GitHub Actions (plantillas reutilizables)
- [x] Manifiestos de Kubernetes (Deployment/Service Blue-Green)
- [x] Script de monitoreo y rollback automático (watchdog)
- [x] Redacción del README técnico
- [x] Diagnóstico de errores durante la implementación (ver justificación)

## Partes desarrolladas/adaptadas manualmente por el estudiante
- [x] Configuración específica del clúster EKS con credenciales propias de AWS Academy
- [x] Pruebas y depuración del pipeline en el clúster real
- [x] Ajustes de nombres, namespaces y variables al entorno propio
- [x] Ensayo y ejecución de la demo en vivo, incluida la respuesta a la falla inyectada

## Justificación

Usé Claude como apoyo durante todo el desarrollo, principalmente para estructurar
los workflows de GitHub Actions (plantillas reutilizables con `workflow_call`),
los manifiestos de Kubernetes para la estrategia Blue-Green, y el script de
monitoreo con rollback automático. Cada resultado generado lo probé y adapté
contra mi clúster EKS real (credenciales de AWS Academy, nombres de recursos,
región), corrigiendo lo que no calzaba con mi entorno.

Durante los ensayos de la "prueba de fuego" (inyección de falla en vivo) me
encontré con un error que en un primer momento no logré identificar: el
watchdog reportaba fallas de forma intermitente incluso sin haber roto nada,
lo que generaba falsos positivos y rollbacks innecesarios. Diagnosticar la
causa real me tomó bastante tiempo, ya que no era evidente a simple vista.
Recurrí a Claude para depurar el problema paso a paso: primero se identificó
que el mecanismo de chequeo vía `port-forward` no era confiable contra un
clúster remoto en AWS por la latencia de red, y luego que el rollout de
Kubernetes dejaba pods sanos antiguos corriendo en paralelo a los pods
defectuosos nuevos, lo que hacía que las fallas no fueran consistentes. Con
esa guía corregí el script de monitoreo (consultando directo la URL pública
del LoadBalancer) y forcé el estado de falla real reduciendo réplicas del
despliegue defectuoso, lo que finalmente permitió comprobar el ciclo completo
de detección y rollback automático funcionando de forma correcta sobre EKS.

En todos los casos verifiqué el resultado ejecutando los comandos yo mismo
contra el clúster real antes de incorporarlo al entregable, y el README, los
workflows y los manifiestos finales reflejan la configuración efectivamente
usada en mi despliegue.

---
> Nota: Duoc UC solicita declarar el uso de IA como parte de los aspectos
> formales de esta evaluación. Esta plantilla debe completarse con información
> real y específica del trabajo efectivamente realizado, no dejarse genérica.
