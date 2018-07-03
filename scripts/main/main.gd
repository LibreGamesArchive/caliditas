extends Node2D

enum {
	PLAYER1 = 0
	PLAYER2 = 1
}
const START_CARDS = 4

var timer
var field = [[],[]]
var hand = [[],[]]
var graveyard = [[],[]]
var deck = [[],[]]
var mana = [0,0]
var mana_max = [0,0]
var health = [10,10]
var temperature = [0,0]
var player_name = ["",""]
var player = -1
var turn = -1
var selected_card
var zoom = 1.0
var used_positions = [[],[]]
var select = "none"
var state
var using_card = false
var ai = true
var multiplayer = false
var server = true

var text_temp = preload("res://scenes/main/text_temp.tscn")

signal card_played(player,card,target)
signal turn_started(player)
signal target_selected(target)
signal effect_used()


class Card:
	var ID
	var owner
	var type
	var level
	var temperature
	var last_temp
	var node
	var pos
	var in_game
	var equiped
	
	func _init(t,p,n,a=false):
		ID = t
		owner = p
		type = Cards.data[ID]["type"]
		level = Cards.data[ID]["level"]
		temperature = Cards.data[ID]["temperature"]
		last_temp = temperature
		node = n
		in_game = a
		equiped = []
	
	func update():
		node.get_node("Level").set_text(str(level))
		node.get_node("Temp").set_text(str(temperature))
		if (temperature>0):
			node.get_node("OverlayTemp").set_self_modulate(Cards.COLOR_HOT)
		elif (temperature<0):
			node.get_node("OverlayTemp").set_self_modulate(Cards.COLOR_COLD)
		else:
			node.get_node("OverlayTemp").set_self_modulate(Color(0.5,0.5,0.5))
		if (temperature!=last_temp):
			var text
			var ti = Main.text_temp.instance()
			if (temperature>last_temp):
				text = "+"
				ti.get_node("Label").add_color_override("font_color",Cards.COLOR_HOT)
			else:
				text = "-"
				ti.get_node("Label").add_color_override("font_color",Cards.COLOR_COLD)
			ti.get_node("Label").set_text(text+str(abs(temperature-last_temp)))
			ti.set_global_position(node.get_node("Temp").get_global_position()-Vector2(16,0))
			Main.add_child(ti)
			last_temp = temperature
		for i in range(equiped.size()):
			var card = equiped[i]
			var offset = min(75,200/equiped.size())
			var pos = node.get_global_position()+Vector2(0,offset*(i+1))*(1-2*owner)
			card.node._z = -i-1
			card.node.set_z_index(-i-1)
			card.node.pos = pos
			card.node.get_node("Tween").interpolate_property(card.node,"global_position",card.node.get_global_position(),pos,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT)
			card.node.get_node("Tween").start()
	
	func remove_equipment():
		for c in []+equiped:
			c.destroy()
		equiped.clear()
	
	func destroy():
		for c in equiped:
			c.node.get_node("AnimationPlayer").play("fade_out")
			c.node._z -= 1
			c.node.z_index -= 1
			c.node.type = "dead"
		node.get_node("AnimationPlayer").play("fade_out")
		node._z -= 1
		node.z_index -= 1
		node.type = "dead"
		if (pos!=null):
			Main.used_positions[owner].erase(pos)
		in_game = false
		Main.graveyard[owner].push_back(self)
		Main.field[owner].erase(self)
		if (Cards.data[ID].has("on_removed")):
			Main.apply_effect(self,"on_removed")
		for card in equiped:
			if (Cards.data[card.ID].has("on_removed")):
				Main.apply_effect(card,"on_removed",self)

# Used for sorting arrays descending by absolute value of temperature.
class TemperatureSorter:
	static func sort_ascending(a,b):
		return abs(a.temperature)>abs(b.temperature)




