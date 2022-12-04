extends Control


#Buttons
onready var less_button 
onready var more_button 
onready var sell_button 
onready var back_button 

##Labels
onready var current_amount_for_sale_label 
onready var sale_price_label 
onready var cuttings_label 

##To store references of the labels and buttons
var items = {}


##data
var current_grass_stored = 0
var grass_price_model = null




func _ready():
	pass
	
	
"""
	Function to get the values of the nodes before the ready function is run
	Used when this object is stored but not displayed
"""
func get_items_list():
	#Buttons
	less_button = $Less
	more_button = $More
	sell_button = $Sell
	back_button = $Back

	##Labels
	current_amount_for_sale_label = $"Current Selected Amount"
	sale_price_label = $"Sale Price"
	cuttings_label = $Cuttings
	
	items["less_button"] = less_button
	items["more_button"] = more_button
	
	items["sell_button"] = sell_button
	items["back_button"] = back_button
	

"""
	Returns an item from this class that matches the description
"""
func get_item(key):
	print(items.size())
	return items[key]

func set_grass_stored(val):
	current_grass_stored = val
	
func get_grass_stored():
	return current_grass_stored
	
func set_grass_price_model(price_model):
	grass_price_model = price_model

func _process(delta):
	sale_price_label.text = str(grass_price_model.get_grass_price())
