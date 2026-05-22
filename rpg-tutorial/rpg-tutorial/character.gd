extends Node2D
@export var race_stats : CharacterStats

var str_stat : float
var mag_stat : float
var end_stat : float
var lck_stat : float
var base_spd : int
var speed    : int

var max_health    : int
var current_health : int
var max_mana      : int
var current_mana  : int
var heal_cooldown : int = 0  # rounds remaining before can heal again
var buff_stages : Dictionary = {"ATK": 0, "DEF": 0, "AGI": 0}
var buff_turns : Dictionary = {"ATK": 0, "DEF": 0, "AGI": 0}
var affinities  : Dictionary = {}
var hit_streak  : Dictionary = {}  # tracks consecutive hits per element
var ailment       : String = ""  # "burn" "shock" "chill" "dizzy" "stun" or ""
var ailment_turns : int    = 0

var is_downed : bool = false  # NEW: skips turn when true
var is_charged : bool = false
var is_guarding    : bool = false
var is_hypered     : bool = false   # from Hyper
var is_concentrated: bool = false   # from Concentrate

var level      : int = 10
var moves_array : Array

func _ready():
	assign_stats()

func assign_stats():
	$Sprite2D.texture = race_stats.sprite
	str_stat = race_stats.STR * 0.1 * level
	mag_stat = race_stats.MAG * 0.1 * level
	end_stat = race_stats.END * 0.1 * level
	lck_stat = race_stats.LCK * 0.1 * level
	base_spd = int(race_stats.SPD * 0.1 * level)
	speed    = base_spd

	max_health     = int(end_stat * 30)
	current_health = max_health
	max_mana       = int(mag_stat * 7)
	current_mana   = max_mana

	affinities = {
		"slash":    race_stats.aff_slash,
		"blunt":    race_stats.aff_blunt,
		"pierce":   race_stats.aff_pierce,
		"fire":     race_stats.aff_fire,
		"water":    race_stats.aff_water,
		"wind":     race_stats.aff_wind,
		"electric": race_stats.aff_electric,
	}

	# Initialise hit streak counter for every element
	for element in affinities.keys():
		hit_streak[element] = 0

	moves_array = race_stats.moveset.duplicate()

	$ProgressBar.max_value = max_health
	$ProgressBar.value     = current_health
	$ManaBar.max_value = max_mana      # ADD
	$ManaBar.value     = current_mana  # ADD

func get_effective_stat(stat_name : String) -> float:
	match stat_name:
		"STR": return str_stat * (1.0 + buff_stages["ATK"] * 0.25)
		"MAG": return mag_stat * (1.0 + buff_stages["ATK"] * 0.25)
		"DEF": return end_stat * (1.0 + buff_stages["DEF"] * 0.25)
		"AGI": return speed    * (1.0 + buff_stages["AGI"] * 0.25)
	return 0.0

func apply_buff(buff_stat : String, stages : int) -> bool:
	var before = buff_stages[buff_stat]
	buff_stages[buff_stat] = clamp(buff_stages[buff_stat] + stages, -2, 2)
	if buff_stages[buff_stat] != before:
		buff_turns[buff_stat] = 3  # always refresh to 3 rounds on change
		return true
	return false

func tick_buffs():
	for stat in buff_stages.keys():
		if buff_stages[stat] != 0:
			buff_turns[stat] -= 1
			if buff_turns[stat] <= 0:
				buff_stages[stat] = 0
				buff_turns[stat]  = 0
	if heal_cooldown > 0:
		heal_cooldown -= 1

func reset_buffs():
	buff_stages = {"ATK": 0, "DEF": 0, "AGI": 0}

# CHANGED: added silent parameter so HP cost of physical moves
# doesn't play the hurt animation on the attacker
func change_health(change : int, silent : bool = false):
	current_health -= change
	current_health  = clamp(current_health, 0, max_health)
	if not silent:
		if change > 0:
			$AnimationPlayer.play("hurt")
		elif change < 0:
			$AnimationPlayer.play("recover")
	var tween = get_tree().create_tween()
	tween.tween_property($ProgressBar, "value", current_health, 0.5)
	await tween.finished

func change_mana(change : int):
	current_mana -= change
	current_mana  = clamp(current_mana, 0, max_mana)
	var tween = get_tree().create_tween()
	tween.tween_property($ManaBar, "value", current_mana, 0.3)

func regen_mana():
	var regen = int(mag_stat * 0.3)
	change_mana(-regen)  # negative = restore
