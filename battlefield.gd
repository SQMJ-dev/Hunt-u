# Battlefield.gd

# ─────────────────────────────────────────────────────────────────────────────
extends Node2D

# ── CONSTANTS ─────────────────────────────────────────────────────────────────

const MOVE_COLORS : Dictionary = {
	"fire":        "#FF6633",
	"electric":    "#FFD700",
	"water":       "#44AAFF",
	"wind":        "#88DD44",
	"slash":       "#DDDDDD",
	"blunt":       "#CC8844",
	"pierce":      "#AAAACC",
	"healing":     "#FF88BB",
	"buff":        "#FFCC44",
	"debuff":      "#CC44FF",
	"charge":      "#AADDFF",
	"guard":       "#8888FF",
	"hyper":       "#FF4488",
	"concentrate": "#AADDFF",
	"cleanse":     "#AAFFAA",
	"steal_buff":  "#FF88FF",
}

const AFFINITY_MODIFIERS : Dictionary = {
	"weak":    1.5,
	"neutral": 1.0,
	"resist":  0.5,
	"null":    0.0,
}

const AILMENT_MAP : Dictionary = {
	"fire":     "burn",
	"electric": "shock",
	"water":    "chill",
	"wind":     "dizzy",
	"blunt":    "stun",
}

const AILMENT_CHANCES : Dictionary = {
	"weak":    0.65,
	"neutral": 0.25,
	"resist":  0.0,
}

# Vertical offset so $char_hand floats above sprite origins.
# Increase the absolute value if the hand overlaps sprites.
const CHAR_HAND_OFFSET : Vector2 = Vector2(80, -90)

# ── VARIABLES ─────────────────────────────────────────────────────────────────

var allies_array  : Array = []
var enemies_array : Array = []

var chara_positions : Dictionary = {
	"ally0":  Vector2(608,202), "ally1":  Vector2(818,430), "ally2":  Vector2(584, 613),
	"enemy0": Vector2(1464, 167), "enemy1": Vector2(1246, 430), "enemy2": Vector2(1464, 613),
}

var battle_dialog_pos  : Vector2 = Vector2(696, 971)
var battle_dialog_size : Vector2 = Vector2(0.72, 1400)
var battle_label_pos   : Vector2 = Vector2(40, 875)
var battle_label_size  : Vector2 = Vector2(1300, 149)

var battle_state
enum STATES {
	CHOOSINGALLY,
	CHOOSINGMAINACTION,
	CHOOSINGATTACK,
	SELECTINGENEMYTARGET,
	SELECTINGALLYTARGET,
	FIGHTING,
}

var selected
var button_selected
var target_selected

var ally_index  : int = 0
var enemy_index : int = 0

var moves_json = load("res://moves.json").data

var vfx_scenes : Dictionary = {}

signal clicked

# ── ADAPTIVE / SKILL TRACKING ──────────────────────────────────────────────────

var player_profile : Dictionary = {
	"turns_played":          0,
	"heals_used":            0,
	"critical_not_healed":   0,
	"buffs_used":            0,
	"debuffs_used":          0,
	"weaknesses_hit":        0,
	"weaknesses_missed":     0,
}
var smoothed_skill        : float = 0.3
var heals_used_this_round : int   = 0
var ai_debug: AIDebugSystem
var use_adaptive_ai: bool = true  
# ── READY / INPUT ─────────────────────────────────────────────────────────────

func _ready():
	# Preload VFX scenes
	vfx_scenes["fire"]   = preload("res://effects/fire_vfx.tscn")
	vfx_scenes["slash"]  = preload("res://effects/slash_vfx.tscn")
	vfx_scenes["blunt"]  = preload("res://effects/slash_vfx.tscn")
	vfx_scenes["pierce"] = preload("res://effects/slash_vfx.tscn")
	vfx_scenes["electric"]   = preload("res://effects/lightning_vfx.tscn")
	vfx_scenes["wind"]   = preload("res://effects/wind_vfx.tscn")
	vfx_scenes["water"]   = preload("res://effects/ice_vfx.tscn")
	vfx_scenes["buff"]   = preload("res://effects/buff_vfx.tscn")
	vfx_scenes["charge"]   = preload("res://effects/buff_vfx.tscn")
	vfx_scenes["concentrate"]   = preload("res://effects/buff_vfx.tscn")
	# Build ally instances from GameData (set by CharacterSelect)
	var char_scene = preload("res://Character.tscn")
	for data in GameData.chosen_ally_data:
		var c : Node2D  = char_scene.instantiate()
		c.race_stats    = data["race_stats"]
		c.name          = data["char_name"]
		$allies.add_child(c)
		c.hide()
		allies_array.append(c)

	# Hide enemies until start_battle positions them
	for child in $enemies.get_children():
		child.hide()

	$char_hand.hide()
	$selection_hand.hide()
	use_adaptive_ai = GameData.use_adaptive_ai
	ai_debug = AIDebugSystem.new(moves_json)
	if use_adaptive_ai:
		$dialog/debugLabel.show()
	else:
		$dialog/debugLabel.hide()
	print("DEBUG INITIALIZED: ", ai_debug != null)
	print("AI MODE: ", "Adaptive" if use_adaptive_ai else "Scripted")
	start_battle()
	

func _input(event):
	match battle_state:
		STATES.CHOOSINGALLY:
			choosing_ally(event)
		STATES.CHOOSINGMAINACTION:
			choosing_main_action(event)
		STATES.CHOOSINGATTACK:
			select_attack(event)
		STATES.SELECTINGENEMYTARGET:
			selecting_target_enemy(event)
		STATES.SELECTINGALLYTARGET:
			selecting_target_ally(event)
		STATES.FIGHTING:
			if event.is_action_pressed("ui_accept"):
				clicked.emit()

# ── HELPERS ───────────────────────────────────────────────────────────────────

func color_move(move_name : String) -> String:
	var move_type = moves_json[move_name]["type"]
	var color     = MOVE_COLORS.get(move_type, "#FFFFFF")
	return "[color=" + color + "]" + move_name + "[/color]"

