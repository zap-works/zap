---
size: XL
blocked: set aside
priority: P3
---
# AI: Zap is as fast as PyTorch and llama.cpp

Measured on a GTX 1650, on a machine shared with other builds: MNIST's epoch takes 1.35 times
PyTorch's time, the transformer's 200 steps 1.8 times, and TinyLlama's decoding runs at 0.77 of
llama.cpp's tokens per second (26.5 against 34.5). Causes found: every dispatch waits on a full
barrier after the one before; a prompt is read a token at a time (no batched causal attention); and
the transformer's steps compute each block's forward pass twice (a checkpoint per step, then its
pull). The code is in `projects/ai` and `std/tensor`.

- [ ] barrier only between dispatches that depend on each other; MNIST's epoch time falls toward
  PyTorch's
- [ ] read a prompt in a batch with causal attention; TinyLlama's prompt time falls
- [ ] compute each block's forward pass once in the transformer's step; its 200 steps take fewer
  seconds than 1.8 times PyTorch's
- [ ] after these, measure again (one at a time): MNIST epoch at or under 1.00x, the transformer
  at or under 1.00x, and TinyLlama's decoding at or over 34.5 tokens per second
