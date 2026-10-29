# 1.0.17 — 2026-10-29

- Simplificación interna del inventario: retirada física del artículo separada de la confirmación de colocación; misma API y mismo consumo al encender.
- Eliminada una función de metadatos sin uso. Sin cambios en controles, modelos, efectos, duración ni valores predeterminados.
- Miniguías ES/EN equivalentes y ejemplo de inicio. Corregidas instrucciones antiguas de colocación, tráfico y duración de los restos.
- Paquete de comprador con lista explícita de archivos, evidencia vinculada a sus hashes y verificación de extracción. Fuentes separadas.
- Candidato comercial: pruebas automatizadas nuevas; validación nueva dentro de FiveM pendiente. No se atribuyen mejoras de FPS a esta limpieza.

---

## Trabajo actual — 28/10/2026

- Asistencia opcional de tráfico ambiente con reposo sin bengalas, límites de trabajo y desvío/frenado conservador. Módulo antiguo excluido.
- Optimización de consultas a conductores/asientos y limpieza de propiedad temporal.
- 22 suites automatizadas; mediciones nativas de CPU y maniobra local registradas en `docs/traffic-lite-20261028/verification.json`, con límites de alcance explícitos.

## 1.0.16 — Coordinación del encendido

- Revisión sync2: combustión durante el contacto; conserva el giro hasta terminar la retirada izquierda, con acercamiento simultáneo. Corrige el desfase de la primera revisión.

- Pose exclusiva del encendido: giro de 15 grados hacia la mano izquierda, calibrado con el esqueleto real en juego.
- La izquierda alcanza la punta real de la bengala; un solo regreso al agarre.
- Conserva sin cambios el diccionario de agarre y el movimiento aprobado al caminar/correr.
- Revisión visual por capturas sucesivas en tres ángulos; ver límites en docs/release-1.0.16/AUDITORIA.md.

## 1.0.15



- Recupera la tarea secundaria sin máscara genérica de torso para el clip parcial de agarre.

- Aplica el mismo modo al equipar, encender, colocar y recuperar la sujeción.

- Sin nuevos bucles ni cambios del prop o diccionario de animaciones.



# 1.0.14 — Agarre continuo y cancelación



Una sola postura al caminar, correr y parar; retirada explícita de la antigua postura de carrera. La pose de soporte incluye ahora la clavícula derecha para evitar añadir el balanceo del hombro a un codo fijo. No cambia la raíz, columna, piernas ni brazo izquierdo. Cancelación mediante X, Escape o Supr, sin ampliar las notificaciones y sin capturar texto de inventarios o chat.



# 1.0.10 — Auditoría de animaciones



Se evita reiniciar el agarre al encender y detenerlo al finalizar correctamente. Se elimina la segunda aproximación de la mano izquierda y se baja su recorrido. La colocación conserva los dedos cerrados al cambiar al agachado sin detener primero el agarre. Se rechazan órdenes de encendido superpuestas, se limpia la animación al cancelar y se restringe el alcance manual.



# 1.0.9 — Encendido



Una sola pasada corta del rascador, muñeca izquierda orientada según el antebrazo y retirada suave. Guía local temporal eliminada al completar o cancelar. Agarre derecho conservado.



# 1.0.8







- Sustituye el agarre anterior por una pose BD con puño cerrado y muñeca derecha neutra; retira la orientación forzada por IK al caminar.



- Calibra el prop dentro del puño y mantiene el margen de la brasa al acortarse la bengala.



- Conserva la pose durante la retirada de la tapa; corrige la transición de agacharse a soltar en el suelo.



- La pose ocupa 446 bytes y se distribuye en la carpeta de assets. Actualizar assets requiere clientes desconectados.



- Las variantes experimentales de ambas manos que cerraron FiveM fueron descartadas. Alcance y limitaciones en docs/release-1.0.8/AUDITORIA.md.







# 1.0.7







- Avisos arriba a la izquierda, fondo ajustado, acento rojo e icono de bengala.



- Agarre recalibrado y orientación de muñeca estable en marcha, preparación y encendido.



- Retirada de tapa por una trayectoria suave delante del torso; brazo portador conserva el mismo objetivo.



- Colocación agachada de 1,2 s, alcance progresivo y mano baja hasta liberar; limpieza al cancelar.



- Corrección del punto de agarre al acortarse el prop para mantener la punta fuera de la palma.



- Catorce suites de regresión, revisión visual local Qbox y actualización del núcleo en ESX/Qbox.







# 1.0.6







- Aviso pequeÃ±o al pie de la pantalla, fondo oscuro ajustado al texto y tipografÃ­a sin condensar; se elimina la franja azul.



- Ancho nativo conservado entre cuadros, un solo rectÃ¡ngulo y sin hilo de interfaz en reposo.



- Audio: selecciÃ³n de hasta cuatro fuentes en una pasada; sin ordenar todos los candidatos ni calcular raÃ­ces de fuentes fuera de alcance.



