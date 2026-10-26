# Breath of the Wild

The Switch recompiler, which turns Breath of the Wild's code into Zap: slice by slice, from boot to control in the Shrine.

The plan is by slices of the game, each made right before the next: slice 1 is the start, from
the boot to leaving the Shrine of Resurrection (README.md says what runs).

## The whole build's time

A cold build of the whole game takes 25 minutes (README.md: 35 processor-seconds a part, nearly
all the IR passes; a warm one about a minute, an unchanged part 0.03 s). Left:
