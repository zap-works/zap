# What the machine is doing: the processors' busy share between two looks and the memory in use,
# as a scheduler reads them before it starts more work.

extern fn GetSystemTimes(out idle u64, out kernel u64, out user u64) bool
extern fn GlobalMemoryStatusEx(status u8[]) bool

# the processors' times at one look, in 100 ns (kernel time includes idle time)
pub type CpuTimes:
	idle u64 = 0
	busy u64 = 0

	# the busy share of the processors since `before`, 0 to 1
	fn busySince(before CpuTimes):
		total = (busy - before.busy) + (idle - before.idle)
		f64(busy - before.busy) / f64(total) if total > 0 else 0.0

# the processors' times now
pub fn cpuTimes() CpuTimes:
	if not GetSystemTimes(out idle, out kernel, out user): return CpuTimes()
	CpuTimes(idle, busy = kernel + user - idle)

# the memory: its total and what is free, in bytes
pub type MemoryUse:
	total i64
	free i64

# the memory now (MEMORYSTATUSEX)
pub fn memoryUse() MemoryUse:
	status u8[] = zeros(64)
	status.setU32le(0, 64)
	if not GlobalMemoryStatusEx(status): return MemoryUse(total = 0, free = 0)
	MemoryUse(total = status.i64le(8), free = status.i64le(16))
