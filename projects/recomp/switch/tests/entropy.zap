# svcGetInfo's entropy as Eden reports it (read from its gdb stub after the call).

import recomp.switch.horizon

test "the process entropy is Eden's, std::mt19937 seeded 0":
	second u64 = 0x9A4E_B343_DBA2_52FB
	third u64 = 0x8B7D_76C3_D8E5_7D67
	expect horizon.processEntropy(2) == second
	expect horizon.processEntropy(3) == third
	expect horizon.processEntropy(4) == none