func reset():
	# Reset to initial values and remove old cards.
	for card in get_node("Cards").get_children():
		card.queue_free()
	field = [[],[]]
	hand = [[],[]]
	graveyard = [[],[]]
	deck = [[],[]]
	mana = [2,3]
	mana_max = [2,3]
	health = [20,20]
	temperature = [0,0]
	used_positions = [[],[]]
	turn = -1
	player = -1
	selected_card = null
	ai = false
	multiplayer = false
	server = true
	select = "none"
	UI.get_node("Player1/VBoxContainer/Health/Bar").set_max(health[PLAYER1])
	UI.get_node("Player2/VBoxContainer/Health/Bar").set_max(health[PLAYER2])
	UI.get_node("Player1/VBoxContainer/ButtonC").show()
	UI.get_node("Player1/VBoxContainer/ButtonE").show()
	Music.temperature = 0
	deselect()

func start():
	# Start a new match.
	timer.set_wait_time(0.2)
	UI.get_node("Player1/VBoxContainer/Name").set_text(player_name[PLAYER1])
	UI.get_node("Player2/VBoxContainer/Name").set_text(player_name[PLAYER2])
	if (ai):
		UI.get_node("Player2/VBoxContainer/ButtonC").hide()
		UI.get_node("Player2/VBoxContainer/ButtonE").hide()
	for i in range(START_CARDS):
		_draw_card(PLAYER1)
		_draw_card(PLAYER2)
		timer.start()
		yield(timer,"timeout")
	
	next_turn()

func game_over(lost=null):
	# Return to menu.
	if (lost==null):
		lost = player==PLAYER1
	timer.set_wait_time(1.0)
	timer.start()
	yield(timer,"timeout")
	get_node("/root/Menu").game_over(lost)

func hide():
	for card in get_node("Cards").get_children():
		card.get_node("AnimationPlayer").play("fade_out")


func find_empty_position(player):
	var p = 0
	while (used_positions[player].has(p)):
		p += 1
		if (!used_positions[player].has(-p)):
			p *= -1
			break
	
	return p

func get_player_temperature(player):
	var temp = temperature[player]
	for card in field[player]:
		temp += card.temperature
	return temp

func ai_turn(player):
	# Start the AI.
	var action = AI.get_creature()
	var counter = 0
	timer.set_wait_time(1.0)
	timer.start()
	yield(timer,"timeout")
	while (action!=null):
		timer.set_wait_time(0.5)
		timer.start()
		yield(timer,"timeout")
		play_card(action["card"],player,action["target"])
		counter += 1
		if (counter>20):
			break
		else:
			action = AI.get_action()
			timer.set_wait_time(0.5)
			timer.start()
			yield(timer,"timeout")
	
	timer.set_wait_time(1.0)
	timer.start()
	yield(timer,"timeout")
	end_turn()


# Send positions instead of classes to other players.
remote func _play_card(c,p,t):
	var target
	var player = (p+1)%2
	var card = hand[player][c]
	if (t.has("type")):
		if (t["type"]=="field"):
			target = field[(t["player"]+1)%2][t["ID"]]
		elif (t["type"]=="equiped"):
			target = field[(t["player"]+1)%2][t["ID"]].equiped[t["index"]]
		elif (t["type"]=="hand"):
			target = hand[(t["player"]+1)%2][t["ID"]]
	play_card(card,player,target)

