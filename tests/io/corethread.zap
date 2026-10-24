# The threads on the core's own start (runtime/core/corethread.zap, which the background jobs
# start their threads with): jobs that each wait for all the others are only done once they
# run on threads of their own at the same time.

test "background jobs that wait for each other run on separate threads":
	arrived = Atomic(0)
	jobs = []
	for k in 0..6:
		jobs.push(background((): meet(arrived, 6, k)))
	total = 0
	for job in 0..jobs.len:
		loop:
			match jobs[job].tryReceive():
				value:
					total += value
					break
				none:
					sleepMs(1)
	expect total == (0..6).sum(it + 1)

# back once count jobs have arrived, or after five seconds (a failure the test then sees)
fn meet(arrived Atomic, count i64, k i64):
	blockingBegin()
	_ = arrived.add(1)
	waited = 0
	while arrived.load() < count and waited < 5000:
		sleepMs(1)
		waited += 1
	blockingEnd()
	if arrived.load() < count: -1 else: k + 1
