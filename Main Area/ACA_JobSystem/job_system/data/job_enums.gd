class_name ACAJobEnums
extends RefCounted
## Shared vocabulary for the portable Job System.
##
## Enums plus their player-facing strings. Nothing here reaches outside
## res://ACA_JobSystem/ and nothing here holds runtime state.


## Contract lifecycle. GENERATED exists only for the instant between the
## generator returning a job and the manager publishing it to the market.
enum Status {
	GENERATED,
	AVAILABLE,
	ACCEPTED,
	IN_PROGRESS,
	COMPLETED,
	EXPIRED,
}

## Grid dimensions live in ACAJobBalance.LAWN_GRID. TINY and HUGE are reserved:
## V1 generation never rolls them (see ACAJobBalance.GENERATED_LAWN_SIZES).
enum LawnSize {
	TINY,
	SMALL,
	MEDIUM,
	LARGE,
	HUGE,
}

## Presentation/flavour only in V1 - property type must not affect pay.
enum PropertyType {
	RESIDENTIAL,
	COMMERCIAL,
	PUBLIC,
	COMMUNITY,
	RURAL,
	INSTITUTIONAL,
	INDUSTRIAL,
	HOSPITALITY,
}

enum Season { SPRING, SUMMER, AUTUMN, WINTER }

enum Economy { RECESSION, SLOW, NORMAL, BOOMING }

enum Climate { WET, NORMAL, DRY, DROUGHT }


const STATUS_NAMES := {
	Status.GENERATED: "Generated",
	Status.AVAILABLE: "Available",
	Status.ACCEPTED: "Accepted",
	Status.IN_PROGRESS: "In Progress",
	Status.COMPLETED: "Completed",
	Status.EXPIRED: "Expired",
}

## Player-facing lawn size wording. The raw grid dimension (96x96, 144x144,
## 192x192) is deliberately never shown to the player.
const LAWN_SIZE_NAMES := {
	LawnSize.TINY: "Tiny Lawn",
	LawnSize.SMALL: "Small Lawn",
	LawnSize.MEDIUM: "Medium Lawn",
	LawnSize.LARGE: "Large Lawn",
	LawnSize.HUGE: "Huge Lawn",
}

const PROPERTY_TYPE_NAMES := {
	PropertyType.RESIDENTIAL: "Residential",
	PropertyType.COMMERCIAL: "Commercial",
	PropertyType.PUBLIC: "Public",
	PropertyType.COMMUNITY: "Community",
	PropertyType.RURAL: "Rural",
	PropertyType.INSTITUTIONAL: "Institutional",
	PropertyType.INDUSTRIAL: "Industrial",
	PropertyType.HOSPITALITY: "Hospitality",
}

const SEASON_NAMES := {
	Season.SPRING: "Spring",
	Season.SUMMER: "Summer",
	Season.AUTUMN: "Autumn",
	Season.WINTER: "Winter",
}

const ECONOMY_NAMES := {
	Economy.RECESSION: "Recession",
	Economy.SLOW: "Slow",
	Economy.NORMAL: "Normal",
	Economy.BOOMING: "Booming",
}

const CLIMATE_NAMES := {
	Climate.WET: "Wet",
	Climate.NORMAL: "Normal",
	Climate.DRY: "Dry",
	Climate.DROUGHT: "Drought",
}


static func status_name(value: int) -> String:
	return STATUS_NAMES.get(value, "Unknown")


static func lawn_size_name(value: int) -> String:
	return LAWN_SIZE_NAMES.get(value, "Lawn")


static func property_type_name(value: int) -> String:
	return PROPERTY_TYPE_NAMES.get(value, "Property")


static func season_name(value: int) -> String:
	return SEASON_NAMES.get(value, "Spring")


static func economy_name(value: int) -> String:
	return ECONOMY_NAMES.get(value, "Normal")


static func climate_name(value: int) -> String:
	return CLIMATE_NAMES.get(value, "Normal")
