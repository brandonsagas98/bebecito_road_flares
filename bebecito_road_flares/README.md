# BD Road Flares · Bebecito Development

**1.0.17 — candidato comercial / commercial candidate.** Bengalas viales para FiveM con OneSync. Núcleo standalone con adaptadores de inventario para ESX, Qbox/OX, QB y proveedores personalizados. Dos carpetas, un solo `ensure`; sin ox_target ni tablas SQL propias.

- [Instalación rápida en español](INSTALAR_ES.md)
- [English quick installation](INSTALL_EN.md)
- [Inventarios y tiendas / inventory and shops](bridges/inventory/README.md)
- [Auditoría de esta versión](docs/release-1.0.17/AUDITORIA.md)
- [Live results, performance and validation scope](docs/release-1.0.17/VALIDATION.md)

## Uso

Usa el artículo `bd_road_flare`: **E para encender → E para colocar delante de los pies**. X cancela antes del encendido o desecha después, sin devolución. E cerca de una bengala colocada permite apagarla cuando la preparación está cerrada. F6 y `/bengalas` también activan la preparación. Requiere existencias salvo que el administrador seleccione explícitamente `Provider='none'`.

El servidor consume exactamente una unidad al encender. Colocar no vuelve a cobrar ni reinicia el reloj; una colocación fallida permite reintentar con la misma bengala mientras siga encendida. Duración predeterminada: **15 minutos desde el encendido**. Cuatro longitudes representan la combustión; humo residual hasta 4,2 segundos, restos locales hasta **10 minutos**, máximo 12. Las bengalas se limpian al desconectarse el dueño o reiniciar el recurso.

Modelo BD, texturas, icono y audio originales incluidos. La página local de audio y avisos no solicita foco de entrada. Se conservan los controles, efectos, animaciones, modelos y valores predeterminados de la base anterior a esta simplificación.

## Standalone y tiendas

No importa ESX ni Qbox en el núcleo. `Config.Inventory.Provider='auto'` selecciona OX primero (ESX o Qbox), después `qb-core` + `qb-inventory` y después ESX nativo. Qbox sin OX no es por sí solo un proveedor de inventario compatible. Otros inventarios requieren adaptador de servidor; standalone no significa compatibilidad automática con todas las APIs.

Las definiciones de artículo, entradas de tienda e imagen están incluidas. Conserva `consume=0` en OX: el recurso descuenta al encender. La tienda vende `bd_road_flare` con su propio precio, moneda y permisos. El modo `none` ofrece bengalas gratuitas; no mantiene existencias comerciales.

## Rendimiento y tráfico

Los trabajadores de combustión y reconciliación se detienen al quedar vacíos y disiparse los efectos restantes. El servidor conserva una comprobación de instancias de jugadores cada segundo. No se afirma coste cero de todo el recurso.

El humo comparte un presupuesto de 128 volutas; hay hasta ocho luces de suelo, cuatro voces de combustión y 12 restos locales. La selección por distancia se reconcilia cada 400 ms y el dibujo visible ocurre por fotograma. El renderizador limita las entregas gráficas; más bengalas/observadores aún pueden aumentar el coste. Los límites por jugador/global están desactivados por defecto (0); se pueden fijar en `config.lua`. No se cambian silenciosamente para mejorar cifras.

`Config.TrafficLite` utiliza una franja pasiva por eventos de hasta 12 bengalas y 24 piezas locales. `Config.NativeRoadClosure` añade cierres de navegación con referencias compartidas. Reutilizan la reconciliación existente: no escanean vehículos ni dan órdenes a conductores. La navegación de GTA puede variar por vía; no garantiza que vehículos con rutas previas eviten toda colisión. Ambos sistemas se pueden desactivar en configuración.

Esta versión simplifica mantenimiento y distribución. **No se anuncia una mejora nueva de FPS o CPU sin captura nueva en FiveM.** Las pruebas automatizadas incluidas usan Lua real con APIs del juego e inventarios simuladas. La validación nueva con clientes ESX/Qbox queda indicada en VALIDATION.md.

## API

Cliente: `StartDeploymentMode()`, `GetClientState()`, `IsDeploymentActive()`, `IgniteHeldFlare()`, `PlaceHeldFlare()`, `PlaceHeldFlareAt(coords,normal)`, `ExtinguishNearestFlare()`. OX utiliza `bebecito_road_flares.useFlare`. Las operaciones respetan estados, foco de interfaz, permisos y comprobaciones del servidor; un resultado true acepta el inicio, no certifica su finalización. La colocación con coordenadas exige pavimento válido.

Servidor: `GetInventoryProvider()` y `RegisterInventoryAdapter({count=...,remove=...})` en modo custom. Las dos funciones del adaptador deben ser autoritativas y síncronas; ver el contrato incluido.

## Distribución y actualizaciones

El ZIP del comprador contiene únicamente los dos recursos, documentación y hashes. Las fuentes editables se entregan en otro ZIP; no se instalan en el servidor. No se incluyen laboratorios, copias de seguridad ni referencias privadas. Se conserva LICENSE (MIT).

Instala o actualiza modelos con el servidor vacío. Los modelos están separados para permitir reiniciar solo el núcleo sin descargarlos. No detengas `bd_road_flare_assets` con jugadores conectados. Sigue la miniguía correspondiente para conservar tu configuración y actualizar el inventario.