## Move $char_hand above a character or enemy sprite.
func move_char_hand_to(character : Node2D) -> void:
	$char_hand.position = character.position + CHAR_HAND_OFFSET
	$char_hand.show()

# ── BATTLE START ──────────────────────────────────────────────────────────────

func start_battle():
	$dialog/bottomBoxLabel.add_theme_font_size_override("normal_font_size", 30)
	$dialog/bottomBoxLabel.position = battle_label_pos
	$dialog/bottomBoxLabel.size     = battle_label_size

	# Colour-code HP bars
	for x in allies_array:
		x.get_node("ProgressBar").modulate = Color(0.2, 0.9, 0.3)   # green
	for x in $enemies.get_children():
		x.get_node("ProgressBar").modulate = Color(0.9, 0.2, 0.9)   # purple

	# Position and show allies
	for i in allies_array.size():
		var x = allies_array[i]
		x.position = chara_positions["ally" + str(i)]
		x.show()
		x.get_node("ProgressBar").show()
		x.get_node("ManaBar").show()
		x.get_node("ProgressBar/HP").show()
		x.get_node("ManaBar/MP").show()

	# Position and show enemies
	for child in $enemies.get_children():
		enemies_array.append(child)
		child.position = chara_positions["enemy" + str(enemies_array.find(child))]
		child.get_node("Sprite2D").flip_h = true
		child.get_node("ProgressBar").show()
		child.get_node("ManaBar").show()
		child.get_node("ProgressBar/HP").show()
		child.get_node("ManaBar/MP").show()
		child.show()

	ally_index = 0
	selected   = allies_array[ally_index]

	move_char_hand_to(selected)
	$selection_hand.hide()
	$dialog/bottomBoxLabel.text = selected.name + "'s turn! Press confirm to act."
	battle_state = STATES.CHOOSINGALLY

# ── BACK NAVIGATION ───────────────────────────────────────────────────────────

func back_to_choosingally():
	for child in $attackButtons.get_children():
		child.hide()
	$selection_hand.hide()
	move_char_hand_to(selected)
	_write_ally_hud_text(selected)
	battle_state = STATES.CHOOSINGALLY

func back_to_choosingattack():
	for pos in selected.moves_array.size():
		get_node("attackButtons/" + str(pos) + "Box").show()
		get_node("attackButtons/" + str(pos) + "Label").text = selected.moves_array[pos]
		get_node("attackButtons/" + str(pos) + "Label").show()
	var idx = selected.moves_array.find(button_selected)
	var box = get_node("attackButtons/" + str(idx) + "Box")
	$selection_hand.position = box.global_position + Vector2(-40, box.size.y / 2)
	$selection_hand.show()
	move_char_hand_to(selected)
	var m = moves_json[button_selected]
	$dialog/bottomBoxLabel.text  = m["description"] + "\nType: [color=" + MOVE_COLORS.get(m["type"], "#FFFFFF") + "]" + m["type"] + "[/color]"
	if m["is_physical"]:
		$dialog/bottomBoxLabel.text += "\nPower: " + str(m["power"]) + "  |  HP cost: " + str(m["hp_cost_percent"]) + "%"
	elif m["power"] > 0:
		$dialog/bottomBoxLabel.text += "\nPower: " + str(m["power"]) + "  |  MP cost: " + str(m["mp_cost"])
	elif m["healing_power"] > 0:
		$dialog/bottomBoxLabel.text += "\nHeal power: " + str(m["healing_power"]) + "  |  MP cost: " + str(m["mp_cost"])
	else:
		$dialog/bottomBoxLabel.text += "\nMP cost: " + str(m["mp_cost"])
	battle_state = STATES.CHOOSINGATTACK

# ── ALLY TURN ─────────────────────────────────────────────────────────────────

## Writes the standard "your turn" info for an ally into the bottom label.
func _write_ally_hud_text(ally):
	$dialog/bottomBoxLabel.text  = ally.name + "'s turn!\n"
	$dialog/bottomBoxLabel.text += "HP: " + str(ally.current_health) + "/" + str(ally.max_health)
	$dialog/bottomBoxLabel.text += "  MP: " + str(ally.current_mana)  + "/" + str(ally.max_mana) + "\n"
	$dialog/bottomBoxLabel.text += "STR " + str(int(ally.str_stat))
	$dialog/bottomBoxLabel.text += "  MAG " + str(int(ally.mag_stat))
	$dialog/bottomBoxLabel.text += "  END " + str(int(ally.end_stat))
	$dialog/bottomBoxLabel.text += "  SPD " + str(ally.base_spd)
	$dialog/bottomBoxLabel.text += "  LCK " + str(int(ally.lck_stat))
	if ally.ailment != "":
		$dialog/bottomBoxLabel.text += "\nAilment: " + ally.ailment

func choosing_ally(event):
	move_char_hand_to(selected)
	_write_ally_hud_text(selected)
	if event.is_action_pressed("ui_accept"):
		show_main_action_menu()

func show_main_action_menu():
	$mainActionButtons.show()
	button_selected = $mainActionButtons/AttackBox
	$selection_hand.position = button_selected.position + Vector2(-15, 0)
	$selection_hand.show()
	# char_hand stays on the acting character
	move_char_hand_to(selected)
	$dialog/bottomBoxLabel.text = "What will " + selected.name + " do?"
	battle_state = STATES.CHOOSINGMAINACTION

func choosing_main_action(event):
	if event.is_action_pressed("ui_cancel"):
		$mainActionButtons.hide()
		$selection_hand.hide()
		move_char_hand_to(selected)
		battle_state = STATES.CHOOSINGALLY
		return

	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up") or \
	   event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		if button_selected == $mainActionButtons/AttackBox:
			button_selected = $mainActionButtons/SkillsBox
		elif button_selected == $mainActionButtons/SkillsBox:
			button_selected = $mainActionButtons/GuardBox
		else:
			button_selected = $mainActionButtons/AttackBox
	$selection_hand.position = button_selected.position + Vector2(-15, 0)

	if event.is_action_pressed("ui_accept"):
		$mainActionButtons.hide()
		if button_selected == $mainActionButtons/AttackBox:
			button_selected  = "Strike"
			target_selected  = enemies_array[0]
			$selection_hand.hide()
			move_char_hand_to(target_selected)
			battle_state = STATES.SELECTINGENEMYTARGET
		elif button_selected == $mainActionButtons/SkillsBox:
			show_attacks()
		else:
			$selection_hand.hide()
			battle_state = STATES.FIGHTING
			execute_guard()

