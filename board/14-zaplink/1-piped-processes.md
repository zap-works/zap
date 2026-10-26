---
size: M
check: a test starts a program with pipes, writes to it, reads its lines without waiting, ends it
---
# Piped processes in std/win

A program started with its stdin, stdout and stderr as pipes (CreatePipe, inheritable ends,
STARTF_USESTDHANDLES), read without waiting (PeekNamedPipe), written, its end seen and killed
(TerminateProcess); its environment without the variables named. The pty's code (std/win/pty.zap)
shows the shape.
