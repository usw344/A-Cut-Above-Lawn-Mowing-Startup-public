extends Control


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

signal new_game
signal load_game
signal options

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func handle_new_game_button_clicked():
	emit_signal("new_game","New Game")

func handle_load_game_button_clicked():
	emit_signal("load_game","Load Game")

func handle_option_button_clicked():
	emit_signal("options","Options")
