extends Node2D

# ── VARIABLES ──────────────────────────────────────────────────────────────────

var non_selected_characters : Array
var allies_array : Array
var enemies_array : Array
var selection_dialog_pos  : Vector2
var selection_dialog_size : Vector2
var battle_dialog_pos     : Vector2
var battle_dialog_size    : Vector2
var battle_label_pos      : Vector2
var battle_label_size     : Vector2
var chara_positions : Dictionary = {
	"ally0": Vector2(510, 657), "ally1": Vector2(950, 657), "ally2": Vector2(1340, 657),
	"enemy0": Vector2(570, 223), "enemy1": Vector2(1000, 223), "enemy2": Vector2(1400, 223)
}

var battle_state
enum STATES {PREBATTLE, CONFIRMSELECTION, CHOOSINGALLY, CHOOSINGATTACK, CHOOSINGMAINACTION, SELECTINGENEMYTARGET, SELECTINGALLYTARGET, FIGHTING}

var selected
var button_selected
var target_selected

var moves_json = load("res://moves.json").data

var ally_index  : int = 0
var enemy_index : int = 0

var player_profile : Dictionary = {
	"turns_played": 0,
	"heals_used": 0,
	"critical_not_healed": 0,
	"buffs_used": 0,
	"debuffs_used": 0,
	"weaknesses_hit": 0,
	"weaknesses_missed": 0,
}
var smoothed_skill        : float = 0.3
var heals_used_this_round : int   = 0

var vfx_scenes : Dictionary = {}
signal clicked

const PREVIEW_POSITION = Vector2(962, 514)

# ── CONSTANTS ──────────────────────────────────────────────────────────────────

const MOVE_COLORS : Dictionary = {
	"fire":     "#FF6633",
	"electric": "#FFD700",
	"water":    "#44AAFF",
	"wind":     "#88DD44",
	"slash":    "#DDDDDD",
	"blunt":    "#CC8844",
	"pierce":   "#AAAACC",
	"healing":  "#FF88BB",
	"buff":     "#FFCC44",
	"debuff":   "#CC44FF",
	"charge": "#AADDFF",
	"guard":       "#8888FF",
	"hyper":       "#FF4488",
	"concentrate": "#AADDFF",
	"cleanse":     "#AAFFAA",
	"steal_buff":  "#FF88FF",
}

func color_move(move_name : String) -> String:
	var move_type = moves_json[move_name]["type"]
	var color     = MOVE_COLORS.get(move_type, "#FFFFFF")
	return "[color=" + color + "]" + move_name + "[/color]"

const AFFINITY_MODIFIERS : Dictionary = {
	"weak": 1.5, "neutral": 1.0, "resist": 0.5, "null": 0.0
}

const AILMENT_MAP : Dictionary = {
	"fire":     "burn",
	"electric": "shock",
	"water":    "chill",
	"wind":     "dizzy",
	"blunt":    "stun"
}

const AILMENT_CHANCES : Dictionary = {
	"weak":    0.65,
	"neutral": 0.25,
	"resist":  0.0
}

# ── READY / INPUT ──────────────────────────────────────────────────────────────

func _ready():
	vfx_scenes["fire"]     = preload("res://effects/fire_vfx.tscn")
	selection_dialog_pos  = $dialog/bottomBox.position
	selection_dialog_size = $dialog/bottomBox.scale
	battle_dialog_pos     = Vector2(696, 971)
	battle_dialog_size    = Vector2(0.72, 1400)
	battle_label_pos      = Vector2(40, 875)
	battle_label_size     = Vector2(1300, 149)
	battle_state = STATES.PREBATTLE
	for child in $characters.get_children():
		non_selected_characters.append(child)
		child.hide()
	for child in $enemies.get_children():
		child.hide()
	selected = non_selected_characters[0]
	selected.position = PREVIEW_POSITION
	selected.show()
	$selection_hand.hide()
	$dialog/topBox.show()
	$dialog/topBoxLabel.show()
	update_character_preview()

