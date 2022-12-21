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
var current_amount_in_sale_label = 0

var funds = 0 

var per_click_counter = 1


##Signals
signal update_model

func _ready():
	get_items_list()

	
	
"""w
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
	
	items["upward_grouping"] = $"Upward Grouping"
	items["downward_grouping"] = $"Downward Grouping"
	

"""
	Returns an item from this class that matches the description
"""
func get_item(key):
	return items[key]


	
"""
	Function to get the current stored cuttings value in the deposit screen
"""
func get_grass_stored():
	return current_grass_stored

func add_grass_to_sell():
	if current_amount_in_sale_label < get_grass_stored(): ## can't sell more than there is
		##check if more is being added to label than there is grass
		if get_grass_stored() - (current_amount_in_sale_label + per_click_counter) <= 0:
			current_amount_in_sale_label += (get_grass_stored() - current_amount_in_sale_label) 
		else:
			current_amount_in_sale_label += per_click_counter
		update_display()
	
func remove_grass_to_sell():
	if current_amount_in_sale_label > 0: #value to remain 0 or above
		if current_amount_in_sale_label - per_click_counter >= 0:
			current_amount_in_sale_label -= per_click_counter
		else:
			current_amount_in_sale_label = 0
		update_display()

###################################################### Function relating to grass price
"""
	Set the grass model object
"""
func set_grass_price_model(price_model):
	grass_price_model = price_model

"""
	Sell the grass amount selected
	
	emit: signal to change model for amount of funds
"""
func sell_grass():

	##add the value of grass to total funds in game
	funds += get_grass_value_in_funds()
	
	##remove the amount from the sale label data
	current_grass_stored -= current_amount_in_sale_label
	
	##reset amount of grass shown in label
	current_amount_in_sale_label = 0
	
	
	emit_signal("update_model")
	update_display()
	
	

func get_grass_value_in_funds():
	return grass_price_model.get_grass_price() * current_amount_in_sale_label

##################################################################### General Functions OR relating to model
"""
	Function to update data in the labels from the variables stored
"""
func update_display():
	$Cuttings.text = str(get_grass_stored())
	$"Current Selected Amount".text = str(current_amount_in_sale_label)

func _process(delta):
	sale_price_label.text = str(grass_price_model.get_grass_price())
	$"Price Applied To Amount".text = str(get_grass_value_in_funds() )
	
	$"Current Funds".text = str(funds)

"""
	Set funds
	this function is used by the Game_Script
"""
func set_funds(value):
	funds = value

func get_funds():
	return funds

"""
	Set the grass stored value for the cuttings display
	this function is used by the Game_Script
"""
func set_grass_stored(val):
	current_grass_stored = val
	update_display()

##################################################################### Functions relating to grouping
func update_add_to_sale_per_click():
	calc_per_click_counter()
	get_item("upward_grouping").text = str(per_click_counter)
	get_item("downward_grouping").text = str(-per_click_counter)
	


func calc_per_click_counter():
	per_click_counter *= 10
	if per_click_counter > 1000:
		per_click_counter = 1
