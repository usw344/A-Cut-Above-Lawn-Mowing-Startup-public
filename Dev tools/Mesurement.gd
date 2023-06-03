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

func start_get_m():
	before = Time.get_ticks_msec()
func stop_get_m():
	return Time.get_ticks_usec() - before
