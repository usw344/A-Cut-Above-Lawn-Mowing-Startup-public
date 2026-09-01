class_name ACARegionalHub
extends Node3D
## A SERVICE LOT IN ANOTHER PART OF THE MAP, built from a description.
##
## When the business buys a lot in a new territory, the world has to get bigger
## in a way the player can see. This is that: a self-contained hub with its own
## ground, its own street plan, its own buildings, its own planting, its own
## traffic and its own horizon, laid out from a table rather than authored.
##
## ---------------------------------------------------------------------------
## FOUR HUBS, ONE SCENE, AND WHY
## ---------------------------------------------------------------------------
## The Business Town is an authored scene of about four hundred nodes, and it is
## the right shape for the place the game starts in - it is where the player
## spends most of their time and it has earned the attention. Authoring four
## more of those would be most of a development pass.
##
## So the regional hubs are a LAYOUT DESCRIPTION plus a builder. Each region
## declares its ground, its street plan, its buildings, its scenery and its
## horizon, and this class puts them down. They share the town's asset library
## and its materials, so a country depot is made of the same world the town is.
##
## ---------------------------------------------------------------------------
## WHAT MAKES FOUR HUBS FOUR PLACES
## ---------------------------------------------------------------------------
## Every model in this file also appears in at least one other hub. NONE of the
## difference between them is a unique asset, and all of it is composition:
##
##   FOOTPRINT     the island each region stands on, and the camera framing that
##                 goes with it. Big Town is laid out on two and a half times
##                 the ground Medium City is, and the camera is pulled back to
##                 match, so it reads as a bigger place before anything on it
##                 has been looked at.
##   STREET PLAN   `roads` is a list of STRIPS. Medium City is a grid, Big Town
##                 is a dual carriageway with cross streets, Rural is one
##                 highway across an otherwise empty county, and Country Parks
##                 is a single park road with a spur off it.
##   DENSITY       how much is standing between the streets, and how close
##                 together.
##   GROUND        grass, concrete, gravel and asphalt in different proportions.
##                 A trade yard is mostly hard surface; a park is mostly not.
##   TRAFFIC       four profiles over the SAME route mechanism, from nine cars
##                 in Big Town to two on a country lane.
##   HORIZON       what is beyond the island: a skyline of blank blocks, a belt
##                 of trees, a field pattern, or a forest.
##
## ---------------------------------------------------------------------------
## THE LOT GROWS WITH THE BUSINESS
## ---------------------------------------------------------------------------
## Exactly as `ACABusinessYard` does, and driven by the same thing: how
## established the company is in THIS territory. A lot the player has just
## bought is a truck, a machine and a crate; one they have worked for a month
## has more machines, a van, bins for the clippings, a fence and a board.
##
## NO PEOPLE. Machines, vehicles, buildings and signage, like everywhere else.
##
## PUBLIC API
##   build(region: int) -> void
##   region() -> int
##   destinations_root() -> Node3D          for ACABusinessTown's picking
##   camera_pivot() / camera_size() / camera_min_width()
##   tagline() -> String
##   region_air() -> Dictionary             what the region's air is like
##   traffic() -> ACATownTraffic
##
## SIGNALS: None.
##
## INVARIANTS
##   * NO COLLISION and NO PHYSICS beyond the interaction areas the picking
##     needs. It is scenery on a fixed isometric camera.
##   * Built once, in `build()`. Nothing here runs per frame except the traffic,
##     which owns its own process.
##   * EVERY VEHICLE STAYS ON TARMAC. Routes are derived from the same `roads`
##     table the road tiles are laid from, so a car cannot be on a street that
##     is not there.

# ------------------------------------------------------------------- assets
const ASSETS := "res://Main Area/ACA_BusinessTown/Assets/"
const MATERIALS := "res://Main Area/ACA_BusinessTown/Materials/"
const GENERATED := "res://Main Area/ACA_BusinessTown/Generated/"
const VEHICLES := "res://Assets/Vehicles and Mowers/Work Vehicles/"

const ROAD_STRAIGHT := ASSETS + "Roads/road_straight.gltf"
const ROAD_JUNCTION := ASSETS + "Roads/road_junction.gltf"
const ROAD_CROSSING := ASSETS + "Roads/road_straight_crossing.gltf"
const TRUCK := VEHICLES + "truck.glb"
const TRAILER := VEHICLES + "truck-flat.glb"
const VAN := VEHICLES + "van.glb"
const MOWER := GENERATED + "Mower.tscn"
const CRATE := ASSETS + "Props/box_A.gltf"
const CRATE_B := ASSETS + "Props/box_B.gltf"
const BIN := ASSETS + "Props/dumpster.gltf"
const TRASH := ASSETS + "Props/trash_A.gltf"
const HYDRANT := ASSETS + "Props/firehydrant.gltf"
const TRAFFIC_LIGHT := ASSETS + "Props/trafficlight_B.gltf"
const FENCE := GENERATED + "SiteFence.tscn"
const PLANTER := GENERATED + "Planter.tscn"
const PARK_STRUCTURE := GENERATED + "Park Structure.tscn"
const LAMP := ASSETS + "Props/streetlight.gltf"
const WATER_TOWER := ASSETS + "Props/watertower.gltf"
const BENCH := ASSETS + "Props/bench.gltf"

## The town's own parked cars, reused as parked cars.
const CARS := [
	ASSETS + "Vehicles/car_hatchback.gltf",
	ASSETS + "Vehicles/car_sedan.gltf",
	ASSETS + "Vehicles/car_stationwagon.gltf",
	ASSETS + "Vehicles/car_taxi.gltf",
]

## ---------------------------------------------------------------------------
## EVERY PACK IN THIS SCENE IS AUTHORED AT A DIFFERENT SIZE
## ---------------------------------------------------------------------------
## These are not style choices, they are corrections, and they are READ OFF THE
## BUSINESS TOWN rather than guessed - the town is the reference for how big
## everything in this world is, and a hub that disagrees with it reads as a
## different game.
##
##   trees      the town plants KayKit foliage at 0.26 - 0.30.
##   vehicles   the town's KayKit cars are at 1.0 and are about a unit long; the
##              Kenney work vehicles are about twice that, so half is what puts
##              a pickup a little longer than a hatchback.
##   yard plant the town's own yard runs at 1.0 inside a plot scaled to 0.38.
##   houses     the town's Quaternius meshes stand at 0.9.
##   benches    1.7 in the town. Hydrants 1.4. Streetlights and planters 1.0.
const VEHICLE_SCALE := 0.5
const YARD_PROP_SCALE := 0.45
## ...except the machines, which are the one thing on the plot that says what
## the business does, and at 0.45 were three pixels of green.
const MOWER_SCALE := 0.75
const TREE_SCALE := 0.28
const BUSH_SCALE := 0.34
const ROCK_SCALE := 0.40
const BENCH_SCALE := 1.7
const HOUSE_SCALE := 0.9
const HYDRANT_SCALE := 1.4

## KayKit City Builder blocks - three to five storeys. These are TOWN buildings
## and they are used where a town is what is wanted.
const BUILDING_A := ASSETS + "Buildings/building_A.gltf"
const BUILDING_B := ASSETS + "Buildings/building_B.gltf"
const BUILDING_C := ASSETS + "Buildings/building_C.gltf"
const BUILDING_D := ASSETS + "Buildings/building_D.gltf"
const BUILDING_E := ASSETS + "Buildings/building_E.gltf"
const BUILDING_F := ASSETS + "Buildings/building_F.gltf"
const BUILDING_G := ASSETS + "Buildings/building_G.gltf"
const BUILDING_H := ASSETS + "Buildings/building_H.gltf"

## Quaternius single- and two-storey buildings, as bare meshes with one surface.
## THE FIRST RENDER OF THESE HUBS PUT FOUR-STOREY APARTMENT BLOCKS ON A HIGHWAY
## SERVICE LOT IN OPEN COUNTRY, which is the loudest single thing wrong with it:
## the buildings said "city" while everything around them said "field". A rural
## depot and a park compound are built out of these instead.
const HOUSES := "res://Main Area/ACA_BusinessTown/Assets/Buildings/"
const HOUSE_1 := HOUSES + "q_1Story.obj"
const HOUSE_1_GABLE := HOUSES + "q_1Story_GableRoof.obj"
const HOUSE_1_ROUND := HOUSES + "q_1Story_RoundRoof.obj"
const HOUSE_1_SIGN := HOUSES + "q_1Story_Sign.obj"
const HOUSE_2_GABLE := HOUSES + "q_2Story_GableRoof.obj"
const HOUSE_2_WIDE := HOUSES + "q_2Story_Wide.obj"
const HOUSE_MATERIAL := MATERIALS + "quaternius_shop.tres"

const CITY_BUILDINGS := [
	BUILDING_A, BUILDING_B, BUILDING_C, BUILDING_D,
	BUILDING_E, BUILDING_F, BUILDING_G, BUILDING_H,
]

const TREES := [
	ASSETS + "Foliage/Tree_1_A_Color1.gltf",
	ASSETS + "Foliage/Tree_2_A_Color1.gltf",
	ASSETS + "Foliage/Tree_3_A_Color1.gltf",
	ASSETS + "Foliage/Tree_4_A_Color1.gltf",
]
const TREES_B := [
	ASSETS + "Foliage/Tree_1_B_Color1.gltf",
	ASSETS + "Foliage/Tree_2_B_Color1.gltf",
	ASSETS + "Foliage/Tree_3_B_Color1.gltf",
	ASSETS + "Foliage/Tree_4_B_Color1.gltf",
]
const BUSHES := [
	ASSETS + "Foliage/Bush_1_C_Color1.gltf",
	ASSETS + "Foliage/Bush_2_A_Color1.gltf",
	ASSETS + "Foliage/Bush_3_A_Color1.gltf",
	ASSETS + "Foliage/Bush_4_A_Color1.gltf",
]
const TUFTS := [ASSETS + "Foliage/Grass_1_A_Color1.gltf"]
const ROCKS := [
	ASSETS + "Foliage/Rock_1_A_Color1.gltf",
	ASSETS + "Foliage/Rock_1_D_Color1.gltf",
]

# ---------------------------------------------------------------- geometry

## A road tile is two units square, so everything on a street plan is laid on a
## two-unit grid and a carriageway is two units wide.
const TILE := 2.0
## Where the tarmac sits above the island's top surface.
const ROAD_Y := 0.03
## How far a traffic lane sits from its street's centre line. A car body is
## about 0.84 across and a half-carriageway is 1.0, so this leaves 0.13 of kerb
## either side - the same clearance `ACATownTraffic` uses in the town.
const LANE := 0.45