func execute_guard():
	selected.is_guarding = true
	var mp_bonus = int(selected.mag_stat * 0.9)
	selected.change_mana(-mp_bonus)
	$dialog/bottomBoxLabel.text = selected.name + " takes a defensive stance! +" + str(mp_bonus) + " MP recovered."
	await clicked
	advance_ally_turn()

func show_attacks():
	for pos in selected.moves_array.size():
		get_node("attackButtons/" + str(pos) + "Box").show()
		get_node("attackButtons/" + str(pos) + "Label").text = selected.moves_array[pos]
		get_node("attackButtons/" + str(pos) + "Label").show()
	button_selected = selected.moves_array[0]
	var idx = selected.moves_array.find(button_selected)
	# selection_hand → attack button;  char_hand → acting character
	var box = get_node("attackButtons/" + str(idx) + "Box")
	$selection_hand.position = box.global_position + Vector2(-40, box.size.y / 2)
	$selection_hand.show()
	move_char_hand_to(selected)
	battle_state = STATES.CHOOSINGATTACK

func select_attack(event):
	if event.is_action_pressed("ui_cancel"):
		back_to_choosingally()
		return

	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		if selected.moves_array.find(button_selected) == selected.moves_array.size() - 1:
			button_selected = selected.moves_array[0]
		else:
			button_selected = selected.moves_array[selected.moves_array.find(button_selected) + 1]
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		button_selected = selected.moves_array[selected.moves_array.find(button_selected) - 1]

	var idx = selected.moves_array.find(button_selected)
	var box = get_node("attackButtons/" + str(idx) + "Box")
	$selection_hand.position = box.global_position + Vector2(-40, box.size.y / 2)

	var m = moves_json[button_selected]
	$dialog/bottomBoxLabel.text  = m["description"] + "\nType: [color=" + MOVE_COLORS.get(m["type"], "#FFFFFF") + "]" + m["type"] + "[/color]"
	if m["is_physical"]:
		$dialog/bottomBoxLabel.text += "\nPower: " + str(m["power"]) + "  |  HP cost: " + str(m["hp_cost_percent"]) + "%"
	elif m["power"] > 0:
		$dialog/bottomBoxLabel.text += "\nPower: " + str(m["power"]) + "  |  MP cost: " + str(m["mp_cost"])
	elif m["healing_power"] > 0:
		$dialog/bottomBoxLabel.text += "\nHeal power: " + str(m["healing_power"]) + "  |  MP cost: " + str(m["mp_cost"])
	else:
		$dialog/bottomBoxLabel.text += "\nMP cost: " + str(m["mp_cost"])

	if event.is_action_pressed("ui_accept"):
		for child in $attackButtons.get_children():
			child.hide()
		$selection_hand.hide()
		checking_attack()

func checking_attack():
	var move = moves_json[button_selected]
	match move["targets"]:
		"all_enemies", "all_allies":
			battle_state = STATES.FIGHTING
			execute_ally_aoe(button_selected)
		"single_enemy":
			target_selected = enemies_array[0]
			move_char_hand_to(target_selected)
			battle_state = STATES.SELECTINGENEMYTARGET
		"single_ally":
			target_selected = selected
			move_char_hand_to(target_selected)
			battle_state = STATES.SELECTINGALLYTARGET
		"self":
			battle_state = STATES.FIGHTING
			execute_ally_single(button_selected, selected)
		_:
			battle_state = STATES.FIGHTING
			execute_ally_single(button_selected, selected)

func selecting_target_enemy(event):
	if event.is_action_pressed("ui_cancel"):
		if not selected.moves_array.has(button_selected):
			show_main_action_menu()
		else:
			back_to_choosingattack()
		return

	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		if enemies_array.find(target_selected) == enemies_array.size() - 1:
			target_selected = enemies_array[0]
		else:
			target_selected = enemies_array[enemies_array.find(target_selected) + 1]
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		target_selected = enemies_array[enemies_array.find(target_selected) - 1]

	move_char_hand_to(target_selected)
	$dialog/bottomBoxLabel.text = "Use " + color_move(button_selected) + " on " + target_selected.name + "?"
	var m = moves_json[button_selected]
	if m["type"] == "debuff":
		var current = target_selected.buff_stages.get(m["buff_stat"], 0)
		if current <= -2:
			$dialog/bottomBoxLabel.text += "\n[color=#FF4444]Already at minimum — won't have effect![/color]"

	if event.is_action_pressed("ui_accept"):
		var move = moves_json[button_selected]
		if move["type"] == "debuff":
			if target_selected.buff_stages.get(move["buff_stat"], 0) <= -2:
				$dialog/bottomBoxLabel.text = target_selected.name + "'s " + move["buff_stat"] + " can't go lower. Pick another target or press cancel."
				return
		battle_state = STATES.FIGHTING
		execute_ally_single(button_selected, target_selected)