- Observadores: retirada de ordenaciÃ³n innecesaria y transmisiÃ³n correcta de etapa al efecto de ceniza.



- Regresiones de selecciÃ³n de audio con distintos Ã³rdenes y de reutilizaciÃ³n de medida del aviso.







# 1.0.5







- Avisos de una sola acciÃ³n con presentaciÃ³n azul marino y acento rojo; sin contador.



- E enciende y luego coloca; X descarta la unidad encendida. ColocaciÃ³n directa con animaciÃ³n.



- Motas cercanas de ceniza sin objetos ni mensajes de red.



- El apagado anticipado conserva la longitud consumida en lugar de un muÃ±Ã³n final incorrecto.



- Regresiones del ciclo natural completo y de la interfaz sin captura del mouse.







# 1.0.4







- Nueva silueta de combustiÃ³n con corona irregular, raÃ­z incandescente y halo rojo independiente.



- Acortamiento aparente al mirar desde arriba: la llama conserva una cabeza compacta en vez de extenderse sobre el suelo.



- Humo con variaciÃ³n de orientaciÃ³n, expansiÃ³n mÃ¡s suave, salida inicial segÃºn la orientaciÃ³n del prop y tinte de luz prÃ³ximo a la punta que cambia entre dÃ­a y noche.



- Seis volutas cercanas en lugar de ocho: 60 unidades pasan de 1.080 a 960 triÃ¡ngulos mÃ¡ximos de efectos por cuadro, incluyendo el halo nuevo.



- Chispas mÃ¡s legibles con trayectorias reutilizadas por rÃ¡faga; no se crean entidades o mensajes de red por chispa.



- Las texturas originales de efectos suman menos de 172 KB.







# 1.0.3







- Cabeza de combustiÃ³n mÃ¡s ancha, nÃºcleo blanco caliente y contorno rojo animado.



- Humo gris con turbulencia, ascenso, deriva por viento y disipaciÃ³n de hasta 4,2 s.



- Chispas breves cerca de la punta, sin entidades ni eventos de red adicionales.



- Detalle por distancia: ocho volutas hasta 12 m, cuatro hasta 60 m y llama simplificada hasta 120 m; descarte de dibujo fuera de cÃ¡mara.



- Eliminado el lÃ­mite oculto de siete bengalas sostenidas remotas: cada jugador cercano conserva su representaciÃ³n.



- AuditorÃ­a y perfil local de CPU incluidos en docs/release-1.0.3.







# 1.0.2







- Cantidad sin lÃ­mites por defecto; 0 desactiva lÃ­mites globales y por jugador.



- Llama y humo para todas las bengalas dentro de la distancia de detalle; lÃ­mites opcionales del dueÃ±o.



- ArtÃ­culo Roadflares, icono transparente aprobado y ejemplos de tienda a $50 configurables.



- Prop BD con impresiÃ³n longitudinal y tapa estriada, aplicado a todas las etapas.



- Luces, mezcla de audio, caducidad y protecciÃ³n contra spam siguen gestionadas.







## 1.0.1 Â· 2026-10-27







- EdiciÃ³n visual ligera: retirados del arranque y del paquete los mÃ³dulos de geometrÃ­a y conducciÃ³n NPC.



- Ayuda en pantalla dividida por componentes para evitar que GTA recorte el contador de bengalas.



- RecuperaciÃ³n de artÃ­culos utilizables al cambiar o reiniciar proveedores de inventario.



- InstalaciÃ³n ES/EN actualizada, texto UTF-8 reparado y matriz de compatibilidad verificable.







## 1.0.0 Â· 2026-10-26















- ColocaciÃ³n directa delante de los pies: sin apuntar, marcador, navegaciÃ³n ni hilo de vista previa en el flujo normal.







- Agacharse durante 1,8 segundos y mantener la mano baja hasta la entrega al suelo; cancelaciones no cuentan como Ã©xito.







- Encendido con objetivos de ambas manos en coordenadas del personaje, siempre por delante del torso; retirada independiente del rumbo.







- Cuerpo rojo mate BD con impresiÃ³n oscura; se elimina la gran etiqueta blanca.







- Llama diurna mÃ¡s definida y base de orientaciÃ³n completa para vistas elevadas; humo en coordenadas del mundo con orientaciÃ³n compartida por estela.







- Consultas de posiciÃ³n compartidas entre llama/humo/audio y cÃ¡lculo de punta limitado a las ocho luces seleccionadas.







- Prefiltro de distancia para el apagado cercano. Control de vehÃ­culos NPC opcional, desactivado de fÃ¡brica.







- SincronizaciÃ³n real entre dos clientes Qbox: llama/humo/audio, agarre remoto y misma bengala en suelo. Agarre remoto en bucle normal.







