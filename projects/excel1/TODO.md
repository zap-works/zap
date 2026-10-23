# TODO: Excel 1.00

1. Every menu, dialog and file path exercised by a scripted test, with each trap it reaches
   written (live it dies on a Toolbox trap not written yet).
2. The p-code dispatcher and the code Excel copies into RAM before running it stay interpreted
   (56% of the instructions of the About run): recompile code copied at run time by the bytes it
   was copied from, then measure the recompiled run against the interpreted one.
3. Read the `.a2r` flux captures through a data separator (as MAME's floppy code reads flux) as the
   tracks' source where their turns disagree, in place of the `.moof` bits and the noise model.
4. About shows 98% free memory where the screenshot shows 99%: the Toolbox's own heap use set
   against the ROM's.
5. Open the sample documents (File > Open: the Standard File package) and match the other
   screenshots in `excel1/disks/extras/`.
