---
size: L
priority: P1
---
# Code written as code: what fmt still changes

(std/codegen, fmt; the Switch's forms).
codegen.Source writes recomp.snes's and the Switch's translate/ code as fmt lays it out but for
two things fmt still does over it. Lines past 100 columns stay unbroken: DKC's 27, SMW's 224,
deko_basic's 1,881, 23,327 in BotW's first 6,000 functions, nearly all forms
(`core.writeFp(c, 0, core.fpArith(...))`, `c.emulate(arm64.Instr(...), 0x...)`); breaking them
as fmt does needs wrap.zap's breaking in one home both reach. And the Switch's forms
(forms/forms.zap's formLines, arm64's Instr.literal) write `x = x + e`, `(u64(2) << 0)` in
parentheses and decimals ungrouped (`u64(134414336)`): 5,823 places fmt rewrites in
deko_basic; they take a Source and `{n:#}`. fmt's guard join (rewriteMatch.zap) and digit
grouping (rewriteForms.zap) are second copies of Source's and the runtime's formatLiteral
until the seeds know `#` and std/codegen, then fmt calls them.
