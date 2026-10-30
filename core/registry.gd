extends Node
## Registry: грузит всё содержимое из res://data/ (и user://mods/), автогенерирует предметы
## и рецепты по материалам, строит индексы «где добыть / где используется», валидирует данные.

const DATA_DIR := "res://data"
const MODS_DIR := "user://mods"

var balance: Dictionary = {}
var items: Dictionary = {}          # id -> ItemDef
var item_order: Array[String] = []
var materials: Dictionary = {}      # id -> Dictionary
var recipes: Dictionary = {}        # id -> RecipeDef
var recipe_order: Array[String] = []
var stations: Dictionary = {}       # id -> StationDef
var station_order: Array[String] = []
var station_by_item: Dictionary = {} # item id -> station id
var generators: Dictionary = {}     # id -> GeneratorDef
var miners: Dictionary = {}         # id -> MinerDef
var nodes: Dictionary = {}          # id -> NodeDef
var node_order: Array[String] = []
var veins: Dictionary = {}          # id -> NodeDef
var vein_order: Array[String] = []
var dimension: Dictionary = {}      # сырые данные карты (тайлы, зоны, база)
var quests: Dictionary = {}         # id -> QuestDef
var quest_order: Array[String] = []
var chapters: Array[Dictionary] = []
var features: Array[Dictionary] = []

var produced_by: Dictionary = {}    # item -> Array[String] recipe ids
var used_in: Dictionary = {}        # item -> Array[String] recipe ids
var dropped_by: Dictionary = {}     # item -> Array[String] node/vein ids
var tag_items: Dictionary = {}      # tag -> Array[String]

var errors: Array[String] = []
var warnings: Array[String] = []


func _ready() -> void:
	var data := load_data_dir(DATA_DIR)
	_merge_mods(data)
	build(data)
	validate()
	for e in errors:
		push_error("[Registry] " + e)
	for w in warnings:
		push_warning("[Registry] " + w)


# --- Загрузка -------------------------------------------------------------------------------

static func load_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("[Registry] не удалось прочитать %s" % path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("[Registry] %s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## Собирает сырые данные в один словарь: {balance, materials, items, recipes, ...}.
static func load_data_dir(dir: String) -> Dictionary:
	var data := {
		"balance": load_json(dir + "/balance.json"),
		"materials": load_json(dir + "/materials.json"),
		"items": (load_json(dir + "/items.json") as Dictionary).get("items", []),
		"stations": (load_json(dir + "/stations.json") as Dictionary).get("stations", []),
		"generators": (load_json(dir + "/power.json") as Dictionary).get("generators", []),
		"miners": (load_json(dir + "/miners.json") as Dictionary).get("miners", []),
		"features": (load_json(dir + "/unlocks.json") as Dictionary).get("features", []),
		"recipes": [],
		"dimension": load_json(dir + "/dimensions/overworld.json"),
		"chapters": [],
	}
	for file in _json_files(dir + "/recipes"):
		(data["recipes"] as Array).append_array((load_json(file) as Dictionary).get("recipes", []))
	for file in _json_files(dir + "/quests"):
		(data["chapters"] as Array).append(load_json(file))
	return data


static func _json_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append(dir + "/" + f)
	out.sort()
	return out


func _merge_mods(data: Dictionary) -> void:
	for file in _json_files(MODS_DIR):
		var mod: Variant = load_json(file)
		if mod is Dictionary:
			(data["items"] as Array).append_array((mod as Dictionary).get("items", []))
			(data["recipes"] as Array).append_array((mod as Dictionary).get("recipes", []))
			print("[Registry] мод загружен: ", file)


# --- Построение -----------------------------------------------------------------------------

func build(data: Dictionary) -> void:
	_clear()
	balance = data.get("balance", {})
	var mat_data: Dictionary = data.get("materials", {})
	for m: Dictionary in mat_data.get("materials", []):
		materials[m["id"]] = m
	for raw: Dictionary in data.get("items", []):
		_add_item(_parse_item(raw))
	_generate_material_items(mat_data)
	for raw: Dictionary in data.get("stations", []):
		_add_station(raw)
	for raw: Dictionary in data.get("generators", []):
		_add_generator(raw)
	for raw: Dictionary in data.get("miners", []):
		_add_miner(raw)
	for raw: Dictionary in data.get("recipes", []):
		_add_recipe(_parse_recipe(raw))
	_generate_form_recipes(mat_data)
	_generate_tool_recipes()
	_load_dimension(data.get("dimension", {}))
	var chs: Array = data.get("chapters", [])
	chs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["chapter"].get("order", 0)) < int(b["chapter"].get("order", 0)))
	for ch: Dictionary in chs:
		_load_chapter(ch)
	features.assign(data.get("features", []))
	_build_indices()


