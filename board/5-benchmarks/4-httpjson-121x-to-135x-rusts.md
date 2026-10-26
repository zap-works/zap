---
size: L
priority: P3
---
# httpJson 1.21x to 1.35x Rust's

(two measurements): its messages are views of the
connection's buffer now (peak memory 0.87x to 1.07x Rust's with them). Left: the allocations of
each parsed request (the start line's and the headers' strings), the threads' wake-ups on the
loopback, one send per batch of pipelined responses, TCP_NODELAY, a reused read buffer, and a
sampler that follows the jobs.
