class_name ACAJobCatalog
extends RefCounted
## Job site names and the lawn sizes each property type can produce.
##
## Deliberately simple pools - no weighting system. Edit the arrays to change
## what the market can offer. Site names stay generic: no personal customer
## names and no fictional business names.

const SITE_NAMES := {
	ACAJobEnums.PropertyType.RESIDENTIAL: [
		"Suburban Home",
		"Corner House",
		"Residential Property",
		"Large Residential Lot",
		"Townhouse Grounds",
	],
	ACAJobEnums.PropertyType.COMMERCIAL: [
		"Convenience Store Grounds",
		"Small Office Grounds",
		"Local Shop Grounds",
		"Roadside Business",
		"Commercial Property",
	],
	ACAJobEnums.PropertyType.PUBLIC: [
		"Local Park",
		"Neighborhood Green",
		"Playground Grounds",
		"Public Green Space",
	],
	ACAJobEnums.PropertyType.COMMUNITY: [
		"Community Hall Grounds",
		"Recreation Centre Grounds",
		"Local Library Grounds",
		"Community Garden Perimeter",
	],
	ACAJobEnums.PropertyType.RURAL: [
		"Rural Property",
		"Country Home",
		"Farmhouse Lawn",
		"Rural Roadside Property",
	],
	ACAJobEnums.PropertyType.INSTITUTIONAL: [
		"School Grounds",
		"Daycare Grounds",
		"Clinic Grounds",
		"Institutional Property",
	],
	ACAJobEnums.PropertyType.INDUSTRIAL: [
		"Warehouse Grounds",
		"Workshop Property",
		"Storage Facility Grounds",
		"Light Industrial Lot",
	],
	ACAJobEnums.PropertyType.HOSPITALITY: [
		"Motel Grounds",
		"Campground Common Area",
		"Roadside Inn Grounds",
		"Event Venue Grounds",
	],
}

## Which lawn sizes each property type may produce.
const SIZE_POOLS := {
	ACAJobEnums.PropertyType.RESIDENTIAL: [
		ACAJobEnums.LawnSize.SMALL, ACAJobEnums.LawnSize.MEDIUM,
	],
	ACAJobEnums.PropertyType.COMMERCIAL: [
		ACAJobEnums.LawnSize.SMALL, ACAJobEnums.LawnSize.MEDIUM,
	],
	ACAJobEnums.PropertyType.PUBLIC: [
		ACAJobEnums.LawnSize.MEDIUM, ACAJobEnums.LawnSize.LARGE,
	],
	ACAJobEnums.PropertyType.COMMUNITY: [
		ACAJobEnums.LawnSize.SMALL, ACAJobEnums.LawnSize.MEDIUM, ACAJobEnums.LawnSize.LARGE,
	],
	ACAJobEnums.PropertyType.RURAL: [
		ACAJobEnums.LawnSize.MEDIUM, ACAJobEnums.LawnSize.LARGE,
	],
	ACAJobEnums.PropertyType.INSTITUTIONAL: [
		ACAJobEnums.LawnSize.MEDIUM, ACAJobEnums.LawnSize.LARGE,
	],
	ACAJobEnums.PropertyType.INDUSTRIAL: [
		ACAJobEnums.LawnSize.SMALL, ACAJobEnums.LawnSize.MEDIUM, ACAJobEnums.LawnSize.LARGE,
	],
	ACAJobEnums.PropertyType.HOSPITALITY: [
		ACAJobEnums.LawnSize.MEDIUM, ACAJobEnums.LawnSize.LARGE,
	],
}

## Property types V1 generation may roll, in a stable order. The generator
## indexes this array, so reordering it changes what a given seed produces.
const GENERATED_PROPERTY_TYPES: Array[int] = [
	ACAJobEnums.PropertyType.RESIDENTIAL,
	ACAJobEnums.PropertyType.COMMERCIAL,
	ACAJobEnums.PropertyType.PUBLIC,
	ACAJobEnums.PropertyType.COMMUNITY,
	ACAJobEnums.PropertyType.RURAL,
	ACAJobEnums.PropertyType.INSTITUTIONAL,
	ACAJobEnums.PropertyType.INDUSTRIAL,
	ACAJobEnums.PropertyType.HOSPITALITY,
]


static func site_names(property_type: int) -> Array:
	return SITE_NAMES.get(property_type, ["Property"])


static func size_pool(property_type: int) -> Array:
	return SIZE_POOLS.get(property_type, ACAJobBalance.GENERATED_LAWN_SIZES)