func _clear() -> void:
	for d: Dictionary in [items, materials, recipes, stations, station_by_item, generators, miners, nodes,
			veins, quests, produced_by, used_in, dropped_by, tag_items]:
		d.clear()
	for a: Array in [item_order, recipe_order, station_order, node_order, vein_order, quest_order,
			chapters, features, errors, warnings]:
		a.clear()


func _parse_item(raw: Dictionary) -> ItemDef:
	var it := ItemDef.new()
	it.id = raw["id"]
	it.name_key = raw.get("name", "ITEM_" + it.id.to_upper())
	it.icon = raw.get("icon", "block")
	it.color = Color(raw.get("color", "#ffffff"))
	it.unit = raw.get("unit", "piece")
	it.era = int(raw.get("era", 0))
	it.tags.assign(raw.get("tags", []))
	it.kind = raw.get("kind", "item")
	it.fuel = float(raw.get("fuel", 0.0))
	it.heat = int(raw.get("heat", 0))
	return it


func _add_item(it: ItemDef) -> void:
	if items.has(it.id):
		errors.append("предмет '%s' объявлен дважды" % it.id)
		return
	items[it.id] = it
	item_order.append(it.id)


func _generate_material_items(mat_data: Dictionary) -> void:
	var forms: Dictionary = mat_data.get("forms", {})
	var tool_types: Array = tool_balance().get("types", [])
	var head_cost: Dictionary = tool_balance().get("head_cost", {})
	for m: Dictionary in mat_data.get("materials", []):
		for form: String in m.get("forms", []):
			var f: Dictionary = forms.get(form, {})
			var it := ItemDef.new()
			it.id = "%s_%s" % [m["id"], form]
			it.name_key = "ITEM_" + it.id.to_upper()
			it.icon = f.get("icon", form)
			it.color = Color(m.get("color", "#ffffff"))
			it.era = int(m.get("era", 0))
			it.tags.assign(f.get("tags", []))
			it.material = m["id"]
			it.form = form
			_add_item(it)
		if m.has("tool"):
			var t: Dictionary = m["tool"]
			for type: String in tool_types:
				var tool := ItemDef.new()
				tool.id = "tool_%s_%s" % [type, m["id"]]
				tool.name_key = "ITEM_" + tool.id.to_upper()
				tool.icon = type
				tool.color = Color(m.get("color", "#ffffff"))
				tool.era = int(m.get("era", 0))
				tool.tags.assign(["tool", type])
				tool.material = m["id"]
				tool.kind = "tool"
				tool.tool = {
					"type": type, "tool_tier": int(t["tool_tier"]), "damage": float(t["damage"]),
					"durability": int(t["durability"]), "head_item": t["head_item"],
					"head_cost": int(head_cost.get(type, 1)), "material": m["id"], "station": t["station"],
				}
				_add_item(tool)


func _add_station(raw: Dictionary) -> void:
	var s := StationDef.new()
	s.id = raw["id"]
	s.item = raw.get("item", "")
	s.energy = raw.get("energy", "none")
	s.voltage = raw.get("voltage", "")
	s.era = int(raw.get("era", 0))
	s.builtin = bool(raw.get("builtin", false))
	s.multiblock = raw.get("multiblock", {})
	s.speed_cost.assign(raw.get("speed_cost", []))
	s.efficiency_cost.assign(raw.get("efficiency_cost", []))
	if items.has(s.item):
		s.icon = (items[s.item] as ItemDef).icon
		s.color = (items[s.item] as ItemDef).color
	s.icon = raw.get("icon", s.icon)
	s.color = Color(raw.get("color", s.color.to_html()))
	stations[s.id] = s
	station_order.append(s.id)
	if not s.item.is_empty():
		station_by_item[s.item] = s.id


