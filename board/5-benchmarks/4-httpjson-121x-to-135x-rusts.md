---
size: L
priority: P3
---
# httpJson runs under 1.00x of Rust's time

`tests/benchmarks/httpJson.zap` measured 1.21x and 1.35x Rust's time in two measurements. Its
messages are views of the connection's buffer now, which brought its peak memory to 0.87x to 1.07x
Rust's. Left are the costs below; try each and keep it only if the ratio falls.

- [ ] allocate less per parsed request (the start line's and the headers' strings): make them views
  of the buffer
- [ ] fewer thread wake-ups on the loopback, and one send per batch of pipelined responses
- [ ] set `TCP_NODELAY` and reuse one read buffer per connection
- [ ] a sampler that follows the jobs, so the profile shows where the threads spend time
- [ ] after these, `zap test --only bench tests/benchmarks/httpJson.zap` shows the ratio under 1.00x
