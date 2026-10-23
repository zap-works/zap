# TODO: FireRed

1. Cycle counting exact (IWRAM's sound buffer and frame counters still differ from mGBA's).
2. The assets split into graphics, maps, text, music and tables: needs the decomp's symbol map,
   which comes only from building pokefirered with agbcc.
3. A frame-for-frame check against mGBA: needs a headless mGBA (the Windows build has its GDB
   stub only in the windowed app).
4. Compile time and memory of the generated code (100 s, 2.3 GB).
