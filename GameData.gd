# GameData.gd
# ─────────────────────────────────────────────────────────────────────────────
# Autoload singleton — register this in Project → Project Settings → Autoload
# as "GameData" so both scenes can access it via GameData.chosen_ally_data
# ─────────────────────────────────────────────────────────────────────────────
extends Node

# Each entry is a Dictionary: { "race_stats": <CharacterStats>, "char_name": String }
var chosen_ally_data : Array = []