func _add_generator(raw: Dictionary) -> void:
	var g := GeneratorDef.new()
	g.id = raw["id"]
	g.type = raw["type"]
	g.era = int(raw.get("era", 0))
	g.steam_per_tick = float(raw.get("steam_per_tick", 0.0))
	g.buffer = float(raw.get("buffer", 0.0))
	g.warmup_sec = float(raw.get("warmup_sec", 0.0))
	g.fuel_tag = raw.get("fuel_tag", "")
	g.auto_tag = raw.get("auto_tag", "")
	g.eu_per_tick = float(raw.get("eu_per_tick", 0.0))
	g.pull = int(raw.get("pull", 1))
	g.capacity = float(raw.get("capacity", 0.0))
	generators[g.id] = g


func _add_miner(raw: Dictionary) -> void:
	var m := MinerDef.new()
	m.id = raw["id"]
	m.era = int(raw.get("era", 0))
	m.tool_tier = int(raw.get("tool_tier", 0))
	m.damage_per_sec = float(raw.get("damage_per_sec", 1.0))
	m.tool_types.assign(raw.get("tool_types", []))
	m.energy = raw.get("energy", "none")
	m.usage = float(raw.get("usage", 0.0))
	miners[m.id] = m


func _parse_recipe(raw: Dictionary) -> RecipeDef:
	var r := RecipeDef.new()
	r.id = raw["id"]
	r.station = raw["station"]
	for i: Dictionary in raw.get("inputs", []):
		var inp := {"n": int(i.get("n", 1))}
		if i.has("tag"):
			inp["tag"] = i["tag"]
		else:
			inp["item"] = i["item"]
		r.inputs.append(inp)
	for o: Dictionary in raw.get("outputs", []):
		r.outputs.append({"item": o["item"], "n": int(o.get("n", 1)), "chance": float(o.get("chance", 1.0))})
	r.ticks = int(raw.get("ticks", 20))
	r.eu = float(raw.get("eu", 0.0))
	r.heat = int((raw.get("req", {}) as Dictionary).get("heat", 0))
	return r


func _add_recipe(r: RecipeDef) -> void:
	if recipes.has(r.id):
		errors.append("рецепт '%s' объявлен дважды" % r.id)
		return
	recipes[r.id] = r
	recipe_order.append(r.id)


## Рецепты по шаблонам форм: «руда → слиток» и т.п. для каждого материала с нужными формами.
func _generate_form_recipes(mat_data: Dictionary) -> void:
	for tpl: Dictionary in mat_data.get("form_recipes", []):
		for m: Dictionary in mat_data.get("materials", []):
			var mforms: Array = m.get("forms", [])
			var flags: Array = m.get("flags", [])
			var ok := true
			for flag: String in tpl.get("flags", []):
				ok = ok and flags.has(flag)
			for part: Dictionary in tpl["inputs"] + tpl["outputs"]:
				ok = ok and mforms.has(part["form"])
			if not ok:
				continue
			var r := RecipeDef.new()
			r.id = "%s_%s" % [tpl["id"], m["id"]]
			r.station = tpl["station"]
			r.ticks = int(tpl.get("ticks", 100))
			r.eu = float(tpl.get("eu", 0.0))
			r.generated = true
			for i: Dictionary in tpl["inputs"]:
				r.inputs.append({"item": "%s_%s" % [m["id"], i["form"]], "n": int(i["n"])})
			for o: Dictionary in tpl["outputs"]:
				r.outputs.append({"item": "%s_%s" % [m["id"], o["form"]], "n": int(o["n"]), "chance": 1.0})
			if tpl.get("byproduct", false) and m.has("ore_byproduct"):
				var bp: Dictionary = m["ore_byproduct"]
				r.outputs.append({"item": bp["item"], "n": 1, "chance": float(bp["chance"])})
			_add_recipe(r)