- Once suites automatizadas. Perfiles locales de 1.000 fotogramas e informe de validaciÃ³n incluidos.















## 0.2.0-rc3 Â· 2026-10-26















- Bengala sostenida hacia arriba por peticiÃ³n del propietario; mango calibrado entre los dedos y uniÃ³n al personaje corregida.







- Agarre reproduce el clip a velocidad normal y retiene el Ãºltimo fotograma; se recupera tras transiciones y se limpia al retirar el prop.







- Encendido con un solo raspado y retirada de la mano izquierda; colocaciÃ³n de cuerpo completo con objetivo de alcance; orientaciÃ³n previa al apagado.







- Audio original BD: raspado, siseo con microcrepitaciÃ³n y dos contactos de apagado. Sin muestras de terceros.







- Mezclador local sin interfaz/foco, mÃ¡ximo cuatro voces continuas, cuatro retiros breves y dos golpes; un buffer compartido y suspensiÃ³n en reposo.







- Once suites automatizadas, evidencia de agarre y reproducciÃ³n dentro de FiveM. El candidato conserva la validaciÃ³n multijugador con equipos distintos como requisito previo a una publicaciÃ³n comercial final.







# 0.2.0-rc2 Â· 26 octubre 2026















- AuditorÃ­a contrastada con documentaciÃ³n de CHP y video vial del fabricante; no se copian sus assets ni se atribuye certificaciÃ³n.







- Humo original visible, ascenso y deriva en coordenadas del mundo; disipaciÃ³n residual limitada a 2,4 segundos.







- CorrecciÃ³n de la carga del atlas en el cliente probado y de los tipos UV nativos; texturas 256Ã—512 y 128Ã—128.







- Hasta 64 volutas dibujadas y 144 triÃ¡ngulos por fotograma; ocho luces de suelo predeterminadas y reutilizaciÃ³n de la validaciÃ³n por ciclo.







- Transporte con punta hacia abajo; apagado mediante postura agachada y contactos de la cabeza con el pavimento, con props cosmÃ©ticos limitados y limpieza.







- API `ExtinguishNearestFlare()` para inventarios/menÃºs; conserva las comprobaciones de interacciÃ³n y servidor.







- Nuevas pruebas de UV, presupuesto sostenido, limpieza del prop de apagado y humo residual. Evidencia y perfiles en `docs/visual-audit-20261026/`.















# 0.2.0-rc1 Â· 26 octubre 2026















- Once modelos BD suaves con tapa separada, soporte, punta irregular carbonizada, cuatro etapas en mano/suelo y resto consumido; atlas compartido e icono renderizado desde el modelo.







- Llama con textura animada original y humo nativo gris; eliminado el renderer de bloques/lÃ­neas del paquete comercial.







- Consumo de artÃ­culo al encender, ticket autoritativo y reloj Ãºnico mano/suelo; colocaciÃ³n sin cobro adicional y sin reiniciar duraciÃ³n.







- Anuncios de bengalas en mano a observadores de la misma instancia; hasta siete props remotos locales, snapshots y cancelaciÃ³n de cargas pendientes.







- Poses originales de manos, retirada de tapa y colocaciÃ³n mediante animaciÃ³n de dejar objeto; limpieza de tapa incluso al cancelar.







- Presupuestos compartidos, UV/vÃ©rtices reutilizados, ciclos vacÃ­os detenidos y restos con lÃ­mite/TTL.







- Nuevas pruebas de contabilidad, etapas, pendientes, efectos, observadores y animaciones. Assets compilados y leÃ­dos de vuelta.















El acabado nuevo permanece como candidato hasta completar revisiÃ³n visual, dos clientes reales y perfiles CPU/GPU de esta versiÃ³n. Las pruebas de 0.1.0 se conservan como evidencia histÃ³rica.















# 0.1.0-rc1 Ã‚Â· 26 octubre 2026















- Adaptadores de inventario OX, ESX, QB y contrato personalizado; modo sin inventario explÃ­cito.







- Stock y consumo autoritativos, sesiones, exclusiÃ³n de colocaciones concurrentes y lÃ­mites globales.







- Modelo e icono originales BD, incluidos en un recurso de assets separado para reiniciar el cÃ³digo sin descargar el modelo.







- Correcciones de nativos del servidor, llegada al pavimento, Ãºltima unidad y limpieza de objetos en mano.







- Metadatos completos, reloj local de apagado, sincronizaciÃ³n inicial y limpieza por instancia corregidos.







- PartÃ­culas nativas predeterminadas; detalle procedural opcional, presupuestos de 24 partÃ­culas/12 luces y coordenadas estÃ¡ticas almacenadas para render.







- GuÃ­as ES/EN, ejemplos de tiendas, pruebas automatizadas y mediciones locales reproducibles.















El estado de las pruebas y los criterios pendientes de publicaciÃ³n se detallan en `docs/audit-20261026/RESULTADO_FINAL.md`.















