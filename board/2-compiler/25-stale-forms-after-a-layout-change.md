---
size: L
priority: P0
branch: compiler-25
by: d1ad7bf9-57fa-4859-a8f8-c3d65b1c60c3
---
# Stale forms after a layout change

A build with build/cache/ir from before a change of a struct's fields makes a wrong executable:
the compiler built so from compiler-1's sources (IrInst's args and key moved into a part, Node's
part split) stops at once (access violation reading 0x8 or 0x78) on its next build, while the
same sources built with `ZAP_RUN=nocache` are right. It happens with main's zap and with the seed,
so `zap test --only build`'s fixed point fails ("zap1 cannot build the compiler") until
build/fixedpoint/*/build/cache is deleted, and an incremental `zap build compiler/zap.zap` after
such a change may give a broken build/zap.exe.

To reproduce: export main's compiler/, runtime/ and std/ to a new dir, build its compiler/zap.zap
there with build/zap.exe (it fills that dir's build/cache), copy the changed compiler/ over it,
build again, then have the result build compiler/zap.zap (cold): it crashes. Found so far: only
build/cache/ir matters (parse/ and the kept stages do not); dropping the program's .forms file
alone made the seed's build right, but taking none of its entry forms (entryFormOf) did not, and
neither half of the ir dir's shards alone breaks it: two entries of different files together do.
Suspects: a form or kept code whose key misses a type's layout reached through another type
(keptEntryKeys.zap's typeNames), or a kept code (keptCode.zap) taken past its form's check.

- [ ] the case reduced to a test of `zap test` (a struct's field moved, two files, two builds)
- [ ] the key that misses it fixed
