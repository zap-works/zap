---
size: XL
---
# GPU: flow control and instructions

condition codes (CC, .X: IADD.CC/IADD.X pairs, BRA by a condition),
indirect and call flow (BRX, JMX, CAL, RET), a jump to an outer if's end or an outer loop (no
labelled break: the program is left out), rounding modes other than nearest-even, IADD.SAT,
IADD3.RS, I2I.SAT, IMNMX's extended modes, XMAD.CSFU, P2R/R2P of condition codes or by a register,
IMAD, IMUL, LEA, PRMT, half floats (HADD2, HMUL2, HFMA2, HSET2, HSETP2), SHFL and VOTE (Zap has
`laneAt`, `laneAll`), special registers but the lane and the thread and group ids. The renderer
(not written) must give the depth range the game set (the compiler maps z from -1..1 to 0..1,
spec 11), the y direction, the vertex formats as Vec4 floats, constant buffer banks and texture
handles as above.