func selecting_target_ally(event):
	if event.is_action_pressed("ui_cancel"):
		if not selected.moves_array.has(button_selected):
			show_main_action_menu()
		else:
			back_to_choosingattack()
		return

	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		if allies_array.find(target_selected) == allies_array.size() - 1:
			target_selected = allies_array[0]
		else:
			target_selected = allies_array[allies_array.find(target_selected) + 1]
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		target_selected = allies_array[allies_array.find(target_selected) - 1]

	move_char_hand_to(target_selected)
	$dialog/bottomBoxLabel.text = "Use " + color_move(button_selected) + " on " + target_selected.name + "?"
	var m = moves_json[button_selected]
	if m["type"] == "buff":
		var current = target_selected.buff_stages.get(m["buff_stat"], 0)
		if current >= 2:
			$dialog/bottomBoxLabel.text += "\n[color=#FF4444]Already at maximum — won't have effect![/color]"

	if event.is_action_pressed("ui_accept"):
		var move = moves_json[button_selected]
		if move["type"] == "buff":
			if target_selected.buff_stages.get(move["buff_stat"], 0) >= 2:
				$dialog/bottomBoxLabel.text = target_selected.name + "'s " + move["buff_stat"] + " can't go higher. Pick another target or press cancel."
				return
		battle_state = STATES.FIGHTING
		execute_ally_single(button_selected, target_selected)

# ── ALLY EXECUTION ─────────────────────────────────────────────────────────────

func execute_ally_single(move_name : String, target):
	$char_hand.hide()
	$selection_hand.hide()
	var success = await resolve_action(selected, move_name, target)
	if success:
		track_player_action(selected, move_name, target)
	advance_ally_turn()

func execute_ally_aoe(move_name : String):
	var move = moves_json[move_name]
	$char_hand.hide()
	$selection_hand.hide()
	if not can_use_move(selected, move_name):
		var resource = "HP" if move["is_physical"] else "MP"
		$dialog/bottomBoxLabel.text = selected.name + " doesn't have enough " + resource + "!"
		await clicked
		advance_ally_turn()
		return

	$dialog/bottomBoxLabel.text = selected.name + " used " + color_move(move_name) + "!"
	selected.play_attack_anim()   # ← attack bob animation
	await clicked
	await spend_move_cost(selected, move_name)

	var targets = enemies_array if move["targets"] == "all_enemies" else allies_array
	var hit_anyone = false
	for t in targets:
		if t.visible:
			hit_anyone = true
			await resolve_hit_on_target(selected, move_name, t)
	if not hit_anyone:
		$dialog/bottomBoxLabel.text = "No targets left to hit!"
		await clicked

	match move["type"]:
		"healing": player_profile["heals_used"] += 1; heals_used_this_round += 1
		"buff":    player_profile["buffs_used"]  += 1
		"debuff":  player_profile["debuffs_used"] += 1
	advance_ally_turn()

func advance_ally_turn():
	selected.regen_mana()
	if check_battle_over():
		return
	ally_index += 1
	await start_next_ally_turn()

func start_next_ally_turn():
	while ally_index < allies_array.size():
		var next = allies_array[ally_index]
		if not next.visible:
			ally_index += 1
			continue
		selected = next
		selected.is_guarding = false
		move_char_hand_to(selected)
		$selection_hand.hide()
		battle_state = STATES.FIGHTING
		var lost_turn = await process_ailment(selected)
		if check_battle_over():
			return
		if lost_turn:
			ally_index += 1
			continue
		$dialog/bottomBoxLabel.text = selected.name + "'s turn! Press confirm to act."
		battle_state = STATES.CHOOSINGALLY
		return

	enemy_index = 0
	$char_hand.hide()
	$selection_hand.hide()
	run_enemy_turn()

# ── ENEMY TURN ─────────────────────────────────────────────────────────────────

func run_enemy_turn():
	while enemy_index < enemies_array.size() and not enemies_array[enemy_index].visible:
		enemy_index += 1
	if enemy_index >= enemies_array.size():
		start_new_round()
		return

	var current_enemy = enemies_array[enemy_index]
	current_enemy.is_guarding = false
	move_char_hand_to(current_enemy)

	battle_state = STATES.FIGHTING
	var ailment_skip = await process_ailment(current_enemy)
	if check_battle_over():
		return
	if ailment_skip:
		current_enemy.regen_mana()
		if not check_battle_over():
			enemy_index += 1
			run_enemy_turn()
		return

	var chosen    = pick_enemy_action(current_enemy)
	var move_name = chosen[1]
	var move      = moves_json[move_name]

	if move["targets"] in ["all_enemies", "all_allies"]:
		if not can_use_move(current_enemy, move_name):
			$dialog/bottomBoxLabel.text = current_enemy.name + " can't afford " + color_move(move_name) + "!"
			await clicked
		else:
			$dialog/bottomBoxLabel.text = current_enemy.name + " used " + color_move(move_name) + "!"
			current_enemy.play_attack_anim()   # ← attack bob animation
			await clicked
			await spend_move_cost(current_enemy, move_name)
			var targets = allies_array if move["targets"] == "all_enemies" else enemies_array
			var hit_anyone = false
			for t in targets:
				if t.visible:
					hit_anyone = true
					await resolve_hit_on_target(current_enemy, move_name, t)
			if not hit_anyone:
				$dialog/bottomBoxLabel.text = "No targets left!"
				await clicked
	else:
		var target = chosen[2] if chosen.size() >= 3 else current_enemy
		if target.visible:
			await resolve_action(current_enemy, move_name, target)
		else:
			$dialog/bottomBoxLabel.text = target.name + " is already gone — " + current_enemy.name + "'s move is wasted!"
			await clicked

	current_enemy.regen_mana()
	if not check_battle_over():
		enemy_index += 1
		run_enemy_turn()

# ── utility AI ────────────────────────────────────────────────────────────────────

func player_has_active_buff() -> bool:
	for ally in allies_array:
		if not ally.visible: continue
		for stat in ally.buff_stages.values():
			if stat > 0: return true
	return false

func get_most_buffed_ally():
	var best       = null
	var best_total = 0
	for ally in allies_array:
		if not ally.visible: continue
		var total = 0
		for stat in ally.buff_stages.values():
			total += stat
		if total > best_total:
			best_total = total
			best       = ally
	return best

