# Runtime builtins: deterministic random numbers, time, stdin.

import fs

mut rng = Random(42)
mut rolls = []
loop 8:
	rolls.push(rng.next(1..=6))
mut line = ""
for r in rolls:
	line += "{r} "
print(line)
f = rng.next(0.0..1.0)
print(f >= 0.0 and f < 1.0)   # true
print(rng.next(10..=10))   # 10

start = clockMs()
sleepMs(20)
elapsed = clockMs() - start
print(elapsed >= 15)   # true

# echo stdin lines until end of input
mut count = 0
loop:
	match stdin.line():
		line:
			count += 1
			print("line {count}: {line.trimmed()}")
		none: break
print("read {count} lines")

test "random numbers repeat for their seed, the clock goes forward and stdin reads what it was fed":
	stdin.feed("""
		alpha
		  beta  
		gamma
		""")
	main()
	prints """
	    1 2 2 4 2 6 4 6 
	    true
	    10
	    true
	    line 1: alpha
	    line 2: beta
	    line 3: gamma
	    read 3 lines
	    """

test "seconds runs with clockMs, and createDir makes the dirs above":
	s0 = clockSeconds()
	m0 = clockMs()
	sleepMs(20)
	print(clockSeconds() - s0 >= 0.015 and clockMs() - m0 >= 15 and unixSeconds() > 1_760_000_000)
	fs.createDir("{testDir()}runtime-test/a/b") ?? print("{error}")
	print(fs.exists("{testDir()}runtime-test/a/b"))
	prints """
	    true
	    true
	    """
