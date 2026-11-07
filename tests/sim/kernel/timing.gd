extends RefCounted
## Timing for tests that check a cost (A45). The gate runs while other gates load the machine, and
## load only ever adds time. So a cost is asserted on the fastest of several runs, which still
## measures the code, while a single run or a mean also measures whatever else is running.


## The fewest microseconds `work` took over `runs` calls of it. `work` must leave nothing behind
## that changes the next run.
static func best_usec(work: Callable, runs: int = 5) -> int:
	var best := -1
	for n in runs:
		var started := Time.get_ticks_usec()
		work.call()
		var took := Time.get_ticks_usec() - started
		best = took if best < 0 else mini(best, took)
	return best
