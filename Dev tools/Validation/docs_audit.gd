extends SceneTree
## DEVELOPMENT ONLY. Checks the documentation against the repository.
##
##   godot --headless --path <project> \
##     --script "res://Dev tools/Validation/docs_audit.gd"
##
## Documentation rots silently. A `res://` path in a Markdown file is a CLAIM
## about the repository, and nothing checks it — so a file can be renamed and
## every page that mentions it quietly becomes a lie. This is small on purpose:
## it verifies claims that are mechanically checkable and says nothing about
## whether the prose is any good.
##
## What it checks:
##   1. every `res://` path mentioned in a doc exists;
##   2. every relative Markdown link resolves to a real file;
##   3. every page listed in `mkdocs.yml` exists, and every page exists in the nav;
##   4. no page still mentions a class or path this build removed.

const DOC_DIRS: PackedStringArray = ["res://project-docs"]
const EXTRA_DOCS: PackedStringArray = ["res://README.md"]
const MKDOCS := "res://mkdocs.yml"

## Names that were REMOVED or RENAMED. A doc still mentioning one is stale by
## definition, so this list is how a rename gets to fail loudly.
const RETIRED: Dictionary = {
	"ACAWeatherVisualAdapter.TIME_PROFILES":
		"look data moved to addons/aca_sky3d_environment/profiles/",
	"ACAWeatherVisualAdapter.WEATHER_LAYERS":
		"look data moved to addons/aca_sky3d_environment/profiles/",
	"Weather/particles/rain_particles.tscn":
		"replaced by ACAPrecipitationRig, built in code",
	"addons/GodotWeatherSystem":
		"never installed in this project",
}

## Pages whose JOB is to record what is dead, and which therefore have to be
## allowed to name it. Everywhere else, mentioning a retired name means the page
## still believes in it.
const RETIRED_ALLOWED_IN: PackedStringArray = [
	"legacy-and-experimental.md",
	"architecture.md",
	"plugins-and-third-party.md",
	# Closing a flag means naming the thing being closed.
	"decisions-and-open-questions.md",
]

## Paths a doc names precisely BECAUSE they are missing. Sky3D ships a `.tscn`
## referencing a shader it does not contain; that is a third-party defect this
## project documents rather than one it should fix, and the audit must not flag
## the documentation of a known fault as a fault.
const ALLOWED_MISSING: PackedStringArray = [
	"res://addons/sky_3d/shaders/SimpleMoon.gdshader",
	# The dead precipitation resources point at an addon that was never
	# installed here. Naming the broken target is the entire content of that
	# finding; a doc that could not quote it could not explain it.
	"res://addons/GodotWeatherSystem/scripts/PrecipitationResource.cs",
	"res://addons/GodotWeatherSystem/particles/rain_particles.tscn",
]

## A regex fragment written into a usage example is not a path.
const BACKSLASH := "\\"

var _pass := 0
var _fail := 0
var _warn := 0


func _initialize() -> void:
	var docs := _all_docs()
	print("[DOCS] auditing %d Markdown files" % docs.size())

	_check_res_paths(docs)
	_check_relative_links(docs)
	_check_nav(docs)
	_check_retired(docs)

	print("[DOCS AUDIT] %d passed, %d failed, %d warnings" % [_pass, _fail, _warn])
	quit(1 if _fail > 0 else 0)


# ================================================================== the checks

## Every `res://` path a doc names must exist. This is the check that catches a
## rename, and it is the reason the tool exists.
func _check_res_paths(docs: PackedStringArray) -> void:
	var missing: Array[String] = []
	var checked := 0
	# TWO patterns, because a path can be written two ways and both are claims.
	#
	# The hard part is that THIS PROJECT HAS SPACES IN ITS PATHS —
	# `res://Game/App/Main Menu Screen.tscn` is a real file — so a pattern that
	# stops at whitespace truncates almost everything and then reports it all as
	# missing. That is a tool that cries wolf rather than one that finds
	# anything. A code span has an unambiguous end; outside one, the only
	# reliable end marker is the FILE EXTENSION.
	var backticked := RegEx.new()
	backticked.compile("`(res://[^`]+)`")
	var bare := RegEx.new()
	# LAZY, up to the first file extension on the line. That is what makes
	# spaces safe: the match runs through them and stops at `.gd` / `.tscn` /
	# whatever, rather than at the first space. `search_all` still picks up a
	# second path later on the same line, because it resumes after the first.
	#
	# LONGEST EXTENSION FIRST. Alternation is first-match, so `gd` listed before
	# `gdshader` truncates `SimpleMoon.gdshader` to `SimpleMoon.gd` and then
	# reports a file that was never named as missing.
	var extensions := "gdshader|gltf|tscn|tres|json|import|uid|glb|png|jpg|wav|ogg|txt|cfg|svg|md|gd"
	# Backticks end the match as well as newlines: a code span closing mid-line
	# is a boundary, or `res://UI/` followed by prose mentioning a script runs
	# the two together into one path that does not exist.
	bare.compile("(res://[^\\n`]*?\\.(?:%s))" % extensions)

	for doc in docs:
		var text := _read(doc)
		var found := PackedStringArray()
		for m in backticked.search_all(text):
			found.append(m.get_string(1))
		for m in bare.search_all(text):
			found.append(m.get_string(1))
		# A backticked path matches BOTH patterns, and reporting one problem
		# twice makes a short list look like a long one.
		var seen := {}
		for raw: String in found:
			var path := raw.strip_edges()
			if seen.has(path):
				continue
			seen[path] = true
			# A directory, a wildcard or a <placeholder> is not a claim about a
			# specific file.
			if path.ends_with("/") or path.contains("*") or path.contains("<"):
				continue
			if path.contains("…") or path.contains(BACKSLASH):
				continue
			if ALLOWED_MISSING.has(path):
				continue
			checked += 1
			if DirAccess.dir_exists_absolute(path):
				continue
			if not FileAccess.file_exists(path):
				missing.append("%s -> %s" % [doc.get_file(), path])

	_report("Paths: %d res:// references checked, all exist" % checked,
		missing.is_empty(), missing)


