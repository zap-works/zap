# The knobs of the fleet, set from the page while the daemon runs: how many agents at once, how
# fast the plan may be spent, the default model, and the machine's ceilings and each agent's caps.

import json
import win

pub type Settings:
	limit i64 = 7   # agents at once on this machine, the sessions opened by hand included
	lands i64 = 2   # lands the daemon runs at once
	pace f64 = 1.0   # how many times as fast as evenly to its reset the plan's use may grow
	planCeiling f64 = 0.95   # no agent starts past this share of a window of the plan
	model str = "sonnet"   # an agent's model when its ask names none
	effort str = "high"   # an agent's effort when its ask names none
	cpuCeiling f64 = 0.85   # no agent starts while the processors are busier than this
	memoryFloor f64 = 2.0   # no agent starts with fewer GB free
	agentMemory f64 = 6.0   # GB an agent and what it starts may hold, 0 for no cap
	agentCpu f64 = 0.0   # the share of the processors an agent may take, 0 for no cap
	autoQueue bool = false   # agents started on the board's Ready cards when there is room

	# the settings with what the JSON object names changed
	fn changedBy(body str):
		doc = json.parse(body) ?? return self.copy()
		root = doc.root
		Settings(
			limit = i64(doc.number(root, "limit") ?? f64(limit)),
			lands = i64(doc.number(root, "lands") ?? f64(lands)),
			pace = doc.number(root, "pace") ?? pace,
			planCeiling = doc.number(root, "planCeiling") ?? planCeiling,
			model = doc.textOf(root, "model").copy() if doc.textOf(root, "model") != "" else model.copy(),
			effort = doc.textOf(root, "effort").copy() if doc.textOf(root, "effort") != "" else effort.copy(),
			cpuCeiling = doc.number(root, "cpuCeiling") ?? cpuCeiling,
			memoryFloor = doc.number(root, "memoryFloor") ?? memoryFloor,
			agentMemory = doc.number(root, "agentMemory") ?? agentMemory,
			agentCpu = doc.number(root, "agentCpu") ?? agentCpu,
			autoQueue = (doc.number(root, "autoQueue") ?? (1.0 if autoQueue else 0.0)) != 0.0
		)

# a window of the plan as the agents' streams tell it: its use and when it resets
pub type Window:
	use f64
	resetsAt i64   # unix seconds
	at i64 = 0   # when the use was read
	baseUse f64 = 0.0   # an earlier reading, the start of the rate
	baseAt i64 = 0

	# the window read again: the earlier reading kept as the rate's start while it is under half an
	# hour old, else the last reading taken as the new start
	fn readAgain(seen f64, resets i64, now i64):
		if at == 0 or resets != resetsAt:
			return Window(use = seen, resetsAt = resets, at = now, baseUse = seen, baseAt = now)
		if now - baseAt > 1_800:
			return Window(use = seen, resetsAt = resets, at = now, baseUse = use, baseAt = at)
		Window(use = seen, resetsAt = resets, at = now, baseUse, baseAt)

	# seconds until the window is used up at the rate since the earlier reading; none while it
	# does not grow
	fn runsOutIn() i64?:
		if at <= baseAt or use <= baseUse: return none
		rate = (use - baseUse) / (at - baseAt)
		i64((1.0 - use).max(0.0) / rate)

	# the share of the window the pace allows now: its elapsed share times the pace
	fn allowed(name str, pace f64, now i64):
		length = 7 * 86_400 if name == "seven_day" else 5 * 3_600
		elapsed = (f64(now - (resetsAt - length)) / f64(length)).max(0.0).min(1.0)
		(elapsed * pace).min(1.0)

# the machine as last seen: processors, memory and GPU
pub type Machine:
	cpu f64 = 0.0   # busy share since the look before
	memory win.MemoryUse = win.MemoryUse(total = 0, free = 0)
	gpu str = ""   # nvidia-smi's use and memory, "" without one
	times win.CpuTimes = win.CpuTimes()

	# the machine looked at again
	fn looked():
		now = win.cpuTimes()
		Machine(cpu = now.busySince(times), memory = win.memoryUse(), gpu = gpu.copy(), times = now)

# the GPU's use and memory as nvidia-smi gives them, "" when there is none
pub fn gpuUse() str:
	ran = Process.output("nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits")
	if ran.code != 0: return ""
	parts = ran.out.trimmed().split(",").map(.trimmed().copy())
	if parts.len < 3: return ""
	"GPU {parts[0]}%, {parts[1]}/{parts[2]} MB"
