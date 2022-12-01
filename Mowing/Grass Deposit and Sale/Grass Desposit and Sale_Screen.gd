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


var items = {}


func _ready():
	items["less_button"] = less_button
	items["more_button"] = more_button
	
	items["sell_button"] = sell_button
	items["back_button"] = back_button
	
	

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