func play_vfx(move_type : String, target_position : Vector2):
	if not vfx_scenes.has(move_type):
		return
	var vfx = vfx_scenes[move_type].instantiate()
	add_child(vfx)
	vfx.position = target_position
	await vfx.tree_exited 

func _input(event):
	match battle_state:
		STATES.PREBATTLE:
			selecting_allies(event)
		STATES.CONFIRMSELECTION:
			confirm_selected(event)
		STATES.CHOOSINGALLY:
			choosing_ally(event)
		STATES.CHOOSINGATTACK:
			select_attack(event)
		STATES.CHOOSINGMAINACTION:   # ADD
			choosing_main_action(event)
		STATES.SELECTINGENEMYTARGET:
			selecting_target_enemy(event)
		STATES.SELECTINGALLYTARGET:
			selecting_target_ally(event)
		STATES.FIGHTING:
			if event.is_action_pressed("ui_accept"):
				clicked.emit()

# ── BACK NAVIGATION ────────────────────────────────────────────────────────────

func back_to_choosingally():
	for child in $attackButtons.get_children():
		child.hide()
	$selection_hand.position     = selected.position
	$dialog/bottomBoxLabel.text  = selected.name + "'s turn!\n"
	$dialog/bottomBoxLabel.text += "HP: " + str(selected.current_health) + "/" + str(selected.max_health)
	$dialog/bottomBoxLabel.text += "  MP: " + str(selected.current_mana) + "/" + str(selected.max_mana) + "\n"
	$dialog/bottomBoxLabel.text += "STR " + str(int(selected.str_stat))
	$dialog/bottomBoxLabel.text += "  MAG " + str(int(selected.mag_stat))
	$dialog/bottomBoxLabel.text += "  END " + str(int(selected.end_stat))
	$dialog/bottomBoxLabel.text += "  SPD " + str(selected.base_spd)
	$dialog/bottomBoxLabel.text += "  LCK " + str(int(selected.lck_stat))
	if selected.ailment != "":
		$dialog/bottomBoxLabel.text += "\nAilment: " + selected.ailment
	battle_state = STATES.CHOOSINGALLY

func back_to_choosingattack():
	for pos in selected.moves_array.size():
		get_node("attackButtons/" + str(pos) + "Box").show()
		get_node("attackButtons/" + str(pos) + "Label").text = selected.moves_array[pos]
		get_node("attackButtons/" + str(pos) + "Label").show()
	var idx = selected.moves_array.find(button_selected)
	$selection_hand.position = get_node("attackButtons/" + str(idx) + "Box").position + Vector2(-65, 0)
	var m = moves_json[button_selected]
	$dialog/bottomBoxLabel.text = m["description"] + "\nType: [color=" + MOVE_COLORS.get(m["type"], "#FFFFFF") + "]" + m["type"] + "[/color]"
	if m["is_physical"]:
		$dialog/bottomBoxLabel.text += "\nPower: " + str(m["power"]) + "  |  HP cost: " + str(m["hp_cost_percent"]) + "%"
	elif m["power"] > 0:
		$dialog/bottomBoxLabel.text += "\nPower: " + str(m["power"]) + "  |  MP cost: " + str(m["mp_cost"])
	elif m["healing_power"] > 0:
		$dialog/bottomBoxLabel.text += "\nHeal power: " + str(m["healing_power"]) + "  |  MP cost: " + str(m["mp_cost"])
	else:
		$dialog/bottomBoxLabel.text += "\nMP cost: " + str(m["mp_cost"])
	battle_state = STATES.CHOOSINGATTACK

# ── PREBATTLE ──────────────────────────────────────────────────────────────────

