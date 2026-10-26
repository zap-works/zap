# A stack overflow is reported as StackOverflow, on the main thread and in a job.
# host: linux
fn down(n i64) i64:
	down(n + 1) + 1

test "main thread" stops StackOverflow:
	print(down(args.len))

test "a job" stops StackOverflow:
	start = args.len
	mut j = background((): down(start))
	loop:
		if j.tryReceive() is v:
			print(v)
			break
