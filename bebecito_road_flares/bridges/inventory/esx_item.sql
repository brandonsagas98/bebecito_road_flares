-- Native ESX inventory only. OX-backed ESX uses ox_items.lua instead.
-- Run once after checking the items table schema used by your ESX release.
INSERT INTO items (name, label, weight, rare, can_remove)
VALUES ('bd_road_flare', 'Roadflares', 200, 0, 1)
ON DUPLICATE KEY UPDATE label = VALUES(label);
