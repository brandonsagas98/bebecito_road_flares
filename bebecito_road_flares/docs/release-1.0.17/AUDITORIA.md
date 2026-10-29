# Auditoría de entrega · BD Road Flares 1.0.17

Fecha: 2026-10-29. Diseño aprobado: conservar dos recursos y el uso actual. Estado: candidato comercial con pruebas automatizadas y comprobación real de uso y rendimiento en ESX/OX y Qbox/OX; alcance detallado en VALIDATION.md.

## Correcciones y simplificación

- Inventory.consume deja de redefinirse: la retirada física es una función privada explícita. La API pública conserva la confirmación de colocación y el consumo al encender. Se conserva también el modo anterior ConsumeOnIgnition=false.
- Eliminada sanitizeMetadata de lifecycle, sin llamadas. Se conserva el constructor autoritativo usado por publicación y sincronización.
- No se modifican controles, animaciones, modelos, texturas, audio, presupuestos, duración ni configuración predeterminada. Los restos siguen configurados en 600000 ms (10 minutos).
- Guías ES/EN equivalentes: E enciende y coloca; X cancela/desecha; E apaga en suelo. Ya no indican clic izquierdo ni cancelación previa con E.
- Documentación del tráfico corregida: franja pasiva por eventos y cierre nativo, no el antiguo controlador de vehículos.

- Ejemplos OX y QB corregidos con coma final: la entrada puede pegarse antes de otro artículo sin provocar un error de sintaxis. Probado ejecutando la tabla combinada en Lua.

## Distribución

El ZIP antiguo de 1.0.16 no representaba los últimos cambios. Este candidato se construye desde una lista explícita de archivos. Se excluyen backups, perfiles, pruebas, herramientas y referencias privadas del paquete del comprador. Se mantienen los dos recursos y un solo ensure del núcleo. Los modelos y sus bytes se conservan.

El constructor exige las 30 suites requeridas aprobadas, versión coincidente y hashes de todas las entradas de comprador idénticos a los capturados para las pruebas. Rechaza evidencia vacía, incompleta, fallida o código cambiado después de verificar. No hereda live-results de revisiones anteriores. Cada ZIP lleva SHA256SUMS.json. La construcción verifica extracción y hashes del paquete de comprador y comprueba los archivos de fuentes por separado.

## Seguridad y compatibilidad revisadas

La autorización, existencia y consumo se comprueban en servidor. Se mantienen sesiones por jugador/instancia, deduplicación, límites configurables, validación de coordenadas/superficie/distancia y bloqueo de colocaciones simultáneas. Los contratos existentes ejercitan fallos de creación, inventario vacío, reintentos, desconexión y limpieza. Esto no equivale a certificar todas las APIs de terceros: los inventarios personalizados deben cumplir el contrato síncrono incluido.

ESX/OX y Qbox/OX comparten la misma integración OX sin dependencia de framework en el núcleo. ESX nativo y QB mantienen adaptadores. qbx_core sin un inventario compatible no suministra existencias. No se promete compatibilidad universal automática.

## Rendimiento

Se conserva la arquitectura por eventos, distancia y presupuestos. La limpieza evita duplicación y código sin uso; no demuestra por sí sola una reducción de milisegundos. La clasificación/reconciliación ocurre cada 400 ms con bengalas; el dibujo se limita por fotograma. El servidor conserva una comprobación de instancias cada segundo y algunas difusiones recorren jugadores: no se anuncia coste cero ni coste constante.

Con límites de cantidad desactivados, el coste depende de las bengalas y observadores. Humo compartido: 128 volutas; luces: 8; audio: 4 fuentes; restos: 12. El tráfico limita su franja local a 12 nodos/24 piezas. No se eliminan efectos para obtener una mejora aparente. Las nuevas capturas de CPU con 1/15/60 bengalas registraron 0.136/0.470/0.852 ms por fotograma en Qbox y 0.151/0.501/0.876 ms en ESX. Son cargas sintéticas del dibujado real con un cliente, sin comparación antes/después; véase VALIDATION.md.

## Evidencia y aceptación

verification.json contiene la ejecución actual, su alcance y hashes del candidato. Los contratos usan Lua real con natives/red/inventarios simulados. Los ensayos de empaquetado reproducen exclusión de un archivo privado, rechazo de cambios posteriores y rechazo de resultados de pruebas inválidos. La evidencia de extracción y hashes de ZIP se entrega junto al paquete en dist.

Consulta VALIDATION.md para resultados y límites de las comprobaciones en juego. La versión queda instalada en ambos servidores locales del propietario, con copias de seguridad previas. En Qbox se integra el objeto en los catálogos de gobierno y Ammunation conservando permisos, trabajos y restricciones existentes. El laboratorio privado se detiene tras retirar los objetos de prueba. La licencia MIT se conserva.
