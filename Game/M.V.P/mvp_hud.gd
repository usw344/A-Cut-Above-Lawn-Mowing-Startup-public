extends Control

@onready var FPS_Counter: Label = $"FPS counter"

func _physics_process(delta: float) -> void:
	update_debug_stats()
	
func _ready() -> void:
	pass
	
	
func update_debug_stats():
	var fps = Performance.get_monitor(Performance.TIME_FPS)

	var ram_bytes = Performance.get_monitor(Performance.MEMORY_STATIC)
	var ram_mb = ram_bytes / 1024.0 / 1024.0

	var process_time = Performance.get_monitor(Performance.TIME_PROCESS)
	var physics_time = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var cpu_ms = (process_time + physics_time) * 1000.0

	FPS_Counter.text = "FPS: %d\nRAM: %.2f MB\nCPU: %.2f ms" % [
		int(fps),
		ram_mb,
		cpu_ms
	]
