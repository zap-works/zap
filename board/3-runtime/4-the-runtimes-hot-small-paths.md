---
size: L
priority: P2
---
# The runtime's hot small paths

measured on the benchmarks that touch them: `{x:.2}` through
an exact bignum (num.zap's fmtFixed) given a wide-multiply path for `dec <= 17`; bytesHash's
serial FNV chain given four lanes for keys of 32 bytes or more (rapidhash); an interpolation of
22 bytes or fewer built in the frame; stdout's buffer reserved at first use, stderr written
without a block per line, a pipe read straight into the list's spare capacity; `programArgs`
parsed on first use; a channel's wait on `WaitOnAddress` with no 10 ms timeout; `background` jobs
on the pool, not a thread each.
