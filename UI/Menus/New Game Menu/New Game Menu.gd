extends Control

var game_difficulty_list = [
	"Normal game difficulty",
	"Hard game difficulty",
	"Challange difficulty"]

var file = File.new()
var save_location_of_game = "res://saves/"

signal new_game(game_num,game_diff)

func _ready():
	$"Game difficulty menu".add_item("Select item",0)
	setup()


func setup():
	for i in range(0,game_difficulty_list.size()):
		$"Game difficulty menu".add_item(game_difficulty_list[i],i)

func start_game():
	var menu = $"Game difficulty menu" 
	
	##get game diffuculty
	var item_index = menu.get_item_index(menu.get_selected_id())
	var game_dif = menu.get_item_text(item_index)
	
	var game_number = $"Game number input".text
	
	var store_data = {
		"game number":game_number,
		"game_difficulty":game_dif
	}
	
	##check if a game number was entered 
	if game_number == "Enter game number here":
		print("in new game menu code no game number was enterted")
	
	##save data
	#update save location
	save_location_of_game += game_number
	save_location_of_game +="/"
	save_location_of_game +="game_infomation.save"
	
	
	##make new directory for this game
	var dir = Directory.new()
	if(dir.dir_exists("res://Saves/"+game_number)):
		print("There is a game with this numner or somethng else")
		return
	else:
		dir.open("res://Saves/")
		dir.make_dir(game_number)

	##if game is new then location .../Saves/game_number/game_information.save 
	#save the file
	#open file
	file.open(save_location_of_game,File.WRITE)
	file.store_var(store_data,true)
	file.close()
	
	##emit the signal to switch to game mode
	emit_signal("new_game",game_number,game_dif)
