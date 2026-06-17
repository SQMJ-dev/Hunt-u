extends Resource
class_name CharacterStats

@export var sprite : Texture2D
@export_multiline var description : String = ""

# Base stats — scaled by level in the character script.
# At level 10 these values become the actual in-battle numbers.
@export_group("Stats")
@export var STR : int = 10   # physical attack power
@export var MAG : int = 10   # magic attack power
@export var END : int = 10   # defence + determines max HP
@export var SPD : int = 10   # turn order
@export var LCK : int = 10   # crit and dodge rate

# Per-element affinities. Each slot shows a dropdown in the inspector.
@export_group("Affinities")
@export_enum("weak", "neutral", "resist", "null") var aff_slash    : String = "neutral"
@export_enum("weak", "neutral", "resist", "null") var aff_blunt    : String = "neutral"
@export_enum("weak", "neutral", "resist", "null") var aff_pierce   : String = "neutral"
@export_enum("weak", "neutral", "resist", "null") var aff_fire     : String = "neutral"
@export_enum("weak", "neutral", "resist", "null") var aff_water    : String = "neutral"
@export_enum("weak", "neutral", "resist", "null") var aff_wind     : String = "neutral"
@export_enum("weak", "neutral", "resist", "null") var aff_electric : String = "neutral"

# Full move pool — 3 are picked randomly at battle start.
# Keep at least 4 moves here so there is some variety each fight.
@export_group("Moves")
@export var moveset : Array[String] = []
