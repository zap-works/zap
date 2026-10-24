# Loadable builds on Linux (runtime/core/loaded.zap): not made yet (zap build --loadable refuses
# Linux), so a load finds no room and says so.

fn mappedImage(p i64) (i64, i64):
	_ = p
	(0, 0)

fn makeRunnable(base i64, size i64):
	_ = base
	_ = size
