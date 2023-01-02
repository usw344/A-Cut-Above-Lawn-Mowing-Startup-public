extends Control

var dir = Directory.new()

func _ready():
	dir.change_dir("res://Saves/")
	
	add_items_to_option_button(get_current_directories())

func get_current_directories():
	var list_of_directories =[]
	dir.list_dir_begin(true,true)
	
	##loop though all the save files
	var current_get_next_str = " "
	while current_get_next_str != "":
		current_get_next_str = dir.get_next()
		list_of_directories.append(current_get_next_str)
	##pop at back to remove empty string
	list_of_directories.pop_back()
	
#	print(list_of_directories)
	return list_of_directories

func add_items_to_option_button(list_of_strings):
	$"Saved game options".add_item("Select a saved game",0)
	for i in range(0,list_of_strings.size()):
		$"Saved game options".add_item(list_of_strings[i],i+1)
	
