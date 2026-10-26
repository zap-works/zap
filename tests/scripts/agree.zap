# The check of the scripts bench: each Zap script and its Python one print the same bytes, run
# as the race runs them, on the fixed inputs.
import problems

test "the Zap and Python scripts print the same bytes" for name in [
	"count",
	"gitLog",
	"table",
	"grep",
	"loc",
	"jsonq",
	"csvSum",
	"replace",
	"todo",
	"diff",
	"gitStat"
]:
	expect problems.agree(name)
