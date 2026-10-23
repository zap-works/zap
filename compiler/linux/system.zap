# The compiler built for Linux (target.zap's linux/ dirs, here beside zap.zap): what its Windows
# parts do with Windows' own functions. No job caps the tests' processes; free memory is
# /proc/meminfo's; a process is its id; the sampling profiler is the processor's (std/perf).

import fs
import perf

fn capTestProcesses():
	pass

# the machine's physical memory not in use, in bytes (MemAvailable)
fn freeMemory():
	for line in (fs.readFile("/proc/meminfo") ?? "").lines():
		if line.startsWith("MemAvailable:"):
			return (i64.parse(line[13..].replace("kB", "").trimmed()) ?? 0) * 1024
	0

# the memory each of the processes holds now with every process it started, and theirs: their
# resident pages, in bytes (0 for one that ended)
fn treeMemories(pids i64[]) i64[]:
	pids.map(treeResident(it))

fn treeResident(pid i64) i64:
	perf.residentBytes(pid) + perf.childrenOf(pid).map(treeResident(it)).sum()

fn getProcessId(process i64):
	process

# ZAP_RUN=profile: the program (its command line, run by sh) sampled every profilePeriod
# cycles on every thread by the processor (std/perf), each sample named by the executable's map;
# the functions by the samples in their own code (no stack is walked: no total), and with
# profile=name the addresses in that function the samples stopped at the most. Its exit code.
fn profileRun(exe str, line str, watchedName str):
	fns = functionsOf(exe)
	run = perf.runCounted("sh -c {quoteArg(line)}", "", "", 0, 0.0, profilePeriod, true)
	if run.code == -1: return -1
	counts = perf.samplesByFunction(fns, run.addresses)
	s = Samples(
		own = counts.copy(),
		total = zeros(fns.len),
		count = run.addresses.len,
		watched = fns.findIndex(.name == watchedName) ?? -1,
		callers = zeros(fns.len),
		hot = {}
	)
	reportSamples(fns, s, "self", counts)
	if s.watched >= 0:
		for address in run.addresses:
			rva = address - imageBase
			if perf.functionAtRva(fns, rva) == s.watched:
				s.hot.add(rva, 1)
		reportHot(s, watchedName)
	run.code

# the cycles between two samples of ZAP_RUN=profile's
profilePeriod = 1_000_003

# no job counts a test program's processor time: each process is capped by ulimit -t
# (targets/run.zap's runCommand)
fn jobHolding(p Process) i64:
	0

fn jobCpuMs(job i64) i64:
	0

fn closeJob(job i64):
	pass
