extends GridMap


var noise = OpenSimplexNoise.new()



# Called when the node enters the scene tree for the first time.
func _ready():
	
	var val = 150
	for x in range (val):
		for y in range (val):
			for z in range (val):
				if y < noise.get_noise_2d(x,z) * 10 + 5:
					set_cell_item(x,y,z,1)
				elif y < noise.get_noise_2d(x,z) * 10 + 15:
					set_cell_item(x,y,z,0)