# ------------------------------------------------------------- the layouts

## ONE ENTRY PER REGION, and each one is a PLACE rather than a palette swap.
##
##   `island`      how big the ground slab is, and `centre_z` where it sits.
##   `ground`      the material the island's top surface is made of.
##   `camera`      the framing this layout wants: size, minimum width, pivot.
##   `roads`       the street plan, as strips. See `_build_roads()`.
##   `aprons`      the hard-surfaced rectangles: the working plot, the parking.
##   `offices`     the three buildings the player can click.
##   `yard`        where the company's own plant stands.
##   `plant`       the rectangles scenery may be scattered INSIDE. Everything
##                 already built - tarmac, aprons, buildings, the pond - is
##                 subtracted automatically, so these say where the region has
##                 open ground rather than where each individual tree goes.
##   `green`       patches of grass laid on a hard-surfaced region, so a trade
##                 park is not one unbroken slab of concrete.
##   `traffic`     how many cars, how fast, and whether any of them circulate.
##   `scenery`     which composer fills the rest of the island.
##   `horizon`     what stands beyond it.
const LAYOUTS := {
	# =====================================================================
	# MEDIUM CITY - a denser town an hour up the road. A real grid: two
	# streets across, one down, and buildings in every block between them.
	# =====================================================================
	ACAServiceTerritory.Region.COMMERCIAL_DISTRICT: {
		"island": Vector2(42.0, 23.0),
		"centre_z": -5.0,
		"ground": "concrete.tres",
		"skirt": "earth.tres",
		"camera": {"size": 26.5, "min_width": 43.0, "pivot": Vector3(-0.5, 0.9, -4.8)},
		"tagline": "Trade park service yard",
		"roads": [
			{"axis": "x", "at": -5.0, "from": -20.0, "to": 20.0, "through": true,
				"crossing_at": -4.0},
			{"axis": "x", "at": -12.0, "from": -20.0, "to": 20.0, "through": true},
			{"axis": "z", "at": 8.0, "from": -16.0, "to": 10.0, "through": true},
			{"axis": "z", "at": -16.0, "from": -12.0, "to": -5.0, "through": false},
		],
		"aprons": [
			{"rect": Rect2(-19.0, 0.2, 14.0, 5.6), "material": "asphalt.tres"},
			# NOT ACROSS THE CROSS STREET. The street at x = 8 is two units of
			# tarmac wide, so an apron that started at 3.5 had the road tiles
			# laid straight over the middle of it and the bay lines running out
			# the far side.
			{"rect": Rect2(10.0, -2.4, 10.0, 8.0), "material": "asphalt.tres",
				"bays": 4, "bay_axis": "x"},
		],
		"offices": [
			{"id": &"job_office", "model": BUILDING_F, "at": Vector3(-15.5, 0.0, -1.5),
				"yaw": 0.0, "name": "Contracts Desk", "sign": "JOBS",
				"blurb": "Forecourts, landscaped strips and institutional grounds.",
				"colour": Color(0.435, 0.522, 0.612)},
			{"id": &"service_lot", "model": BUILDING_B, "at": Vector3(-9.0, 0.0, -1.3),
				"yaw": 0.0, "name": "Service Yard", "sign": "DEPOT",
				"blurb": "The yard itself. Trailer, configuration, and the road out.",
				"colour": Color(0.404, 0.435, 0.412)},
			{"id": &"business_hq", "model": BUILDING_G, "at": Vector3(-2.6, 0.0, -1.5),
				"yaw": -0.06, "name": "Regional Office", "sign": "OFFICE",
				"blurb": "The company's books, its fleet and its territories.",
				"colour": Color(0.400, 0.612, 0.337)},
		],
		"yard": {"at": Vector3(-15.5, 0.0, 2.9), "spread": 0.86},
		# A DEVELOPED DISTRICT HAS ALMOST NO PLANTING, and what it has is in
		# pockets: a green square between the depot and the cross street, and
		# the verge behind the back row.
		"plant": [
			Rect2(-4.6, 0.4, 11.0, 5.4),
			Rect2(-20.6, -15.5, 2.4, 14.0),
		],
		"green": [Rect2(-4.6, 0.4, 11.0, 5.4)],
		"traffic": {"min_cars": 4, "max_cars": 6, "min_speed": 1.7, "max_speed": 2.9,
			"loop": [Vector2(-16.0, -5.0), Vector2(8.0, -5.0),
				Vector2(8.0, -12.0), Vector2(-16.0, -12.0)]},
		"scenery": "city",
		"horizon": "city",
	},
	# =====================================================================
	# BIG TOWN - the regional centre. A dual carriageway with a planted
	# median, two cross streets, a civic plaza, and the largest parking
	# area anywhere in the game. Framed a third wider than Medium City.
	# =====================================================================
	ACAServiceTerritory.Region.HOSPITALITY_STRIP: {
		"island": Vector2(52.0, 34.0),
		"centre_z": -3.5,
		"ground": "concrete.tres",
		"skirt": "earth.tres",
		"camera": {"size": 33.5, "min_width": 55.0, "pivot": Vector3(-0.5, 0.9, -2.2)},
		"tagline": "Regional operations depot",
		"roads": [
			# THE ARTERIAL. Two one-way carriageways with a median between them,
			# which is the single clearest way to say "this is a bigger road"
			# with the same two-unit tiles every other street is built from.
			{"axis": "x", "at": -8.4, "from": -25.0, "to": 25.0, "through": true,
				"one_way": -1},
			{"axis": "x", "at": -5.2, "from": -25.0, "to": 25.0, "through": true,
				"one_way": 1, "crossing_at": -6.0},
			{"axis": "x", "at": -16.0, "from": -25.0, "to": 25.0, "through": true},
			{"axis": "z", "at": -10.0, "from": -20.0, "to": 12.0, "through": true},
			{"axis": "z", "at": 14.0, "from": -20.0, "to": 12.0, "through": true},
		],
		"aprons": [
			{"rect": Rect2(-24.0, 4.0, 16.0, 7.4), "material": "asphalt.tres"},
			{"rect": Rect2(-21.0, -2.8, 27.0, 5.8), "material": "concrete_dark.tres",
				"raise": 0.16},
			{"rect": Rect2(16.0, -2.6, 9.4, 13.0), "material": "asphalt.tres",
				"bays": 6, "bay_axis": "x"},
		],
		"offices": [
			{"id": &"job_office", "model": BUILDING_G, "at": Vector3(-17.5, 0.16, 0.2),
				"yaw": 0.0, "name": "Bookings Office", "sign": "JOBS",
				"blurb": "Civic frontage, venue grounds, and the customers who notice.",
				"colour": Color(0.694, 0.478, 0.545)},
			{"id": &"service_lot", "model": BUILDING_B, "at": Vector3(-6.5, 0.16, 0.4),
				"yaw": 0.0, "name": "Operations Depot", "sign": "DEPOT",
				"blurb": "Rollers, catchers, and the trailer that carries them.",
				"colour": Color(0.404, 0.435, 0.412)},
			{"id": &"business_hq", "model": BUILDING_C, "at": Vector3(3.4, 0.16, 0.2),
				"yaw": -0.05, "name": "Company Office", "sign": "OFFICE",
				"blurb": "The company's books, its fleet and its territories.",
				"colour": Color(0.400, 0.612, 0.337)},
		],
		"yard": {"at": Vector3(-16.5, 0.0, 7.4), "spread": 1.15},
		"plant": [
			Rect2(-6.6, 4.4, 18.6, 7.0),
			Rect2(-25.4, -20.0, 3.4, 12.0),
		],
		"green": [Rect2(-6.6, 4.4, 18.6, 7.0)],
		"traffic": {"min_cars": 6, "max_cars": 9, "min_speed": 1.9, "max_speed": 3.3,
			"loop": [Vector2(-10.0, -8.4), Vector2(14.0, -8.4),
				Vector2(14.0, -16.0), Vector2(-10.0, -16.0)]},
		"scenery": "bigtown",
		"horizon": "skyline",
	},
	# =====================================================================
	# RURAL HIGHWAY - one road across an otherwise empty county. Low
	# buildings, a gravel lot, and field after field to the horizon.
	# =====================================================================
	ACAServiceTerritory.Region.RURAL_HIGHWAY: {
		"island": Vector2(54.0, 33.0),
		"centre_z": -3.0,
		"ground": "grass.tres",
		"skirt": "earth.tres",
		"camera": {"size": 34.5, "min_width": 57.0, "pivot": Vector3(-1.0, 0.9, -1.6)},
		"tagline": "Highway service lot",
		"roads": [
			# A HIGHWAY IS FOUR UNITS OF TARMAC, laid as two carriageways with
			# no median: the one place in the game where a road is wider than a
			# street, and the reason the lot beside it reads as roadside.
			{"axis": "x", "at": -11.0, "from": -26.0, "to": 26.0, "through": true,
				"one_way": -1},
			{"axis": "x", "at": -9.0, "from": -26.0, "to": 26.0, "through": true,
				"one_way": 1},
			{"axis": "z", "at": -4.0, "from": -9.0, "to": -2.0, "through": false},
		],
		"aprons": [
			{"rect": Rect2(-17.0, -4.6, 26.0, 8.8), "material": "dirt.tres"},
		],
		"offices": [
			{"id": &"job_office", "model": HOUSE_2_GABLE, "at": Vector3(-12.5, 0.0, -1.6),
				"yaw": 0.1, "name": "Site Office", "sign": "JOBS",
				"blurb": "Contracts coming off the highway and the country around it.",
				"colour": Color(0.878, 0.651, 0.235)},
			{"id": &"service_lot", "model": HOUSE_1_ROUND, "at": Vector3(-3.6, 0.0, -1.0),
				"yaw": 0.0, "name": "Service Lot", "sign": "DEPOT",
				"blurb": "Load the trailer, set the machine up, and move between areas.",
				"colour": Color(0.729, 0.639, 0.361)},
			{"id": &"supply_store", "model": HOUSE_1_SIGN, "at": Vector3(5.6, 0.0, -1.6),
				"yaw": -0.12, "name": "Fuel and Feed", "sign": "SUPPLY",
				"blurb": "Diesel off the forecourt, and somewhere to weigh in the clippings.",
				"colour": Color(0.851, 0.478, 0.169)},
		],
		"yard": {"at": Vector3(-12.0, 0.0, 1.6), "spread": 1.05},
		# OPEN COUNTRY IS PLANTED EVERYWHERE IT IS NOT BUILT ON, which is most
		# of it. The forbidden set below keeps it off the tarmac and the lot.
		"plant": [Rect2(-26.0, -18.5, 52.0, 31.0)],
		# SPARSE, AND FASTER. Two or three vehicles, and they are passing rather
		# than circulating: there is no loop on a highway.
		"traffic": {"min_cars": 2, "max_cars": 4, "min_speed": 3.2, "max_speed": 4.6},
		"scenery": "rural",
		"horizon": "fields",
	},
	# =====================================================================
	# COUNTRY PARKS - the compound is small on purpose and the park is what
	# fills the frame: a pond, trails, groves, meadow and a forest edge.
	# =====================================================================
	ACAServiceTerritory.Region.CIVIC_PARK: {
		"island": Vector2(58.0, 35.0),
		"centre_z": -3.0,
		"ground": "grass.tres",
		"skirt": "earth.tres",
		"camera": {"size": 36.5, "min_width": 60.0, "pivot": Vector3(1.0, 0.9, -1.8)},
		"tagline": "Parks maintenance compound",
		"roads": [
			{"axis": "x", "at": -13.0, "from": -28.0, "to": 28.0, "through": true},
			{"axis": "z", "at": -14.0, "from": -13.0, "to": -4.0, "through": false},
		],
		"aprons": [
			{"rect": Rect2(-22.0, -4.6, 16.0, 8.0), "material": "concrete_dark.tres"},
		],
		"offices": [
			{"id": &"job_office", "model": HOUSE_1_GABLE, "at": Vector3(-19.0, 0.0, -1.8),
				"yaw": 0.08, "name": "Parks Depot Office", "sign": "JOBS",
				"blurb": "Municipal greens, civic grounds and conservation work.",
				"colour": Color(0.373, 0.580, 0.451)},
			{"id": &"service_lot", "model": HOUSE_2_WIDE, "at": Vector3(-12.4, 0.0, -1.4),
				"yaw": 0.0, "name": "Machinery Bay", "sign": "DEPOT",
				"blurb": "Wide decks, spare fuel, and where the day is planned.",
				"colour": Color(0.545, 0.780, 0.478)},
			{"id": &"supply_store", "model": HOUSE_1, "at": Vector3(-6.2, 0.0, -1.8),
				"yaw": -0.08, "name": "Stores", "sign": "SUPPLY",
				"blurb": "Fuel, and the weighbridge for what comes off the greens.",
				"colour": Color(0.851, 0.478, 0.169)},
		],
		"yard": {"at": Vector3(-18.0, 0.0, 1.0), "spread": 0.95},
		"plant": [Rect2(-28.0, -19.5, 56.0, 33.0)],
		"traffic": {"min_cars": 1, "max_cars": 2, "min_speed": 1.2, "max_speed": 2.0},
		"scenery": "park",
		"horizon": "forest",
	},
}