func selecting_allies(event):
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		selected.hide()
		if non_selected_characters.find(selected) == non_selected_characters.size() - 1:
			selected = non_selected_characters[0]
		else:
			selected = non_selected_characters[non_selected_characters.find(selected) + 1]
		selected.position = PREVIEW_POSITION
		selected.show()
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		selected.hide()
		selected = non_selected_characters[non_selected_characters.find(selected) - 1]
		selected.position = PREVIEW_POSITION
		selected.show()
	update_character_preview()
	if event.is_action_pressed("ui_accept"):
		prepare_confirm_selection()

func update_character_preview():
	$dialog/topBoxLabel.text  = "[ " + selected.name + " ]\n"
	$dialog/topBoxLabel.text += "HP: " + str(selected.max_health)
	$dialog/topBoxLabel.text += "  MP: " + str(selected.max_mana) + "\n"
	$dialog/topBoxLabel.text += "STR " + str(int(selected.str_stat))
	$dialog/topBoxLabel.text += "  MAG " + str(int(selected.mag_stat))
	$dialog/topBoxLabel.text += "  END " + str(int(selected.end_stat))
	$dialog/topBoxLabel.text += "  SPD " + str(selected.base_spd)
	$dialog/topBoxLabel.text += "  LCK " + str(int(selected.lck_stat)) + "\n"
	var weaknesses = []
	var nulls_list = []
	for element in selected.affinities.keys():
		if selected.affinities[element] == "weak":
			weaknesses.append(element)
		elif selected.affinities[element] == "null":
			nulls_list.append(element)
	if weaknesses.size() > 0:
		$dialog/topBoxLabel.text += "Weak: " + ", ".join(weaknesses)
	if nulls_list.size() > 0:
		$dialog/topBoxLabel.text += "  Null: " + ", ".join(nulls_list)
	$dialog/bottomBoxLabel.text = selected.race_stats.description + "\n\nMoves:\n"
	for move_name in selected.race_stats.moveset:
		var m = moves_json[move_name]
		$dialog/bottomBoxLabel.text += color_move(move_name) + "  [color=" + MOVE_COLORS.get(m["type"], "#FFFFFF") + "]" + m["type"] + "[/color]"
		if m["power"] > 0:
			$dialog/bottomBoxLabel.text += "  Pwr: " + str(m["power"])
		if m["healing_power"] > 0:
			$dialog/bottomBoxLabel.text += "  Heal: " + str(m["healing_power"])
		if m["is_physical"]:
			$dialog/bottomBoxLabel.text += "  Cost: " + str(m["hp_cost_percent"]) + "% HP"
		elif m["mp_cost"] > 0:
			$dialog/bottomBoxLabel.text += "  Cost: " + str(m["mp_cost"]) + " MP"
		$dialog/bottomBoxLabel.text += "\n\n"

func prepare_confirm_selection():
	$confirmButtons.show()
	$dialog/topBox.hide()
	$dialog/topBoxLabel.hide()
	button_selected = $confirmButtons/YesBox
	$dialog/bottomBoxLabel.text = "Add " + selected.name + " to your party?\n(" + str(allies_array.size()) + "/3 chosen)"
	$selection_hand.show()
	$selection_hand.position = button_selected.position + Vector2(-15, 0)
	battle_state = STATES.CONFIRMSELECTION

func confirm_selected(event):
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down") or \
	   event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		if button_selected == $confirmButtons/YesBox:
			button_selected = $confirmButtons/NoBox
		else:
			button_selected = $confirmButtons/YesBox
	$selection_hand.position = button_selected.position + Vector2(-15, 0)
	if event.is_action_pressed("ui_accept"):
		$confirmButtons.hide()
		$selection_hand.hide()
		if button_selected == $confirmButtons/NoBox:
			$dialog/topBox.show()
			$dialog/topBoxLabel.show()
			selected.position = PREVIEW_POSITION
			selected.show()
			update_character_preview()
			battle_state = STATES.PREBATTLE
		else:
			allies_array.append(selected)
			non_selected_characters.erase(selected)
			selected.hide()
			if allies_array.size() == 3:
				start_battle()
			else:
				selected = non_selected_characters[0]
				selected.position = PREVIEW_POSITION
				selected.show()
				$dialog/topBox.show()
				$dialog/topBoxLabel.show()
				update_character_preview()
				battle_state = STATES.PREBATTLE

