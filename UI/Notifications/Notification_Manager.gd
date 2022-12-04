extends Control

onready var notification_container = $VBoxContainer 

var list_of_notifications_display = [] ##for notification displayed on screen
var list_of_notifications_storage = [] ##for all notifications in the current use of program

var screen_notification_display_limit = 5

var counter = 0
var ending_of_label = 1
var label = preload("res://UI/Notifications/Notification Label.tscn")
# Called when the node enters the scene tree for the first time.
func _ready():
	pass


"""
	Function to add a notification to the notification list
	param notification: a string 
"""
func add_notification(notification):
	var new_notification_label = label.instance()
	new_notification_label.set_text_for_label(notification)
	
	list_of_notifications_storage.append(new_notification_label)
	counter += 1
	
	if counter > 6:
		notification_container.get_child(0).queue_free()
		notification_container.add_child(new_notification_label)
	else:
		notification_container.add_child(new_notification_label)

"""
	Removes all currently displayed notifications from the screen
"""
func clear_all_displayed_notifications():
	for x in notification_container.get_child_count():
		notification_container.get_child(x).queue_free()
	

		

