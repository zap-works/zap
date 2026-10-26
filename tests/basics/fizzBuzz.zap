# FizzBuzz, plus a few number-theory classics: gcd, lcm, prime factors, Collatz.

import fs

fn gcd(a i64, b i64):
	x = a
	y = b
	while y != 0:
		t = y
		y = x % y
		x = t
	x

fn factors(n0 i64):
	out = []
	n = n0
	p = 2
	while p * p <= n:
		while n % p == 0:
			out.push(p)
			n /= p
		p += 1
	if n > 1:
		out.push(n)
	out

fn collatzLen(n0 i64):
	n = n0
	steps = 1
	while n != 1:
		if n % 2 == 0:
			n /= 2
		else:
			n = 3 * n + 1
		steps += 1
	steps

for i in 1..31:
	if i % 15 == 0:
		print("FizzBuzz")
	elif i % 3 == 0:
		print("Fizz")
	elif i % 5 == 0:
		print("Buzz")
	else:
		print(i)
a i64 = 462
b i64 = 1071
g = gcd(a, b)
print("gcd {a} {b} = {g}, lcm = {a / g * b}")
for n in [360, 97, 1001, 65_536, 600_851_475_143]:
	parts = factors(n).map("{it}")
	print("{n} = {parts.join(" * ")}")
mut best i64 = 1
mut bestLen = 1
mut n i64 = 1
while n < 100_000:
	l = collatzLen(n)
	if l > bestLen:
		bestLen = l
		best = n
	n += 1
print("longest Collatz under 100000: {best} ({bestLen} steps)")

test "fizzbuzz, gcd, the factors and the longest Collatz chain print their known values":
	main()
	prints fs.readFile("tests/basics/fizzBuzz.expected") ?? ""
