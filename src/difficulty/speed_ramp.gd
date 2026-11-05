class_name SpeedRamp
extends RefCounted
## The run's speed curve as a pure function of elapsed time (no nodes, no clock), so it can be
## tested deterministically. Implements story-006 (design/game-brief.md, MVP feature 6).
##
## Linear ramp: speed = start + rate * elapsed, never above the cap. It never decreases.


## Scroll speed in px/s after `elapsed` seconds of running.
## start: speed at time 0; rate: px/s gained per second (a negative rate counts as 0, so the
## speed never falls); cap: highest speed allowed. A cap below the start speed leaves the speed
## at the start value.
static func speed_at(elapsed: float, start: float, rate: float, cap: float) -> float:
	return minf(start + maxf(rate, 0.0) * maxf(elapsed, 0.0), maxf(cap, start))
