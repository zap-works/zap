# Minecraft: a world of blocks

A world of blocks to walk, dig and build in, in the manner of Minecraft, without an edge: hills,
beaches, seas and snowy peaks, trees, meadows of tall grass, ores below, made in chunks on other
threads as the player walks (the frame never waits for them) and let go behind. The textures are
photographed materials of ambientCG (CC0, `assets/blocks/`, made by `makeTextures.zap`), lit as
light behaves under a sky the air scatters (`graphics/`). `zap run projects/minecraft/main.zap`:
click to take the mouse; WASD walk, space jumps, the mouse looks, the left button breaks the block
aimed at, the right one places the block chosen (1-9 or the wheel). `world/` makes and keeps the
chunks, `tests/` checks them.