## A broken link in a docs site is a dead end for whoever is reading it.
func _check_relative_links(docs: PackedStringArray) -> void:
	var broken: Array[String] = []
	var checked := 0
	var regex := RegEx.new()
	regex.compile("\\]\\(([^)]+)\\)")

	for doc in docs:
		var base := doc.get_base_dir()
		for m in regex.search_all(_read(doc)):
			var target := m.get_string(1).strip_edges()
			if target.begins_with("http") or target.begins_with("#") \
					or target.begins_with("res://") or target.begins_with("mailto:"):
				continue
			# Drop an anchor before resolving the file.
			var hash_at := target.find("#")
			if hash_at >= 0:
				target = target.substr(0, hash_at)
			if target.is_empty():
				continue
			checked += 1
			var resolved := base.path_join(target).simplify_path()
			if not FileAccess.file_exists(resolved) \
					and not DirAccess.dir_exists_absolute(resolved):
				broken.append("%s -> %s" % [doc.get_file(), target])

	_report("Links: %d relative links checked, all resolve" % checked,
		broken.is_empty(), broken)


## A page that exists but is in no nav is a page nobody will find; a nav entry
## with no page is a 404.
func _check_nav(docs: PackedStringArray) -> void:
	var nav := _read(MKDOCS)
	if nav.is_empty():
		_report("Nav: mkdocs.yml is readable", false, ["mkdocs.yml not found"])
		return

	var orphans: Array[String] = []
	for doc in docs:
		if not doc.begins_with("res://project-docs"):
			continue
		var relative := doc.replace("res://project-docs/", "")
		if not nav.contains(relative):
			orphans.append(relative)
	_report("Nav: every project-docs page is reachable from mkdocs.yml",
		orphans.is_empty(), orphans)

	var dangling: Array[String] = []
	var regex := RegEx.new()
	regex.compile("([A-Za-z0-9_\\-/]+\\.md)")
	for m in regex.search_all(nav):
		var page := m.get_string(1)
		if not FileAccess.file_exists("res://project-docs/" + page):
			dangling.append(page)
	_report("Nav: every mkdocs.yml entry points at a real page",
		dangling.is_empty(), dangling)


## The rename check. A doc naming something this build removed is stale, and
## saying so is the whole point.
func _check_retired(docs: PackedStringArray) -> void:
	var stale: Array[String] = []
	for doc in docs:
		if RETIRED_ALLOWED_IN.has(doc.get_file()):
			continue
		var text := _read(doc)
		for needle: String in RETIRED:
			if text.contains(needle):
				stale.append("%s still mentions '%s' (%s)"
					% [doc.get_file(), needle, RETIRED[needle]])
	_report("Freshness: no page mentions a removed class or path",
		stale.is_empty(), stale)


# ==================================================================== helpers

func _all_docs() -> PackedStringArray:
	var out := PackedStringArray()
	for dir in DOC_DIRS:
		out.append_array(_markdown_under(dir))
	for extra in EXTRA_DOCS:
		if FileAccess.file_exists(extra):
			out.append(extra)
	return out


func _markdown_under(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_markdown_under(full))
		elif name.get_extension() == "md":
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _report(label: String, ok: bool, problems: Array) -> void:
	if ok:
		_pass += 1
		print("[DOCS] %s: PASS" % label)
		return
	_fail += 1
	printerr("[DOCS] %s: FAIL" % label)
	for p in problems:
		printerr("[DOCS]     %s" % p)
