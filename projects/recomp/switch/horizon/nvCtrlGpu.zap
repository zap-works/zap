# /dev/nvhost-ctrl-gpu, what the GPU is (switchbrew: NV services#nvhost-ctrl-gpu): its
# characteristics, the zcull unit's geometry and the masks of the units present, as the Tegra X1
# (GM20B: one GPC of two TPCs, one SM each) reports them.

import recomp.switch.maxwell

characteristicsSize = 0xA0

# the Tegra X1's GPU characteristics, field by field (the order of switchbrew's table)
fn tegraX1Characteristics():
	g = []
	g.pushU32le(0x120)   # arch
	g.pushU32le(0xB)   # impl
	g.pushU32le(0xA1)   # rev
	g.pushU32le(1)   # num_gpc
	g.pushU64le(0x4_0000)   # l2_cache_size
	g.pushU64le(0)   # on_board_video_memory_size
	for v in [2, 0x20, 0x2_0000, 0x2_0000, 0x1B, 0x3_0000, 1]:   # tpc per gpc ... gpc_mask
		g.pushU32le(v)
	for v in [0x503, 0x503, 0x80, 0x28, 0]:   # sm versions, warp count, va bits, reserved
		g.pushU32le(v)
	g.pushU64le(0x55)   # flags
	for v in [
		maxwell.classTwoD,
		maxwell.classThreeD,
		maxwell.classCompute,
		maxwell.classChannel,
		maxwell.classInline,
		maxwell.classCopy
	]:
		g.pushU32le(v)
	for v in [1, 0, 2, 1, 0, 1, 0x2_1D70, 0]:   # fbps ... rop_l2_en_mask
		g.pushU32le(v)
	g.pushU64le(0x62_3032_6D67)   # "gm20b"
	g.pushU64le(0)   # gr_compbit_store_base_hw
	g

fn ctrlGpuIoctl(mut k Kernel, cmd i64, mut io u8[]):
	match cmd:
		0x4701: put32(io, 0, 1)   # ZCULL_GET_CTX_SIZE
		0x4702:   # ZCULL_GET_INFO: ten words
			for n, v in [0x20, 0x20, 0x400, 0x800, 0x20, 0x20, 0xC0, 0x20, 0x40, 0x10]:
				put32(io, n * 4, v)
		0x4703, 0x4704, 0x4707, 0x4708, 0x470D, 0x470E: pass   # ZBC tables, FLUSH_L2, ...
		0x4705: characteristics(io)
		0x4706: put32(io, 16, 3)   # GET_TPC_MASKS: both TPCs of GPC 0
		0x4712: put32(io, 0, 2)   # NUM_VSMS
		0x4714:   # ZBC_GET_ACTIVE_SLOT_MASK
			put32(io, 0, 7)
			put32(io, 4, 1)
		0x471C: put64(io, 0, k.now() * 10_000 / 192)   # GET_GPU_TIME, in nanoseconds
		_: return nvNotImplemented
	nvOk

# GET_CHARACTERISTICS: the buffer size is set to the structure's and the structure written after
# it (the buffer address the client sends is ignored)
fn characteristics(mut io u8[]):
	chars = tegraX1Characteristics()
	put64(io, 0, characteristicsSize)
	for n, b in chars:
		io[16 + n] = b
