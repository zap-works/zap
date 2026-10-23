# Tables against lists: the lab's balls (projects/lab/physics/balls.zap) stepped as a Table<Ball> and,
# the same sources with the table written as a list, as a Ball[]. Each case is the table's
# processor cycles over the list's, and the two print the same sums.
# With `--ab zap` (`ZAP_RUN=ab=zap` with zap test --only bench) the two programs are each built by both zaps and
# raced instead (std/compare's A/B), here or on the ssh machine.
#
#   zap test --only bench
import compare
import fs

request = compare.timedSuiteRequest(args)
dir = "build/tables"
balls = 5000
steps = 20_000 if request.full else 2000

# the sources of the list variant: the table's, with `Table<...>` written as a list
fn listed(from str, to str):
	text = fs.readFile(from) ?? fail("suite.zap: cannot read {from}")
	_ = fs.writeFile(
		to,
		text.replace("Table<physics.Ball>", "physics.Ball[]").replace("Table<Ball>", "Ball[]")
	)

# a program the A/B races, run with arg
fn raced(name str, zap str, arg str):
	compare.Problem(
		name = name.copy(),
		zap = zap.copy(),
		others = [],
		arg = arg.copy(),
		quickArg = arg.copy(),
		smallArg = arg.copy(),
		stdin = false,
		flags = ""
	)

if request.name in "lab-balls":
	_ = fs.createDir(dir)
	_ = fs.createDir("{dir}/physics")
	listed("projects/lab/bench/balls.zap", "{dir}/ballsList.zap")
	listed("projects/lab/physics/balls.zap", "{dir}/physics/balls.zap")
	arg = "{balls} {steps}"
	if request.ab != "":
		# the A/B (--ab zap): the table's program and the list's, each built by both zaps, raced
		problems = [
			raced("lab-balls", "projects/lab/bench/balls.zap", arg),
			raced("lab-balls-list", "{dir}/ballsList.zap", arg)
		]
		compare.abSuite(problems, _: "", request)
		exit(0)
	tableExe = compare.build("projects/lab/bench/balls.zap", "")
	listExe = compare.build("{dir}/ballsList.zap", "")
	if tableExe == "" or listExe == "":
		exit(1)
	table = compare.measure(tableExe, arg, "", "{dir}/table.out", request.runs, 0) ?? exit(1)
	list = compare.measure(listExe, arg, "", "{dir}/list.out", request.runs, 0) ?? exit(1)
	if (fs.readFile("{dir}/table.out") ?? "") != (fs.readFile("{dir}/list.out") ?? ""):
		exit(1, "lab-balls: the table and the list print different sums")
	compare.benchLine(
		"lab-balls",
		"time",
		table.cycles,
		list.cycles,
		"Ball[]",
		"projects/lab/bench/balls.zap",
		arg,
		""
	)
