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
var player = -1
var turn = -1
var selected_card
var zoom = 1.0
var used_positions = [[],[]]
var select = "none"
var state
var using_card = false
var ai = true

signal target_selected(target)
signal effect_used()


class Card:
	var ID
	var owner
	var type
	var level
	var temperature
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
		node = n
		in_game = a
		equiped = []
	
	func update():
		node.get_node("Level").set_text(str(level))
		node.get_node("Temp").set_text(str(temperature))
		if (temperature>0):
			node.get_node("OverlayTemp").set_modulate(Cards.COLOR_HOT)
		elif (temperature<0):
			node.get_node("OverlayTemp").set_modulate(Cards.COLOR_COLD)
		else:
			node.get_node("OverlayTemp").set_modulate(Color(0.5,0.5,0.5))
		for i in range(equiped.size()):
			var card = equiped[i]
			var offset = min(75,200/equiped.size())
			var pos = node.get_global_position()+Vector2(0,offset*(i+1))*(1-2*owner)
			card.node._z = -i-1
			card.node.z_index = -i-1
			card.node.pos = pos
			card.node.get_node("Tween").interpolate_property(card.node,"global_position",card.node.get_global_position(),pos,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT)
			card.node.get_node("Tween").start()
	
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
	

class TemperatureSorter:
	static func sort_ascending(a,b):
		return abs(a.temperature)>abs(b.temperature)




func reset():
	# Reset to initial values and remove old cards.
	for card in field[PLAYER1]+field[PLAYER2]+hand[PLAYER1]+hand[PLAYER2]:
		card.node.queue_free()
	field = [[],[]]
	hand = [[],[]]
	graveyard = [[],[]]
	deck = [[],[]]
	mana = [2,3]
	mana_max = [2,3]
	health = [20,20]
	used_positions = [[],[]]
	turn = -1
	player = -1
	selected_card = null
	select = "none"
	UI.get_node("Player1/VBoxContainer/Health/Bar").set_max(20)
	UI.get_node("Player2/VBoxContainer/Health/Bar").set_max(20)
	UI.get_node("Player1/VBoxContainer/ButtonC").show()
	UI.get_node("Player1/VBoxContainer/ButtonE").show()
	Music.temperature = 0
	deselect()

func start():
	# Start a new match.
	timer.set_wait_time(0.2)
	for i in range(START_CARDS):
		draw_card(PLAYER1)
		draw_card(PLAYER2)
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
	get_node("/root/Menu")._show()
	get_node("/root/Menu").game_over(lost)
	UI._hide()
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
	var temp = 0
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


