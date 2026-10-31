class_name SimRng
extends RefCounted
## Named random streams over the state's `rng` map. A stream's start depends only on the seed
## and its name, so an extra draw or a new stream in one system never shifts another.

const FNV_OFFSET := -3750763034362895579
const FNV_PRIME := 1099511628211
const MAX_BOUND := 2147483647

var _streams: Dictionary
var _seed: int
var _generator := RandomNumberGenerator.new()


func _init(streams: Dictionary, seed_value: int) -> void:
	_streams = streams
	_seed = seed_value


## A uniform integer from 0 to 2^32 - 1.
func next_u32(stream: String) -> int:
	_load_stream(stream)
	var value := _generator.randi()
	_streams[stream] = _generator.state
	return value


## A uniform integer from 0 to bound - 1.
func below(stream: String, bound: int) -> int:
	assert(bound >= 1 and bound <= MAX_BOUND, "bound out of range")
	_load_stream(stream)
	var value := _generator.randi_range(0, bound - 1)
	_streams[stream] = _generator.state
	return value


func _load_stream(stream: String) -> void:
	if _streams.has(stream):
		_generator.state = _streams[stream]
	else:
		_generator.seed = _seed ^ _name_hash(stream)


static func _name_hash(stream: String) -> int:
	var result := FNV_OFFSET
	for byte in stream.to_utf8_buffer():
		result = (result ^ byte) * FNV_PRIME
	return result