## Инструменты: первый тир — головка + палки; следующие — апгрейд «старый инструмент + материал».
func _generate_tool_recipes() -> void:
	var by_type: Dictionary = {}
	for id: String in item_order:
		var it: ItemDef = items[id]
		if it.kind == "tool":
			if not by_type.has(it.tool["type"]):
				by_type[it.tool["type"]] = []
			(by_type[it.tool["type"]] as Array).append(it)
	var sticks := int(tool_balance().get("first_tier_sticks", 2))
	for type: String in by_type:
		var list: Array = by_type[type]
		list.sort_custom(func(a: ItemDef, b: ItemDef) -> bool: return a.tool["tool_tier"] < b.tool["tool_tier"])
		for i in list.size():
			var tool: ItemDef = list[i]
			var r := RecipeDef.new()
			r.id = "craft_" + tool.id
			r.station = tool.tool["station"]
			r.ticks = 60 + 40 * int(tool.tool["tool_tier"])
			r.generated = true
			if i == 0:
				r.inputs.append({"item": "stick", "n": sticks})
			else:
				r.inputs.append({"item": (list[i - 1] as ItemDef).id, "n": 1})
			r.inputs.append({"item": tool.tool["head_item"], "n": int(tool.tool["head_cost"])})
			r.outputs.append({"item": tool.id, "n": 1, "chance": 1.0})
			_add_recipe(r)


func _parse_node(raw: Dictionary) -> NodeDef:
	var n := NodeDef.new()
	n.id = raw["id"]
	var p: Array = raw.get("pos", [0, 0])
	n.pos = Vector2i(int(p[0]), int(p[1]))
	n.zone = raw.get("zone", "start")
	n.icon = raw.get("icon", "rock")
	n.color = Color(raw.get("color", "#ffffff"))
	n.tool_type = raw.get("tool_type", "pickaxe")
	n.hardness = float(raw.get("hardness", 10.0))
	n.min_tool_tier = int(raw.get("min_tool_tier", 0))
	n.era_tool_tier = int(raw.get("era_tool_tier", n.min_tool_tier))
	n.vein_size = int(raw.get("vein_size", 4))
	n.reveal = raw.get("reveal", {})
	n.vein_slot = int(raw.get("vein_slot", -1))
	for d: Dictionary in raw.get("drops", []):
		n.drops.append({"item": d["item"], "min": int(d.get("min", 1)), "max": int(d.get("max", 1)),
			"chance": float(d.get("chance", 1.0))})
	return n


func _load_dimension(dim: Dictionary) -> void:
	dimension = dim
	for raw: Dictionary in dim.get("nodes", []):
		var n := _parse_node(raw)
		nodes[n.id] = n
		node_order.append(n.id)
	for raw: Dictionary in dim.get("veins", []):
		var v := _parse_node(raw)
		veins[v.id] = v
		vein_order.append(v.id)


func _load_chapter(ch: Dictionary) -> void:
	var info: Dictionary = ch["chapter"]
	var ids: Array[String] = []
	for raw: Dictionary in ch.get("quests", []):
		var q := QuestDef.new()
		q.id = raw["id"]
		q.chapter = info["id"]
		var p: Array = raw.get("pos", [0, 0])
		q.pos = Vector2(float(p[0]), float(p[1]))
		q.requires.assign(raw.get("requires", []))
		q.requires_mode = raw.get("requires_mode", "all")
		q.main = bool(raw.get("main", true))
		q.visibility = raw.get("visibility", "visible")
		q.goals_mode = raw.get("goals_mode", "all")
		q.goals.assign(raw.get("goals", []))
		q.rewards = raw.get("rewards", {})
		q.icon = raw.get("icon", "")
		if quests.has(q.id):
			errors.append("квест '%s' объявлен дважды" % q.id)
			continue
		quests[q.id] = q
		quest_order.append(q.id)
		ids.append(q.id)
	chapters.append({"id": info["id"], "era": int(info.get("era", 0)), "quests": ids})


func _build_indices() -> void:
	for id: String in item_order:
		for tag in (items[id] as ItemDef).tags:
			_push(tag_items, tag, id)
	for rid: String in recipe_order:
		var r: RecipeDef = recipes[rid]
		for o in r.outputs:
			_push(produced_by, o["item"], rid)
		for i in r.inputs:
			for item_id in input_candidates(i):
				_push(used_in, item_id, rid)
	for nid: String in node_order + vein_order:
		var n: NodeDef = nodes[nid] if nodes.has(nid) else veins[nid]
		for d in n.drops:
			_push(dropped_by, d["item"], nid)


static func _push(dict: Dictionary, key: String, value: String) -> void:
	if not dict.has(key):
		var list: Array[String] = []
		dict[key] = list
	if not (dict[key] as Array).has(value):
		(dict[key] as Array).append(value)


# --- Доступ ---------------------------------------------------------------------------------

func item(id: String) -> ItemDef:
	return items.get(id)


func has_item(id: String) -> bool:
	return items.has(id)


