extends CharacterBody2D

@export var speed: float = 250.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _physics_process(delta):
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	velocity = direction * speed
	
	move_and_slide()
	
	if velocity.length() > 0:
		
		if abs(velocity.x) > abs(velocity.y):
			animated_sprite.play("walk_side")
			
			if velocity.x < 0:
				animated_sprite.flip_h = true
			else:
				animated_sprite.flip_h = false
		else:
			animated_sprite.flip_h = false
			
			if velocity.y < 0:
				animated_sprite.play("walk_back")
			else:
				animated_sprite.play("walk_front")
				
	else:
		animated_sprite.play("idle")
		
		
@export var max_health_halves: int = 6
var current_health_halves: int

signal health_changed(new_health)
signal died

func _ready():
	current_health_halves = max_health_halves
	health_changed.emit(current_health_halves)

func take_damage(damage_amount_halves: int = 1):
	
	if current_health_halves <= 0:
		return

	current_health_halves -= damage_amount_halves
	
	current_health_halves = max(0, current_health_halves)
	
	print("Vida actual: ", current_health_halves)
	
	health_changed.emit(current_health_halves)
	
	if current_health_halves == 0:
		die()

func heal(heal_amount_halves: int = 1):
	current_health_halves += heal_amount_halves
	
	current_health_halves = min(current_health_halves, max_health_halves)
	
	print("Vida actual: ", current_health_halves)
	
	health_changed.emit(current_health_halves)

func add_heart_container():
	max_health_halves += 2
	heal(2)

func die():
	print("¡El jugador ha muerto!")
	
	died.emit()
	
	set_physics_process(false)
	hide()
	
	await get_tree().create_timer(2.0).timeout
	get_tree().reload_current_scene()

func _unhandled_input(event):
	
	# Comprueba si la tecla que apretaste es la 'T'
	if event.is_action_pressed("move_down"):
		
		# ¡Llama a tu propia función de daño!
		print("¡Prueba de daño!")
		take_damage(1) # 1 = una mitad de corazón
