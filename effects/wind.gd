extends AnimatedSprite2D

func _ready():
	play("wind")                               # start the animation
	animation_finished.connect(queue_free)     # delete self when done