func play_card(card,player,target=null):
	if (card.owner!=player || mana[player]<card.level || !(card in hand[player])):
		return
	
	var c
	print("Player "+str(player)+" plays card "+str(card)+".")
	if (multiplayer && player==PLAYER1):
		for i in range(hand[player].size()):
			if (hand[player][i]==card):
				c = i
				break
	using_card = true
	get_node("SoundPlay").play()
	state = {"used":false}
	if (!card.node.get_node("Image").is_visible() || card.node.get_node("Animation").get_current_animation()=="hide"):
		card.node.get_node("Animation").play("show")
	if (card.type=="creature"):
		var p2
		var p1 = Vector2(card.node.get_global_position().x,0.5*card.node.get_global_position().y)
		spawn_creature(card,player)
		card.node.get_node("Tween").remove_all()
		card.node.get_node("Tween").interpolate_property(card.node,"global_position",card.node.get_global_position(),p1,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT)
		p2 = Vector2(225*card.pos,200*(1-2*player))
		card.node.get_node("Tween").interpolate_property(card.node,"global_position",p1,p2,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT,0.25)
		card.node.get_node("Tween").start()
	elif (card.type=="spell" && Cards.data[card.ID].has("on_play")):
		var p = Vector2(card.node.get_global_position().x,0.5*card.node.get_global_position().y)
		card.node.get_node("Tween").interpolate_property(card.node,"global_position",card.node.get_global_position(),p,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT)
		card.node.get_node("Tween").start()
		call_deferred("use_effect",card,"on_play",player,target)
		yield(self,"effect_used")
		if (state==null || !state["used"]):
			print("Invalid selection, break spell casting.")
			deselect(false)
			if ((ai || multiplayer) && player==PLAYER2):
				card.node.get_node("Animation").play("hide")
			return
		
		if (state.has("target") && state["target"]!=null && (state["target"] in field[PLAYER1]+field[PLAYER2])):
			var pos
			var offset
			var p2
			target = state["target"]
			pos = target.node.get_global_position()+Vector2(0,(100*(target.equiped.size()+3)-225*int(player==PLAYER2))*(1-2*target.owner))
			offset = min(75,200/(target.equiped.size()+1))
			p2 = target.node.get_global_position()+Vector2(0,offset*(target.equiped.size()+1))*(1-2*target.owner)
			card.node._z = -target.equiped.size()-1
			card.node.set_z_index(-target.equiped.size()-1)
			card.node.type = "equiped"
			card.node.pos = pos
			target.equiped.push_back(card)
			target.update()
			card.node.get_node("Tween").remove_all()
			if (card.node.get_global_position()==p):
				card.node.get_node("Tween").interpolate_property(card.node,"global_position",card.node.get_global_position(),pos,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT)
				card.node.get_node("Tween").interpolate_property(card.node,"global_position",pos,p2,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT,0.25)
			else:
				card.node.get_node("Tween").interpolate_property(card.node,"global_position",p,pos,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT,0.25)
				card.node.get_node("Tween").interpolate_property(card.node,"global_position",pos,p2,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT,0.5)
			card.node.get_node("Tween").start()
			if (Cards.data[card.ID].has("animation")):
				var pi = load("res://scenes/animations/"+Cards.data[card.ID]["animation"]+".tscn").instance()
				target.node.add_child(pi)
				pi.look_at(card.node.get_global_position())
				pi.rotate(PI)
		else:
			card.node.type = "dead"
			if (Cards.data[card.ID].has("animation")):
				if (state.has("target") && state["target"]!=null):
					var pi
					target = state["target"]
					pi = load("res://scenes/animations/"+Cards.data[card.ID]["animation"]+".tscn").instance()
					target.node.add_child(pi)
					pi.look_at(card.node.get_global_position())
					pi.rotate(PI)
				else:
					var pi = load("res://scenes/animations/"+Cards.data[card.ID]["animation"]+".tscn").instance()
					card.node.add_child(pi)
			timer.set_wait_time(0.5)
			timer.start()
			yield(timer,"timeout")
			card.node.get_node("AnimationPlayer").play("fizzle")
		card.in_game = true
		hand[player].erase(card)
	
	if (multiplayer && player==PLAYER1):
		var t = {}
		if (state!=null && state.has("_target")):
			t = state["_target"]
		if (c!=null):
			rpc("_play_card",c,player,t)
	using_card = false
	mana[player] -= card.level
	deselect(false)
	update_stats()
	sort_hand(player)
	sort_cards()
	emit_signal("card_played",player,card,target)

func spawn_creature(card,player):
	var pID = find_empty_position(player)
	var pos = Vector2(225*pID,200*(1-2*player))
	used_positions[player].push_back(pID)
	card.pos = pID
	hand[player].erase(card)
	card.node.get_node("Tween").interpolate_property(card.node,"global_position",card.node.get_global_position(),pos,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT)
	card.node.get_node("Tween").start()
	card.node._z = 0
	card.node.set_z_index(0)
	card.in_game = true
	card.node.type = "creature"
	card.node.pos = pos
	if (Cards.data[card.ID].has("on_play")):
		apply_effect(card,"on_play")
	for p in range(2):
		for c in field[p]:
			if (Cards.data[c.ID].has("on_creature_spawn")):
				apply_effect(c,"on_creature_spawn",card)
	for c in field[player]:
		if (Cards.data[c.ID].has("on_ally_creature_spawn")):
			apply_effect(c,"on_ally_creature_spawn",card)
	for c in field[(player+1)%2]:
		if (Cards.data[c.ID].has("on_enemy_creature_spawn")):
			apply_effect(c,"on_enemy_creature_spawn",card)
	field[player].push_back(card)