## What the region's air is like, as a small tint and a haze weight the hub's
## light adapter mixes in. VISUAL ONLY: it is not a second weather system, it
## does not change with the sky, and the sky remains the one authority on what
## the weather is.
const REGION_AIR := {
	ACAServiceTerritory.Region.COMMERCIAL_DISTRICT: {
		"tint": Color(0.960, 0.965, 0.985), "haze": 0.20},
	ACAServiceTerritory.Region.HOSPITALITY_STRIP: {
		"tint": Color(0.968, 0.960, 0.965), "haze": 0.34},
	ACAServiceTerritory.Region.RURAL_HIGHWAY: {
		"tint": Color(1.000, 0.995, 0.962), "haze": 0.10},
	ACAServiceTerritory.Region.CIVIC_PARK: {
		"tint": Color(0.985, 1.000, 0.972), "haze": 0.24},
}

var _region: int = ACAServiceTerritory.Region.RURAL_HIGHWAY
var _destinations: Node3D = null
var _growth: Node3D = null
var _traffic: ACATownTraffic = null
## Rectangles nothing may be scattered on, derived from what has already been
## built: every road strip, every apron, every placed building and the pond.
## Deriving it is the point - an early version of these hubs kept ONE rectangle
## per region by hand, and a tree stood in the middle of a car park the first
## time a layout moved.
var _forbidden: Array[Rect2] = []
## Where scenery MAY go, from the layout.
var _plant: Array[Rect2] = []
var _rng := RandomNumberGenerator.new()


# ======================================================================= build

func build(region: int) -> void:
	_region = region if LAYOUTS.has(region) else ACAServiceTerritory.Region.RURAL_HIGHWAY
	var layout: Dictionary = LAYOUTS[_region]
	# SEEDED PER REGION, so a hub looks the same every time the player drives
	# back to it. A depot that rearranged its own trees between visits would be
	# the one thing about it nobody could explain.
	_rng.seed = hash(Vector2i(_region, 4207))
	_forbidden = []
	_plant = []
	for rect: Rect2 in layout.get("plant", []):
		_plant.append(rect)
	if _plant.is_empty():
		var island: Vector2 = layout["island"]
		var cz: float = float(layout["centre_z"])
		_plant.append(Rect2(-island.x * 0.5 + 1.5, cz - island.y * 0.5 + 1.5,
			island.x - 3.0, island.y - 3.0))
	_reserve_built_ground(layout)

	for child in get_children():
		child.queue_free()

	_build_ground(layout)
	_build_horizon(String(layout["horizon"]), layout)
	_build_roads(layout)
	_build_destinations(layout)
	_build_yard(layout)
	_build_scenery(String(layout["scenery"]), layout)
	_build_traffic(layout)
	_apply_growth()


func region() -> int:
	return _region


func destinations_root() -> Node3D:
	return _destinations


func traffic() -> ACATownTraffic:
	return _traffic


func camera_pivot() -> Vector3:
	return (LAYOUTS[_region]["camera"] as Dictionary)["pivot"]


func camera_size() -> float:
	return float((LAYOUTS[_region]["camera"] as Dictionary)["size"])


func camera_min_width() -> float:
	return float((LAYOUTS[_region]["camera"] as Dictionary)["min_width"])


func tagline() -> String:
	return String(LAYOUTS.get(_region, {}).get("tagline", ""))


## The region's own air, for the light adapter. `{ tint, haze }`.
func region_air() -> Dictionary:
	return REGION_AIR.get(_region, {"tint": Color.WHITE, "haze": 0.2})


## Everything the layout itself puts down, as rectangles nothing may stand on.
## Roads are widened by a car's width so a tree never overhangs a carriageway,
## and the aprons by a little less.
func _reserve_built_ground(layout: Dictionary) -> void:
	for strip: Dictionary in layout["roads"]:
		var at := float(strip["at"])
		var lo := minf(float(strip["from"]), float(strip["to"])) - 1.4
		var hi := maxf(float(strip["from"]), float(strip["to"])) + 1.4
		if String(strip["axis"]) == "x":
			_forbidden.append(Rect2(lo, at - 2.0, hi - lo, 4.0))
		else:
			_forbidden.append(Rect2(at - 2.0, lo, 4.0, hi - lo))
	for entry: Dictionary in layout["aprons"]:
		_forbidden.append((entry["rect"] as Rect2).grow(0.6))
	for entry: Dictionary in layout["offices"]:
		var at: Vector3 = entry["at"]
		_forbidden.append(Rect2(at.x - 2.4, at.z - 2.4, 4.8, 4.8))
	var yard: Vector3 = (layout["yard"] as Dictionary)["at"]
	_forbidden.append(Rect2(yard.x - 5.0, yard.z - 2.6, 20.0, 5.6))


## Is this point on something already built?
func _occupied(at: Vector2) -> bool:
	for rect in _forbidden:
		if rect.has_point(at):
			return true
	return false


## Reserve a rectangle so nothing is scattered over it afterwards. Called by the
## composers for the things they build themselves - a pond, a trail, a row of
## buildings - so the order in `build()` is what decides precedence.
func _reserve(rect: Rect2) -> void:
	_forbidden.append(rect)


# ====================================================================== ground

## THE SAME THREE-LAYER ISLAND THE TOWN STANDS ON: a top surface, an earth step
## under it, and a rock base under that. It is what makes a hub read as a place
## on a map rather than as a plane with things on it.
func _build_ground(layout: Dictionary) -> void:
	var island: Vector2 = layout["island"]
	var cz: float = float(layout["centre_z"])
	var root := Node3D.new()
	root.name = "Island"
	add_child(root)

	_slab(root, Vector3(island.x, 0.55, island.y), Vector3(0.0, -0.275, cz),
		String(layout["ground"]))
	_slab(root, Vector3(island.x - 1.4, 1.4, island.y - 1.4),
		Vector3(0.0, -1.25, cz), String(layout["skirt"]))
	_slab(root, Vector3(island.x - 3.8, 1.2, island.y - 3.8),
		Vector3(0.0, -2.45, cz), "rock.tres")

	for entry: Dictionary in layout["aprons"]:
		var rect: Rect2 = entry["rect"]
		var lift: float = float(entry.get("raise", 0.0))
		_slab(root, Vector3(rect.size.x, 0.09 + lift, rect.size.y),
			Vector3(rect.position.x + rect.size.x * 0.5, 0.05 + lift * 0.5,
				rect.position.y + rect.size.y * 0.5),
			String(entry["material"]))
		if int(entry.get("bays", 0)) > 0:
			_parking_bays(root, rect, int(entry["bays"]),
				String(entry.get("bay_axis", "x")), lift)