func show_main_action_menu():
	$mainActionButtons.show()
	button_selected = $mainActionButtons/AttackBox
	$selection_hand.position = button_selected.position + Vector2(-15, 0)
	$dialog/bottomBoxLabel.text = "What will " + selected.name + " do?"
	battle_state = STATES.CHOOSINGMAINACTION
	
func choosing_main_action(event):
	if event.is_action_pressed("ui_cancel"):
		$mainActionButtons.hide()
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
			# Basic free Strike — go straight to enemy targeting
			button_selected = "Strike"
			target_selected = enemies_array[0]
			battle_state = STATES.SELECTINGENEMYTARGET
		elif button_selected == $mainActionButtons/SkillsBox:
			show_attacks()  # existing function, shows moves_array
		else:
			# Guard
			battle_state = STATES.FIGHTING
			execute_guard()
			
func execute_guard():
	selected.is_guarding = true
	var mp_bonus = int(selected.mag_stat * 0.9)
	selected.change_mana(-mp_bonus)
	$dialog/bottomBoxLabel.text = selected.name + " takes a defensive stance! +" + str(mp_bonus) + " MP recovered."
	await clicked
	advance_ally_turn()
	
func update_hud():
	if not $BattleHUD:
		return
	for i in allies_array.size():
		var ally = allies_array[i]
		var prefix = "Ally" + str(i)
		$BattleHUD.get_node(prefix + "Portrait").texture = ally.race_stats.sprite
		$BattleHUD.get_node(prefix + "NameLabel").text        = ally.name
		var hp_bar = $BattleHUD.get_node(prefix + "HP")
		hp_bar.max_value = ally.max_health
		hp_bar.value     = ally.current_health
		var mp_bar = $BattleHUD.get_node(prefix + "MP")
		mp_bar.max_value = ally.max_mana
		mp_bar.value     = ally.current_mana
		# Ailment + buffs
		var status = ""
		if ally.ailment != "":
			status += "[color=#FF8844]" + ally.ailment + "[/color]  "
		for stat in ally.buff_stages.keys():
			if ally.buff_stages[stat] > 0:
				status += "[color=#44FF44]↑" + stat + "[/color](" + str(ally.buff_turns[stat]) + ") "
			elif ally.buff_stages[stat] < 0:
				status += "[color=#FF4444]↓" + stat + "[/color](" + str(ally.buff_turns[stat]) + ") "
		$BattleHUD.get_node(prefix + "Status").text = status
# ── BATTLE START ───────────────────────────────────────────────────────────────

func start_battle():
	$dialog/bottomBoxLabel.add_theme_font_size_override("normal_font_size", 30)
	$dialog/bottomBox.position      = battle_dialog_pos
	$dialog/bottomBox.scale         = battle_dialog_size
	$dialog/bottomBoxLabel.position = battle_label_pos
	$dialog/bottomBoxLabel.size     = battle_label_size
	
	for x in allies_array:
		x.position = chara_positions["ally" + str(allies_array.find(x))]
		x.show()
		x.get_node("ProgressBar").show()
		x.get_node("ManaBar").show()
	for x in non_selected_characters:
		x.hide()
	for x in $enemies.get_children():
		enemies_array.append(x)
		x.position = chara_positions["enemy" + str(enemies_array.find(x))]
		x.get_node("Sprite2D").flip_h = true
		x.get_node("ProgressBar").show()
		x.get_node("ManaBar").show()
		x.show()
	$dialog/topBox.hide()
	$dialog/topBoxLabel.hide()
	ally_index = 0
	selected   = allies_array[ally_index]
	$selection_hand.position = selected.position
	$selection_hand.show()
	$dialog/bottomBoxLabel.text = selected.name + "'s turn! Press confirm to act."
	battle_state = STATES.CHOOSINGALLY
	#update_hud()

