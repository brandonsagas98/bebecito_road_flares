-- Add this entry to your inventory's items table. Ship images/roadflare.png
-- to ox_inventory/web/images. Add { name='bd_road_flare', price=50 } to a shop.
return {
    ['bd_road_flare'] = {
        label = 'Roadflares',
        description = 'Bengala vial de seguridad · Bebecito Development',
        weight = 200,
        stack = true,
        close = true,
        consume = 0,
        client = { image = 'roadflare.png', export = 'bebecito_road_flares.useFlare' }
    },
}