## Painted bays, and a car in most of them. A parking area with no lines on it
## is a slab of asphalt; the lines are the whole of what makes it a car park.
func _parking_bays(parent: Node3D, rect: Rect2, count: int, axis: String,
		lift: float) -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.906, 0.902, 0.851)
	white.roughness = 0.95
	white.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var y := 0.105 + lift
	for i in count + 1:
		var t := float(i) / float(count)
		if axis == "x":
			var z := rect.position.y + 1.0 + t * (rect.size.y - 2.0)
			_slab_material(parent, Vector3(rect.size.x - 2.4, 0.02, 0.12),
				Vector3(rect.position.x + rect.size.x * 0.5, y, z), white)
		else:
			var x := rect.position.x + 1.0 + t * (rect.size.x - 2.0)
			_slab_material(parent, Vector3(0.12, 0.02, rect.size.y - 2.4),
				Vector3(x, y, rect.position.y + rect.size.y * 0.5), white)
	for i in count:
		if _rng.randf() > 0.72:
			continue
		var t := (float(i) + 0.5) / float(count)
		var at := Vector3.ZERO
		var yaw := 0.0
		if axis == "x":
			at = Vector3(rect.position.x + rect.size.x * 0.5, 0.12 + lift,
				rect.position.y + 1.0 + t * (rect.size.y - 2.0))
			yaw = PI * 0.5
		else:
			at = Vector3(rect.position.x + 1.0 + t * (rect.size.x - 2.0),
				0.12 + lift, rect.position.y + rect.size.y * 0.5)
		_prop(parent, String(CARS[_rng.randi() % CARS.size()]), at,
			yaw + _rng.randf_range(-0.04, 0.04), 1.0, 0)


# ======================================================================= roads

## THE STREET PLAN, laid from a list of STRIPS.
##
## A strip is one carriageway: an axis, a centre line, and where it starts and
## stops. Tiles go down on the two-unit grid, a crossing tile is dropped in
## where one is asked for, and where two strips meet the tile becomes a
## junction. That is the whole of it - and because the TRAFFIC ROUTES are
## generated from the same table, a car cannot be driving on a street that was
## never laid.
func _build_roads(layout: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Roads"
	add_child(root)
	var strips: Array = layout["roads"]

	for strip: Dictionary in strips:
		var axis := String(strip["axis"])
		var at := float(strip["at"])
		var from := float(strip["from"])
		var to := float(strip["to"])
		var crossing_at := float(strip.get("crossing_at", INF))
		var steps := int(floor((to - from) / TILE))
		for i in steps + 1:
			var along := from + float(i) * TILE
			var position := Vector3(along, ROAD_Y, at) if axis == "x" \
				else Vector3(at, ROAD_Y, along)
			var path := ROAD_STRAIGHT
			var yaw := 0.0 if axis == "x" else PI * 0.5
			if _crosses_here(strips, strip, along):
				path = ROAD_JUNCTION
			elif is_finite(crossing_at) and absf(along - crossing_at) < TILE * 0.5:
				path = ROAD_CROSSING
			var node := _instance(path, root)
			if node == null:
				continue
			node.position = position
			node.rotation.y = yaw


## Does another strip cross this one at this point? Two strips on the same axis
## never count: a dual carriageway is two strips side by side and neither of
## them is a junction in the other.
func _crosses_here(strips: Array, strip: Dictionary, along: float) -> bool:
	var axis := String(strip["axis"])
	var at := float(strip["at"])
	for other: Dictionary in strips:
		if String(other["axis"]) == axis:
			continue
		var other_at := float(other["at"])
		if absf(other_at - along) > TILE * 0.5:
			continue
		var lo := minf(float(other["from"]), float(other["to"])) - TILE * 0.5
		var hi := maxf(float(other["from"]), float(other["to"])) + TILE * 0.5
		if at >= lo and at <= hi:
			return true
	return false


# ================================================================ destinations

## The buildings the player can click. Built as `ACAInteractiveBuilding`s so the
## town's own picking, hover, selection and panel all work unchanged - the hub
## does not have a second interaction system, it reuses the one that exists.
func _build_destinations(layout: Dictionary) -> void:
	_destinations = Node3D.new()
	_destinations.name = "Destinations"
	add_child(_destinations)

	for entry: Dictionary in layout["offices"]:
		var building := _make_building(entry)
		if building != null:
			_destinations.add_child(building)


func _make_building(entry: Dictionary) -> ACAInteractiveBuilding:
	var model := _building_model(String(entry["model"]))
	if model == null:
		push_warning("[HUB] could not load %s" % entry["model"])
		return null

	var building := ACAInteractiveBuilding.new()
	building.name = String(entry["name"]).replace(" ", "")
	building.building_id = StringName(entry["id"])
	building.display_name = String(entry["name"])
	building.description = String(entry["blurb"])
	building.action_label = "OPEN"
	building.accent_color = entry["colour"]
	building.focus_point = Vector3(0.0, 1.1, 0.4)
	building.focus_zoom = 11.5
	building.position = entry["at"]
	building.rotation.y = float(entry["yaw"])

	# The wrapper expects these three children by name - see
	# `ACAInteractiveBuilding._get_configuration_warnings()`.
	var visual := Node3D.new()
	visual.name = "Visual"
	building.add_child(visual)
	# A FORECOURT, in the building's own accent. Without one, the three
	# buildings the player can actually click are lost among the twenty they
	# cannot: a pad reads as "this one is a place" at a glance.
	var pad := BoxMesh.new()
	pad.size = Vector3(4.3, 0.07, 4.3)
	_piece(visual, pad, load(MATERIALS + "asphalt.tres"), Vector3(0.0, 0.03, 0.0))
	# ONE PAINTED KERB ACROSS THE FRONT, not a border all the way round: a ring
	# in the building's accent reads as a selection box the player cannot turn
	# off, which is the last thing three clickable buildings need.
	var kerb := BoxMesh.new()
	kerb.size = Vector3(4.3, 0.08, 0.34)
	var painted := StandardMaterial3D.new()
	painted.albedo_color = entry["colour"]
	painted.roughness = 0.95
	painted.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_piece(visual, kerb, painted, Vector3(0.0, 0.035, 2.15))
	model.name = "Model"
	visual.add_child(model)
	_sign(visual, String(entry["sign"]), entry["colour"])

	var area := Area3D.new()
	area.name = "InteractionArea"
	# Layer 9 is the town's own pick layer; see `ACABusinessTown.PICK_LAYER`.
	area.collision_layer = ACABusinessTown.PICK_MASK
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 2.8, 2.6)
	shape.shape = box
	shape.position = Vector3(0.0, 1.4, 0.0)
	area.add_child(shape)
	building.add_child(area)

	var marker := Node3D.new()
	marker.name = "SelectionMarker"
	marker.position = Vector3(0.0, 0.13, 0.0)
	var ring := MeshInstance3D.new()
	ring.name = "Mesh"
	var torus := TorusMesh.new()
	torus.inner_radius = 1.45
	torus.outer_radius = 1.61
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(ring)
	building.add_child(marker)

	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = String(entry["name"])
	label.position = Vector3(0.0, 3.1, 0.0)
	label.pixel_size = 0.0042
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 4
	label.outline_render_priority = 3
	label.outline_modulate = Color(0.11, 0.13, 0.15, 0.92)
	label.font_size = 96
	label.outline_size = 22
	building.add_child(label)
	return building


## THE TWO KINDS OF BUILDING ASSET IN THIS PROJECT, behind one call.
##
## KayKit's city blocks are packed SCENES with their own materials. Quaternius's
## houses are bare OBJ MESHES with one surface each, and the town paints them
## with `quaternius_shop.tres` - which is exactly what is done here, so a rural
## depot office and the town's own corner shop are the same building in the same
## paint.
func _building_model(path: String) -> Node3D:
	if path.ends_with(".obj"):
		var mesh := load(path) as Mesh
		if mesh == null:
			return null
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.set_surface_override_material(0, load(HOUSE_MATERIAL))
		instance.scale = Vector3(HOUSE_SCALE, HOUSE_SCALE, HOUSE_SCALE)
		var holder := Node3D.new()
		holder.add_child(instance)
		return holder
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D


## A painted board on a post, exactly like the Supply Store's in the town. NO
## COMPANY NAME and no proprietor: the board says what the building is for.
func _sign(parent: Node3D, text: String, accent: Color) -> void:
	var root := Node3D.new()
	root.name = "Sign"
	root.position = Vector3(0.72, 0.1, 0.9)
	parent.add_child(root)

	var post := CylinderMesh.new()
	post.top_radius = 0.035
	post.bottom_radius = 0.035
	post.height = 0.66
	post.radial_segments = 8
	post.rings = 1
	_piece(root, post, load(MATERIALS + "wood_dark.tres"), Vector3(0.0, 0.33, 0.0))

	var board := BoxMesh.new()
	board.size = Vector3(0.94, 0.38, 0.06)
	var painted := StandardMaterial3D.new()
	painted.albedo_color = accent
	painted.roughness = 0.9
	painted.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_piece(root, board, painted, Vector3(0.0, 0.78, 0.0))

	var caption := Label3D.new()
	caption.text = text
	caption.position = Vector3(0.0, 0.78, 0.045)
	caption.pixel_size = 0.0028
	caption.modulate = Color(0.16, 0.17, 0.18)
	caption.font_size = 96
	caption.outline_size = 0
	root.add_child(caption)


# ======================================================================= yard

## THE BUSINESS'S OWN PLANT, on the apron in front of the service unit. This is
## the part that grows: `_apply_growth()` shows more of it as the company
## becomes established in this territory.
func _build_yard(layout: Dictionary) -> void:
	_growth = Node3D.new()
	_growth.name = "Plant"
	add_child(_growth)
	var spec: Dictionary = layout["yard"]
	var o: Vector3 = spec["at"]
	var s: float = float(spec.get("spread", 1.0))

	# Always there, from the day the lot is bought.
	_prop(_growth, TRUCK, o + Vector3(0.0, 0.12, 0.0), 0.2, VEHICLE_SCALE, 0)
	_prop(_growth, MOWER, o + Vector3(1.9 * s, 0.12, 0.4), 0.6, MOWER_SCALE, 0)
	_prop(_growth, CRATE, o + Vector3(-2.1 * s, 0.12, -0.7), 0.2, YARD_PROP_SCALE, 0)

	# NOTICED: the trailer arrives, and somewhere for the clippings.
	_prop(_growth, TRAILER, o + Vector3(-1.8 * s, 0.12, 0.4), 0.2, VEHICLE_SCALE, 1)
	_prop(_growth, BIN, o + Vector3(10.2 * s, 0.12, 0.5), -PI * 0.5, YARD_PROP_SCALE, 1)

	# ESTABLISHED: more machines, a van, and the plot starts to fill.
	_prop(_growth, MOWER, o + Vector3(2.9 * s, 0.12, 0.9), -0.4, MOWER_SCALE, 2)
	_prop(_growth, VAN, o + Vector3(7.4 * s, 0.12, 0.5), PI * 0.5, VEHICLE_SCALE, 2)
	_prop(_growth, CRATE_B, o + Vector3(-2.3 * s, 0.12, 0.2), -0.3, YARD_PROP_SCALE, 2)

	# PREFERRED and above: the lot is fenced, lit, and has the company's board
	# on the gate. A fence bay is exactly two units wide, so the run is spaced
	# at two and reads as one fence rather than as a row of gates.
	for i in 8:
		_prop(_growth, FENCE, o + Vector3(-2.6 * s + float(i) * 2.0, 0.12, 1.7),
			0.0, 1.0, 3)
	_prop(_growth, LAMP, o + Vector3(11.6 * s, 0.12, -0.6), 0.0, 1.0, 3)
	_prop(_growth, MOWER, o + Vector3(3.9 * s, 0.12, 1.3), 0.15, MOWER_SCALE, 3)
	_company_board(o + Vector3(-4.0 * s, 0.12, -0.4), 3)
	_yard_dressing(o, s)