func create_creature(type,player,pos):
	var node = Cards.create_card(type)
	var card = Card.new(type,player,node)
	node.card = card
	node.pos = pos
	node.set_global_position(pos)
	get_node("Cards").add_child(node)
	spawn_creature(card,player)

func use_effect(card,effect,player,target=null):
	var data = Cards.data[card.ID]
	var type = data[effect]
	var s = type.split("-")
	var ammount = 0
	var enemy = (player+1)%2
	var target_type
	if (s.size()>1):
		type = s[0]
		ammount = int(s[1])
	
	if (data.has("target")):
		target_type = data["target"].split("-")
		if ("creature" in target_type):
			if (target==null):
				select = "creature"
				if (multiplayer && player!=PLAYER1):
					printt("Invalid target selected.")
					state = {"used":true}
					emit_signal("effect_used")
				if (player==PLAYER1):
					UI.get_node("Player1/VBoxContainer/ButtonC").set_text(tr("CANCEL"))
					UI.get_node("Player1/VBoxContainer/ButtonC").set_disabled(false)
				print("Please select a "+select+" card.")
				for c in field[player]:
					c.node.get_node("Animation").play("blink")
				if !("ally" in target_type):
					for c in field[enemy]:
						c.node.get_node("Animation").play("blink")
				yield(self,"target_selected")
				target = selected_card
		
		if (target!=null):
			if (("ally" in target_type) && target.owner!=player):
				target = null
		if (target==null):
			state = {"used":false}
			emit_signal("effect_used")
			return
	
	state = {"used":false}
	if (multiplayer && player==PLAYER1):
		var t = {}
		if (target!=null):
			for p in range(2):
				for i in range(field[p].size()):
					var _c = field[p][i]
					if (_c==target):
						t["ID"] = i
						t["player"] = p
						t["type"] = "field"
						break
					for j in range(_c.equiped.size()):
						if (_c.equiped[j]==target):
							t["ID"] = i
							t["player"] = p
							t["type"] = "equipment"
							t["index"] = j
							break
				for i in range(hand[p].size()):
					if (hand[p][i]==target):
						t["ID"] = i
						t["player"] = p
						t["type"] = "hand"
			if (t.size()>0):
				state["_target"] = t
	
	if (type=="neutralize_temp"):
		if (target.temperature==0):
			emit_signal("effect_used")
			return
	elif (type=="kill_cold"):
		if (target.temperature>=0 || -target.temperature>ammount):
			emit_signal("effect_used")
			return
	elif (type=="kill_hot"):
		if (target.temperature<=0 || target.temperature>ammount):
			emit_signal("effect_used")
			return
	elif (type=="kill_level"):
		if (target.level>ammount):
			emit_signal("effect_used")
			return
	elif (type=="explosion"):
		var dmg = abs(target.temperature)
		if (dmg==0 || target.owner!=player):
			emit_signal("effect_used")
			return
	
	apply_effect(card,effect,target)
	
	state["used"] = true
	state["target"] = target
	emit_signal("effect_used")
	return

