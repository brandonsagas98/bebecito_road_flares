# BD Road Flares 1.0.17 · Miniguía de instalación

Requiere FiveM con OneSync. Núcleo standalone; funciona con ESX o Qbox mediante el inventario del servidor. La instalación recomendada es **ox_inventory**. No necesita ox_target, una librería de interfaz ni tablas SQL propias. El inventario conserva sus dependencias habituales.

## ESX o Qbox con ox_inventory: 5 pasos

1. Copia **las dos carpetas** `bebecito_road_flares` y `bd_road_flare_assets` dentro de `resources`. Conserva sus nombres; no copies el ZIP de fuentes al servidor.
2. Abre `ox_inventory/data/items.lua`. Dentro de la tabla existente, pega solo la entrada `['bd_road_flare']` de `bridges/inventory/ox_items.lua`, con su coma. **No pegues otro `return`**. Conserva `consume = 0` y `export = 'bebecito_road_flares.useFlare'`.
3. Copia `images/roadflare.png` a `ox_inventory/web/images/`.
4. Dentro de `inventory` de una tienda existente en `ox_inventory/data/shops.lua`, añade esta línea (precio de ejemplo):

   ```lua
   { name = 'bd_road_flare', price = 50 },
   ```

   Conserva los permisos, ubicaciones y moneda de tu tienda. Esto no crea una tienda nueva.
5. En `server.cfg`, **después del framework y de ox_inventory**, añade:

   ```cfg
   ensure bebecito_road_flares
   ```

   Los modelos arrancan automáticamente por dependencia. Conserva `Config.Inventory.Provider = 'auto'`. Realiza la instalación o actualización de artículos/modelos con el servidor vacío y reinicia durante mantenimiento.

## Comprobar y usar

Compra una bengala y úsala en el inventario. **E** enciende y descuenta exactamente una unidad; **E otra vez** agacha y coloca delante de los pies. **X** cancela antes de encender (gratis) o apaga y desecha después (sin devolución). Escape y Supr también cancelan; las teclas pueden reasignarse en FiveM. Con la preparación cerrada, **E** junto a una bengala colocada la apaga.

**F6** y `/bengalas` también abren/cierran la preparación y requieren existencias. Cada nueva bengala requiere otra activación. Si falla la colocación, puedes reintentar con la misma unidad mientras siga encendida; no se cobra otra. Duración predeterminada: **15 minutos desde el encendido**, compartidos entre mano y suelo. Al apagarse puede quedar un resto local hasta **10 minutos**, máximo 12 restos.

Verifica que abrir y cancelar no quita artículos, encender quita uno y colocar no quita otro. No añadas un segundo descuento al callback de uso. La tienda cobra la compra normalmente.

## Otros inventarios

- **ESX nativo:** usa `Config.Inventory.Provider = 'esx'` o auto sin OX. Registra `bd_road_flare` en tu inventario y tienda. `bridges/inventory/esx_item.sql` es solo un ejemplo: comprueba el esquema antes de importarlo. El recurso registra su uso automáticamente.
- **QB:** usa `qb-core` y `qb-inventory`, agrega solo la entrada de `qb_item.lua` a los artículos compartidos, copia el icono y añade el artículo a tu tienda. Ejemplo: `qb_shop.lua`. Qbox con OX debe seguir los cinco pasos anteriores.
- **Personalizado:** `Provider = 'custom'` necesita un puente de servidor; ejemplo y contrato en `bridges/inventory/README.md`.
- **Sin inventario:** `Provider = 'none'` permite uso gratuito. No lo uses para vender unidades con control de existencias.

## Si no funciona / actualizar

Comprueba nombres de carpetas, OneSync, orden de inicio, identificador del artículo, export de OX e imagen. Revisa la consola si falta una dependencia. No instales duplicados del recurso.

Para una actualización, guarda tu configuración y adapta sus valores al nuevo `config.lua`. Con el servidor vacío reemplaza las dos carpetas. Si usas la consola de recursos, ejecuta `refresh` antes de iniciar el núcleo. Nunca detengas o reemplaces `bd_road_flare_assets` con jugadores conectados. Reiniciar solo el núcleo limpia las bengalas activas y conserva los modelos cargados.

Configura idioma (`es`/`en`), efectos y permisos opcionales en `config.lua`. Las bengalas no persisten al reiniciar ni cuando su dueño se desconecta. Consulta `docs/release-1.0.17/VALIDATION.md` para el alcance de pruebas del candidato.
