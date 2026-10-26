---
size: M
---
# The files parsed in parallel

(Go parses a package's files at once): a load is 0.4 to 0.9 s
on one thread, and files are independent until their declarations join one arena.