func apply_effect(card,event,target=null):
	var effect = Cards.data[card.ID][event]
	var enemy = (card.owner+1)%2
	var array = effect.split("-")
	var base = array[0]
	var ammount
	if (array.size()>1):
		ammount = int(array[1])
	
	if (base=="inc_temp"):
		target.temperature += ammount
		target.update()
	elif (base=="dec_temp"):
		target.temperature -= ammount
		target.update()
	elif (base=="neutralize_temp"):
		if (target.temperature>0):
			target.temperature -= ammount
		elif (target.temperature<0):
			target.temperature += ammount
		target.update()
	elif (base=="ice_armor"):
		if (player==card.owner):
			target.temperature += ammount
		else:
			target.temperature -= ammount
		target.update()
	elif (base=="fire_armor"):
		if (player==target.owner):
			target.temperature -= ammount
		else:
			target.temperature += ammount
		target.update()
	elif (base=="inc_ally_temp"):
		for c in field[card.owner]:
			c.temperature += ammount
			c.update()
	elif (base=="dec_ally_temp"):
		for c in field[card.owner]:
			c.temperature -= ammount
			c.update()
	elif (base=="kill_cold"):
		if (target.temperature<0 && -target.temperature<=ammount):
			target.destroy()
	elif (base=="kill_hot"):
		if (target.temperature>0 && target.temperature<=ammount):
			target.destroy()
	elif (base=="kill_level"):
		if (target.level<=ammount):
			target.destroy()
	elif (base=="kill_all_hot"):
		for c in field[PLAYER1]+field[PLAYER2]:
			if (c.temperature>0 && c.temperature<=ammount):
				c.destroy()
	elif (base=="kill_all_cold"):
		for c in field[PLAYER1]+field[PLAYER2]:
			if (c.temperature<0 && -c.temperature<=ammount):
				c.destroy()
	elif (base=="draw"):
		get_node("SoundShuffle").play()
		for i in range(ammount):
			_draw_card(player)
			timer.set_wait_time(0.2)
			timer.start()
			yield(timer,"timeout")
		timer.set_wait_time(0.1)
		timer.start()
		yield(timer,"timeout")
		sort_hand(player)
	elif (base=="move_to_hand"):
		hand[target.owner].push_back(target)
		field[target.owner].erase(target)
		target.remove_equipment()
		if (Cards.data[target.ID].has("on_removed")):
			apply_effect(target,"on_removed")
		target.in_game = false
		target.node.type = "hand"
		target.temperature = Cards.data[target.ID]["temperature"]
		target.level = Cards.data[target.ID]["level"]
		target.update()
		if (target.owner!=player && !((ai || multiplayer) && target.owner==PLAYER1)):
			target.node.get_node("Animation").play("hide")
		used_positions[enemy].erase(target.pos)
		sort_hand(enemy)
	elif (base=="invert_temp"):
		target.temperature *= -1
		target.update()
	elif (base=="cleanse"):
		target.remove_equipment()
		target.temperature = Cards.data[target.ID]["temperature"]
		target.level = Cards.data[target.ID]["level"]
		target.update()
		card.destroy()
	elif (base=="explosion"):
		var dmg = abs(target.temperature)
		target.destroy()
		if (dmg>0):
			for c in field[PLAYER1]+field[PLAYER2]:
				if (abs(c.temperature)<dmg):
					c.destroy()
	elif (base=="spawn"):
		if (array.size()>=2):
			for i in range(ammount):
				create_creature(array[2],card.owner,card.node.pos)
	elif (base=="assemble"):
		for c in []+field[card.owner]:
			card.temperature += c.temperature
			c.destroy()
		card.update()
	elif (base=="global_diffusion"):
		var global_temp = (get_player_temperature(PLAYER1)+get_player_temperature(PLAYER2))/2
		target.temperature += ammount*sign(global_temp-target.temperature)
	elif (base=="global_diffusion_all"):
		var global_temp = (get_player_temperature(PLAYER1)+get_player_temperature(PLAYER2))/2
		for c in field[PLAYER1]+field[PLAYER2]:
			c.temperature += ammount*sign(global_temp-c.temperature)
	elif (base=="inc_player_temp"):
		temperature[card.owner] += ammount
	elif (base=="dec_player_temp"):
		temperature[card.owner] -= ammount
	
	

# Send positions instead of classes to other players.
remote func _attack(a,t,no_counter=false):
	var attacker = field[(a["player"]+1)%2][a["index"]]
	var target = field[(t["player"]+1)%2][t["index"]]
	attack(attacker,target,no_counter)

