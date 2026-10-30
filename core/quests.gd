extends Node
## Quests: дерево квестов по главам-эпохам (раздел 10). Триггеры: obtain / have / craft /
## break / stat / checkbox. Награды забираются кликом: предметы, выбор 1 из N, открытие
## систем, смена эпохи, финал демо.

signal quest_state_changed(quest_id: String)

enum State { LOCKED, AVAILABLE, COMPLETED, CLAIMED }

var states: Dictionary = {}     # quest id -> State
var checked: Dictionary = {}    # quest id -> true (отмеченные checkbox-цели)


func reset() -> void:
	states.clear()
	checked.clear()


func state(qid: String) -> State:
	return states.get(qid, State.LOCKED)


## Выполнен (награда может быть ещё не забрана).
func is_done(qid: String) -> bool:
	return state(qid) >= State.COMPLETED


func prerequisites_met(qid: String) -> bool:
	var q := Registry.quest(qid)
	if q.requires.is_empty():
		return true
	var any := false
	var all := true
	for req in q.requires:
		any = any or is_done(req)
		all = all and is_done(req)
	return any if q.requires_mode == "any" else all


## Прогресс цели: [текущее, нужно].
func goal_progress(qid: String, goal: Dictionary) -> Vector2i:
	var need := int(goal.get("n", 1))
	var cur := 0
	match goal["type"]:
		"obtain":
			cur = _sum_by_item_or_tag(goal, Storage.total_obtained)
		"have":
			cur = _sum_by_item_or_tag(goal, Storage.counts)
		"craft":
			if goal.has("station"):
				cur = int(Progress.crafted_at.get(str(goal["station"]) + ":" + str(goal["item"]), 0))
			else:
				cur = _sum_by_item_or_tag(goal, Progress.crafted)
		"break":
			cur = int(Progress.broken.get(goal["node"], 0))
		"stat":
			cur = floori(Progress.stat(goal["stat"]) + 1e-6)
		"checkbox":
			need = 1
			cur = 1 if checked.has(qid) else 0
		_:
			push_error("[Quests] неизвестный тип цели '%s' в %s" % [goal["type"], qid])
	return Vector2i(mini(cur, need), need)


func _sum_by_item_or_tag(goal: Dictionary, source: Dictionary) -> int:
	if goal.has("item"):
		return int(source.get(goal["item"], 0))
	var total := 0
	for id: String in Registry.tag_items.get(goal["tag"], []):
		total += int(source.get(id, 0))
	return total


func goals_met(qid: String) -> bool:
	var q := Registry.quest(qid)
	var any := false
	var all := true
	for g in q.goals:
		var p := goal_progress(qid, g)
		any = any or p.x >= p.y
		all = all and p.x >= p.y
	return any if q.goals_mode == "any" else all


func check_all() -> void:
	var changed := true
	while changed:
		changed = false
		for qid: String in Registry.quest_order:
			var s := state(qid)
			if s == State.LOCKED and prerequisites_met(qid):
				states[qid] = State.AVAILABLE
				quest_state_changed.emit(qid)
				changed = true
				s = State.AVAILABLE
			if s == State.AVAILABLE and goals_met(qid):
				states[qid] = State.COMPLETED
				quest_state_changed.emit(qid)
				Events.quest_completed.emit(qid)
				changed = true


func set_checked(qid: String) -> void:
	if state(qid) == State.AVAILABLE:
		checked[qid] = true
		check_all()


func claimable() -> Array[String]:
	var out: Array[String] = []
	for qid: String in Registry.quest_order:
		if state(qid) == State.COMPLETED:
			out.append(qid)
	return out


## Забирает награду. choice — индекс варианта для наград «выбор 1 из N».
func claim(qid: String, choice: int = 0) -> bool:
	if state(qid) != State.COMPLETED:
		return false
	var rw := Registry.quest(qid).rewards
	states[qid] = State.CLAIMED
	for e: Dictionary in rw.get("items", []):
		Storage.add(e["item"], int(e["n"]), false)
	var options: Array = rw.get("choice", [])
	if not options.is_empty():
		for e: Dictionary in options[clampi(choice, 0, options.size() - 1)]:
			Storage.add(e["item"], int(e["n"]), false)
	for f: String in rw.get("unlock", []):
		Progress.unlock(f)
	if rw.has("era"):
		Progress.set_era(int(rw["era"]))
	quest_state_changed.emit(qid)
	Events.quest_claimed.emit(qid)
	if rw.get("demo_end", false):
		Progress.finish_demo()
	check_all()
	return true


## Видимость на полотне: закрытые квесты глубже 1 уровня от доступных скрываются.
func is_visible_on_canvas(qid: String) -> bool:
	var q := Registry.quest(qid)
	if state(qid) != State.LOCKED:
		return true
	if q.visibility == "hidden":
		return false
	for req in q.requires:
		if state(req) != State.LOCKED:
			return true
	return q.requires.is_empty()


func chapter_progress(chapter_id: String) -> Vector2i:
	for ch in Registry.chapters:
		if ch["id"] == chapter_id:
			var done := 0
			for qid: String in ch["quests"]:
				done += 1 if is_done(qid) else 0
			return Vector2i(done, (ch["quests"] as Array).size())
	return Vector2i.ZERO


func serialize() -> Dictionary:
	var s: Dictionary = {}
	for qid: String in states:
		s[qid] = int(states[qid])
	return {"states": s, "checked": checked.keys()}


func deserialize(data: Dictionary) -> void:
	reset()
	for qid: String in data.get("states", {}):
		if Registry.quests.has(qid):
			states[qid] = int(data["states"][qid]) as State
	for qid: String in data.get("checked", []):
		checked[qid] = true
