---
size: L
branch: server
---
# A compiler process kept running

its stages, nodes and types warm in memory (Kotlin's and
Gradle's daemons, Bazel's workers): `zap test`'s builds and a watch of the sources skip the
caches' reading and the process's start.
