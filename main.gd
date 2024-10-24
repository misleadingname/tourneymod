extends Node

var tourney_prefab: PackedScene = preload("res://mods/misname.fishtourney/Scenes/Interactables/tourney_place.tscn")
var in_game: bool = false

signal tourney_net

func spawn_tourney(node: Node):
	if Network.PLAYING_OFFLINE:
		return
	
	var map: Node = get_tree().current_scene
	in_game = map.name == "world"
	
	if node.name != "main_map": return
	if not in_game: return
	
	if node.get_node_or_null("tourney_place"): return
	
	var tourney_instance: Spatial = tourney_prefab.instance()
	tourney_instance.transform.origin = Vector3(57.15, 3.25, -40)
	tourney_instance.rotation_degrees = Vector3(0, 190, 0)
	node.add_child(tourney_instance)

func readPackets():
	if Network.PLAYING_OFFLINE: return
	
	var PACKET_SIZE = Steam.getAvailableP2PPacketSize(4)
	if PACKET_SIZE > 0:
		var PACKET = Steam.readP2PPacket(PACKET_SIZE, 4)
		
		if PACKET.empty():
			print("Error! Empty Packet!")
		
		var data = bytes2var(PACKET.data.decompress_dynamic( - 1, File.COMPRESSION_GZIP))
		
#		PlayerData._send_notification("[RECEIVE NET] from: " + str(data.steamid) + " ... " + str(data))

		emit_signal("tourney_net", data.steamid, data)

func _ready():
	add_to_group("MISNAMETOURNEYMOD")
	get_tree().connect("node_added", self, "spawn_tourney")
	set_process(true)

func _process(delta):
	if Network.STEAM_LOBBY_ID > 0:
		readPackets()