# ── ALLY TURN ──────────────────────────────────────────────────────────────────

func choosing_ally(event):
	$selection_hand.position     = selected.position
	$dialog/bottomBoxLabel.text  = selected.name + "'s turn!\n"
	$dialog/bottomBoxLabel.text += "HP: " + str(selected.current_health) + "/" + str(selected.max_health)
	$dialog/bottomBoxLabel.text += "  MP: " + str(selected.current_mana) + "/" + str(selected.max_mana) + "\n"
	$dialog/bottomBoxLabel.text += "STR " + str(int(selected.str_stat))
	$dialog/bottomBoxLabel.text += "  MAG " + str(int(selected.mag_stat))
	$dialog/bottomBoxLabel.text += "  END " + str(int(selected.end_stat))
	$dialog/bottomBoxLabel.text += "  SPD " + str(selected.base_spd)
	$dialog/bottomBoxLabel.text += "  LCK " + str(int(selected.lck_stat))
	if selected.ailment != "":
		$dialog/bottomBoxLabel.text += "\nAilment: " + selected.ailment
	if event.is_action_pressed("ui_accept"):
		show_main_action_menu()

func show_attacks():
	for pos in selected.moves_array.size():
		get_node("attackButtons/" + str(pos) + "Box").show()
		get_node("attackButtons/" + str(pos) + "Label").text = selected.moves_array[pos]
		get_node("attackButtons/" + str(pos) + "Label").show()
	button_selected = selected.moves_array[selected.moves_array.size() - 1]
	battle_state = STATES.CHOOSINGATTACK

func select_attack(event):
	if event.is_action_pressed("ui_cancel"):
		back_to_choosingally()
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		if selected.moves_array.find(button_selected) == selected.moves_array.size() - 1:
			button_selected = selected.moves_array[0]
		else:
			button_selected = selected.moves_array[selected.moves_array.find(button_selected) + 1]
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		button_selected = selected.moves_array[selected.moves_array.find(button_selected) - 1]
	$selection_hand.position = get_node("attackButtons/" + str(selected.moves_array.find(button_selected)) + "Box").position + Vector2(-65, 0)
	var m = moves_json[button_selected]
	$dialog/bottomBoxLabel.text = m["description"] + "\nType: [color=" + MOVE_COLORS.get(m["type"], "#FFFFFF") + "]" + m["type"] + "[/color]"
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
		checking_attack()

func checking_attack():
	var move = moves_json[button_selected]
	match move["targets"]:
		"all_enemies", "all_allies":
			battle_state = STATES.FIGHTING
			execute_ally_aoe(button_selected)
		"single_enemy":
			target_selected = enemies_array[0]
			battle_state = STATES.SELECTINGENEMYTARGET
		"single_ally":
			target_selected = selected
			battle_state = STATES.SELECTINGALLYTARGET
		"self":                                    # ADD THIS CASE
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
	$selection_hand.position = target_selected.position
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
				$dialog/bottomBoxLabel.text = target_selected.name + "'s " + move["buff_stat"] + " can't go lower. Pick another target or go back."
				return  # block the action, player picks again or presses cancel
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
	$selection_hand.position = target_selected.position
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
				$dialog/bottomBoxLabel.text = target_selected.name + "'s " + move["buff_stat"] + " can't go higher. Pick another target or go back."
				return
		battle_state = STATES.FIGHTING
		execute_ally_single(button_selected, target_selected)

# ── ALLY EXECUTION ─────────────────────────────────────────────────────────────

func execute_ally_single(move_name : String, target):
	var success = await resolve_action(selected, move_name, target)
	if success:
		track_player_action(selected, move_name, target)
	advance_ally_turn()

