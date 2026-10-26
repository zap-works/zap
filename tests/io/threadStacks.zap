# 32 threads alive at once under a 1 GB data limit: a thread's stack (128 MB) is not data to the
# kernel, so they all start and are joined.
# host: linux (the limit and the stacks are Linux's)

extern "libc.so.6" fn setrlimit(resource i64, limit i64[]) i64

rlimitData = 2

test "32 threads run under a 1 GB RLIMIT_DATA":
	expect setrlimit(rlimitData, [1_073_741_824, 1_073_741_824]) == 0
	jobs = []
	for k in 0..32:
		jobs.push(background((): waitedJob(k)))
	total = 0
	for job in 0..jobs.len:
		loop:
			match jobs[job].tryReceive():
				value:
					total += value
					break
				none:
					sleepMs(1)
	expect total == (0..32).sum(it + 1)

# a job that waits outside the program, so the pool starts a thread for each one
fn waitedJob(k i64):
	blockingBegin()
	sleepMs(300)
	blockingEnd()
	k + 1
