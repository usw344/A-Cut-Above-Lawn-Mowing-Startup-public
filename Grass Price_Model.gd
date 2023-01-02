extends Node


var noise = OpenSimplexNoise.new()
var array_of_points = PoolVector2Array() 

var events_multiplier = {"Winter":0.5}


func _ready():
	noise.set_seed(randi())
	noise.set_octaves(6)
	noise.set_period(128)


var insert_into_array = Vector2()
var counter = 0
func _process(delta):
	counter += delta
	##print( (noise.get_noise_1d(counter)+1) ) 
	insert_into_array = Vector2(counter, noise.get_noise_1d(counter)+1)
	array_of_points.append(insert_into_array)


"""
	Returns the current grass price
	
	return float which contains current grass price rounded to 3 decimal places
"""
func get_grass_price():
	return stepify(array_of_points[array_of_points.size()-1].y,0.001) ##return the last value added to the point array

