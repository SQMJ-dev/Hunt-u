# AIDebugSystem.gd
# ─────────────────────────────────────────────────────────────────────────────
# Option A: Displays AI decision-making in real-time
# Option C: Tracks skill score progression for visualization
# ─────────────────────────────────────────────────────────────────────────────

class_name AIDebugSystem

var skill_history: Array = []  # [{"turn": 1, "skill": 0.30, "tier": 1}, ...]
var decision_history: Array = []  # Track last 5 decisions
var moves_json: Dictionary

func _init(moves_data: Dictionary):
	moves_json = moves_data

# ── OPTION A: Log current AI decision for live display ──────────────────────
func log_decision(turn: int, enemy_name: String, tier: int, selected_goal: String, 
				  action: String, world_state: Dictionary) -> String:
	# Store decision
	var decision = {
		"turn": turn,
		"enemy": enemy_name,
		"tier": tier,
		"goal": selected_goal,
		"action": action,
		"world": world_state
	}
	decision_history.append(decision)
	
	# Keep only last 5 decisions
	if decision_history.size() > 5:
		decision_history.pop_front()
	
	# Return formatted debug text
	return format_decision_display(decision, world_state)

# ── Format decision for on-screen display ──────────────────────────────────
func format_decision_display(decision: Dictionary, world: Dictionary) -> String:
	var text = ""
	text += "[color=#FFFF00]─── AI DECISION ───[/color]\n"
	text += "[color=#88CCFF]Enemy:[/color] " + decision["enemy"] + "\n"
	text += "[color=#88CCFF]Turn:[/color] " + str(decision["turn"]) + "  "
	text += "[color=#88CCFF]Tier:[/color] " + str(decision["tier"]) + "\n\n"
	
	text += "[color=#FFFF00]World State:[/color]\n"
	text += "  Self HP: " + "%.0f%%" % (world.get("self_hp_ratio", 0) * 100) + "\n"
	text += "  Critical Ally: " + ("YES" if world.get("critical_ally") else "NO") + "\n"
	text += "  Player Buffed: " + ("YES" if world.get("player_buffed") else "NO") + "\n\n"
	
	text += "[color=#00FF00]Selected Goal:[/color] " + decision["goal"] + "\n"
	text += "[color=#00FF00]Action Chosen:[/color] " + decision["action"] + "\n"
	
	return text

# ── OPTION C: Track skill score for visualization ────────────────────────────
func log_skill_update(turn: int, skill_score: float, tier: int):
	skill_history.append({
		"turn": turn,
		"skill": skill_score,
		"tier": tier
	})

# ── Export skill data for graphing ─────────────────────────────────────────
func export_skill_data_csv(filepath: String) -> bool:
	var csv = "Turn,Skill_Score,Tier\n"
	
	for entry in skill_history:
		csv += "%d,%.3f,%d\n" % [entry["turn"], entry["skill"], entry["tier"]]
	
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if file == null:
		print("ERROR: Could not save skill data to ", filepath)
		return false
	
	file.store_string(csv)
	print("Skill data exported to: ", filepath)
	return true

# ── Get data for reporting ──────────────────────────────────────────────────
func get_skill_history() -> Array:
	return skill_history

func get_decision_history() -> Array:
	return decision_history
