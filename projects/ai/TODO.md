# TODO: AI models on the GPU

Judged by the same tests' measures.

1. A tensor's shape in its type where it is known (`Tensor<[784, 128]>`, a product's shapes met
   when compiling), the runtime's shape kept for the others; today every shape is checked when
   the program runs.
2. Speed (GTX 1650, a machine shared with other builds): MNIST's epoch 1.35x PyTorch's time, the
   transformer's 200 steps 1.8x, TinyLlama's decoding 0.77x llama.cpp's tokens per second (26.5
   against 34.5). Every dispatch waits on a full barrier after the one before; a prompt is read a
   token at a time (no batched causal attention); the transformer's steps compute each block's
   forward pass twice (a checkpoint per step, then its pull).
