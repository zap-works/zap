---
size: L
blocked: set aside
priority: P3
---
# AI: a tensor's shape is part of its type where it is known

Today every tensor shape is checked when the program runs (`std/tensor`, used by `projects/ai`). A
shape known at compile time, such as `Tensor<[784, 128]>`, should be part of the type so a product's
shapes are checked when compiling, and the runtime shape stays for the tensors whose shape is not
known.

- [ ] add shape parameters to the tensor type (number parameters, spec 3.6) in `std/tensor`, and
  check a matrix product's shapes at compile time; a mismatched product in a test is a compile error
  naming both shapes
- [ ] keep the runtime shape for tensors without a known shape; the existing `projects/ai` programs
  (`mnist.zap`, `transformer.zap`) still run with the same results
