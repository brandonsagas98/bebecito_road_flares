# Validation / Validación · 1.0.17

**Commercial candidate / candidato comercial.** New automated evidence is bundled in verification.json. It executes actual Lua with mocked game, network and inventory APIs. It does not certify GTA rendering, audio on a real client, GPU cost, server load or every inventory version.

Live tests were run on 2026-10-29 with this version installed on the owner's local Qbox + ox_inventory and ESX + ox_inventory servers. Both installations retain the two resources. Qbox Ammunation purchase passed; real inventory use, cancellation before ignition, one-item consumption on ignition, placement without a second charge and extinguishing passed on both frameworks. ESX used a tagged test item, not a public shop purchase. Visual flame and smoke were observed. Test fixtures were removed and character position/test stock restored.

Se probaron en juego ESX/OX y Qbox/OX con 1.0.17. La compra real en Ammunation de Qbox y el ciclo de uso en ambos funcionaron sin cambiar controles ni efectos. Las instalaciones quedan actualizadas. Las tiendas de gobierno de Qbox incluyen el objeto conservando sus permisos. Los catálogos de recursos previamente detenidos se aplican cuando estos se inician.

## Measured performance / Rendimiento medido

Native client profiler, 1000 frames per case; mean resource CPU milliseconds per frame:

| Framework | 0 flares | 1 flare | 15 flares | 60 flares |
|---|---:|---:|---:|---:|
| Qbox/OX, GTA b3751 | 0.000 | 0.136 | 0.470 | 0.852 |
| ESX/OX, GTA b3258 | 0.000 | 0.151 | 0.501 | 0.876 |

One real client, fixed airport camera and synthetic networked flare fixtures exercising the real renderer. The idle sample had no resource ticks in that capture; this does not mean zero server cost. Profiles include profiler overhead and exclude server CPU, GPU and browser audio CPU. They are not a before/after comparison or a 60-player test. No universal FPS improvement is claimed. Private raw profiles, inventory data and server configuration are excluded from the buyer archive.

Un cliente real y objetos de prueba para cargar el dibujado real. No representan 60 jugadores ni certifican todas las versiones de inventario. Las pruebas automatizadas complementan estas comprobaciones.

## Additional acceptance scope / Alcance adicional pendiente

Repeat with **ESX + ox_inventory** and **Qbox + ox_inventory**; record server artifacts, inventory/core versions, client build, hardware and configuration.

- Buy bd_road_flare from an existing shop; its configured price is charged and the image appears.
- Use/cancel before ignition: no item removed. E ignites: exactly one removed. E places: no second removal. X discards with no refund. E extinguishes a nearby placed flare with preparation closed.
- Empty inventory refuses use; failed placement can retry the existing burning flare without another item. Duration continues from ignition; placement does not reset it.
- With two clients in the same instance, verify held/ground flame, smoke, light, audio, placement and extinguish. A different instance must not receive those flares.
- Verify expiry, owner disconnect, instance change and core restart clean up. Update/restart models only with the server empty.
- Compare idle and 1/15/60 flares, near/far and on/off screen, in the same scene against the prior version. Record resource CPU, frame times/FPS, client audio and network; separate CPU/GPU/browser costs. Synthetic flares do not represent 60 players.
- Test passive traffic/routing on straight roads, intersections and curves; do not promise universal avoidance of vehicles with existing routes.
- If selling native ESX, QB or a custom inventory setup, repeat the purchase/consume/restart flow with that actual adapter.

The session above does not certify two simultaneous real clients, a full 15-minute live expiry, every traffic scenario or native ESX/QB/custom inventories. Repeat the applicable checks above before advertising those specific validations. No universal live certification is claimed.