func recipe(id: String) -> RecipeDef:
	return recipes.get(id)


func station(id: String) -> StationDef:
	return stations.get(id)


func node(id: String) -> NodeDef:
	return nodes.get(id)


func quest(id: String) -> QuestDef:
	return quests.get(id)


## Предметы, подходящие под вход рецепта (конкретный предмет или #тег).
func input_candidates(inp: Dictionary) -> Array[String]:
	if inp.has("tag"):
		var out: Array[String] = []
		out.assign(tag_items.get(inp["tag"], []))
		return out
	return [inp["item"] as String]


func recipes_for_station(station_id: String) -> Array[String]:
	var out: Array[String] = []
	for rid in recipe_order:
		if (recipes[rid] as RecipeDef).station == station_id:
			out.append(rid)
	return out


func tool_balance() -> Dictionary:
	return balance.get("tools", {})


func mining_balance() -> Dictionary:
	return balance.get("mining", {})


func station_balance() -> Dictionary:
	return balance.get("stations", {})


func ticks_per_second() -> float:
	return float(balance.get("ticks_per_second", 20))


## Индекс тира напряжения для EU/t: ULV=0, LV=1, MV=2...
func voltage_tier_for(eu: float) -> int:
	var tiers: Array = balance.get("voltage", [])
	for i in tiers.size():
		if eu <= float((tiers[i] as Dictionary)["eu"]):
			return i
	return tiers.size()


func voltage_tier_index(id: String) -> int:
	var tiers: Array = balance.get("voltage", [])
	for i in tiers.size():
		if (tiers[i] as Dictionary)["id"] == id:
			return i
	return -1


func voltage_eu(id: String) -> float:
	var idx := voltage_tier_index(id)
	return float((balance["voltage"][idx] as Dictionary)["eu"]) if idx >= 0 else 0.0


func voltage_name(tier: int) -> String:
	var tiers: Array = balance.get("voltage", [])
	return (tiers[tier] as Dictionary)["id"] if tier >= 0 and tier < tiers.size() else "?"


## Имя предмета: явный перевод ITEM_<ID>, иначе собирается из формы и материала.
func item_name(id: String) -> String:
	var it := item(id)
	if it == null:
		return id
	var key_tr := TranslationServer.translate(it.name_key)
	if key_tr != it.name_key:
		return key_tr
	if it.kind == "tool":
		return "%s (%s)" % [TranslationServer.translate("TOOL_" + str(it.tool["type"]).to_upper()),
			TranslationServer.translate("MAT_" + it.material.to_upper())]
	if not it.form.is_empty():
		return TranslationServer.translate("FORM_" + it.form.to_upper()) % \
			TranslationServer.translate("MAT_" + it.material.to_upper() + "_GEN")
	return id


func station_name(id: String) -> String:
	var s := station(id)
	if s != null and not s.item.is_empty():
		return item_name(s.item)
	return TranslationServer.translate("STATION_" + id.to_upper())


func node_name(id: String) -> String:
	return TranslationServer.translate("NODE_" + id.to_upper())


# --- Валидатор ------------------------------------------------------------------------------

## Проверяет ссылки, достижимость предметов и циклы квестов. Возвращает число ошибок.
func validate() -> int:
	_validate_refs()
	_validate_reachability()
	_validate_quest_cycles()
	return errors.size()


func _check_item(id: String, where: String) -> void:
	if not items.has(id):
		errors.append("%s ссылается на несуществующий предмет '%s'" % [where, id])


