# `use fusedMultiplyAdd` at the top of a file: its functions, methods and tests round each multiply-add
# once
use fusedMultiplyAdd

type Scaled:
	x f64

	fn less():
		x * 10.0 - 1.0

fn less(a f64):
	a * 10.0 - 1.0

test "use fusedMultiplyAdd over a file":
	a = 0.1
	expect less(a).toBits() == 4_363_988_038_922_010_624
	expect Scaled(x = a).less().toBits() == 4_363_988_038_922_010_624
	expect (a * 10.0 - 1.0).toBits() == 4_363_988_038_922_010_624
