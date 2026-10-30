extends Node
## Шина сигналов между системами симуляции и UI (раздел 14).
## Сигналы испускаются из других автолоадов, поэтому предупреждение unused_signal подавлено.

@warning_ignore_start("unused_signal")
## Предмет попал в хранилище (любым способом).
signal item_obtained(item_id: String, amount: int)
## Предмет впервые попал в discovered.
signal item_discovered(item_id: String)
signal block_broken(node_id: String, manual: bool)
signal crafted(item_id: String, amount: int, station_id: String, recipe_id: String)
signal station_installed(station_id: String)
signal generator_installed(generator_id: String)
signal tool_equipped(tool_type: String)
signal tool_broken(tool_type: String, item_id: String)
signal tool_durability_warning(tool_type: String, fraction: float)
signal quest_completed(quest_id: String)
signal quest_claimed(quest_id: String)
signal feature_unlocked(feature_id: String)
signal era_changed(era: int)
signal veins_changed()
signal power_deficit(ratio: float)
signal recipes_discovered(recipe_ids: Array)
signal demo_finished()
## Полная перезагрузка состояния (новая игра, загрузка сейва).
signal state_reset()
## Сообщение для всплывающего уведомления UI.
signal notify(text: String, kind: String)
@warning_ignore_restore("unused_signal")
