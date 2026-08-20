class_name ACACreditsLoader
extends RefCounted
## Scans one folder for credit / licence text files and turns them into entries.
##
## ADDING A CREDIT IS A FILE COPY. Drop a text file into the folder below,
## named `<Name_Of_Thing>_licence.txt`, and it appears in the Credits screen.
## No code change, no list to update, no scene to edit.
##
##     Sky3D_licence.txt        ->  "Sky3D"
##     Kenney_Assets_licence.txt->  "Kenney Assets"
##
## The BODY OF THE FILE IS THE CREDIT and is displayed verbatim. Never
## summarise, reword or reformat licence text - copy it in whole.

# ---------------------------------------------------------------- THE folder
## THE one configured path. Change it here and nowhere else.
const CREDITS_DIRECTORY := "res://Credits"

## Recognised name endings, checked case-insensitively. `_licence` is the
## project convention; the rest are accepted so a file dropped in with the
## American spelling or a "credits" name still shows up.
const RECOGNISED_SUFFIXES: PackedStringArray = [
	"_licence", "_license", "_credit", "_credits",
]

## Only these extensions are considered. Anything else in the folder - a
## README.md, an image, a stray .import - is ignored.
const RECOGNISED_EXTENSIONS: PackedStringArray = ["txt", "md"]


## Every credit in `directory`, sorted deterministically by display title
## (case-insensitive), then by file name so two identical titles never swap.
##
## Returns an Array of Dictionaries: `{ title: String, file: String, path: String }`.
## The text itself is NOT read here - call `load_text()` for the selected entry,
## so a folder with a hundred licences costs one directory listing.
static func list_entries(directory: String = CREDITS_DIRECTORY) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		push_warning("ACACreditsLoader: cannot open %s" % directory)
		return entries

	for file_name in dir.get_files():
		# Exported builds can hand back the import artefact instead.
		var clean := file_name.trim_suffix(".remap").trim_suffix(".import")
		if not is_credit_file(clean):
			continue
		entries.append({
			"title": title_from_filename(clean),
			"file": clean,
			"path": directory.path_join(clean),
		})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var at: String = String(a["title"]).to_lower()
		var bt: String = String(b["title"]).to_lower()
		if at == bt:
			return String(a["file"]) < String(b["file"])
		return at < bt)
	return entries


## True when this file name follows the convention. Unrelated files are ignored.
static func is_credit_file(file_name: String) -> bool:
	if not RECOGNISED_EXTENSIONS.has(file_name.get_extension().to_lower()):
		return false
	var stem := file_name.get_basename().to_lower()
	for suffix in RECOGNISED_SUFFIXES:
		# The suffix has to be a real suffix AND leave a name behind, so a file
		# literally called "licence.txt" is not treated as a credit for "".
		if stem.ends_with(suffix) and stem.length() > suffix.length():
			return true
	return false


## `Kenney_Assets_licence.txt` -> `Kenney Assets`.
static func title_from_filename(file_name: String) -> String:
	var stem := file_name.get_basename()
	var lower := stem.to_lower()
	for suffix in RECOGNISED_SUFFIXES:
		if lower.ends_with(suffix) and lower.length() > suffix.length():
			stem = stem.substr(0, stem.length() - suffix.length())
			break
	stem = stem.replace("_", " ").replace("-", " ").strip_edges()
	# Collapse runs of spaces left by names like `Some__Pack_licence.txt`.
	while stem.contains("  "):
		stem = stem.replace("  ", " ")
	return stem


## The file's contents, exactly as written. Empty string if it cannot be read -
## the caller shows that as a problem rather than inventing text.
static func load_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ACACreditsLoader: cannot read %s" % path)
		return ""
	var text := file.get_as_text()
	file.close()
	return text
