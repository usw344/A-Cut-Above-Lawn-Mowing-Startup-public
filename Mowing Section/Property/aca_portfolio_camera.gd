class_name ACAPortfolioCamera
extends Node
## THE ESTABLISHING SHOT. One standardised viewpoint per property, used twice:
## once on arrival and once when the contract is finished.
##
## ---------------------------------------------------------------------------
## THE TWO SHOTS HAVE TO BE THE SAME SHOT
## ---------------------------------------------------------------------------
## A before-and-after pair is worth nothing if the camera moved, so the framing
## is a pure function of the property: its lawn centre, its half extent, and the
## corner the machine arrives from. No seed, no jitter, no player input and no
## dependence on where the mower happens to be standing. Two calls a contract
## apart produce two images of the same view.
##
## ---------------------------------------------------------------------------
## IT RENDERS ITS OWN SMALL VIEWPORT
## ---------------------------------------------------------------------------
## Grabbing the player's own screen would photograph the HUD along with the
## lawn, and hiding the HUD for a frame to avoid that is a visible flicker at
## the two moments the game is trying to look its best. So this owns a
## `SubViewport` at thumbnail size sharing the scene's `World3D`, with a camera
## of its own. It renders ONCE per capture, at 480x270, and is idle otherwise.
##
## PUBLIC API
##   frame(property: ACAProperty) -> void      point it at a property
##   capture() -> Viewport                     render one frame and hand it over
##   is_ready() -> bool
##
## SIGNALS: None.
##
## INVARIANTS
##   * The framing is derived from the property alone and never moves between
##     the before and after shots of one contract.
##   * `capture()` awaits exactly one draw and leaves the player's own viewport
##     untouched. It never changes which camera the player is looking through.
##
## PERSISTENCE OWNERSHIP: None. `ACAPortfolio` owns the images and the metadata.

## Thumbnail render size. Matches `ACAPortfolio`'s own bounds, so the image is
## never scaled up and never larger than it is stored at.
const WIDTH := 480
const HEIGHT := 270

## Where the camera stands, as multiples of the lawn's half extent. Behind and
## above the arrival corner, looking across the property - which is the view the
## player themselves gets in the first second of a contract, and is therefore
## the one they will recognise in a gallery.
const BACK := 1.55
const SIDE := 0.72
const HEIGHT_FACTOR := 0.62
## ...and how far up the property the camera looks, so the far fence is in shot
## rather than the horizon.
const LOOK_AHEAD := 0.15

## Field of view. Slightly wide, because a Small contract and a Large one both
## have to fill the same frame and the wide end flatters the small one less
## badly than the narrow end crops the large one.
const FOV := 58.0

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _framed := false


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Portfolio Viewport"
	_viewport.size = Vector2i(WIDTH, HEIGHT)
	_viewport.transparent_bg = false
	# ONCE, and only when asked. Anything else would be a second render of the
	# whole property every frame for two photographs a contract.
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.handle_input_locally = false
	_viewport.audio_listener_enable_3d = false
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.name = "Portfolio Camera"
	_camera.fov = FOV
	_camera.near = 0.5
	_camera.far = 4000.0
	_viewport.add_child(_camera)

	# THE SAME WORLD THE PLAYER IS IN. Sharing it rather than building one is
	# what makes this a second view of the property rather than a second copy.
	_viewport.world_3d = get_viewport().world_3d


func is_ready() -> bool:
	return _viewport != null and _camera != null and _framed


## Point the camera at this property. Pure: same property, same viewpoint.
func frame(property: ACAProperty) -> void:
	if property == null or _camera == null:
		return
	var lawn := property.lawn()
	if lawn == null:
		return
	var centre := lawn.lawn_centre()
	var half := lawn.lawn_half_extent()

	# BEHIND THE ARRIVAL CORNER. `ACAProperty.mower_start_transform()` puts the
	# machine off the -X edge on the centre line, so the shot is taken from a
	# little further out and to one side of exactly that.
	var eye := Vector3(
		centre.x - half * BACK,
		0.0,
		centre.z - half * SIDE)
	eye.y = property.ground_height_at(eye.x, eye.z) + half * HEIGHT_FACTOR
	var target := Vector3(centre.x + half * LOOK_AHEAD, centre.y, centre.z)

	_camera.global_position = eye
	_camera.look_at(target, Vector3.UP)
	_framed = true


## Render one frame and hand the viewport over. The caller reads the image from
## it - `ACAPortfolio` does the scaling and the writing.
##
## Returns null when there is nothing framed, which is what a caller checks
## rather than assuming a photograph happened.
func capture() -> Viewport:
	if not is_ready():
		return null
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# One draw, and only one. `frame_post_draw` is the point at which the
	# viewport's texture holds what was just rendered.
	await RenderingServer.frame_post_draw
	return _viewport
