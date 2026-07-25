extends SceneTree

const Schema := preload("res://better_spewing/contracts/canonical_state_schema.gd")
const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")


func _init() -> void:
	var result := Serializer.serialize_state_checked(Schema.default_state())
	if not result.ok:
		print("P1A_ZERO_FIXTURE result=FAIL error=%s" % result.error)
		quit(1)
		return
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(result.bytes)
	var hash: String = context.finish().hex_encode()
	print("P1A_ZERO_FIXTURE result=PASS bytes=%d sha256=%s" % [result.bytes.size(), hash])
	print("P1A_SCHEMA_FIXTURE sha256=%s fields=%d" % [Schema.descriptor_hash(), Schema.FIELD_ORDER.size()])
	print("P1A_TUNING_FIXTURE bytes=%d sha256=%s" % [Tuning.canonical_bytes().size(), Tuning.canonical_hash()])
	quit(0)