func get_world_state(chara) -> Dictionary:
	var critical_ally = null
	var low_hp_ally   = null
	for teammate in enemies_array:
		if not teammate.visible: continue
		if teammate.current_health < teammate.max_health * 0.25:
			critical_ally = teammate
		elif teammate.current_health < teammate.max_health * 0.5 and low_hp_ally == null:
			low_hp_ally = teammate

	var weakness_target = null
	var weakness_move   = ""
	for atk in chara.moves_array:
		if moves_json[atk]["power"] > 0 and can_use_move(chara, atk):
			for ally in allies_array:
				if ally.visible and ally.affinities.get(moves_json[atk]["type"], "neutral") == "weak":
					weakness_target = ally
					weakness_move   = atk
					break
		if weakness_target: break

	var chilled_ally = null
	for ally in allies_array:
		if ally.visible and ally.ailment == "chill":
			chilled_ally = ally
			break

	return {
		"self_hp_ratio":      float(chara.current_health) / max(chara.max_health, 1),
		"self_atk_stage":     chara.buff_stages["ATK"],
		"critical_ally":      critical_ally,
		"low_hp_ally":        low_hp_ally,
		"player_buffed":      player_has_active_buff(),
		"most_buffed_player": get_most_buffed_ally(),
		"all_players_alive":  allies_array.filter(func(a): return a.visible).size() >= 3,
		"weakness_target":    weakness_target,
		"weakness_move":      weakness_move,
		"chilled_ally":       chilled_ally,
	}

func get_active_goals(tier : int) -> Array:
	var all_goals = [
		["team_survive",     10, 1],
		["self_survive",      9, 1],
		["exploit_chill",     8, 3],
		["exploit_weakness",  7, 2],
		["counter_buff",      6, 2],
		["debuff_enemy",    5.5, 2],
		["aoe_pressure",      5, 2],
		["buff_self",         4, 3],
		["smart_damage",      2, 2],
		["basic_damage",      1, 1],
	]
	var active = []
	for goal in all_goals:
		if goal[2] <= tier:
			active.append({"id": goal[0], "priority": goal[1]})
	active.sort_custom(func(a, b): return a["priority"] > b["priority"])
	return active
# ── ADAPTIVE AI ──────────────────────────────────────
func utility_plan(chara) -> Array:
	print("utility_PLAN CALLED for: ", chara.name)
	var tier  = get_enemy_tier()
	var world = get_world_state(chara)
	var goals = get_active_goals(tier)
	
	for goal in goals:
		var action = find_action_for_goal(chara, goal["id"], world)
		if action.size() > 0:
			var debug_text = ai_debug.log_decision(
				player_profile["turns_played"],
				chara.name,
				tier,
				goal["id"],
				action[1],
				world
			)
			$dialog/debugLabel.text = debug_text
			
			ai_debug.log_skill_update(
				player_profile["turns_played"],
				smoothed_skill,
				tier
			)
			
			return action
	
	# Fallback action
	var fallback = fallback_action(chara)
	
	# NEW: Log fallback decision too
	var debug_text = ai_debug.log_decision(
		player_profile["turns_played"],
		chara.name,
		tier,
		"fallback",
		fallback[1],
		world
	)
	$dialog/debugLabel.text = debug_text
	
	ai_debug.log_skill_update(
		player_profile["turns_played"],
		smoothed_skill,
		tier
	)
	
	return fallback

# ── SCRIPTED AI (BASELINE FOR COMPARISON) ──────────────────────────────────────

func scripted_plan(chara) -> Array:
	print("SCRIPTED_PLAN CALLED for: ", chara.name)
	var m = moves_json
	
	# SCRIPTED RULE 1: If critical ally exists → heal them
	var critical_ally = null
	for teammate in enemies_array:
		if teammate.visible and teammate.current_health < teammate.max_health * 0.25:
			critical_ally = teammate
			break
	
	if critical_ally != null:
		for atk in chara.moves_array:
			if m[atk]["type"] == "healing" and can_use_move(chara, atk):
				if m[atk]["targets"] == "single_ally":
					return [chara, atk, critical_ally]
				elif m[atk]["targets"] == "all_allies":
					return [chara, atk]
	
	# SCRIPTED RULE 2: If self HP low → heal self
	var self_hp_ratio = float(chara.current_health) / max(chara.max_health, 1)
	if self_hp_ratio < 0.3:
		for atk in chara.moves_array:
			if m[atk]["type"] == "healing" and can_use_move(chara, atk):
				if m[atk]["targets"] == "single_ally":
					return [chara, atk, chara]
				elif m[atk]["targets"] == "all_allies":
					return [chara, atk]
	
	# SCRIPTED RULE 3: Always attack (no adaptive strategy)
	var damage_moves = []
	for atk in chara.moves_array:
		if m[atk]["power"] > 0 and can_use_move(chara, atk):
			damage_moves.append(atk)
	
	if damage_moves.size() > 0:
		var chosen = damage_moves[0]  # Always picks first available attack (predictable/scripted)
		var alive  = allies_array.filter(func(a): return a.visible)
		if alive.size() > 0:
			if m[chosen]["targets"] == "all_enemies":
				return [chara, chosen]
			return [chara, chosen, alive[0]]  # Always targets first alive ally
	
	return fallback_action(chara)
	
