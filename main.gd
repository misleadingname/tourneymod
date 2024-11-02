extends Node

var tourney_prefab: PackedScene = preload("res://mods/misname.fishtourney/Scenes/Interactables/tourney_place.tscn")
var in_game: bool = false

signal tourney_net

func spawn_tourney(node:Node):
	if Network.PLAYING_OFFLINE:
		return
	in_game = node.name == "world"
	if not in_game: return
	var map_holder = node.get_node("Viewport/main/map")
	var current_map = map_holder.get_child(0)
	
	if get_tree().get_nodes_in_group("tourney_instance"): return
	
	var spawn_points = get_tree().get_nodes_in_group("tourney_spawn")
	if spawn_points:
		for sp in spawn_points:
			_instance_tourney(sp.transform.origin,sp.rotation_degrees,sp.get_parent())
	else:
		if !current_map.get_node_or_null("zones"): return
		var main_zone = current_map.get_node_or_null("zones/main_zone")
		if !main_zone: return
		_instance_tourney(Vector3(57.15, 3.25, -40),Vector3(0, 190, 0),main_zone)

func _instance_tourney(trans:Vector3,rotat:Vector3,parent:Node):
	var tourney_instance: Spatial = tourney_prefab.instance()
	tourney_instance.transform.origin = trans
	tourney_instance.rotation_degrees = rotat
	parent.add_child(tourney_instance)
	tourney_instance.add_to_group("tourney_instance")

func readPackets():
	if Network.PLAYING_OFFLINE: return
	
	var PACKET_SIZE = Steam.getAvailableP2PPacketSize(4)
	if PACKET_SIZE > 0:
		var PACKET = Steam.readP2PPacket(PACKET_SIZE, 4)
		
		if PACKET.empty():
			print("Error! Empty Packet!")
		
		var data = bytes2var(PACKET.data.decompress_dynamic( - 1, File.COMPRESSION_GZIP))
		
		#PlayerData._send_notification("[RECEIVE NET] from: " + str(data.steamid) + " ... " + str(data))

		emit_signal("tourney_net", data.steamid, data)

func _ready():
	add_to_group("MISNAMETOURNEYMOD")
	get_tree().root.connect("child_entered_tree",self,"spawn_tourney",[],CONNECT_DEFERRED)
	set_process(true)

func _process(delta):
	if Network.STEAM_LOBBY_ID > 0:
		readPackets()