func execute_ally_aoe(move_name : String):
	var move = moves_json[move_name]
	if not can_use_move(selected, move_name):
		var resource = "HP" if move["is_physical"] else "MP"
		$dialog/bottomBoxLabel.text = selected.name + " doesn't have enough " + resource + "!"
		await clicked
		advance_ally_turn()
		return
	$dialog/bottomBoxLabel.text = selected.name + " used " + color_move(move_name) + "!"
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
		"healing":
			player_profile["heals_used"] += 1
			heals_used_this_round += 1
		"buff":
			player_profile["buffs_used"] += 1
		"debuff":
			player_profile["debuffs_used"] += 1
	advance_ally_turn()

func advance_ally_turn():
	selected.regen_mana()
	if check_battle_over():
		return
	ally_index += 1
	await start_next_ally_turn()
	#update_hud()

func start_next_ally_turn():
	while ally_index < allies_array.size():
		var next = allies_array[ally_index]
		if not next.visible:
			ally_index += 1
			continue
		if next.is_downed:
			next.is_downed = false
			battle_state = STATES.FIGHTING
			$dialog/bottomBoxLabel.text = next.name + " is knocked down and loses their turn!"
			$selection_hand.position = next.position
			$selection_hand.show()
			await clicked
			ally_index += 1
			continue
		selected = next
		selected.is_guarding = false
		$selection_hand.position = selected.position
		$selection_hand.show()
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
	if current_enemy.is_downed:
		current_enemy.is_downed = false
		$dialog/bottomBoxLabel.text = current_enemy.name + " is knocked down and loses their turn!"
		await clicked
		current_enemy.regen_mana()
		if not check_battle_over():
			enemy_index += 1
			run_enemy_turn()
		return
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
	

# ── GOAP AI ────────────────────────────────────────────────────────────────────
# Architecture: FSM controls battle flow. GOAP drives enemy decisions.
# Adaptive tier system controls which goals are active each battle phase.
#
# GOAP loop per enemy turn:
#   1. Evaluate world state  — facts about the current situation
#   2. Get active goals      — filtered by current skill tier
#   3. Plan                  — iterate goals by priority, find first achievable action
#   4. Execute               — return chosen action to run_enemy_turn

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

# Step 1 — World state: a snapshot of facts the planner reasons about
func get_world_state(chara) -> Dictionary:
	var critical_ally = null
	var low_hp_ally   = null
	for teammate in enemies_array:
		if not teammate.visible: continue
		if teammate.current_health < teammate.max_health * 0.25:
			critical_ally = teammate
		elif teammate.current_health < teammate.max_health * 0.5 and low_hp_ally == null:
			low_hp_ally = teammate

	# Find best weakness target and the move to exploit it
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

	# Find a chilled ally — vulnerability for physical moves
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

# Step 2 — Goals: what the enemy is trying to achieve
# Format: [goal_id, priority, min_tier_required]
# Tier gates which goals are available — beginner enemies only survive and spam,
# experienced enemies unlock tactical and exploitative goals
func get_active_goals(tier : int) -> Array:
	var all_goals = [
		["team_survive",     10, 1],
		["self_survive",     9,  1],
		["exploit_chill",    8,  3],
		["exploit_weakness", 7,  2],
		["counter_buff",     6,  2],
		["aoe_pressure",     5,  2],
		["buff_self",        4,  3],
		["smart_damage",     2,  2],
		["basic_damage",     1,  1],
	]
	var active = []
	for goal in all_goals:
		if goal[2] <= tier:
			active.append({"id": goal[0], "priority": goal[1]})
	active.sort_custom(func(a, b): return a["priority"] > b["priority"])
	return active

# Step 3 — Planner: iterates goals by priority, returns the first achievable action
# This is the GOAP planning loop — goal-directed, not rule-scripted
func goap_plan(chara) -> Array:
	var tier  = get_enemy_tier()
	var world = get_world_state(chara)
	var goals = get_active_goals(tier)
	for goal in goals:
		var action = find_action_for_goal(chara, goal["id"], world)
		if action.size() > 0:
			return action
	return fallback_action(chara)