func find_action_for_goal(chara, goal_id : String, world : Dictionary) -> Array:
	var m = moves_json
	match goal_id:
		"team_survive":
			var target = world["critical_ally"]
			if target == null: return []
			if chara.heal_cooldown > 0: return []
			for atk in chara.moves_array:
				if m[atk]["type"] == "healing" and can_use_move(chara, atk):
					chara.heal_cooldown = 2
					if m[atk]["targets"] == "all_allies":    return [chara, atk]
					elif m[atk]["targets"] == "single_ally": return [chara, atk, target]
		"self_survive":
			if world["self_hp_ratio"] >= 0.30: return []
			if chara.heal_cooldown > 0: return []
			for atk in chara.moves_array:
				if m[atk]["type"] == "healing" and can_use_move(chara, atk):
					chara.heal_cooldown = 2
					if m[atk]["targets"] == "all_allies":    return [chara, atk]
					elif m[atk]["targets"] == "single_ally": return [chara, atk, chara]
		"exploit_chill":
			var target = world["chilled_ally"]
			if target == null: return []
			for atk in chara.moves_array:
				if m[atk]["is_physical"] and m[atk]["power"] > 0 and can_use_move(chara, atk):
					return [chara, atk, target]
		"exploit_weakness":
			var target = world["weakness_target"]
			var wm     = world["weakness_move"]
			if target == null or wm == "": return []
			if can_use_move(chara, wm):
				return [chara, wm, target]
		"counter_buff":
			if not world["player_buffed"]: return []
			var target = world["most_buffed_player"]
			if target == null: return []
			for atk in chara.moves_array:
				if m[atk]["type"] == "debuff" and can_use_move(chara, atk):
					return [chara, atk, target]
		"aoe_pressure":
			if not world["all_players_alive"]: return []
			for atk in chara.moves_array:
				if m[atk]["targets"] == "all_enemies" and can_use_move(chara, atk):
					if randf() >= 0.3:
						return [chara, atk]
		"buff_self":
			if world["self_atk_stage"] >= 1: return []
			if randf() > 0.6: return []
			for atk in chara.moves_array:
				if m[atk]["type"] == "buff" and m[atk]["buff_stat"] == "ATK" and can_use_move(chara, atk):
					return [chara, atk, chara]
		"smart_damage":
			for atk in chara.moves_array:
				if m[atk]["targets"] == "single_enemy" and m[atk]["power"] > 0 and can_use_move(chara, atk):
					for ally in allies_array:
						if not ally.visible: continue
						var affinity = ally.affinities.get(m[atk]["type"], "neutral")
						if affinity != "null" and affinity != "resist":
							return [chara, atk, ally]
		"basic_damage":
			var damage_moves = []
			for atk in chara.moves_array:
				if m[atk]["power"] > 0 and can_use_move(chara, atk):
					damage_moves.append(atk)
			if damage_moves.size() > 0:
				var chosen = damage_moves[randi() % damage_moves.size()]
				var alive  = allies_array.filter(func(a): return a.visible)
				if alive.size() > 0:
					if m[chosen]["targets"] == "all_enemies": return [chara, chosen]
					return [chara, chosen, alive[randi() % alive.size()]]
		"debuff_enemy":
			if not world["player_buffed"]: return []
			var target = world["most_buffed_player"]
			if target == null: return []
			for atk in chara.moves_array:
				if moves_json[atk]["type"] == "debuff" and can_use_move(chara, atk):
					return [chara, atk, target]
	return []

func pick_enemy_action(chara) -> Array:
	if use_adaptive_ai:
		return utility_plan(chara)
	else:
		return scripted_plan(chara)

func fallback_action(chara) -> Array:
	for atk in chara.moves_array:
		if can_use_move(chara, atk):
			if moves_json[atk]["targets"] in ["single_enemy", "all_enemies"]:
				for ally in allies_array:
					if ally.visible: return [chara, atk, ally]
			else:
				return [chara, atk, chara]
	return [chara, chara.moves_array[0], allies_array[0] if allies_array.size() > 0 else chara]

# ── ROUND RESET ───────────────────────────────────────────────────────────────

func start_new_round():
	for ally in allies_array:
		ally.tick_buffs()
		ally.refresh_buff_icons() 
	for enemy in enemies_array:
		enemy.tick_buffs()
		enemy.refresh_buff_icons()
	player_profile["turns_played"] += 1
	check_critical_not_healed()
	update_skill_score()
	ally_index = 0
	await start_next_ally_turn()

# ── WIN / LOSE ────────────────────────────────────────────────────────────────

func check_battle_over() -> bool:
	var to_free = []
	for character in allies_array + enemies_array:
		if not character.visible:
			to_free.append(character)
	for dead in to_free:
		if allies_array.has(dead):
			allies_array.erase(dead)
		elif enemies_array.has(dead):
			enemies_array.erase(dead)
		dead.queue_free()
	if allies_array.size() == 0 or enemies_array.size() == 0:
		$char_hand.hide()
		$selection_hand.hide()
		if allies_array.size() == 0:
			$dialog/bottomBoxLabel.text = "Oh no! You lose."
		else:
			$dialog/bottomBoxLabel.text = "Congratulations! You win!"
		end_battle()
		return true
	return false

func end_battle():
	ai_debug.export_skill_data_csv("user://ai_skill_data.csv")
	
	await clicked
	get_tree().reload_current_scene()

# ── RESOURCE MANAGEMENT ───────────────────────────────────────────────────────

func can_use_move(attacker, move_name : String) -> bool:
	var move = moves_json[move_name]
	if move["is_physical"]:
		var cost = int(attacker.max_health * move["hp_cost_percent"] / 100.0)
		return attacker.current_health > cost
	else:
		return attacker.current_mana >= move["mp_cost"]

func spend_move_cost(attacker, move_name : String):
	var move = moves_json[move_name]
	if move["is_physical"]:
		var cost = int(attacker.max_health * move["hp_cost_percent"] / 100.0)
		await attacker.change_health(cost, true)
	else:
		attacker.change_mana(move["mp_cost"])

# ── DODGE / CRIT ──────────────────────────────────────────────────────────────

func get_dodge_chance(attacker, target) -> float:
	var base     = 0.05
	var lck_diff = (target.lck_stat - attacker.lck_stat) * 0.005
	var agi_buff = target.buff_stages["AGI"] * 0.05
	return clamp(base + lck_diff + agi_buff, 0.0, 0.50)

func roll_dodge(attacker, target) -> bool:
	return randf() < get_dodge_chance(attacker, target)

func get_crit_chance(attacker, target) -> float:
	var base     = 0.05
	var lck_diff = (attacker.lck_stat - target.lck_stat) * 0.005
	return clamp(base + lck_diff, 0.01, 0.40)

func roll_crit(attacker, target) -> bool:
	return randf() < get_crit_chance(attacker, target)

# ── DAMAGE CALCULATION ────────────────────────────────────────────────────────