func _validate_refs() -> void:
	for rid in recipe_order:
		var r: RecipeDef = recipes[rid]
		var where := "рецепт '%s'" % rid
		if not stations.has(r.station):
			errors.append("%s: неизвестная станция '%s'" % [where, r.station])
		for i in r.inputs:
			if i.has("tag"):
				if not tag_items.has(i["tag"]):
					errors.append("%s: нет предметов с тегом #%s" % [where, i["tag"]])
			else:
				_check_item(i["item"], where)
		for o in r.outputs:
			_check_item(o["item"], where)
		if r.outputs.is_empty():
			errors.append("%s: нет выходов" % where)
	for sid in station_order:
		var s: StationDef = stations[sid]
		if not s.item.is_empty():
			_check_item(s.item, "станция '%s'" % sid)
		for c in s.speed_cost + s.efficiency_cost:
			_check_item(c["item"], "апгрейд станции '%s'" % sid)
		for p: Dictionary in s.multiblock.get("parts", []):
			_check_item(p["item"], "мультиблок '%s'" % sid)
	for id in item_order:
		var it: ItemDef = items[id]
		if it.kind == "generator" and not generators.has(id):
			errors.append("генератор '%s' не описан в power.json" % id)
		if it.kind == "miner" and not miners.has(id):
			errors.append("майнер '%s' не описан в miners.json" % id)
		if it.kind == "station" and not station_by_item.has(id):
			errors.append("станция-предмет '%s' не описана в stations.json" % id)
	for nid in node_order + vein_order:
		var n: NodeDef = nodes[nid] if nodes.has(nid) else veins[nid]
		for d in n.drops:
			_check_item(d["item"], "блок '%s'" % nid)
	for qid in quest_order:
		var q: QuestDef = quests[qid]
		var where := "квест '%s'" % qid
		for req in q.requires:
			if not quests.has(req):
				errors.append("%s требует несуществующий квест '%s'" % [where, req])
		for g in q.goals:
			if g.has("item"):
				_check_item(g["item"], where)
			if g.has("tag") and not tag_items.has(g["tag"]):
				errors.append("%s: нет предметов с тегом #%s" % [where, g["tag"]])
			if g.has("node") and not nodes.has(g["node"]):
				errors.append("%s: неизвестный блок '%s'" % [where, g["node"]])
			if g.has("station") and not stations.has(g["station"]):
				errors.append("%s: неизвестная станция '%s'" % [where, g["station"]])
		for it in _reward_items(q):
			_check_item(it, where + " (награда)")


func _reward_items(q: QuestDef) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in q.rewards.get("items", []):
		out.append(e["item"])
	for opt: Array in q.rewards.get("choice", []):
		for e: Dictionary in opt:
			out.append(e["item"])
	return out


func _station_reachable(sid: String, have: Dictionary) -> bool:
	var s: StationDef = stations.get(sid)
	if s == null:
		return false
	if s.builtin:
		return true
	if s.is_multiblock():
		for p: Dictionary in s.multiblock["parts"]:
			if not have.has(p["item"]):
				return false
		return true
	return have.has(s.item)


func _validate_reachability() -> void:
	var have: Dictionary = {}
	for nid in node_order + vein_order:
		var n: NodeDef = nodes[nid] if nodes.has(nid) else veins[nid]
		for d in n.drops:
			have[d["item"]] = true
	for qid in quest_order:
		for it in _reward_items(quests[qid]):
			have[it] = true
	var changed := true
	while changed:
		changed = false
		for rid in recipe_order:
			var r: RecipeDef = recipes[rid]
			if not _station_reachable(r.station, have):
				continue
			var ok := true
			for i in r.inputs:
				var any := false
				for c in input_candidates(i):
					any = any or have.has(c)
				ok = ok and any
			if not ok:
				continue
			for o in r.outputs:
				if not have.has(o["item"]):
					have[o["item"]] = true
					changed = true
	for id in item_order:
		if not have.has(id):
			errors.append("предмет '%s' нельзя получить ни одним способом" % id)
		elif not used_in.has(id) and items[id].kind == "item":
			var used := false
			for gid: String in generators:
				var tag: String = (generators[gid] as GeneratorDef).fuel_tag
				used = used or (not tag.is_empty() and (items[id] as ItemDef).has_tag(tag))
			for qid in quest_order:
				for g in (quests[qid] as QuestDef).goals:
					used = used or g.get("item", "") == id
			if not used:
				warnings.append("предмет '%s' нигде не используется" % id)


func _validate_quest_cycles() -> void:
	var state: Dictionary = {}  # 1 — в стеке, 2 — проверен
	for qid in quest_order:
		_quest_dfs(qid, state, [])


func _quest_dfs(qid: String, state: Dictionary, path: Array[String]) -> void:
	if state.get(qid, 0) == 2:
		return
	if state.get(qid, 0) == 1:
		errors.append("цикл в цепочке квестов: %s -> %s" % [" -> ".join(path), qid])
		return
	state[qid] = 1
	path.append(qid)
	var q: QuestDef = quests.get(qid)
	if q != null:
		for req in q.requires:
			_quest_dfs(req, state, path)
	path.pop_back()
	state[qid] = 2
