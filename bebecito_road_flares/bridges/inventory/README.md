# Inventory and shop adapters / Inventarios y tiendas

Use item **bd_road_flare** and keep the resource name **bebecito_road_flares**. The use callback starts preparation; the flare server removes one unit on ignition. Never remove a second unit in your callback. Shop purchases retain their normal price and stock rules.

Quick guides: [Español](../../INSTALAR_ES.md) · [English](../../INSTALL_EN.md).

| Setup | Provider | Item/shop examples |
| --- | --- | --- |
| ESX or Qbox + ox_inventory | auto / ox | ox_items.lua, ox_shop.lua |
| Native ESX inventory | auto / esx | esx_item.sql (check existing schema) |
| qb-core + qb-inventory | auto / qb | qb_item.lua, qb_shop.lua |
| Another inventory | custom | custom_adapter.lua |
| Free standalone use, no stock | none | F6 or /bengalas |

## OX on ESX / Qbox

Merge only the `['bd_road_flare']` entry from `ox_items.lua` into `ox_inventory/data/items.lua`; do not paste a second return. Keep `consume=0` and the client export. Copy `images/roadflare.png` to `ox_inventory/web/images`. Add the entry from `ox_shop.lua` to an existing shop inventory in `ox_inventory/data/shops.lua`; keep that shop's locations, groups and currency. Start OX before the flare core. No framework import is needed in this product.

ES: pega solo la entrada dentro de la tabla existente, conserva consume=0, copia el icono y añade la línea a una tienda. Qbox con OX usa esta instalación, no los artículos compartidos de QB.

## Native ESX

Start es_extended before the flare core. Register the item in the existing inventory and shop. The resource automatically registers RegisterUsableItem and uses the player's authoritative inventory API. The SQL example targets name/label/weight/rare/can_remove; inspect your schema before importing. ESX backed by OX should use the OX path instead. Do not load a second framework copy.

## QB

Start qb-core and qb-inventory before the flare core. Merge only the `qb_item.lua` entry into QBCore.Shared.Items, copy the image to your inventory's image folder and add the item to your existing shop; `qb_shop.lua` is an example for a products list. The resource registers the usable callback and removes through qb-inventory. Qbox/OX follows the OX path above.

## Custom synchronous inventory

Set Config.Inventory.Provider='custom'. Start a separate server bridge after the core and register:

```lua
exports.bebecito_road_flares:RegisterInventoryAdapter({
    count = function(source, item)
        return YourInventory.Count(source, item)
    end,
    remove = function(source, item, amount)
        return YourInventory.Remove(source, item, amount) == true
    end
})
```

Replace YourInventory with your real API. count must return a finite nonnegative number; remove must atomically remove the requested amount and return true only on success. Both must complete synchronously, without Wait or async callbacks. Re-register after restarting the core or bridge. The item's client use handler calls `exports.bebecito_road_flares:StartDeploymentMode()`; do not remove an item there. Never trust client-supplied counts/removal results. Async inventories need a reservation/commit integration outside this example's contract.

## No inventory

Provider='none' explicitly enables free standalone use. Auto fails closed when no supported inventory is available. Do not choose none for commercial stock-controlled items.
