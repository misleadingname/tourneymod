extends Interactable

var exists: bool = false

var tourney_hud: PackedScene = preload("res://mods/misname.fishtourney/Scenes/HUD/tourney_hud.tscn")
var tourney_hud_instance: CanvasLayer = tourney_hud.instance()

var joined: bool = false
var tourney_active: bool = false

var queued_people: Array = []
var playing_people: Array = []

var people_scores: Dictionary = {}

onready var intermission_timer: Timer = $IntermissionTimer
onready var tourney_timer: Timer = $TourneyTimer
onready var update_timer: Timer = $UpdateTimer

func _send_net(type: String, data: Dictionary = {}, target: String = "all"):
	var complete_data: Dictionary =  {"type": ("misnametourney_%s" % type), "steamid": Network.STEAM_ID}
	complete_data.merge(data)
	
#	PlayerData._send_notification("[SEND NET] to: " + target + " ... " + str(complete_data))
	
	Network._send_P2P_Packet(complete_data, target, 2, 4)

func _receive_net(steamid, data):
	var type: String = (data["type"]).trim_prefix("misnametourney_")
	match type:
		"tourney_exists_question":
			if not Network.GAME_MASTER: return
			_send_net("tourney_exists_response", {}, str(steamid))
		"tourney_exists_response":
			exists = true
		"signinout":
			if queued_people.has(steamid):
				_leave_tourney(steamid)
			else:
				_join_tourney(steamid)
		"start":
			if tourney_active: return
			tourney_active = true
			
			if not queued_people.has(Network.STEAM_ID): return
			_start_tourney()
		"finish":
			if not tourney_active: return
			tourney_active = false
		"score_request":
			_send_net("score_response", {"score": _get_fish_amt()}, str(steamid))
		"score_response":
			people_scores[steamid] = data["score"]
		"send_notif":
			if not joined: return
			PlayerData._send_notification(data["body"], data["red"])
		"results":
			print(data["scores"])
			
			for i in data["scores"].size():
				var id = data["scores"].keys()[i]
				var score = data["scores"][id]
				PlayerData._send_notification("%s%s place: %s with %s fish%s!" % [i + 1, _get_ordinal(i + 1), Network._get_username_from_id(id), score, "" if score == 1 else "es"])

func _get_player_actor():
	return get_tree().current_scene.get_node("Viewport/main/entities/player")

#################################################################################################

func _ready():
	monitoring = false
	add_to_group("interactable")
	
	# god forgive me for this line but I think this is a good way of finding the node that IS actually the mod.
	var mod_node: Node = get_tree().get_nodes_in_group("MISNAMETOURNEYMOD")[0]
	
	mod_node.connect("tourney_net", self, "_receive_net")
	
	intermission_timer.connect("timeout", self, "_intermission_timer_timeout")
	tourney_timer.connect("timeout", self, "_finish_tourney")
	update_timer.connect("timeout", self, "_update_timer_timeout")
	
	yield(get_tree().create_timer(3), "timeout")
	
	_send_net("tourney_exists_question", {}, str(Network.KNOWN_GAME_MASTER))

func _get_fish_amt():
	var num: int = 0
	
	for i in PlayerData.inventory.size():
		var item = PlayerData.inventory[i]
		if item.id.begins_with("fish_") and item.id != "fish_trap" and item.id != "fish_trap_ocean": num += 1
		if item.id.begins_with("wtrash_"): num += 1
		if item.id == "treasure_chest": num += 1
	
	return num
	
func _get_ordinal(d: int):
	var suffix = "th"
	
	if d % 10 == 1 and d != 11:
		suffix = "st"
	elif d % 10 == 2 and d != 12:
		suffix = "nd"
	elif d % 10 == 3 and d != 13:
		suffix = "rd"

	return suffix

func _ensure_clean_inv():
	return _get_fish_amt() == 0

func _activate(actor: Actor):
	if not exists:
		PlayerData._send_notification("Unfortunately the tourney is closed as the lobby master doesn't have the mod!", 1)
		return

	if not _ensure_clean_inv():
		PlayerData._send_notification("Please sell all of your fishable items before attending!", 1)
		return
	
	if tourney_active:
		PlayerData._send_notification("A tourney is currently happening, check back later!")
		return
	
	_send_net("signinout")

