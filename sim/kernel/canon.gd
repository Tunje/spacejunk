class_name Canon
extends RefCounted
## The canonical save codec (contracts section 8). int is "123", String is "s:text", maps are
## objects whose pairs sort with integer keys first, and a float or object is a hard error.

const CONTROL_LIMIT := 32

## Why the last call failed, with the path to the bad value. Empty after a success.
static var error := ""


## Canonical text for a plain-data value, or "" with error set.
static func encode(value: Variant) -> String:
	error = ""
	var parts := PackedStringArray()
	_write(value, parts, "$")
	if error != "":
		return ""
	return "".join(parts)


## The value behind canonical text, or null with error set. Anything that does not re-encode to
## the same bytes is refused, so a loaded state always saves back identically.
static func decode(text: String) -> Variant:
	error = ""
	var parser := JSON.new()
	if parser.parse(text) != OK:
		_fail("not JSON: %s" % parser.get_error_message())
		return null
	var value: Variant = _read(parser.data)
	if error != "":
		return null
	if encode(value) != text:
		_fail("not canonical text")
		return null
	return value


static func _read(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_STRING:
			return _read_text(value)
		TYPE_ARRAY:
			var result: Array = []
			var values: Array = value
			for item: Variant in values:
				result.append(_read(item))
			return result
		TYPE_DICTIONARY:
			var result := {}
			var map: Dictionary = value
			for key: Variant in map:
				result[_read_text(key)] = _read(map[key])
			return result
	_fail("unexpected %s in save" % type_string(typeof(value)))
	return null


## An int's text survives to_int and back only if it is canonical and in range.
static func _read_text(text: String) -> Variant:
	if text.begins_with("s:"):
		return text.substr(2)
	var number := text.to_int()
	if str(number) != text:
		_fail("bad integer %s" % text)
	return number


static func _write(value: Variant, parts: PackedStringArray, path: String) -> void:
	match typeof(value):
		TYPE_BOOL:
			parts.append("true" if value else "false")
		TYPE_INT:
			parts.append(_int_text(value))
		TYPE_STRING:
			parts.append(_string_text(value))
		TYPE_ARRAY:
			_write_array(value, parts, path)
		TYPE_DICTIONARY:
			_write_map(value, parts, path)
		_:
			_fail("%s has unsupported type %s" % [path, type_string(typeof(value))])


static func _write_array(values: Array, parts: PackedStringArray, path: String) -> void:
	parts.append("[")
	for i in values.size():
		if i > 0:
			parts.append(",")
		_write(values[i], parts, "%s[%d]" % [path, i])
	parts.append("]")


static func _write_map(map: Dictionary, parts: PackedStringArray, path: String) -> void:
	var int_keys: Array[int] = []
	var string_keys: Array[String] = []
	for key: Variant in map:
		match typeof(key):
			TYPE_INT:
				int_keys.append(key)
			TYPE_STRING:
				string_keys.append(key)
			_:
				_fail("%s has a key of unsupported type %s" % [path, type_string(typeof(key))])
				return
	int_keys.sort()
	string_keys.sort()
	parts.append("{")
	var first := true
	for key in int_keys:
		if not first:
			parts.append(",")
		first = false
		parts.append(_int_text(key))
		parts.append(":")
		_write(map[key], parts, "%s.%d" % [path, key])
	for key in string_keys:
		if not first:
			parts.append(",")
		first = false
		parts.append(_string_text(key))
		parts.append(":")
		_write(map[key], parts, "%s.%s" % [path, key])
	parts.append("}")


static func _int_text(value: int) -> String:
	return "\"%d\"" % value


static func _string_text(text: String) -> String:
	var escaped := text.replace("\\", "\\\\").replace("\"", "\\\"")
	for i in escaped.length():
		if escaped.unicode_at(i) < CONTROL_LIMIT:
			escaped = _escape_controls(escaped)
			break
	return "\"s:%s\"" % escaped


static func _escape_controls(text: String) -> String:
	var parts := PackedStringArray()
	for i in text.length():
		var code := text.unicode_at(i)
		parts.append("\\u%04x" % code if code < CONTROL_LIMIT else text[i])
	return "".join(parts)


static func _fail(message: String) -> void:
	if error == "":
		error = message