## THE THINGS A WORKING YARD HAS ON IT THAT ARE NOT THE COMPANY'S FLEET: fuel
## drums, stacked pallets and a bulk tank. None of it grows and none of it is
## interactive - it is there because an apron with four vehicles on it and
## nothing else renders as a car park with a truck lost in the middle of it.
func _yard_dressing(o: Vector3, s: float) -> void:
	var root := Node3D.new()
	root.name = "Dressing"
	root.set_meta(&"growth_level", 0)
	_growth.add_child(root)

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.427, 0.475, 0.494)
	steel.roughness = 0.55
	steel.metallic = 0.45
	var drum_paint := StandardMaterial3D.new()
	drum_paint.albedo_color = Color(0.749, 0.404, 0.216)
	drum_paint.roughness = 0.8

	# A bulk tank on a stand, which is what a yard that runs machines has.
	var tank := CylinderMesh.new()
	tank.top_radius = 0.34
	tank.bottom_radius = 0.34
	tank.height = 1.6
	tank.radial_segments = 12
	var tank_node := MeshInstance3D.new()
	tank_node.mesh = tank
	tank_node.material_override = steel
	tank_node.position = o + Vector3(5.6 * s, 0.55, -1.1)
	tank_node.rotation = Vector3(0.0, 0.0, PI * 0.5)
	root.add_child(tank_node)

	# Fuel drums, in a group rather than a line.
	for i in 5:
		var drum := CylinderMesh.new()
		drum.top_radius = 0.13
		drum.bottom_radius = 0.13
		drum.height = 0.34
		drum.radial_segments = 10
		var node := MeshInstance3D.new()
		node.mesh = drum
		node.material_override = drum_paint
		node.position = o + Vector3(6.9 * s + _rng.randf_range(-0.45, 0.45), 0.29,
			-0.9 + _rng.randf_range(-0.4, 0.4))
		root.add_child(node)

	# Stacked pallets, three high.
	var timber := load(MATERIALS + "wood.tres")
	for i in 4:
		var slab := BoxMesh.new()
		slab.size = Vector3(0.9, 0.11, 0.72)
		var node := MeshInstance3D.new()
		node.mesh = slab
		node.material_override = timber
		node.position = o + Vector3(-3.2 * s, 0.18 + float(i) * 0.12, 1.0)
		node.rotation.y = _rng.randf_range(-0.05, 0.05)
		root.add_child(node)


## The board on the gate. A green board with a cream stripe, which is exactly
## what `ACABusinessYard` puts on the home yard - and, as there, no name on it
## beyond the game's own.
func _company_board(at: Vector3, level: int) -> void:
	var root := Node3D.new()
	root.name = "Board"
	root.position = at
	_growth.add_child(root)
	root.set_meta(&"growth_level", level)

	var post := BoxMesh.new()
	post.size = Vector3(0.07, 1.05, 0.07)
	_piece(root, post, load(MATERIALS + "wood.tres"), Vector3(0.0, 0.52, 0.0))

	var board := BoxMesh.new()
	board.size = Vector3(1.25, 0.38, 0.05)
	var painted := StandardMaterial3D.new()
	painted.albedo_color = Color(0.243, 0.435, 0.278)
	painted.roughness = 0.8
	_piece(root, board, painted, Vector3(0.0, 0.98, 0.0))

	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.95, 0.07, 0.02)
	var cream := StandardMaterial3D.new()
	cream.albedo_color = Color(0.949, 0.925, 0.867)
	_piece(root, stripe, cream, Vector3(0.0, 0.98, 0.04))


## Show the plant the business has earned in THIS territory. Additive, exactly
## like the home yard: a quiet month never demolishes a shed.
func _apply_growth() -> void:
	var territory := get_node_or_null(^"/root/Territory")
	var presence: float = territory.call(&"presence", _region) if territory != null else 0.0
	# The four presence bands map straight on to the four levels of plant, so
	# the lot IS the standing rather than a second measure of it.
	var level := 0
	for i in ACAServiceTerritory.PRESENCE_BANDS.size():
		if presence >= float(ACAServiceTerritory.PRESENCE_BANDS[i]["at"]):
			level = mini(i, 3)
	if _growth == null:
		return
	for child in _growth.get_children():
		var node := child as Node3D
		if node == null:
			continue
		node.visible = int(node.get_meta(&"growth_level", 0)) <= level


# ==================================================================== traffic

## The town's own traffic node, handed this region's street plan.
##
## Routes are DERIVED from `roads`, one pair per through strip (or one, on a
## one-way carriageway), offset to the correct side of the centre line. So the
## four traffic profiles are four numbers over one mechanism, and no hub can put
## a car anywhere a road is not.
func _build_traffic(layout: Dictionary) -> void:
	var spec: Dictionary = layout["traffic"]
	var through: Array = []
	for strip: Dictionary in layout["roads"]:
		if not bool(strip.get("through", false)):
			continue
		var axis := String(strip["axis"])
		var at := float(strip["at"])
		var from := float(strip["from"]) - 1.4
		var to := float(strip["to"]) + 1.4
		var one_way := int(strip.get("one_way", 0))
		for direction in [1, -1]:
			if one_way != 0 and direction != one_way:
				continue
			var start := from if direction > 0 else to
			var finish := to if direction > 0 else from
			# Offset to one consistent side of the direction of travel, so two
			# cars meeting on the same street pass on opposite sides.
			var offset := LANE * float(direction)
			var a := Vector2.ZERO
			var b := Vector2.ZERO
			if axis == "x":
				a = Vector2(start, at + offset)
				b = Vector2(finish, at + offset)
			else:
				a = Vector2(at - offset, start)
				b = Vector2(at - offset, finish)
			through.append({
				"name": "%s_%d_%d" % [axis, int(at), direction],
				"corners": [a, b],
			})

	var loops: Array = []
	if spec.has("loop"):
		loops.append({"name": "block", "corners": _loop_corners(spec["loop"])})

	_traffic = ACATownTraffic.new()
	_traffic.name = "Traffic"
	_traffic.configure({
		"loops": loops,
		"through": through,
		"min_cars": int(spec.get("min_cars", 3)),
		"max_cars": int(spec.get("max_cars", 5)),
		"min_speed": float(spec.get("min_speed", 1.5)),
		"max_speed": float(spec.get("max_speed", 2.6)),
	})
	add_child(_traffic)


## A block loop is given as its four corner centre lines; this insets each one
## to the correct side so the car goes round the block rather than down the
## middle of both streets.
func _loop_corners(centres: Array) -> Array:
	var out: Array = []
	var count := centres.size()
	for i in count:
		var here: Vector2 = centres[i]
		var next: Vector2 = centres[(i + 1) % count]
		var previous: Vector2 = centres[(i - 1 + count) % count]
		var into := (next - here).normalized()
		var outof := (here - previous).normalized()
		var normal := Vector2(-into.y, into.x) + Vector2(-outof.y, outof.x)
		if normal.length() < 0.01:
			normal = Vector2(-into.y, into.x)
		out.append(here + normal.normalized() * LANE)
	return out


# ==================================================================== horizon

## WHAT IS BEYOND THE ISLAND, and the thing that turns a diorama into a place
## that continues.
##
## A far shelf sits behind and to one side of the main island, a step lower and
## in a quieter material, and carries whatever that region has on ITS horizon: a
## skyline of blank blocks, a belt of trees, or a pattern of fields. Nothing on
## the shelf is ever detailed, clickable or lit differently. It exists to be
## read at a glance and never looked at.
func _build_horizon(kind: String, layout: Dictionary) -> void:
	if kind.is_empty():
		return
	var root := Node3D.new()
	root.name = "Horizon"
	add_child(root)
	var island: Vector2 = layout["island"]
	var cz: float = float(layout["centre_z"])
	var back_z := cz - island.y * 0.5
	var half := island.x * 0.5

	var far_material := "grass_dark.tres"
	if kind == "city" or kind == "skyline":
		far_material = "concrete_dark.tres"
	# The shelf: one slab behind the island and one off its left shoulder, both
	# a step down, so the land reads as continuing rather than stopping.
	_slab(root, Vector3(island.x + 34.0, 0.5, 24.0),
		Vector3(-4.0, -1.55, back_z - 11.0), far_material)
	_slab(root, Vector3(22.0, 0.5, island.y + 14.0),
		Vector3(-half - 11.0, -1.55, cz + 2.0), far_material)

	match kind:
		"city":
			_silhouette_row(root, back_z - 6.0, -24.0, 26.0, 7, 2.4, 5.2,
				Color(0.560, 0.588, 0.620))
			_silhouette_row(root, back_z - 15.0, -26.0, 24.0, 6, 3.2, 7.0,
				Color(0.612, 0.635, 0.667))
			_tree_line(root, back_z - 19.5, -26.0, 24.0, 12, -1.3)
		"skyline":
			# THE REGIONAL CENTRE HAS A SKYLINE, and it is made of blank boxes.
			# Nothing on it has a window, a door or a material of its own: at
			# this distance a silhouette IS the building, and eight hundred
			# detailed meshes would buy nothing a player could see.
			_silhouette_row(root, back_z - 5.0, -28.0, 30.0, 9, 3.0, 7.5,
				Color(0.545, 0.576, 0.612))
			_silhouette_row(root, back_z - 12.0, -30.0, 30.0, 8, 5.0, 12.0,
				Color(0.596, 0.624, 0.663))
			_silhouette_row(root, back_z - 19.0, -30.0, 30.0, 6, 7.5, 16.0,
				Color(0.647, 0.671, 0.706))
			_silhouette_row(root, cz + 2.0, -half - 20.0, -half - 6.0, 4,
				4.0, 9.0, Color(0.596, 0.624, 0.663), true)
		"fields":
			# FIELD BANDS. Long strips in alternating greens with a hedge line
			# between them, which is what open country looks like from the air
			# and costs six slabs.
			for i in 6:
				var z := back_z - 3.0 - float(i) * 3.4
				var shade := "grass.tres" if i % 2 == 0 else "grass_dark.tres"
				if i % 3 == 2:
					shade = "dirt.tres"
				_slab(root, Vector3(island.x + 30.0, 0.16, 3.2),
					Vector3(-4.0 + _rng.randf_range(-1.5, 1.5), -1.22, z), shade)
			_tree_line(root, back_z - 5.5, -26.0, 24.0, 16, -1.15)
			_tree_line(root, back_z - 15.5, -28.0, 22.0, 13, -1.15)
			_scatter_band(root, TREES, 9, Rect2(-half - 20.0, cz - 6.0,
				10.0, island.y * 0.7), TREE_SCALE, -1.3)
			# A gentle rise on the far side, so the horizon is not a straight
			# line all the way across.
			_hill(root, Vector3(-16.0, -1.4, back_z - 21.0), Vector3(34.0, 3.4, 13.0))
			_hill(root, Vector3(14.0, -1.4, back_z - 24.0), Vector3(28.0, 4.6, 12.0))
		"forest":
			_tree_line(root, back_z - 3.0, -30.0, 28.0, 26, -1.15)
			_tree_line(root, back_z - 7.0, -30.0, 28.0, 22, -1.15)
			_tree_line(root, back_z - 11.0, -30.0, 28.0, 18, -1.15)
			_scatter_band(root, TREES_B, 16, Rect2(-half - 20.0, cz - 10.0,
				13.0, island.y * 0.8), TREE_SCALE, -1.3)
			_hill(root, Vector3(-8.0, -1.4, back_z - 17.0), Vector3(44.0, 5.0, 14.0))
			_hill(root, Vector3(20.0, -1.4, back_z - 20.0), Vector3(30.0, 6.4, 13.0))