func attack(attacker,target,no_counter=false):
	var counterattack = !no_counter && abs(target.temperature)>=abs(attacker.temperature) && sign(attacker.temperature)!=sign(target.temperature)
	if (multiplayer && server):
		var a = {}
		var t = {}
		for p in range(2):
			for i in range(field[p].size()):
				if (field[p][i]==attacker):
					a["index"] = i
					a["player"] = p
				if (field[p][i]==target):
					t["index"] = i
					t["player"] = p
		if (a.size()>0 && t.size()>0):
			rpc("_attack",a,t,no_counter)
	if (abs(attacker.temperature)>=abs(target.temperature) && sign(attacker.temperature)!=sign(target.temperature)):
		var pos_a = attacker.node.get_global_position()
		var pos = 0.75*attacker.node.get_global_position()+0.25*target.node.get_global_position()
		if (Cards.data[target.ID].has("on_attacked")):
			apply_effect(target,"on_attacked",attacker)
		for equiped in target.equiped:
			if (Cards.data[equiped.ID].has("on_attacked")):
				apply_effect(equiped,"on_attacked",attacker)
		if (Cards.data[attacker.ID].has("on_attack")):
			apply_effect(attacker,"on_attack",target)
		for equiped in attacker.equiped:
			if (Cards.data[equiped.ID].has("on_attacked")):
				apply_effect(equiped,"on_attacked",target)
		if (Cards.data[attacker.ID].has("animation")):
			var pi = load("res://scenes/animations/"+Cards.data[attacker.ID]["animation"]+".tscn").instance()
			pi.set_global_position(attacker.node.get_global_position())
			pi.scale *= 0.15
			add_child(pi)
			pi.look_at(target.node.get_global_position())
		if (Cards.data[target.ID].has("on_dead")):
			apply_effect(target,"on_dead",attacker)
		for equiped in target.equiped:
			if (Cards.data[equiped.ID].has("on_dead")):
				apply_effect(equiped,"on_dead",attacker)
		target.destroy()
		attacker.node.get_node("Tween").interpolate_property(attacker.node,"global_position",pos_a,pos,0.4,Tween.TRANS_BACK,Tween.EASE_IN_OUT)
		attacker.node.get_node("Tween").interpolate_property(attacker.node,"global_position",pos,pos_a,0.6,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT,0.4)
		attacker.node.get_node("Tween").start()
	if (counterattack):
		attack(target,attacker,true)


func _draw_card(pl,ID=-1):
	if (server):
		ID = draw_card(pl,ID)
		if (multiplayer):
			rpc("draw_card",(pl+1)%2,ID)

remote func draw_card(pl,ID=-1):
	if (deck[pl].size()==0):
		print("Player "+str(pl)+" has no cards left!")
		return
	
	if (ID<0):
		ID = randi()%deck[pl].size()
	var node = Cards.create_card(deck[pl][ID])
	var p = hand[pl].size()
	var card = Card.new(deck[pl][ID],pl,node)
	var offset = min(200,(OS.get_window_size().x-100)/max(hand[pl].size(),1))
	var pos1 = Vector2(-250+500*pl,250-500*pl)
	var pos2 = Vector2((275+p*offset/zoom-OS.get_window_size().x/2.0)*(1-2*pl),OS.get_window_size().y/2.0*(1-2*pl))*zoom
	hand[pl].push_back(card)
	node.card = card
	node._z = 1
	node.set_z_index(1)
	node.set_position(OS.get_window_size()/2.0*Vector2(-1+2*pl,1-2*pl)*zoom)
	get_node("Cards").add_child(node)
	node.get_node("Tween").interpolate_property(node,"global_position",node.get_global_position(),pos1,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT)
	node.get_node("Tween").interpolate_property(node,"global_position",pos1,pos2,0.5,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT,0.25)
	node.get_node("Tween").start()
	node.pos = pos2
	deck[pl].remove(ID)
	update_stats()
	get_node("SoundDraw").play()
	if (ai || multiplayer):
		if (pl==PLAYER2):
			node.get_node("Animation").play("hide",-1,10.0)
	else:
		if (pl!=player):
			node.get_node("Animation").play("hide",-1,10.0)
	return ID