func calculate_damage(attacker, move_name : String, target, is_crit : bool) -> int:
	var move     = moves_json[move_name]
	var affinity = target.affinities.get(move["type"], "neutral")
	var type_mod = AFFINITY_MODIFIERS[affinity]
	var atk_stat = attacker.get_effective_stat("STR") if move["is_physical"] \
				   else attacker.get_effective_stat("MAG")
	var def_stat = target.get_effective_stat("DEF")
	var raw      = (atk_stat * move["power"]) / def_stat
	if attacker.is_charged:
		raw *= 1.5
		attacker.is_charged = false
	if attacker.is_hypered and move["is_physical"]:
		raw *= 2.5
		attacker.is_hypered = false
	if attacker.is_concentrated and not move["is_physical"]:
		raw *= 1.5
		attacker.is_concentrated = false
	if target.is_guarding:
		raw *= 0.5
	if move["is_physical"] and target.ailment == "chill":
		raw *= 1.30
	var crit_mod = 1.5 if is_crit else 1.0
	var variance = randf_range(0.9, 1.1)
	return max(1, int(raw * type_mod * crit_mod * variance))

# ── HIT STREAK / WEAKNESS SHIFT ───────────────────────────────────────────────

func update_hit_streak(target, element : String):
	for key in target.hit_streak.keys():
		if key != element:
			target.hit_streak[key] = 0
	target.hit_streak[element] = target.hit_streak.get(element, 0) + 1

func check_weakness_shift(target, element : String):
	if target.affinities.get(element, "neutral") != "weak":
		return
	if target.hit_streak.get(element, 0) >= get_weakness_shift_threshold():
		target.affinities[element] = "neutral"
		target.hit_streak[element] = 0
		$dialog/bottomBoxLabel.text += "\n" + target.name + " hardens against " + element + "!"

func get_weakness_shift_threshold() -> int:
	match get_enemy_tier():
		1: return 999
		2: return 3
		3: return 2
	return 999

# ── ADAPTIVE SYSTEM ───────────────────────────────────────────────────────────

func track_player_action(attacker, move_name : String, target):
	var move = moves_json[move_name]
	match move["type"]:
		"healing":
			player_profile["heals_used"] += 1
			heals_used_this_round += 1
		"buff":
			player_profile["buffs_used"] += 1
		"debuff":
			player_profile["debuffs_used"] += 1
		_:
			if move["power"] > 0 and target != null:
				var affinity = target.affinities.get(move["type"], "neutral")
				if affinity == "weak":
					player_profile["weaknesses_hit"] += 1
				elif could_hit_weakness(attacker):
					player_profile["weaknesses_missed"] += 1

func could_hit_weakness(attacker) -> bool:
	for atk in attacker.moves_array:
		var m = moves_json[atk]
		if m["power"] > 0:
			for enemy in enemies_array:
				if enemy.visible and enemy.affinities.get(m["type"], "neutral") == "weak":
					return true
	return false

func check_critical_not_healed():
	var had_critical = false
	for ally in allies_array:
		if ally.visible and ally.current_health < ally.max_health * 0.25:
			had_critical = true
			break
	if had_critical and heals_used_this_round == 0:
		player_profile["critical_not_healed"] += 1
	heals_used_this_round = 0

func calculate_skill_score() -> float:
	var turns      = max(player_profile["turns_played"], 1)
	var heal_score = 1.0 - clamp(float(player_profile["critical_not_healed"]) / turns, 0.0, 1.0)
	var buff_score = clamp(float(player_profile["buffs_used"] + player_profile["debuffs_used"]) / turns, 0.0, 1.0)
	var total_type = player_profile["weaknesses_hit"] + player_profile["weaknesses_missed"]
	var type_score = clamp(float(player_profile["weaknesses_hit"]) / max(total_type, 1), 0.0, 1.0)
	return (heal_score * 0.4) + (buff_score * 0.3) + (type_score * 0.3)

func update_skill_score():
	smoothed_skill = lerp(smoothed_skill, calculate_skill_score(), 0.15)

func get_enemy_tier() -> int:
	if smoothed_skill < 0.25: return 1
	if smoothed_skill < 0.55: return 2
	return 3

# ── AILMENTS ──────────────────────────────────────────────────────────────────

func try_apply_ailment(element : String, target, affinity : String):
	if not AILMENT_MAP.has(element): return
	if target.ailment != "":         return
	var chance = AILMENT_CHANCES.get(affinity, 0.0)
	if chance <= 0.0 or randf() > chance: return
	var new_ailment      = AILMENT_MAP[element]
	target.ailment       = new_ailment
	target.ailment_turns = 3 if new_ailment == "burn" else 1
	$dialog/bottomBoxLabel.text += "\n" + target.name + " is afflicted with " + new_ailment + "!"

func process_ailment(character) -> bool:
	if character.ailment == "":
		return false
	match character.ailment:
		"burn":
			var dmg = int(character.max_health * 0.08)
			await character.change_health(dmg)
			$dialog/bottomBoxLabel.text = character.name + " is burning and lost " + str(dmg) + " HP!"
			await clicked
			character.ailment_turns -= 1
			if character.ailment_turns <= 0:
				character.ailment = ""
				$dialog/bottomBoxLabel.text = character.name + " is no longer burning."
				await clicked
			if character.current_health <= 0:
				$dialog/bottomBoxLabel.text = character.name + " was defeated by burn damage!"
				character.get_node("AnimationPlayer").play("death")
				await character.get_node("AnimationPlayer").animation_finished
				character.hide()
				await clicked
			return false
		"shock", "stun":
			$dialog/bottomBoxLabel.text = character.name + " is " + character.ailment + "ed and can't act!"
			await clicked
			character.ailment       = ""
			character.ailment_turns = 0
			return true
	return false

# ── RESOLUTION ────────────────────────────────────────────────────────────────

func resolve_action(attacker, move_name : String, target) -> bool:
	var move = moves_json[move_name]
	if not can_use_move(attacker, move_name):
		var resource = "HP" if move["is_physical"] else "MP"
		$dialog/bottomBoxLabel.text = attacker.name + " doesn't have enough " + resource + " to use " + color_move(move_name) + "!"
		await clicked
		return false
	$dialog/bottomBoxLabel.text = attacker.name + " used " + color_move(move_name) + "!"
	attacker.play_attack_anim()   # ← bob animation; runs in parallel while player reads text
	await clicked
	await spend_move_cost(attacker, move_name)
	await resolve_hit_on_target(attacker, move_name, target)
	return true

