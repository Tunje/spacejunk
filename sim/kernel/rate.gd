class_name Rate
extends RefCounted
## The one per-tick rounding helper. Rates and remainders are non-negative: never pass a net
## figure. Call amount and carry with the same arguments, then store carry as the new remainder.


static func amount(rate: int, remainder: int) -> int:
	assert(rate >= 0 and remainder >= 0, "Rate takes non-negative values")
	return (rate + remainder) / Sim.TICKS_PER_SECOND


static func carry(rate: int, remainder: int) -> int:
	assert(rate >= 0 and remainder >= 0, "Rate takes non-negative values")
	return (rate + remainder) % Sim.TICKS_PER_SECOND