# Step 4 — Action finder: given a goal, finds the action that achieves it
# Checks preconditions before returning. Returns empty array if goal is not achievable.
# This is the backward-chaining step of GOAP — reasoning from goal to action
func find_action_for_goal(chara, goal_id : String, world : Dictionary) -> Array:
	var m = moves_json

	match goal_id:

		"team_survive":
			var target = world["critical_ally"]
			if target == null: return []
			if chara.heal_cooldown > 0: return []  # on cooldown
			for atk in chara.moves_array:
				if m[atk]["type"] == "healing" and can_use_move(chara, atk):
					chara.heal_cooldown = 2  # can't heal again for 2 rounds
					if m[atk]["targets"] == "all_allies":    return [chara, atk]
					elif m[atk]["targets"] == "single_ally": return [chara, atk, target]

		"self_survive":
			if world["self_hp_ratio"] >= 0.30: return []  # was 0.50 — much more conservative
			if chara.heal_cooldown > 0: return []
			for atk in chara.moves_array:
				if m[atk]["type"] == "healing" and can_use_move(chara, atk):
					chara.heal_cooldown = 2
					if m[atk]["targets"] == "all_allies":    return [chara, atk]
					elif m[atk]["targets"] == "single_ally": return [chara, atk, chara]

		"exploit_chill":
			# Precondition: a player ally has chill (takes 30% more physical damage)
			var target = world["chilled_ally"]
			if target == null: return []
			for atk in chara.moves_array:
				if m[atk]["is_physical"] and m[atk]["power"] > 0 and can_use_move(chara, atk):
					return [chara, atk, target]

		"exploit_weakness":
			# Precondition: a type weakness has been identified and the move is affordable
			var target = world["weakness_target"]
			var move   = world["weakness_move"]
			if target == null or move == "": return []
			if can_use_move(chara, move):
				return [chara, move, target]

		"counter_buff":
			# Precondition: a player ally has an active buff stage
			if not world["player_buffed"]: return []
			var target = world["most_buffed_player"]
			if target == null: return []
			for atk in chara.moves_array:
				if m[atk]["type"] == "debuff" and can_use_move(chara, atk):
					return [chara, atk, target]

		"aoe_pressure":
			# Precondition: all 3 player allies are still alive (AOE is most efficient)
			if not world["all_players_alive"]: return []
			for atk in chara.moves_array:
				if m[atk]["targets"] == "all_enemies" and can_use_move(chara, atk):
					if randf() >= 0.3:
						return [chara, atk]

		"buff_self":
			# Precondition: self ATK not yet buffed, random gate prevents always buffing
			if world["self_atk_stage"] >= 1: return []
			if randf() > 0.6: return []
			for atk in chara.moves_array:
				if m[atk]["type"] == "buff" and m[atk]["buff_stat"] == "ATK" and can_use_move(chara, atk):
					return [chara, atk, chara]

		"smart_damage":
			# No strict precondition — avoids resisted and null affinities
			for atk in chara.moves_array:
				if m[atk]["targets"] == "single_enemy" and m[atk]["power"] > 0 and can_use_move(chara, atk):
					for ally in allies_array:
						if not ally.visible: continue
						var affinity = ally.affinities.get(m[atk]["type"], "neutral")
						if affinity != "null" and affinity != "resist":
							return [chara, atk, ally]

		"basic_damage":
			# No preconditions — random move, random target, no type awareness
			# Tier 1 damage goal and final fallback before hard fallback
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

	return []

# Entry point called by run_enemy_turn — delegates entirely to the GOAP planner
func pick_enemy_action(chara) -> Array:
	return goap_plan(chara)