func sort_hand(player):
	# Shift the cards in hand to their right positions with offset depending on their number.
	# Therefore they all fit onto the screen.
	if (player<PLAYER1):
		return
	
	var ID = 0
	var offset = min(200,(OS.get_window_size().x-100)/max(hand[player].size(),1))
	for card in hand[player]:
		var pos = Vector2((275+ID*offset/zoom-OS.get_window_size().x/2.0)*(1-2*player),OS.get_window_size().y/2.0*(1-2*player))*zoom
		card.node.get_node("Tween").interpolate_property(card.node,"global_position",card.node.get_global_position(),pos,0.5,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT)
		card.node.get_node("Tween").start()
		card.node.pos = pos
		ID += 1

func sort_cards():
	# Sort the ordering of card nodes in the tree depending on z index.
	# That will ensure the Control nodes of the cards used for input overlap corresponding to the z index.
	# Does not work though.
	var z_min = 0
	for card in get_node("Cards").get_children():
		if (card.get_z_index()<z_min):
			z_min = card.get_z_index()
	
	for z in range(z_min,2):
		for card in get_node("Cards").get_children():
			if (card.get_z_index()==z):
				card.raise()
				card.get_node("Button").raise()

func select(card,type):
	if ((ai || multiplayer) && player!=PLAYER1):
		return
	if (type!=select):
		deselect(false)
		emit_signal("target_selected",null)
		return
	
	if (selected_card!=null):
		selected_card.node.get_node("Animation").play("deselect")
	selected_card = card
	selected_card.node.get_node("Animation").play("select")
	if (type=="hand"):
		UI.get_node("Player1/VBoxContainer/ButtonC").set_text(tr("PLAY"))
		UI.get_node("Player1/VBoxContainer/ButtonC").set_disabled(false)
	emit_signal("target_selected",card)
	
	if (select=="hand"):
		play_card(card,player)

func deselect(emit=true):
	if (selected_card!=null):
		selected_card.node.get_node("Animation").play("deselect")
	selected_card = null
	select = "hand"
	using_card = false
	UI.get_node("Player1/VBoxContainer/ButtonC").set_disabled(true)
	sort_hand(player)
	for node in get_node("Cards").get_children():
		if (node.get_node("Select").is_visible()):
			node.get_node("Animation").play("deselect")
	if (emit):
		state = null
		emit_signal("target_selected",null)
		emit_signal("effect_used")

func _confirm():
	if (using_card):
		deselect()
		return
	
	if (selected_card!=null):
		play_card(selected_card,player)


func end_turn():
	deselect()
	if (!multiplayer || server):
		attack_phase()
	else:
		rpc_id(1,"attack_phase")

func next_turn(draw=1):
	var enemy
#	if (turn>0):
	deselect()
	turn += 1
	player = turn%2
	enemy = (player+1)%2
	
	mana_max[player] += 1
	mana[player] = mana_max[player]
	if (server):
		for i in range(draw):
			_draw_card(player)
	
	for card in field[PLAYER1]+field[PLAYER2]:
		if (Cards.data[card.ID].has("on_new_turn")):
			apply_effect(card,"on_new_turn",card)
		for equiped in card.equiped:
			if (Cards.data[equiped.ID].has("on_new_turn")):
				apply_effect(equiped,"on_new_turn",card)
	
	selected_card = null
	select = "hand"
	update_stats()
	
	if (!ai && !multiplayer):
		for card in hand[player]:
			card.node.get_node("Animation").play("show")
		for card in hand[enemy]:
			card.node.get_node("Animation").play("hide")
	
	if (hand[PLAYER1].size()==0 && hand[PLAYER2].size()==0):
		game_over(health[PLAYER1]<=health[PLAYER2])
		return
	
	UI.get_node("Player"+str(player+1)+"/VBoxContainer/ButtonE").set_disabled(false)
	UI.get_node("Player"+str(enemy+1)+"/VBoxContainer/ButtonE").set_disabled(true)
	if (!ai && !multiplayer):
		UI.get_node("Player"+str(player+1)+"/VBoxContainer/ButtonC").show()
		UI.get_node("Player"+str(player+1)+"/VBoxContainer/ButtonE").show()
		UI.get_node("Player"+str(enemy+1)+"/VBoxContainer/ButtonC").hide()
		UI.get_node("Player"+str(enemy+1)+"/VBoxContainer/ButtonE").hide()
	
	if (ai && player==PLAYER2):
		ai_turn(player)
	
	emit_signal("turn_started",player)