func play_card(card,player,target=null):
	if (card.owner!=player || mana[player]<card.level || !(card in hand[player])):
		return
	
	print("Player "+str(player)+" plays card "+str(card)+".")
	using_card = true
	get_node("SoundPlay").play()
	if (!card.node.get_node("Image").is_visible() || card.node.get_node("Animation").get_current_animation()=="hide"):
		card.node.get_node("Animation").play("show")
	if (card.type=="creature"):
		var p = find_empty_position(player)
		var pos = Vector2(225*p,200*(1-2*player))
		used_positions[player].push_back(p)
		card.pos = p
		field[player].push_back(card)
		hand[player].erase(card)
		card.node.get_node("Tween").interpolate_property(card.node,"global_position",card.node.get_global_position(),pos,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT)
		card.node.get_node("Tween").start()
		card.node._z = 0
		card.node.z_index = 0
		card.in_game = true
		card.node.type = "creature"
		card.node.pos = pos
		if (Cards.data[card.ID].has("on_play")):
			apply_effect(card,"on_play")
	elif (card.type=="spell" && Cards.data[card.ID].has("on_play")):
		var p = Vector2(card.node.get_global_position().x,0.5*card.node.get_global_position().y)
		card.node.get_node("Tween").interpolate_property(card.node,"global_position",card.node.get_global_position(),p,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT)
		card.node.get_node("Tween").start()
		call_deferred("use_effect",card,"on_play",player,target)
		yield(self,"effect_used")
		if (state==null || !state["used"]):
			printt("Invalid selection, break spell casting.")
			deselect(false)
			if (ai && player==PLAYER2):
				card.node.get_node("Animation").play("hide")
			return
		
		if (state.has("target") && state["target"]!=null && (state["target"] in field[PLAYER1]+field[PLAYER2])):
			var pos = state["target"].node.get_global_position()+Vector2(0,(100*(state["target"].equiped.size()+3)-225*int(player==PLAYER2))*(1-2*state["target"].owner))
			card.node.get_node("Tween").interpolate_property(card.node,"global_position",card.node.get_global_position(),pos,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT)
			card.node.get_node("Tween").start()
			card.node._z = -state["target"].equiped.size()-1
			card.node.z_index = -state["target"].equiped.size()-1
			card.node.type = "equiped"
			card.node.pos = pos
			state["target"].equiped.push_back(card)
			state["target"].update()
			if (Cards.data[card.ID].has("animation")):
				var pi = load("res://scenes/animations/"+Cards.data[card.ID]["animation"]+".tscn").instance()
				state["target"].node.add_child(pi)
				pi.look_at(card.node.get_global_position())
				pi.rotate(PI)
		else:
			card.node.type = "dead"
			if (Cards.data[card.ID].has("animation")):
				if (state.has("target") && state["target"]!=null):
					var pi = load("res://scenes/animations/"+Cards.data[card.ID]["animation"]+".tscn").instance()
					state["target"].node.add_child(pi)
					pi.look_at(card.node.get_global_position())
					pi.rotate(PI)
				else:
					var pi = load("res://scenes/animations/"+Cards.data[card.ID]["animation"]+".tscn").instance()
					card.node.add_child(pi)
			timer.set_wait_time(0.5)
			timer.start()
			yield(timer,"timeout")
			card.node.get_node("AnimationPlayer").play("delayed_fade_out")
		card.in_game = true
		hand[player].erase(card)
	
	using_card = false
	mana[player] -= card.level
	deselect(false)
	update_stats()
	sort_hand(player)

func use_effect(card,effect,player,target=null):
	var data = Cards.data[card.ID]
	var type = data[effect]
	var s = type.split("-")
	var ammount = 0
	var enemy = (player+1)%2
	if (s.size()>1):
		type = s[0]
		ammount = int(s[1])
	
	if (data.has("target") && data["target"]=="creature"):
		if (target==null):
			select = "creature"
			if (player==PLAYER1):
				UI.get_node("Player1/VBoxContainer/ButtonC").set_text(tr("CANCEL"))
				UI.get_node("Player1/VBoxContainer/ButtonC").set_disabled(false)
			print("Please select a "+select+" card.")
			for c in field[player]:
				c.node.get_node("Animation").play("blink")
			if !("ally" in type):
				for c in field[enemy]:
					c.node.get_node("Animation").play("blink")
			yield(self,"target_selected")
			target = selected_card
		
		if (target==null):
			state = {"used":false}
			return
	
	if (type=="inc_temp"):
		target.temperature += ammount
	elif (type=="dec_temp"):
		target.temperature -= ammount
	elif (type=="neutralize_temp"):
		if (target.temperature>0):
			target.temperature -= ammount
		elif (target.temperature<0):
			target.temperature += ammount
		else:
			state = {"used":false}
			emit_signal("effect_used")
			return
	elif (type=="inc_ally_temp"):
		if (target.owner!=player):
			state = {"used":false}
			emit_signal("effect_used")
			return
		target.temperature += ammount
	elif (type=="kill_cold"):
		if (target.temperature>=0 || -target.temperature>ammount):
			state = {"used":false}
			emit_signal("effect_used")
			return
		target.destroy()
	elif (type=="kill_hot"):
		if (target.temperature<=0 || target.temperature>ammount):
			state = {"used":false}
			emit_signal("effect_used")
			return
		target.destroy()
	elif (type=="kill_all_hot"):
		for card in field[PLAYER1]+field[PLAYER2]:
			if (card.temperature>0 && card.temperature<=ammount):
				card.destroy()
	elif (type=="kill_all_cold"):
		for card in field[PLAYER1]+field[PLAYER2]:
			if (card.temperature<0 && -card.temperature<=ammount):
				card.destroy()
	elif (type=="draw"):
		get_node("SoundShuffle").play()
		for i in range(ammount):
			draw_card(player)
			timer.set_wait_time(0.2)
			timer.start()
			yield(timer,"timeout")
		timer.set_wait_time(0.1)
		timer.start()
		yield(timer,"timeout")
		sort_hand(player)
	elif (type=="move_to_hand"):
		hand[enemy].push_back(target)
		field[enemy].erase(target)
		for c in target.equiped:
			c.destroy()
		target.equiped.clear()
		target.in_game = false
		target.node.type = "hand"
		target.temperature = Cards.data[target.ID]["temperature"]
		target.level = Cards.data[target.ID]["level"]
		used_positions[enemy].erase(target.pos)
		sort_hand(enemy)
	elif (type=="invert_temp"):
		target.temperature *= -1
		target.update()
	elif (type=="explosion"):
		var dmg = abs(target.temperature)
		if (dmg==0 || target.owner!=player):
			state = {"used":false}
			emit_signal("effect_used")
			return
		target.destroy()
		for card in field[PLAYER1]+field[PLAYER2]:
			if (abs(card.temperature)<dmg):
				card.destroy()
	
	if (target!=null):
		target.update()
	
	state = {"used":true,"target":target}
	emit_signal("effect_used")
	return

