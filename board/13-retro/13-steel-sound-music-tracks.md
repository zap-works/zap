---
size: M
---
# Lemmings: steel sounds and the music per level are checked against DOS

The sounds are played from the DOS game's AdLib driver (`projects/dos/lemmings/adlib.zap`) with the
effect numbers the oracle's log gave (`game/sound.zap`'s `effectOf`). Two things were never seen in
the oracle: the basher's and the miner's sound when they hit steel (the digger's is known), and the
music track chosen for each level (the order `(rating*30+number)%21+1` is Lemmix's guess).

- [ ] in the oracle (`tools/oracle.lua` logs "effect N iteration I"), run a basher and a miner into
  steel and read the effect numbers; fix `effectOf` in `game/sound.zap` if they differ
- [ ] read which song the DOS game plays on each level (the oracle logs the songs) for one level of
  each rating at least, and fix the song order if the guess is wrong
