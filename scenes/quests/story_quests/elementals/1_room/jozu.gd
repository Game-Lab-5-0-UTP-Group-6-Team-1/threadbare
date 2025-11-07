##cambio mio
class_name Jozu
extends CharacterBody2D


# Arrastra tu escena de bala aquí desde el Inspector
@export var bullet_scene: PackedScene
@export var speed: float = 250.0

# --- Variables de Cooldown ---
@export var shoot_cooldown: float = 2.0 # 2 segundos
var can_shoot: bool = true
var cooldown_counter: float = 0.0
# ------------------------------------

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var facing_direction: Vector2 = Vector2.DOWN 

func _physics_process(delta):
	
	# --- 1. LÓGICA DE COOLDOWN ---
	if not can_shoot:
		cooldown_counter += delta 
		if cooldown_counter >= shoot_cooldown:
			can_shoot = true 
			cooldown_counter = 0.0 

	# --- 2. LÓGICA DE MOVIMIENTO (WASD) ---
	var move_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	velocity = move_direction * speed
	
	move_and_slide()
	
	# (Tu código de animación de movimiento)
	if velocity.length() > 0:
		if abs(velocity.x) > abs(velocity.y):
			animated_sprite.play("walk_side")
			facing_direction = Vector2(sign(velocity.x), 0)
			
			if velocity.x < 0:
				animated_sprite.flip_h = true
			else:
				animated_sprite.flip_h = false
		else:
			animated_sprite.flip_h = false
			
			if velocity.y < 0:
				animated_sprite.play("walk_back")
				facing_direction = Vector2.UP
			else:
				animated_sprite.play("walk_front")
				facing_direction = Vector2.DOWN
	else:
		animated_sprite.play("idle")

	# --- 3. LÓGICA DE DISPARO (FLECHAS) CON COOLDOWN ---
	if can_shoot:
		
		# "is_action_pressed" detecta si la tecla se mantiene presionada
		if Input.is_action_pressed("shoot_up"):
			shoot(Vector2.UP)
			can_shoot = false # ¡Inicia el cooldown!
		elif Input.is_action_pressed("shoot_down"):
			shoot(Vector2.DOWN)
			can_shoot = false # ¡Inicia el cooldown!
		elif Input.is_action_pressed("shoot_left"):
			shoot(Vector2.LEFT)
			can_shoot = false # ¡Inicia el cooldown!
		elif Input.is_action_pressed("shoot_right"):
			shoot(Vector2.RIGHT)
			can_shoot = false # ¡Inicia el cooldown!
		
		
# --- CÓDIGO DE VIDA ---
		
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

# --- FUNCIÓN DE DISPARO ---
func shoot(shoot_direction: Vector2):
	if not bullet_scene:
		print("ERROR: No se asignó la 'Bullet Scene' en el Inspector.")
		return

	var bullet = bullet_scene.instantiate()

	# 1. Asignar dirección (para el script de la bala)
	bullet.direction = shoot_direction
	
	# 2. Asignar posición (Arreglo de "disparar desde los pies")
	var spawn_pos = $AnimatedSprite2D.global_position
	bullet.global_position = spawn_pos + (shoot_direction * 20)
	
	# 3. Asignar rotación
	if shoot_direction == Vector2.LEFT:
		bullet.rotation_degrees = 180
	elif shoot_direction == Vector2.UP:
		bullet.rotation_degrees = -90
	elif shoot_direction == Vector2.DOWN:
		bullet.rotation_degrees = 90
	
	get_tree().current_scene.add_child(bullet)
