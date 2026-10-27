---
size: L
priority: P1
---
# Generated recompiler code is already in `zap fmt`'s form

`std/codegen`'s `codegen.Source` writes the code of recomp.snes and of the Switch recompiler's
`translate/` as `zap fmt` lays it out, except for two things fmt still changes afterwards:

- Lines past 100 columns stay unbroken: DKC's 27, SMW's 224, deko_basic's 1,881, and 23,327 in
  BotW's first 6,000 functions, nearly all forms (`core.writeFp(c, 0, core.fpArith(...))`,
  `c.emulate(arm64.Instr(...), 0x...)`). fmt breaks them with `compiler/tools/fmt/wrap.zap`.
- The Switch's forms (`projects/recomp/switch/forms/forms.zap`'s `formLines`, arm64's
  `Instr.literal`) write `x = x + e`, `(u64(2) << 0)` in parentheses and decimals ungrouped
  (`u64(134414336)`), which fmt rewrites in 5,823 places in deko_basic.

Also, fmt's guard join (`rewriteMatch.zap`) and digit grouping (`rewriteForms.zap`) are second
copies of `Source`'s and the runtime's `formatLiteral`, until the seeds know `#` and `std/codegen`;
then fmt calls those.

- [ ] move `wrap.zap`'s line breaking to one place that both `fmt` and `codegen.Source` use, and
  break long lines in `Source`; the generated DKC and SMW code has no line past 100 columns and
  `zap fmt` changes none of it
- [ ] make the Switch's forms write what fmt would (`x += e`, no extra parentheses, grouped digits,
  through `Source` and `{n:#}`); `zap fmt` on deko_basic's generated code rewrites nothing
- [ ] after the seeds are promoted (by the user), make fmt call `Source`'s guard join and
  `formatLiteral` and delete its copies
