extends RefCounted

const MOUTH_OFFSET_X_FP := 0
const MOUTH_OFFSET_Y_FP := 3 * 256


static func derive(player_state: Dictionary) -> Vector2i:
	var facing := int(player_state.facing)
	return Vector2i(
		int(player_state.position_x_fp) + MOUTH_OFFSET_X_FP * facing,
		int(player_state.position_y_fp) + MOUTH_OFFSET_Y_FP
	)
