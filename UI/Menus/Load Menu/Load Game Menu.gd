extends Control

var dir = Directory.new()
signal load_game(file_to_load)

func _ready():
	dir.change_dir("res://Saves/")
	
	add_items_to_option_button(get_current_directories())

"""
	Return all directories (minus a few) from the saves folder
"""
func get_current_directories():
	var list_of_directories =[]
	dir.list_dir_begin(true,true)
	
	##loop though all the save files
	var current_get_next_str = " "
	while current_get_next_str != "":
		##get next file/dir 
		current_get_next_str = dir.get_next()
		
		##do not add any files
		if(dir.dir_exists(current_get_next_str)):
			list_of_directories.append(current_get_next_str)
	
	##pop at back to remove empty string
	list_of_directories.pop_back()
	
#	print(list_of_directories)
	return list_of_directories

"""
	Add items to the options button
"""
func add_items_to_option_button(list_of_strings):
	$"Saved game options".add_item("Select a saved game",0)
	for i in range(0,list_of_strings.size()):
		$"Saved game options".add_item(list_of_strings[i],i+1)

"""
	Function to load the game
"""
func load_game():
	var menu = $"Saved game options" 
	
	##get game diffuculty
	var item_index = menu.get_item_index(menu.get_selected_id())
	var file_to_load = menu.get_item_text(item_index)

	if file_to_load == "Select a saved game":
		print("no file selected or something")
		return
	##emit signal
	emit_signal("load_game",file_to_load)
	
func get_buttons():
	return {"Main_Menu":$Main_Menu}
