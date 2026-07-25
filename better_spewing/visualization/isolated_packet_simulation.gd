extends Node2D


func _ready() -> void:
	# Renderer-only smoke data. It is never supplied to authoritative simulation
	# or canonical hashing and exists solely to make the isolated scene visible.
	$PacketVisualizer.set_packet_snapshot([
		{"position_x_fp": 120 * 256, "position_y_fp": 180 * 256, "volume_q": 7},
		{"position_x_fp": 190 * 256, "position_y_fp": 220 * 256, "volume_q": 12},
		{"position_x_fp": 270 * 256, "position_y_fp": 260 * 256, "volume_q": 16},
	])