remote func attack_phase():
	if (!server):
		return
	
	var enemy = (player+1)%2
	var list = []+field[player]
	var above_50 = health[enemy]>=10
	# Sort the creatures by abs(temperature).
	# As targets are chosen randomly this will prevent strong creatures defeating weak ones
	# and leaving only strong creatures that can't be killed by the weak ones.
	list.sort_custom(TemperatureSorter,"sort_ascending")
	
	# Attack random enemies that can be defeated.
	for card in list:
		var targets = []
		for t in field[enemy]:
			if (abs(t.temperature)<abs(card.temperature) && sign(t.temperature)!=sign(card.temperature)):
				targets.push_back(t)
		if (targets.size()==0):
			for t in field[enemy]:
				if (abs(t.temperature)==abs(card.temperature) && sign(t.temperature)!=sign(card.temperature)):
					targets.push_back(t)
		if (targets.size()==0):
			continue
		
		var target = targets[randi()%targets.size()]
		attack(card,target)
		timer.set_wait_time(1.0)
		timer.start()
		yield(timer,"timeout")
		if (multiplayer):
			rpc("update_stats")
		else:
			update_stats()
	
	if (multiplayer):
		rpc("attack_phase_end")
	else:
		attack_phase_end()

sync func attack_phase_end():
	var enemy = (player+1)%2
	var draw = 1
	if (turn>1-int(server) && field[enemy].size()==0):
		# Deal damage to enemy.
		var temp = get_player_temperature(player)
		var dmg = min(abs(temp),10)
		if (dmg>0):
			health[enemy] -= dmg
			# Draw 2 cards if damaged, 4 if health drops below 10 the first time.
			draw += 1+2*int(health[enemy]<10)
			if (temp>0):
				UI.get_node("Player"+str(enemy+1)+"/Animation").play("fire_damage")
			else:
				UI.get_node("Player"+str(enemy+1)+"/Animation").play("ice_damage")
			print("Deal "+str(dmg)+" damage to player "+str(enemy)+"!")
	
	if (health[enemy]<=0):
		update_stats()
		game_over()
	else:
		next_turn(draw)


sync func update_stats():
	# Update GUI.
	for p in range(2):
		var temp = get_player_temperature(p)
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Health/Label").set_text(tr("HEALTH")+": "+str(health[p]))
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Health/Bar").set_value(health[p])
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Mana/Label").set_text(tr("MANA")+": "+str(mana[p]))
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Mana/Bar").set_value(mana[p])
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Mana/Bar").set_max(mana_max[p])
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Temp/Label").set_text(tr("TEMPERATURE")+": "+str(temp))
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Temp/Bar").set_value(temp)
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Temp/Bar").get_material().set_shader_param("color",Cards.COLOR_COLD.linear_interpolate(Cards.COLOR_HOT,temp/10.0+0.5))
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Temp/Bar").get_material().set_shader_param("hot",max(temp/10.0,0.0))
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Temp/Top").get_material().set_shader_param("cold",max(-temp/10.0,0.0))
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Deck").set_text(tr("DECK")+": "+str(deck[p].size()))
	Music.temperature = get_player_temperature(player)+0.5*get_player_temperature((player+1)%2)


func _resize():
	zoom = max(1800.0/OS.get_window_size().x,1400.0/OS.get_window_size().y)
	get_node("Camera").make_current()
	get_node("Camera").set_zoom(zoom*Vector2(1,1))
	for p in range(2):
		sort_hand(p)

func _ready():
	timer = Timer.new()
	timer.set_one_shot(true)
	add_child(timer)
	get_tree().connect("screen_resized",self,"_resize")
	_resize()
	get_node("Camera").make_current()
