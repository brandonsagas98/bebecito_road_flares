# BD Road Flares 1.0.17 · Quick installation

Requires FiveM with OneSync. Standalone core; works with ESX or Qbox through the server inventory. **ox_inventory** is the recommended installation. No ox_target, UI library or product-specific SQL tables are required. Your inventory retains its own dependencies.

## ESX or Qbox with ox_inventory: 5 steps

1. Copy **both folders**, `bebecito_road_flares` and `bd_road_flare_assets`, into `resources`. Keep their names; do not install the separate source ZIP on the server.
2. Open `ox_inventory/data/items.lua`. Inside its existing table, paste only the `['bd_road_flare']` entry from `bridges/inventory/ox_items.lua`, including its comma. **Do not paste a second `return`**. Keep `consume = 0` and `export = 'bebecito_road_flares.useFlare'`.
3. Copy `images/roadflare.png` to `ox_inventory/web/images/`.
4. Inside an existing shop's `inventory` in `ox_inventory/data/shops.lua`, add this entry (example price):

   ```lua
   { name = 'bd_road_flare', price = 50 },
   ```

   Keep your shop's permissions, locations and currency. This does not create a new shop.
5. In `server.cfg`, **after the framework and ox_inventory**, add:

   ```cfg
   ensure bebecito_road_flares
   ```

   The models start automatically as a dependency. Keep `Config.Inventory.Provider = 'auto'`. Install or update item/model definitions with the server empty and restart during maintenance.

## Check and use

Buy a flare and use it in your inventory. **E** ignites and consumes exactly one item; **E again** crouches and places it in front of your feet. **X** cancels before ignition (free), or extinguishes and discards it after ignition (no refund). Escape and Delete also cancel; FiveM key bindings can be reassigned. With preparation closed, **E** near a placed flare extinguishes it.

**F6** and `/bengalas` also open/close preparation and require stock. Each new flare requires another activation. If placement fails, retry with the same burning flare while it has time remaining; no second item is charged. Default duration: **15 minutes from ignition**, shared between hand and ground. Extinguished flares may leave local debris for up to **10 minutes**, capped at 12 debris props.

Check that opening/cancelling removes nothing, ignition removes one and placement removes no additional item. Do not add a second removal to the use callback. The shop charges purchases normally.

## Other inventories

- **Native ESX:** use `Config.Inventory.Provider = 'esx'` or auto without OX. Register `bd_road_flare` in your inventory and shop. `bridges/inventory/esx_item.sql` is only an example: check your schema before importing. The resource registers item use automatically.
- **QB:** use `qb-core` and `qb-inventory`, merge only the entry from `qb_item.lua` into shared items, copy the icon and add the item to your shop. Example: `qb_shop.lua`. Qbox with OX should follow the five steps above.
- **Custom:** `Provider = 'custom'` requires a server bridge; see the example and contract in `bridges/inventory/README.md`.
- **No inventory:** `Provider = 'none'` enables free use. Do not use it to sell stock-controlled units.

## Troubleshooting / updates

Check folder names, OneSync, startup order, item identifier, OX export and image. Check the console for missing dependencies. Do not install duplicate copies of the resource.

Before an update, back up your configuration and transfer your settings into the new `config.lua`. Replace both folders with the server empty. If using the resource console, run `refresh` before starting the core. Never stop or replace `bd_road_flare_assets` while players are connected. Restarting only the core cleans active flares and keeps the models loaded.

Set language (`es`/`en`), effects and optional permissions in `config.lua`. Flares do not persist across restarts or owner disconnects. See `docs/release-1.0.17/VALIDATION.md` for this candidate's test scope.