## A row of blank boxes standing in for a block of development. `sideways` lays
## the row down the z axis instead of the x axis.
func _silhouette_row(parent: Node3D, at: float, from: float, to: float,
		count: int, low: float, high: float, tint: Color,
		sideways: bool = false) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var along := lerpf(from, to, t) + _rng.randf_range(-1.1, 1.1)
		var height := _rng.randf_range(low, high)
		var width := _rng.randf_range(3.0, 6.4)
		var depth := _rng.randf_range(3.0, 5.6)
		var at_position := Vector3(along, -1.3 + height * 0.5,
			at + _rng.randf_range(-1.0, 1.0))
		if sideways:
			at_position = Vector3(at + _rng.randf_range(-1.0, 1.0),
				-1.3 + height * 0.5, along)
		_slab_material(parent, Vector3(width, height, depth), at_position, material)


## A line of trees along an edge - a hedgerow, a shelter belt, a forest front.
func _tree_line(parent: Node3D, at: float, from: float, to: float, count: int,
		y: float) -> void:
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var x := lerpf(from, to, t) + _rng.randf_range(-0.9, 0.9)
		var source: Array = TREES if _rng.randf() < 0.6 else TREES_B
		var node := _instance(String(source[_rng.randi() % source.size()]), parent)
		if node == null:
			return
		node.position = Vector3(x, y, at + _rng.randf_range(-0.8, 0.8))
		node.rotation.y = _rng.randf_range(0.0, TAU)
		var scale := _rng.randf_range(0.82, 1.24) * TREE_SCALE
		node.scale = Vector3(scale, scale, scale)


## A low wide dome standing in for rising ground. Cheaper and softer than a mesh
## terrain, and at this distance indistinguishable from one.
func _hill(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 20
	mesh.rings = 9
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.412, 0.510, 0.404)
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.scale = size
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


# ==================================================================== scenery

