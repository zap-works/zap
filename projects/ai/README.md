# AI models on the GPU

The models that check `std/tensor`, `std/gpu` and `grad` (the tensors, the kernels in Zap, the
gradients the compiler writes, SGD, Adam and AdamW, GGUF): `mnist.zap` (`digits/`), a char
transformer (`gpt/`), TinyLlama 1.1B (`llama/`, `llama.zap`, from a GGUF Q8_0 file), `basics/`
the kernels' checks and `bench/` the speeds. The data is in `projects/ai/data/`, outside git;
every check is a test (`zap test projects/ai`), skipped with a line on stderr without the file,
the GPU or llama.cpp.

## State

MNIST and the char transformer match PyTorch's loss; TinyLlama writes llama.cpp's tokens (26.5
against 34.5 tokens/s on a GTX 1650, measured before the barriers only on a hazard and grad
keeping the activations, and the batched causal prompt, merged unfinished). Set aside at this
state.
