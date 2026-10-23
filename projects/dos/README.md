# DOS: what the DOS games share

The parts of the DOS games (`projects/lemmings`, `projects/pop`) that are not a game's own:
`lemmings/` and `pop/` read each game's files (archives, pictures, levels, sounds, the executable's
tables) from the player's own copy, never committed; `opl3.zap` is the Yamaha OPL3 FM synthesizer of
the Sound Blaster and AdLib cards, as Nuked OPL3 emulates it, for the two-operator paths the games'
music takes; `planar.zap` the EGA's planar pictures.
