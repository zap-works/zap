---
size: M
check: a test starts a program with pipes, writes to it, reads its lines without waiting, ends it
branch: agents
by: 704a3f6e-3fab-463a-9569-01d68ba36a46
---
# Piped processes in std/win

A program started with its stdin, stdout and stderr as pipes (CreatePipe, inheritable ends,
STARTF_USESTDHANDLES), read without waiting (PeekNamedPipe), written, its end seen and killed
(TerminateProcess); its environment without the variables named. The pty's code (std/win/pty.zap)
shows the shape.
