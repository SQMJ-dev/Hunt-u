extends AnimatedSprite2D

func _ready():
	play("buff")                               # start the animation
	animation_finished.connect(queue_free)     # delete self when done
