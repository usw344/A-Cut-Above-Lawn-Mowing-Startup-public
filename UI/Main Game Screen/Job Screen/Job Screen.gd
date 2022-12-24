extends Control


var label_scene = preload("res://UI/Main Game Screen/Job Screen/Job Label/Job Label.tscn")
onready var container = $VBoxContainer

func _ready():
	self.add_child(label_scene.instance())