func resolve_hit_on_target(attacker, move_name : String, target):
	var move = moves_json[move_name]

	if move["type"] == "buff" or move["type"] == "debuff":
		await resolve_buff(attacker, move_name, target)
		return
	if move["type"] == "healing":
		await resolve_heal(attacker, move_name, target)
		return
	if move["type"] == "charge":
		attacker.is_charged = true
		$dialog/bottomBoxLabel.text = attacker.name + " is focusing for the next attack!"
		await clicked
		return
	if move["type"] == "hyper":
		attacker.is_hypered = true
		$dialog/bottomBoxLabel.text = attacker.name + " enters a dangerous hyper state!"
		await clicked
		return
	if move["type"] == "concentrate":
		attacker.is_concentrated = true
		play_vfx("concentrate", attacker.position)
		$dialog/bottomBoxLabel.text = attacker.name + " concentrates magical energy!"
		await clicked
		return
	if move["type"] == "guard":
		attacker.is_guarding = true
		var mp_bonus = int(attacker.mag_stat * 0.9)
		attacker.change_mana(-mp_bonus)
		$dialog/bottomBoxLabel.text = attacker.name + " takes a defensive stance!"
		await clicked
		return
	if move["type"] == "cleanse":
		target.ailment       = ""
		target.ailment_turns = 0
		$dialog/bottomBoxLabel.text = target.name + "'s ailment was cured!"
		await clicked
		return
	if move["type"] == "steal_buff":
		var stat = move["buff_stat"]
		if target.buff_stages[stat] > 0:
			target.apply_buff(stat, -1)
			attacker.apply_buff(stat, 1)
			$dialog/bottomBoxLabel.text = attacker.name + " stole " + target.name + "'s " + stat + " boost!"
		else:
			$dialog/bottomBoxLabel.text = "Nothing to steal from " + target.name + "!"
		await clicked
		return

	# ── Dodge / dizzy miss ──
	if attacker.ailment == "dizzy" and randf() < 0.30:
		$dialog/bottomBoxLabel.text = attacker.name + " is dizzy and the attack missed!"
		await clicked
		return
	if roll_dodge(attacker, target):
		$dialog/bottomBoxLabel.text = target.name + " evaded the attack!"
		await clicked
		return

	var affinity = target.affinities.get(move["type"], "neutral")
	if affinity == "null":
		$dialog/bottomBoxLabel.text = color_move(move_name) + " has no effect on " + target.name + "!"
		await clicked
		return

	var is_crit = roll_crit(attacker, target)
	var damage  = calculate_damage(attacker, move_name, target, is_crit)

	$dialog/bottomBoxLabel.text = target.name + " took " + str(damage) + " damage."
	if is_crit:
		$dialog/bottomBoxLabel.text += "\nCritical hit!"
	match affinity:
		"weak":   $dialog/bottomBoxLabel.text += "\nIt's super effective!"
		"resist": $dialog/bottomBoxLabel.text += "\nIt's not very effective..."

	update_hit_streak(target, move["type"])
	play_vfx(move["type"], target.position)

	# ── FIX: change_health is now OUTSIDE the "weak" branch so ALL hits apply damage ──
	if affinity == "weak":
		screen_shake(8.0, 0.2)
		check_weakness_shift(target, move["type"])

	await target.change_health(damage)   # applies for weak, neutral, resist — all affinities

	if target.current_health > 0:
		try_apply_ailment(move["type"], target, affinity)

	await clicked
	if target.current_health <= 0:
		$dialog/bottomBoxLabel.text = target.name + " can't fight anymore!"
		target.get_node("AnimationPlayer").play("death")
		await target.get_node("AnimationPlayer").animation_finished
		target.hide()
		await clicked

func resolve_buff(_attacker, move_name : String, target) -> bool:
	var move    = moves_json[move_name]
	var stat    = move["buff_stat"]
	var stages  = move["buff_stages"]
	var changed = target.apply_buff(stat, stages)
	target.refresh_buff_icons()
	if move["type"] == "buff":
		play_vfx("buff", target.position)
	elif move["type"] == "debuff":
		play_vfx("debuff", target.position)
	if not changed:
		var limit = "maximum" if stages > 0 else "minimum"
		$dialog/bottomBoxLabel.text = target.name + "'s " + stat + " is already at its " + limit + "!"
	else:
		var direction = "rose" if stages > 0 else "fell"
		$dialog/bottomBoxLabel.text = target.name + "'s " + stat + " " + direction + "!"
	await clicked
	return changed

func resolve_heal(attacker, move_name : String, target) -> bool:
	if target.current_health >= target.max_health:
		$dialog/bottomBoxLabel.text = target.name + " is already at full health!"
		await clicked
		return false
	var move   = moves_json[move_name]
	var amount = int(attacker.mag_stat * move["healing_power"])
	amount = min(amount, target.max_health - target.current_health)
	await target.change_health(-amount)
	$dialog/bottomBoxLabel.text = target.name + " recovered " + str(amount) + " HP!"
	await clicked
	return true

# ── VFX ───────────────────────────────────────────────────────────────────────

func play_vfx(move_type : String, target_position : Vector2):
	if not vfx_scenes.has(move_type):
		return
	var vfx = vfx_scenes[move_type].instantiate()
	add_child(vfx)
	vfx.z_index = 2
	vfx.position = target_position
	await vfx.tree_exited

# ── SCREEN SHAKE ──────────────────────────────────────────────────────────────

func screen_shake(intensity : float = 6.0, duration : float = 0.25):
	var tween = get_tree().create_tween()
	var steps = 8
	for i in steps:
		var offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property($Camera2D, "offset", offset, duration / steps)
	tween.tween_property($Camera2D, "offset", Vector2.ZERO, 0.05)
	await tween.finished