func apply_effect(card,event):
	var effect = Cards.data[card.ID][event]
	var array = effect.split("-")
	var base = array[0]
	var ammount
	if (array.size()>1):
		ammount = int(array[1])
	
	if (base=="ice_armor"):
		if (player==card.owner):
			card.temperature += ammount
		else:
			card.temperature -= ammount
		card.update()
	elif (base=="fire_armor"):
		if (player==card.owner):
			card.temperature -= ammount
		else:
			card.temperature += ammount
		card.update()
	elif (base=="inc_ally_temp"):
		for c in field[card.owner]:
			c.temperature += ammount
			c.update()

func attack(attacker,target,no_counter=false):
	var counterattack = !no_counter && abs(target.temperature)>=abs(attacker.temperature) && sign(attacker.temperature)!=sign(target.temperature)
	if (abs(attacker.temperature)>=abs(target.temperature) && sign(attacker.temperature)!=sign(target.temperature)):
		var pos_a = attacker.node.get_global_position()
		var pos = 0.75*attacker.node.get_global_position()+0.25*target.node.get_global_position()
		if (Cards.data[attacker.ID].has("animation")):
			var pi = load("res://scenes/animations/"+Cards.data[attacker.ID]["animation"]+".tscn").instance()
			attacker.node.add_child(pi)
			pi.look_at(target.node.get_global_position())
		target.destroy()
		attacker.node.get_node("Tween").interpolate_property(attacker.node,"global_position",pos_a,pos,0.4,Tween.TRANS_BACK,Tween.EASE_IN_OUT)
		attacker.node.get_node("Tween").interpolate_property(attacker.node,"global_position",pos,pos_a,0.6,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT,0.4)
		attacker.node.get_node("Tween").start()
	if (counterattack):
		attack(target,attacker,true)


func draw_card(pl):
	if (deck[pl].size()==0):
		print("Player "+str(pl)+" has no cards left!")
		return
	
	var ID = randi()%deck[pl].size()
	var node = Cards.create_card(deck[pl][ID])
	var p = hand[pl].size()
	var card = Card.new(deck[pl][ID],pl,node)
	var offset = min(200,(OS.get_window_size().x-100)/max(hand[pl].size(),1))
	var pos1 = Vector2(-250+500*pl,250-500*pl)
	var pos2 = Vector2((225+p*offset/zoom-OS.get_window_size().x/2.0)*(1-2*pl),OS.get_window_size().y/2.0*(1-2*pl))*zoom
	hand[pl].push_back(card)
	node.card = card
	node._z = 1
	node.z_index = 1
	node.set_position(OS.get_window_size()/2.0*Vector2(-1+2*pl,1-2*pl)*zoom)
	get_node("Cards").add_child(node)
	node.get_node("Tween").interpolate_property(node,"global_position",node.get_global_position(),pos1,0.25,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT)
	node.get_node("Tween").interpolate_property(node,"global_position",pos1,pos2,0.5,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT,0.25)
	node.get_node("Tween").start()
	node.pos = pos2
	deck[pl].remove(ID)
	update_stats()
	get_node("SoundDraw").play()
	if (ai):
		if (pl==PLAYER2):
			node.get_node("Animation").play("hide",-1,10.0)
	else:
		if (pl!=player):
			node.get_node("Animation").play("hide",-1,10.0)

