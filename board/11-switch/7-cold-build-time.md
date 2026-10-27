---
size: L
priority: P0
---
# The whole cold build against its batches

The whole cold build (25 minutes) against its batches (four cold parts 17 s, nine minutes
projected): the likely cause is the machine, a four-core notebook that holds turbo clocks for
a batch and not for 25 minutes of full load (not main.zap's loop: eight parts cold took 60 s
through it and 52 s by a plain loop; not the translator, 116 MB; late parts cost the same as
early ones). Confirm by sampling the processor clock during a run; measure on a desktop. The
caches a part writes are still worth cutting: a 60 MB kept stage of its own module (pointless
for a part the stamp keeps whole) and a 48 MB IR shard, 14 GB a build, 17 GB in build/cache.
