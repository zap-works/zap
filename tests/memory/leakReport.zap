# ZAP_RUN=leaks names the calls that allocated each block never freed, from the table error
# traces read (runtime/core/leaks.zap).

fn leakSome():
	rtAlloc(24)

if not args.isEmpty and args[0] == "leak":
	if leakSome() == 0: print("no block")   # (used: an unused allocation is removed)
	return

test "a leak is named by the calls that made it":
	report = Process.output("\"{exePath()}\" leak", vars = [runAssignment("leaks")]).out
	expect "zap leak: 24 bytes at leakSome (tests/memory/leakReport.zap:" in report
	expect "zap leaks: 1 blocks never freed" in report