func _update_intermission_timer():
	if not Network.GAME_MASTER: return
	
	if tourney_active:
		intermission_timer.stop()
		return
	
	if queued_people.size() < 2:
		intermission_timer.stop()
		_send_net("notif", {"body": "Not enough players to start the tourney!", "red": 1})
	else:
		_send_net("notif", {"body": "Starting the tourney in 10 seconds!", "red": 0})
		intermission_timer.start(10)

func _join_tourney(steamid: int):
	if steamid == Network.STEAM_ID:
		joined = true
		PlayerData._send_notification("You've joined the next tourney.")
	else:
		PlayerData._send_notification("%s joined the next tourney." % Network._get_username_from_id(steamid))
	
	queued_people.append(steamid)
	_update_intermission_timer()

func _leave_tourney(steamid: int):
	if steamid == Network.STEAM_ID:
		joined = false
		PlayerData._send_notification("You've left the next tourney.", 1)
	else:
		PlayerData._send_notification("%s left the next tourney." % Network._get_username_from_id(steamid), 1)
	
	queued_people.remove(queued_people.find(steamid))
	_update_intermission_timer()

func _start_tourney():
	update_timer.start(0.5)
	tourney_timer.start(60 * 5)
	get_tree().root.add_child(tourney_hud_instance)
	
	playing_people = queued_people.duplicate()
	
	_get_player_actor().catch_drink_timer = 60 * 5 * 60
	_get_player_actor().catch_drink_boost = 1.15
	_get_player_actor().catch_drink_reel = 1.25
	_get_player_actor().catch_drink_xp = 1.0
	_get_player_actor().catch_drink_tier = 1
	_get_player_actor().catch_drink_gold_add = Vector2(1, 10)
	_get_player_actor().catch_drink_gold_percent = 0.0
	
	queued_people.clear()
	people_scores.clear()
	
	var spawnlocs: Array = get_tree().get_nodes_in_group("trash_point")
	var spawnloc: Position3D = spawnlocs[spawnlocs.size() - 1]

	if _get_player_actor().state == _get_player_actor().STATES.FISHING or _get_player_actor().state == _get_player_actor().STATES.FISHING_CAST or _get_player_actor().state == _get_player_actor().STATES.FISHING_CAST:
			_get_player_actor()._enter_state(_get_player_actor().STATES.FISHING_CANCEL)

	_get_player_actor().cam_push = 0.0
	_get_player_actor().gravity_disable = true

	SceneTransition._fake_scene_change()
	yield (SceneTransition, "_finished")
	_get_player_actor().global_translation = spawnloc.global_translation
	yield (get_tree().create_timer(0.3), "timeout")
	
	_get_player_actor().gravity_disable = false
	_get_player_actor()._enter_state(0)
	_get_player_actor()._exit_animation()
	
	PlayerData._send_notification("The tourney has started!")


func _finish_tourney(cancelled: bool = false):
	if not tourney_active: return
	
	tourney_active = false
	get_tree().root.remove_child(tourney_hud_instance)
	update_timer.stop()
	
	joined = false
	
	_update_intermission_timer()
	_send_net("finish")
	
	if cancelled:
		PlayerData._send_notification("The tourney has been cancelled! Nothing was awarded.", 1)
	else:
		PlayerData._send_notification("The tourney has finished!")
		var players: Array = playing_people.duplicate()
		playing_people.clear()
		
		print(playing_people)
		
		if not Network.GAME_MASTER: return
		
		for player in players:
			print(player)
			_send_net("score_request", {}, str(player))
		
		yield(get_tree().create_timer(1), "timeout") # hacky; make it actually wait for every score.
		
		var keys = people_scores.keys()
		keys.sort_custom(self, "_compare_values")
		
		var sorted_scores: Dictionary = {}
		
		for key in keys:
			sorted_scores[key] = people_scores[key]
		
		for player in players:
			_send_net("results", {"scores": sorted_scores}, str(player))

func _compare_values(a, b):
	return people_scores[b] - people_scores[a]

func _intermission_timer_timeout():
	if not Network.GAME_MASTER: return
	_send_net("start")

func _update_timer_timeout():
	var seconds = int(tourney_timer.time_left) % 60
	var minutes = int(tourney_timer.time_left / 60) % 60
	
	tourney_hud_instance.set_text("%02d:%02d" % [minutes, seconds])
