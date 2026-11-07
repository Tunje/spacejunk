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


## The lowest median of `windows` runs of consecutive samples (A45b). Load comes and goes, so a
## quiet window still shows what the code costs while the whole run's median shows the machine.
static func best_window_median(samples: Array[int], windows: int = 4) -> int:
	var size := maxi(1, samples.size() / windows)
	var best := -1
	for start in range(0, samples.size() - size + 1, size):
		var window := samples.slice(start, start + size)
		window.sort()
		var middle: int = window[window.size() / 2]
		best = middle if best < 0 else mini(best, middle)
	return best


## The perf alarm (A45b): over the budget is a PERF ALARM line, and only over `hard_multiple`
## times the budget, a real regression whatever else the machine is doing, does `test` fail.
static func alarm(test: GutTest, label: String, samples: Array[int], budget_usec: int,
		hard_multiple: int = 3) -> void:
	var quiet := best_window_median(samples)
	print("PERF %s: quietest window's median %d us (alarm at %d us, fails at %d us)" % [label, quiet, budget_usec,
		budget_usec * hard_multiple])
	if quiet >= budget_usec:
		print("PERF ALARM: %s quietest window's median %d us, over %d us" % [label, quiet, budget_usec])
	test.assert_lt(quiet, budget_usec * hard_multiple, "%s: %d times the budget is a regression" % [label,
		hard_multiple])
