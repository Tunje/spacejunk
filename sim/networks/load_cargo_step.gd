class_name LoadCargoStep
extends TransferStep
## The `load_cargo` order. Loading never blocks: it ends when nothing more can move.


func type() -> String:
	return "load_cargo"


func partner_field() -> String:
	return "from"


func op_type() -> String:
	return OP_LOADING
