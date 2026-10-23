# Ragnarok Online LATAM rebuilt in Zap

Ragnarok Online LATAM rebuilt in Zap on the engine from the player's own install (its data.grf:
the map's RSW, GND and GAT, the models and textures, the sprites), nothing of the game in the
repository. `zap run projects/ragnarok/prepare.zap` reads the install once (`--install <folder>`
when it is not in the default one) and writes the map and the hero, ready to use, into
`projects/ragnarok/assets/prepared/`; `zap run projects/ragnarok/main.zap` then reads only that
and opens at once with the hero standing by Prontera's fountain (it prepares first, once, when the
prepared files are missing or of an older format). `ragnarok/` reads the formats, `world/` the
map, `game/` the game.
