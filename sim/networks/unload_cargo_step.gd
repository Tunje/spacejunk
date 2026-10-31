class_name UnloadCargoStep
extends TransferStep
## The `unload_cargo` order. It blocks with `cargo_full` if the destination has no room.


func type() -> String:
	return "unload_cargo"


func partner_field() -> String:
	return "to"


func op_type() -> String:
	return OP_UNLOADING