# Hard fallback: if ALL goals fail (no MP, no valid targets), use first usable move
func fallback_action(chara) -> Array:
	for atk in chara.moves_array:
		if can_use_move(chara, atk):
			if moves_json[atk]["targets"] in ["single_enemy", "all_enemies"]:
				for ally in allies_array:
					if ally.visible: return [chara, atk, ally]
			else:
				return [chara, atk, chara]
	return [chara, chara.moves_array[0], allies_array[0] if allies_array.size() > 0 else chara]

# ── ROUND RESET ────────────────────────────────────────────────────────────────

func start_new_round():
	for ally in allies_array:
		ally.tick_buffs()
	for enemy in enemies_array:
		enemy.tick_buffs()
	for enemy in enemies_array:
		enemy.is_downed = false
	player_profile["turns_played"] += 1
	check_critical_not_healed()
	update_skill_score()
	ally_index = 0
	await start_next_ally_turn()

# ── WIN / LOSE ─────────────────────────────────────────────────────────────────

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
		if allies_array.size() == 0:
			$dialog/bottomBoxLabel.text = "Oh no! You lose."
		else:
			$dialog/bottomBoxLabel.text = "Congratulations! You win!"
		end_battle()
		return true
	return false

func end_battle():
	await clicked
	get_tree().reload_current_scene()

# ── RESOURCE MANAGEMENT ────────────────────────────────────────────────────────

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

# ── DODGE / CRIT ───────────────────────────────────────────────────────────────

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

# ── DAMAGE CALCULATION ─────────────────────────────────────────────────────────

func calculate_damage(attacker, move_name : String, target, is_crit : bool) -> int:
	var move     = moves_json[move_name]
	var affinity = target.affinities.get(move["type"], "neutral")
	var type_mod = AFFINITY_MODIFIERS[affinity]
	var atk_stat = attacker.get_effective_stat("STR") if move["is_physical"] \
				   else attacker.get_effective_stat("MAG")
	var def_stat = target.get_effective_stat("DEF")
	var raw      = (atk_stat * move["power"]) / def_stat
	if attacker.is_charged:
		raw  *= 1.5
		attacker.is_charged = false  # consumed on use
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
	

# ── HIT STREAK / WEAKNESS SHIFT ────────────────────────────────────────────────

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

# ── ADAPTIVE SYSTEM ────────────────────────────────────────────────────────────

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

# ── AILMENTS ───────────────────────────────────────────────────────────────────

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

# ── RESOLUTION ─────────────────────────────────────────────────────────────────

func resolve_action(attacker, move_name : String, target) -> bool:
	var move = moves_json[move_name]
	if not can_use_move(attacker, move_name):
		var resource = "HP" if move["is_physical"] else "MP"
		$dialog/bottomBoxLabel.text = attacker.name + " doesn't have enough " + resource + " to use " + color_move(move_name) + "!"
		await clicked
		return false
	$dialog/bottomBoxLabel.text = attacker.name + " used " + color_move(move_name) + "!"
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
		$dialog/bottomBoxLabel.text = attacker.name + " concentrates magical energy!"
		await clicked
		return
	if move["type"] == "guard":
		attacker.is_guarding = true
		var mp_bonus = int(attacker.mag_stat * 0.9)  # triple regen
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
	if not move["is_physical"]:
		play_vfx(move["type"], target.position) #change later
		if affinity == "weak":
			screen_shake(8.0, 0.2)
			check_weakness_shift(target, move["type"])
			await target.change_health(damage)
			if target.current_health > 0:
				target.is_downed = true
				$dialog/bottomBoxLabel.text += "\n" + target.name + " is knocked down!"
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

func screen_shake(intensity : float = 6.0, duration : float = 0.25):
	var tween = get_tree().create_tween()
	var steps = 8
	for i in steps:
		var offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property($Camera2D, "offset", offset, duration / steps)
	tween.tween_property($Camera2D, "offset", Vector2.ZERO, 0.05)
	await tween.finished
