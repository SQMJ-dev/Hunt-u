# CharacterSelect.gd
# ─────────────────────────────────────────────────────────────────────────────
# Attach to the root Node2D of CharacterSelect.tscn
#
# Required scene nodes:
#   $characters          — Node2D containing all character instances
#   $dialog/topBox       — Panel/Sprite for top dialog
#   $dialog/topBoxLabel  — RichTextLabel for top dialog
#   $dialog/bottomBox    — Panel/Sprite for bottom dialog
#   $dialog/bottomBoxLabel — RichTextLabel (bbcode_enabled = true) for bottom dialog
#   $confirmButtons      — Node holding YesBox and NoBox
#   $confirmButtons/YesBox
#   $confirmButtons/NoBox
#   $selection_hand      — The cursor/arrow scene
# ─────────────────────────────────────────────────────────────────────────────
extends Node2D

# ── CONSTANTS ─────────────────────────────────────────────────────────────────

const PREVIEW_POSITION : Vector2 = Vector2(1030, 514)

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

# ── VARIABLES ─────────────────────────────────────────────────────────────────

var non_selected_characters : Array = []
var allies_array             : Array = []

var battle_state
enum STATES { PREBATTLE, CONFIRMSELECTION }

var selected
var button_selected

var moves_json = load("res://moves.json").data

# ── READY / INPUT ─────────────────────────────────────────────────────────────

func _ready():
	battle_state = STATES.PREBATTLE

	for child in $characters.get_children():
		non_selected_characters.append(child)
		

	selected          = non_selected_characters[0]
	selected.position = PREVIEW_POSITION
	selected.show()

	$selection_hand.hide()
	$dialog/topBox.show()
	$dialog/topBoxLabel.show()
	update_character_preview()

func _input(event):
	match battle_state:
		STATES.PREBATTLE:
			selecting_allies(event)
		STATES.CONFIRMSELECTION:
			confirm_selected(event)

# ── HELPERS ───────────────────────────────────────────────────────────────────

func color_move(move_name : String) -> String:
	var move_type = moves_json[move_name]["type"]
	var color     = MOVE_COLORS.get(move_type, "#FFFFFF")
	return "[color=" + color + "]" + move_name + "[/color]"

# ── PRE-BATTLE CHARACTER BROWSING ─────────────────────────────────────────────

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
	# ── Top box: stats and affinities ──
	$dialog/topBoxLabel.text  = "[ " + selected.name + " ]\n"
	$dialog/topBoxLabel.text += "HP: " + str(selected.max_health)
	$dialog/topBoxLabel.text += "  MP: " + str(selected.max_mana) + "\n"
	$dialog/topBoxLabel.text += "STR " + str(int(selected.str_stat))
	$dialog/topBoxLabel.text += "  MAG " + str(int(selected.mag_stat))
	$dialog/topBoxLabel.text += "  END " + str(int(selected.end_stat))
	$dialog/topBoxLabel.text += "  SPD " + str(selected.base_spd)
	$dialog/topBoxLabel.text += "  LCK " + str(int(selected.lck_stat)) + "\n"

	var weaknesses : Array = []
	var nulls_list : Array = []
	for element in selected.affinities.keys():
		if selected.affinities[element] == "weak":
			weaknesses.append(element)
		elif selected.affinities[element] == "null":
			nulls_list.append(element)
	if weaknesses.size() > 0:
		$dialog/topBoxLabel.text += "Weak: " + ", ".join(weaknesses)
	if nulls_list.size() > 0:
		$dialog/topBoxLabel.text += "  Null: " + ", ".join(nulls_list)

	# ── Bottom box: description and moveset ──
	$dialog/bottomBoxLabel.text = selected.race_stats.description + "\n\nMoves:\n"
	for move_name in selected.race_stats.moveset:
		var m = moves_json[move_name]
		$dialog/bottomBoxLabel.text += color_move(move_name)
		$dialog/bottomBoxLabel.text += "  [color=" + MOVE_COLORS.get(m["type"], "#FFFFFF") + "]" + m["type"] + "[/color]"
		if m["power"] > 0:
			$dialog/bottomBoxLabel.text += "  Pwr: " + str(m["power"])
		if m["healing_power"] > 0:
			$dialog/bottomBoxLabel.text += "  Heal: " + str(m["healing_power"])
		if m["is_physical"]:
			$dialog/bottomBoxLabel.text += "  Cost: " + str(m["hp_cost_percent"]) + "% HP"
		elif m["mp_cost"] > 0:
			$dialog/bottomBoxLabel.text += "  Cost: " + str(m["mp_cost"]) + " MP"
		$dialog/bottomBoxLabel.text += "\n\n"

# ── CONFIRM SELECTION ─────────────────────────────────────────────────────────

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
	   event.is_action_pressed("ui_left")  or event.is_action_pressed("ui_up"):
		if button_selected == $confirmButtons/YesBox:
			button_selected = $confirmButtons/NoBox
		else:
			button_selected = $confirmButtons/YesBox
	$selection_hand.position = button_selected.position + Vector2(-15, 0)

	if event.is_action_pressed("ui_accept"):
		$confirmButtons.hide()
		$selection_hand.hide()

		if button_selected == $confirmButtons/NoBox:
			# Player said No — go back to browsing
			$dialog/topBox.show()
			$dialog/topBoxLabel.show()
			selected.position = PREVIEW_POSITION
			selected.show()
			update_character_preview()
			battle_state = STATES.PREBATTLE
		else:
			# Player said Yes
			allies_array.append(selected)
			non_selected_characters.erase(selected)
			selected.hide()

			if allies_array.size() == 3:
				_launch_battle()
			else:
				selected          = non_selected_characters[0]
				selected.position = PREVIEW_POSITION
				selected.show()
				$dialog/topBox.show()
				$dialog/topBoxLabel.show()
				update_character_preview()
				battle_state = STATES.PREBATTLE

# ── SCENE TRANSITION ─────────────────────────────────────────────────────────

func _launch_battle():
	# Pack chosen party into the GameData autoload, then switch to Battlefield
	GameData.chosen_ally_data.clear()
	for ally in allies_array:
		GameData.chosen_ally_data.append({
			"race_stats": ally.race_stats,
			"char_name":  ally.name
		})
	get_tree().change_scene_to_file("res://Battlefield.tscn")