func sort_hand(player):
	if (player<PLAYER1):
		return
	
	var ID = 0
	var offset = min(200,(OS.get_window_size().x-100)/max(hand[player].size(),1))
	for card in hand[player]:
		var pos = Vector2((225+ID*offset/zoom-OS.get_window_size().x/2.0)*(1-2*player),OS.get_window_size().y/2.0*(1-2*player))*zoom
		card.node.get_node("Tween").interpolate_property(card.node,"global_position",card.node.get_global_position(),pos,0.5,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT)
		card.node.get_node("Tween").start()
		card.node.pos = pos
		ID += 1

func select(card,type):
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
#	if (select=="hand" && (Cards.data[card.ID]["type"]=="creature" || (Cards.data[card.ID]["type"]=="spell" && !Cards.data[card.ID].has("target")))):
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
#	deselect()


func end_turn():
	deselect()
	attack_phase()

func next_turn(draw=1):
	var enemy
	if (turn>0):
		deselect()
	turn += 1
	player = turn%2
	enemy = (player+1)%2
	
	mana_max[player] += 1
	mana[player] = mana_max[player]
	for i in range(draw):
		draw_card(player)
	
	for card in field[PLAYER1]+field[PLAYER2]:
		if (Cards.data[card.ID].has("on_new_turn")):
			apply_effect(card,"on_new_turn")
	
	selected_card = null
	select = "hand"
	update_stats()
	
	if (!ai):
		for card in hand[player]:
			card.node.get_node("Animation").play("show")
		for card in hand[enemy]:
			card.node.get_node("Animation").play("hide")
	
	if (hand[PLAYER1].size()==0 && hand[PLAYER2].size()==0):
		game_over(health[PLAYER1]<=health[PLAYER2])
		return
	
	UI.get_node("Player"+str(player+1)+"/VBoxContainer/ButtonE").set_disabled(false)
	UI.get_node("Player"+str(enemy+1)+"/VBoxContainer/ButtonE").set_disabled(true)
	if (!ai):
		UI.get_node("Player"+str(player+1)+"/VBoxContainer/ButtonC").show()
		UI.get_node("Player"+str(player+1)+"/VBoxContainer/ButtonE").show()
		UI.get_node("Player"+str(enemy+1)+"/VBoxContainer/ButtonC").hide()
		UI.get_node("Player"+str(enemy+1)+"/VBoxContainer/ButtonE").hide()
	
	if (ai && player==PLAYER2):
		ai_turn(player)

func attack_phase():
	var enemy = (player+1)%2
	var list = []+field[player]
	var draw = 1
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
		update_stats()
	
	if (turn>0 && field[enemy].size()==0):
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


func update_stats():
	# Update GUI.
	for p in range(2):
		var temp = get_player_temperature(p)
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Health").set_text(tr("HEALTH")+": "+str(health[p]))
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Health/Bar").set_value(health[p])
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Mana").set_text(tr("MANA")+": "+str(mana[p]))
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Mana/Bar").set_value(mana[p])
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Mana/Bar").set_max(mana_max[p])
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Temp").set_text(tr("TEMPERATURE")+": "+str(temp))
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Temp/Bar").set_value(temp)
		UI.get_node("Player"+str(p+1)+"/VBoxContainer/Temp/Bar").set_modulate(Cards.COLOR_COLD.linear_interpolate(Cards.COLOR_HOT,temp/10.0+0.5))
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