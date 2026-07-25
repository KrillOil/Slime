extends Node2D

var packet_snapshot: Array = []


func set_packet_snapshot(packets: Array) -> void:
	packet_snapshot = packets.duplicate(true)
	queue_redraw()


func _draw() -> void:
	for packet in packet_snapshot:
		var position := Vector2(packet.position_x_fp, packet.position_y_fp) / 256.0
		var radius := 2.0 + float(packet.volume_q) * 0.18
		draw_circle(position, radius, Color(0.35, 0.95, 0.45, 0.9))