## WHAT FILLS THE ISLAND ITSELF, and the second thing that makes four hubs four
## places. Every composer here draws from the same asset list; what differs is
## how much of it there is and how it is arranged.
func _build_scenery(kind: String, layout: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Scenery"
	add_child(root)
	# A HARD-SURFACED REGION STILL HAS GRASS ON IT, in the pockets between what
	# is built. Without these, a trade park renders as one unbroken slab of
	# concrete and the eye has nowhere to rest.
	for rect: Rect2 in layout.get("green", []):
		_kerbed_green(root, rect)
	match kind:
		"city":
			_compose_city(root, layout)
		"bigtown":
			_compose_big_town(root, layout)
		"rural":
			_compose_rural(root, layout)
		"park":
			_compose_park(root, layout)


## MEDIUM CITY. Buildings in every block, close together, with the street
## furniture a developed street has.
func _compose_city(root: Node3D, layout: Dictionary) -> void:
	# The block between the two streets, and the block behind the back one.
	_building_row(root, CITY_BUILDINGS, -8.8, -19.0, 19.0, 8, 0.94, 1.22)
	_building_row(root, CITY_BUILDINGS, -15.6, -19.0, 18.0, 7, 0.92, 1.16)
	# ...and a short terrace down the cross street, which is what makes the
	# corner read as a corner rather than as two roads that happen to meet.
	_building_column(root, CITY_BUILDINGS, 12.0, -14.0, -7.0, 3, 0.9, 1.1)

	_street_furniture(root, 4)
	_lamp_run(root, "x", -3.6, -18.0, 18.0, 7)
	_lamp_run(root, "x", -13.4, -18.0, 18.0, 6)
	_prop(root, TRAFFIC_LIGHT, Vector3(6.4, 0.1, -3.4), 0.0, 1.0, 0)
	_prop(root, TRAFFIC_LIGHT, Vector3(9.6, 0.1, -6.6), PI, 1.0, 0)
	for i in 5:
		_prop(root, PLANTER, Vector3(-16.0 + float(i) * 4.2, 0.1, -3.5), 0.0, 1.0, 0)
	_prop(root, BENCH, Vector3(-3.0, 0.28, 4.4), PI, BENCH_SCALE, 0)
	_prop(root, BENCH, Vector3(1.0, 0.28, 4.4), PI, BENCH_SCALE, 0)
	_scatter(root, BUSHES, 14, BUSH_SCALE)
	_scatter(root, TREES, 11, TREE_SCALE)


## BIG TOWN. Bigger blocks, more of them, a planted central median, and a civic
## frontage on a raised plaza.
func _compose_big_town(root: Node3D, layout: Dictionary) -> void:
	# THE MEDIAN. The arterial's two carriageways are at -8.4 and -5.2, so the
	# strip between them is 1.2 wide and centred on -6.8. Planting it is what
	# tells the player this is a dual carriageway rather than two streets.
	_slab(root, Vector3(48.0, 0.12, 1.2), Vector3(0.0, 0.06, -6.8),
		"concrete_dark.tres")
	for i in 11:
		var x := -22.0 + float(i) * 4.4
		if absf(x + 10.0) < 2.6 or absf(x - 14.0) < 2.6:
			continue
		if i % 2 == 0:
			_prop(root, PLANTER, Vector3(x, 0.14, -6.8), 0.0, 1.0, 0)
		else:
			_prop(root, LAMP, Vector3(x, 0.14, -6.8), 0.0, 1.0, 0)

	# The commercial blocks between the arterial and the back street, at a
	# larger scale than Medium City's: the same models, standing bigger.
	_building_row(root, CITY_BUILDINGS, -12.4, -24.0, 24.0, 9, 1.06, 1.42)
	_building_row(root, CITY_BUILDINGS, -19.6, -24.0, 22.0, 8, 1.02, 1.34)
	_building_column(root, CITY_BUILDINGS, 18.5, -19.0, -10.0, 3, 1.0, 1.25)
	_building_column(root, CITY_BUILDINGS, -14.5, -19.0, -11.0, 2, 1.0, 1.25)

	# The plaza's own furniture. It is raised 0.16, so everything on it is too.
	for i in 6:
		_prop(root, PLANTER, Vector3(-19.0 + float(i) * 4.4, 0.26, 2.2), 0.0, 1.0, 0)
	_prop(root, BENCH, Vector3(-12.0, 0.26, 2.6), PI, BENCH_SCALE, 0)
	_prop(root, BENCH, Vector3(-3.0, 0.26, 2.6), PI, BENCH_SCALE, 0)
	_prop(root, TRASH, Vector3(-7.6, 0.26, 2.6), 0.0, 1.0, 0)

	_street_furniture(root, 6)
	_lamp_run(root, "x", -17.6, -23.0, 23.0, 8)
	_lamp_run(root, "z", -12.4, -18.0, 10.0, 5)
	_lamp_run(root, "z", 16.4, -18.0, 10.0, 5)
	_prop(root, TRAFFIC_LIGHT, Vector3(-12.2, 0.1, -3.6), 0.0, 1.0, 0)
	_prop(root, TRAFFIC_LIGHT, Vector3(16.2, 0.1, -3.6), 0.0, 1.0, 0)
	_prop(root, TRAFFIC_LIGHT, Vector3(-7.8, 0.1, -10.0), PI, 1.0, 0)
	_prop(root, BENCH, Vector3(-4.0, 0.28, 8.2), PI, BENCH_SCALE, 0)
	_prop(root, BENCH, Vector3(2.0, 0.28, 8.2), PI, BENCH_SCALE, 0)
	_prop(root, TRASH, Vector3(-1.0, 0.28, 8.4), 0.0, 1.0, 0)
	_scatter(root, BUSHES, 18, BUSH_SCALE)
	_scatter(root, TREES, 15, TREE_SCALE)


## RURAL HIGHWAY. Almost nothing built, and everything that IS built is low. The
## work is done by the fields, the fence lines and the sheer amount of open
## ground between one thing and the next.
func _compose_rural(root: Node3D, layout: Dictionary) -> void:
	# A barn and a couple of outbuildings on the lot, low and wide.
	_prop_mesh(root, HOUSE_1_ROUND, Vector3(13.6, 0.1, -2.2), -0.35, 1.0)
	_prop_mesh(root, HOUSE_1, Vector3(-19.4, 0.1, -1.0), 0.28, 0.9)
	_prop_mesh(root, HOUSE_1_GABLE, Vector3(20.6, 0.1, 2.6), 0.5, 0.85)
	_prop(root, WATER_TOWER, Vector3(-22.0, 0.1, -6.4), 0.4, 1.0, 0)

	# THE FIELD PATTERN ON THE ISLAND ITSELF, so the near ground agrees with the
	# horizon rather than being a lawn with fields painted behind it.
	_field_band(root, Rect2(-25.0, 6.5, 20.0, 6.0), "grass_dark.tres")
	var ploughed := Rect2(-3.0, 7.0, 26.0, 5.4)
	_field_band(root, ploughed, "dirt.tres")
	_crop_rows(root, ploughed, 7)
	_reserve(ploughed)
	_field_band(root, Rect2(14.0, -8.0, 12.0, 6.0), "grass_dark.tres")

	# Fence lines. A field boundary running away from the camera is the cheapest
	# thing in the game that says "this is farmland".
	_fence_run(root, "z", 12.0, -7.0, 5.0, 6)
	_fence_run(root, "z", -18.0, -7.6, 4.4, 6)
	_fence_run(root, "x", 5.6, -25.0, -5.0, 10)
	_fence_run(root, "x", 12.4, 4.0, 24.0, 10)

	# Roadside furniture: a highway has almost none, which is the point.
	_prop(root, LAMP, Vector3(-4.2, 0.1, -7.6), 0.0, 1.0, 0)
	_prop(root, LAMP, Vector3(16.0, 0.1, -7.6), 0.0, 1.0, 0)
	_hay_bales(root, Vector3(19.0, 0.1, 9.0), 5)
	_hay_bales(root, Vector3(-23.0, 0.1, 4.0), 3)

	_scatter(root, TREES, 30, TREE_SCALE)
	_scatter(root, BUSHES, 26, BUSH_SCALE)
	_scatter(root, ROCKS, 14, ROCK_SCALE)
	_scatter(root, TUFTS, 44, 0.5)


## COUNTRY PARKS. The compound is in one corner and everything else is park: a
## pond, trails, groves, meadow and a forest front. This is the hub that is
## supposed to be worth looking at.
func _compose_park(root: Node3D, layout: Dictionary) -> void:
	_pond(root, Vector3(9.0, 0.0, 2.0), Vector2(17.0, 10.5))

	# THE TRAIL NETWORK. Thin light strips laid end to end along a polyline,
	# which from this camera is a path. It also does the job of breaking the
	# grass up, which is what stops a large green area reading as one lawn.
	_trail(root, [Vector2(-4.0, -11.0), Vector2(-1.0, -6.0), Vector2(1.0, -1.0),
		Vector2(-1.5, 4.5), Vector2(-4.0, 9.0), Vector2(-3.0, 13.0)])
	_trail(root, [Vector2(0.5, -2.0), Vector2(6.0, -4.5), Vector2(13.0, -5.0),
		Vector2(20.0, -3.0), Vector2(24.0, 1.5), Vector2(22.5, 8.0)])
	_trail(root, [Vector2(-14.0, 4.0), Vector2(-9.0, 5.5), Vector2(-4.0, 6.0)])

	_grove(root, Vector3(-8.0, 0.0, -8.0), 7.0, 8)
	_grove(root, Vector3(17.0, 0.0, -9.0), 6.5, 7)
	_grove(root, Vector3(-16.0, 0.0, 8.0), 5.5, 6)
	_grove(root, Vector3(25.0, 0.0, 9.0), 5.0, 6)

	# MEADOW. Long grass that is not cut, which is a thing this game has an
	# opinion about - and here it is scenery rather than a rule.
	#
	# Drawn as OVERLAPPING DISCS rather than as rectangles: a hard-edged green
	# rectangle in the middle of a park reads as a texture error, and three
	# circles that touch read as a patch of ground somebody decided to leave.
	_meadow(root, Vector3(-22.0, 0.0, 9.0), Vector2(15.0, 8.0))
	_meadow(root, Vector3(8.0, 0.0, -9.5), Vector2(16.0, 6.5))
	_scatter(root, TUFTS, 52, 0.62)

	_prop(root, PARK_STRUCTURE, Vector3(-9.5, 0.1, 9.5), 0.35, 1.0, 0)
	for entry in [[Vector3(-2.0, 0.1, 2.0), 0.6], [Vector3(3.5, 0.1, -3.6), -1.2],
			[Vector3(21.0, 0.1, 4.5), 2.2], [Vector3(-4.5, 0.1, 11.5), 0.0]]:
		_prop(root, BENCH, entry[0], float(entry[1]), BENCH_SCALE, 0)
	_prop(root, TRASH, Vector3(-2.9, 0.1, 2.9), 0.0, 1.0, 0)
	_prop(root, TRASH, Vector3(20.4, 0.1, 5.3), 0.0, 1.0, 0)
	for i in 4:
		_prop(root, PLANTER, Vector3(-21.0 + float(i) * 3.4, 0.1, -5.4), 0.0, 1.0, 0)
	_lamp_run(root, "x", -11.4, -22.0, 22.0, 6)

	_scatter(root, TREES, 30, TREE_SCALE)
	_scatter(root, TREES_B, 18, TREE_SCALE)
	_scatter(root, BUSHES, 30, BUSH_SCALE)
	_scatter(root, ROCKS, 12, ROCK_SCALE)


# ------------------------------------------------------------ scenery parts

## A row of buildings along the x axis at a fixed z, at a scale range that is
## the region's own. The SAME MODELS at 1.42 in Big Town and 1.22 in Medium City
## is most of why one of them feels bigger than the other.
func _building_row(parent: Node3D, models: Array, z: float, from: float,
		to: float, count: int, low: float, high: float) -> void:
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var x := lerpf(from, to, t) + _rng.randf_range(-0.7, 0.7)
		var node := _building_model(String(models[_rng.randi() % models.size()]))
		if node == null:
			continue
		parent.add_child(node)
		node.position = Vector3(x, 0.05, z + _rng.randf_range(-0.5, 0.5))
		node.rotation.y = _rng.randf_range(-0.09, 0.09)
		var scale := _rng.randf_range(low, high)
		node.scale = node.scale * scale
		_building_pad(parent, node.position, scale)
		_reserve(Rect2(x - 2.2 * scale, z - 2.2 * scale,
			4.4 * scale, 4.4 * scale))


func _building_column(parent: Node3D, models: Array, x: float, from: float,
		to: float, count: int, low: float, high: float) -> void:
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var z := lerpf(from, to, t) + _rng.randf_range(-0.6, 0.6)
		var node := _building_model(String(models[_rng.randi() % models.size()]))
		if node == null:
			continue
		parent.add_child(node)
		node.position = Vector3(x + _rng.randf_range(-0.5, 0.5), 0.05, z)
		node.rotation.y = PI * 0.5 + _rng.randf_range(-0.09, 0.09)
		var scale := _rng.randf_range(low, high)
		node.scale = node.scale * scale
		_building_pad(parent, node.position, scale)
		_reserve(Rect2(x - 2.2 * scale, z - 2.2 * scale,
			4.4 * scale, 4.4 * scale))


## The plot a backdrop building stands on, in a darker surface than the ground
## around it. The Business Town does exactly this under its own shops, and it is
## what stops a district of thirty buildings reading as thirty objects floating
## on one unbroken field of concrete.
func _building_pad(parent: Node3D, at: Vector3, scale: float) -> void:
	var size := 4.3 * clampf(scale, 0.85, 1.5)
	_slab(parent, Vector3(size, 0.05, size), Vector3(at.x, 0.03, at.z),
		"concrete_dark.tres")


## Bins and hydrants, at a density the region chooses. Present everywhere a
## street is, absent where one is not.
func _street_furniture(parent: Node3D, count: int) -> void:
	for i in count:
		_prop(parent, HYDRANT, Vector3(-18.0 + float(i) * 6.4, 0.1, -3.4),
			0.0, HYDRANT_SCALE, 0)
	for i in maxi(count - 2, 1):
		_prop(parent, TRASH, Vector3(-14.0 + float(i) * 7.8, 0.1, -3.6),
			_rng.randf_range(0.0, TAU), 1.0, 0)


func _lamp_run(parent: Node3D, axis: String, at: float, from: float, to: float,
		count: int) -> void:
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var along := lerpf(from, to, t)
		var position := Vector3(along, 0.1, at) if axis == "x" \
			else Vector3(at, 0.1, along)
		_prop(parent, LAMP, position, 0.0 if axis == "x" else PI * 0.5, 1.0, 0)


func _fence_run(parent: Node3D, axis: String, at: float, from: float, to: float,
		count: int) -> void:
	for i in count:
		var t := float(i) / float(maxi(count - 1, 1))
		var along := lerpf(from, to, t)
		var position := Vector3(along, 0.1, at) if axis == "x" \
			else Vector3(at, 0.1, along)
		_prop(parent, FENCE, position, 0.0 if axis == "x" else PI * 0.5, 1.0, 0)


## A planted square in a hard-surfaced district: grass with a raised kerb round
## it. THE KERB IS THE WHOLE POINT - a green rectangle painted straight on to
## concrete reads as a texture fault, and the same rectangle with a kerb reads
## as a square somebody laid out.
func _kerbed_green(parent: Node3D, rect: Rect2) -> void:
	var kerb := StandardMaterial3D.new()
	kerb.albedo_color = Color(0.729, 0.722, 0.694)
	kerb.roughness = 1.0
	kerb.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var outer := rect.grow(0.32)
	_slab_material(parent, Vector3(outer.size.x, 0.16, outer.size.y),
		Vector3(outer.position.x + outer.size.x * 0.5, 0.08,
			outer.position.y + outer.size.y * 0.5), kerb)
	_slab(parent, Vector3(rect.size.x, 0.19, rect.size.y),
		Vector3(rect.position.x + rect.size.x * 0.5, 0.085,
			rect.position.y + rect.size.y * 0.5), "grass.tres")


## A shallow patch of a different ground in the middle of the ground. Four
## hundredths above the island's surface, which is enough to win the depth test
## and not enough to see an edge on.
func _field_band(parent: Node3D, rect: Rect2, material: String) -> void:
	_slab(parent, Vector3(rect.size.x, 0.06, rect.size.y),
		Vector3(rect.position.x + rect.size.x * 0.5, 0.04,
			rect.position.y + rect.size.y * 0.5), material)


## Furrows across a bare-earth band. Six thin darker strips is the whole of it,
## and it is the difference between "a ploughed field" and "an unexplained brown
## rectangle in the middle of a lawn".
func _crop_rows(parent: Node3D, rect: Rect2, count: int) -> void:
	var furrow := StandardMaterial3D.new()
	furrow.albedo_color = Color(0.400, 0.318, 0.239)
	furrow.roughness = 1.0
	furrow.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var z := rect.position.y + t * rect.size.y
		_slab_material(parent, Vector3(rect.size.x - 1.0, 0.03, 0.34),
			Vector3(rect.position.x + rect.size.x * 0.5, 0.075, z), furrow)


func _hay_bales(parent: Node3D, at: Vector3, count: int) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.847, 0.741, 0.435)
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for i in count:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.42
		mesh.bottom_radius = 0.42
		mesh.height = 0.66
		mesh.radial_segments = 10
		mesh.rings = 1
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		instance.position = at + Vector3(_rng.randf_range(-2.4, 2.4), 0.33,
			_rng.randf_range(-1.6, 1.6))
		instance.rotation = Vector3(0.0, _rng.randf_range(0.0, TAU), PI * 0.5)
		parent.add_child(instance)


