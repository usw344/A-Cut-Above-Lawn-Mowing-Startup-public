extends Node
class_name Mesurment


var filename:String
var before: float
var after: float
var total:float

var current_func: String
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _init(string:String):
	filename = string

func set_filename(string:String):
	filename = string

func start_m(func_mesured:String):
	before = Time.get_ticks_msec()
	current_func = func_mesured
	
func stop_m():
	after = Time.get_ticks_msec()
	total = after - before
	
	print("-----------------  "+ filename +  "  -----------------")
	print()
	print(current_func + " used: " + str(total) + " ms")
	print()
	print("-----------------                    -----------------")

func start_mi(func_mesured:String):
	before = Time.get_ticks_usec()
	current_func = func_mesured
	
func stop_mi():
	after = Time.get_ticks_usec()
	total = after - before
	
	print("-----------------  "+ filename +  "  -----------------")
	print()
	print(current_func+" used: " + str(total) + " microseconds")
	print()
	print("-----------------                    -----------------")

func test_func():
	var arr: Array = []
	var dict:Dictionary = {}
	for x in range(10000000):
		arr.append(x)
		dict[x] = x*x
	
	filename = "Measurement"
	
	start_mi("Mesuring has() on an array")
	var bo:bool = arr.has(10000000-500)
	stop_mi()
	
	start_mi("Mesuring has() on an dict")
	bo = dict.has(90000)
	stop_mi()
	
	start_mi("Mesuring has() on an dict")
	bo = dict.has(randi_range(9000000,10000000-700))
	stop_mi()
	
