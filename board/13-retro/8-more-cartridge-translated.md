---
size: L
---
# SMW: more of the cartridge is translated ahead of time

The recompiler translates only the functions its flow finds from the targets Mesen 2 saw on
`tests/routes/yi1.txt` (about 770 functions, `projects/smw/tables/played.cfg`); the rest runs in
the interpreter, so the sprites of later levels cannot have their windows patched for widescreen.

- [ ] record a longer route through more worlds with Mesen 2's played mode (see the `--mesen`
  command in `projects/smw/README.md`) and regenerate `tables/played.cfg`
- [ ] the translated function count rises, the sprites of the later levels run translated, and
  their windows are patched (retro-7); `zap test projects/smw` passes