## A pond: a dark bank cut into the grass, and a water surface just inside it.
## No reflection probe and no shader - a flat translucent disc under this camera
## is a pond, and anything more is spending a frame budget on scenery.
## A patch of uncut grass, as overlapping discs so it has no straight edges.
func _meadow(parent: Node3D, at: Vector3, size: Vector2) -> void:
	var material := load(MATERIALS + "grass_dark.tres")
	for i in 3:
		var offset := Vector3(_rng.randf_range(-0.30, 0.30) * size.x, 0.0,
			_rng.randf_range(-0.22, 0.22) * size.y)
		var lobe := size * _rng.randf_range(0.62, 0.86)
		_disc(parent, at + offset + Vector3(0.0, 0.035, 0.0), lobe, material)


## A pond. Three overlapping lobes of bank with three of water just inside
## them, so the shore is a shape rather than an ellipse, and a fringe of reeds
## round the outside.
##
## No reflection probe and no shader: a flat translucent surface under this
## camera IS a pond, and anything more is spending a frame budget on scenery.
func _pond(parent: Node3D, at: Vector3, size: Vector2) -> void:
	_reserve(Rect2(at.x - size.x * 0.6, at.z - size.y * 0.6,
		size.x * 1.2, size.y * 1.2))
	var bank := StandardMaterial3D.new()
	bank.albedo_color = Color(0.412, 0.384, 0.318)
	bank.roughness = 1.0
	bank.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	var water := StandardMaterial3D.new()
	# Read off the sky rather than picked: a pond is mostly the sky in it, and
	# a saturated blue disc on green grass is the one colour that never happens
	# outdoors.
	water.albedo_color = Color(0.325, 0.443, 0.478, 0.90)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.10
	water.metallic = 0.35
	water.metallic_specular = 0.90

	var lobes := [
		{"offset": Vector3(0.0, 0.0, 0.0), "scale": 1.0},
		{"offset": Vector3(size.x * 0.26, 0.0, -size.y * 0.16), "scale": 0.68},
		{"offset": Vector3(-size.x * 0.24, 0.0, size.y * 0.19), "scale": 0.60},
	]
	for lobe: Dictionary in lobes:
		var span: Vector2 = size * float(lobe["scale"])
		_disc(parent, at + lobe["offset"] + Vector3(0.0, 0.04, 0.0), span, bank)
	for lobe: Dictionary in lobes:
		var span: Vector2 = size * float(lobe["scale"]) - Vector2(1.5, 1.1)
		_disc(parent, at + lobe["offset"] + Vector3(0.0, 0.09, 0.0), span, water)

	# Reeds and a rock or two at the edge.
	for i in 22:
		var angle := _rng.randf_range(0.0, TAU)
		var edge := at + Vector3(cos(angle) * size.x * 0.5,
			0.06, sin(angle) * size.y * 0.5)
		var source: Array = TUFTS if _rng.randf() < 0.7 else BUSHES
		var node := _instance(String(source[_rng.randi() % source.size()]), parent)
		if node == null:
			return
		node.position = edge
		node.rotation.y = _rng.randf_range(0.0, TAU)
		var scale := _rng.randf_range(0.7, 1.25) * 0.5
		node.scale = Vector3(scale, scale, scale)


func _disc(parent: Node3D, at: Vector3, size: Vector2, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 0.08
	mesh.radial_segments = 28
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.scale = Vector3(size.x, 1.0, size.y)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


## A path, as a run of short slabs laid along a polyline. Each segment is
## rotated to its own direction, so a bend is a bend rather than a corner.
func _trail(parent: Node3D, points: Array) -> void:
	var material := load(MATERIALS + "concrete.tres")
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var mid := (a + b) * 0.5
		var span := b - a
		var mesh := BoxMesh.new()
		mesh.size = Vector3(span.length() + 0.5, 0.06, 1.25)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		instance.position = Vector3(mid.x, 0.045, mid.y)
		instance.rotation.y = -atan2(span.y, span.x)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)
		_reserve(Rect2(minf(a.x, b.x) - 0.9, minf(a.y, b.y) - 0.9,
			absf(span.x) + 1.8, absf(span.y) + 1.8))


## A cluster of trees rather than an even scatter. Woodland grows in groups, and
## a park with its trees spaced evenly reads as an orchard.
func _grove(parent: Node3D, at: Vector3, radius: float, count: int) -> void:
	for i in count:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := sqrt(_rng.randf()) * radius
		var position := at + Vector3(cos(angle) * distance, 0.05,
			sin(angle) * distance * 0.8)
		if _occupied(Vector2(position.x, position.z)):
			continue
		var source: Array = TREES if _rng.randf() < 0.55 else TREES_B
		var node := _instance(String(source[_rng.randi() % source.size()]), parent)
		if node == null:
			return
		node.position = position
		node.rotation.y = _rng.randf_range(0.0, TAU)
		var scale := _rng.randf_range(0.8, 1.3) * TREE_SCALE
		node.scale = Vector3(scale, scale, scale)
	for i in maxi(count / 2, 1):
		var angle := _rng.randf_range(0.0, TAU)
		var distance := sqrt(_rng.randf()) * radius * 1.15
		var position := at + Vector3(cos(angle) * distance, 0.05,
			sin(angle) * distance * 0.8)
		if _occupied(Vector2(position.x, position.z)):
			continue
		var node := _instance(String(BUSHES[_rng.randi() % BUSHES.size()]), parent)
		if node == null:
			return
		node.position = position
		node.rotation.y = _rng.randf_range(0.0, TAU)
		var scale := _rng.randf_range(0.85, 1.25) * BUSH_SCALE
		node.scale = Vector3(scale, scale, scale)


## SCENERY GOES WHERE THE REGION SAYS THERE IS OPEN GROUND, and never on
## anything already built.
##
## An early render of these hubs had trees standing on the apron and in front of
## two of the three buildings, because "outside" was expressed as a distance
## from the centre and the plot is a long rectangle rather than a circle. The
## next one had trees only where a single hand-written rectangle allowed them,
## and half of every island came out bare.
##
## So it is expressed twice over: the layout's `plant` rectangles say where a
## region HAS open ground, and `_forbidden` - derived from the roads, the
## aprons, the buildings and the water - says what is already standing on it.
func _scatter(parent: Node3D, sources: Array, count: int, scale_bias: float) -> void:
	_scatter_at(parent, sources, count, scale_bias, 0.05)


func _scatter_at(parent: Node3D, sources: Array, count: int, scale_bias: float,
		y: float) -> void:
	if sources.is_empty() or _plant.is_empty():
		return
	var total := 0.0
	for rect in _plant:
		total += rect.size.x * rect.size.y
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 24:
		attempts += 1
		var pick := _rng.randf() * total
		var area: Rect2 = _plant[0]
		for rect in _plant:
			pick -= rect.size.x * rect.size.y
			area = rect
			if pick <= 0.0:
				break
		var at := Vector3(
			_rng.randf_range(area.position.x, area.position.x + area.size.x), y,
			_rng.randf_range(area.position.y, area.position.y + area.size.y))
		if _occupied(Vector2(at.x, at.z)):
			continue
		var node := _instance(String(sources[_rng.randi() % sources.size()]), parent)
		if node == null:
			return
		node.position = at
		node.rotation.y = _rng.randf_range(0.0, TAU)
		var scale := _rng.randf_range(0.85, 1.2) * scale_bias
		node.scale = Vector3(scale, scale, scale)
		placed += 1


## The horizon's own scatter, which is BEYOND the island and therefore beyond
## everything the forbidden set is about.
func _scatter_band(parent: Node3D, sources: Array, count: int, area: Rect2,
		scale_bias: float, y: float) -> void:
	if sources.is_empty():
		return
	for i in count:
		var at := Vector3(
			_rng.randf_range(area.position.x, area.position.x + area.size.x), y,
			_rng.randf_range(area.position.y, area.position.y + area.size.y))
		var node := _instance(String(sources[_rng.randi() % sources.size()]), parent)
		if node == null:
			return
		node.position = at
		node.rotation.y = _rng.randf_range(0.0, TAU)
		var scale := _rng.randf_range(0.85, 1.2) * scale_bias
		node.scale = Vector3(scale, scale, scale)


# ====================================================================== parts

func _slab(parent: Node3D, size: Vector3, at: Vector3, material: String) -> void:
	_slab_material(parent, size, at, load(MATERIALS + material))


func _slab_material(parent: Node3D, size: Vector3, at: Vector3,
		material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	if material != null:
		instance.material_override = material
	parent.add_child(instance)


func _prop(parent: Node3D, path: String, at: Vector3, yaw: float,
		scale: float, level: int) -> void:
	var node := _instance(path, parent)
	if node == null:
		return
	node.position = at
	node.rotation.y = yaw
	node.scale = Vector3(scale, scale, scale)
	node.set_meta(&"growth_level", level)


## A Quaternius OBJ standing on the ground as scenery rather than as a
## destination. Same mesh, same paint, no interaction area.
func _prop_mesh(parent: Node3D, path: String, at: Vector3, yaw: float,
		scale: float) -> void:
	var node := _building_model(path)
	if node == null:
		return
	parent.add_child(node)
	node.position = at
	node.rotation.y = yaw
	node.scale = node.scale * scale


func _instance(path: String, parent: Node3D) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("[HUB] could not load %s" % path)
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		return null
	parent.add_child(node)
	return node


func _piece(parent: Node3D, mesh: Mesh, material: Material, at: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	if material != null:
		instance.material_override = material
	parent.add_child(instance)
