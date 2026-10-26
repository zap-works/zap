# coroPrimeSieve: the first n primes by a chain of coroutines joined by bounded queues
# (the programming-language-benchmarks suite's coro-prime-sieve): a generator sends 2, 3, 4...
# and each task holds consecutive filters, a prime and its multiples out of what comes in;
# as many tasks as processors less two, so a number meets the primes in order as in a task per prime.
import asyncio
import os
import sys

CAPACITY = 64


async def generate(out):
    n = 2
    while True:
        await out.put(n)
        n += 1


async def filters(inp, out, found, room, last):
    primes = []
    while True:
        v = await inp.get()
        if any(v % p == 0 for p in primes):
            continue
        if len(primes) < room:
            primes.append(v)
            found.put_nowait(v)
            if last and len(primes) == room:
                return
        else:
            await out.put(v)


async def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    tasks = min(max((os.cpu_count() or 1) - 2, 1), n)
    share = (n + tasks - 1) // tasks
    tasks = (n + share - 1) // share
    found = asyncio.Queue()
    head = asyncio.Queue(CAPACITY)
    running = [asyncio.create_task(generate(head))]
    for k in range(tasks):
        nxt = asyncio.Queue(CAPACITY)
        running.append(asyncio.create_task(filters(head, nxt, found, min(share, n - k * share), k == tasks - 1)))
        head = nxt
    lines = [str(await found.get()) for _ in range(n)]
    for t in running:
        t.cancel()
    await asyncio.gather(*running, return_exceptions=True)
    sys.stdout.buffer.write(("\n".join(lines) + "\n").encode())   # bytes: no CRLF translation


asyncio.run(main())
