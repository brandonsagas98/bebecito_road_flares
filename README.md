# BD Road Flares · FiveM

**Gratis por ahora / Free for now — v1.0.17**

Bengalas viales con encendido y colocación animados, luz, humo y combustión progresiva. Núcleo standalone con integración de inventario para ESX Legacy y Qbox con ox_inventory.

[Descargar ZIP de instalación](https://github.com/brandonsagas98/bebecito_road_flares/releases/download/v1.0.17/BD-Road-Flares-1.0.17-live-checked-20261029.zip) · [Página oficial](https://bebecitodevelopment.com/products/bebecito-road-flares) · [Video SAHP + LSPD](https://www.youtube.com/watch?v=QPEca4hn3II)

[![Demostración BD Road Flares](https://img.youtube.com/vi/QPEca4hn3II/hqdefault.jpg)](https://www.youtube.com/watch?v=QPEca4hn3II)

## Instalación rápida / ES

1. Descarga el ZIP de instalación en Releases. Copia **las dos carpetas** `bebecito_road_flares` y `bd_road_flare_assets` a `resources`, sin cambiar sus nombres.
2. Sigue [INSTALAR_ES.md](bebecito_road_flares/INSTALAR_ES.md) para registrar el artículo y el icono en tu inventario. En OX conserva `consume = 0` y el export incluido.
3. Agrega `bd_road_flare` a las tiendas que prefieras, conservando sus permisos y precio. Los ejemplos no reemplazan tu archivo completo de tiendas.
4. Después del framework y de ox_inventory, añade `ensure bebecito_road_flares`. Los modelos arrancan por dependencia. Instala artículos y modelos con el servidor vacío durante mantenimiento.

Requiere OneSync. No necesita ox_target ni tablas SQL propias. Los inventarios mantienen sus dependencias normales. El paquete de instalación contiene todo lo necesario; no instales archivos de investigación ni fuentes de modelos.

Usa el artículo, **E** enciende, **E** otra vez coloca y **X** cancela o desecha. Una unidad se descuenta al encender; colocar no descuenta otra. Duración predeterminada: 15 minutos desde el encendido. F6 y `/bengalas` también abren la preparación y requieren existencias.

## Quick start / EN

Download the installation ZIP from Releases. Copy both resource folders into `resources`, keeping their names. Follow [INSTALL_EN.md](bebecito_road_flares/INSTALL_EN.md) to register the inventory item and icon and add the item to existing shops. Start `bebecito_road_flares` after your framework and ox_inventory; the asset resource starts automatically. Install or update items and models during maintenance with no players connected.

OneSync is required. The core is standalone; ESX and Qbox integrations use the server inventory. ox_inventory is recommended. Other inventory APIs require their own server adapter. No ox_target or resource-specific SQL tables are needed.

Use the item, press **E** to ignite and **E** again to place. **X** cancels before ignition or discards afterwards. One item is consumed at ignition. Default burn time: 15 minutes starting at ignition.

## Compatibility, traffic and validation

Local ESX and Qbox environments were checked. See the included [validation scope](bebecito_road_flares/docs/release-1.0.17/VALIDATION.md). Traffic reactions depend on GTA navigation and existing vehicle routes; no universal avoidance or FPS guarantee is made. Flares are cleaned up when their owner disconnects or the resource restarts.

- [Inventory and shop integration](bebecito_road_flares/bridges/inventory/README.md)
- [Resource documentation](bebecito_road_flares/README.md)
- [Report an issue](https://github.com/brandonsagas98/bebecito_road_flares/issues)

MIT license. Copyright © 2026 Bebecito Development.
