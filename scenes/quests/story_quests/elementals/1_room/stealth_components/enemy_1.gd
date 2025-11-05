extends CharacterBody2D
class_name Enemy

# --- Estados del Enemigo ---
# --- AÑADIDO: El nuevo estado "DEFEATED" ---
enum State { IDLE, CHASING, ATTACKING, COOLDOWN, DEFEATED }

# --- Variables de Comportamiento ---
@export var speed: float = 200.0
@export var attack_range: float = 50.0  
@export var attack_damage: int = 1
@export var attack_cooldown: float = 2.0 

# --- Referencias de Nodos ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D = $DetectionArea
# --- Variables Internas ---
var player: CharacterBody2D = null
var is_attacking: bool = false 

var current_state: State = State.IDLE

var cooldown_counter: float = 0.0

func _ready():
	animated_sprite.animation_finished.connect(_on_animation_finished)
	

func _physics_process(delta):
	
	# --- AÑADIDO: Comprobación de Muerte ---
	# Si el enemigo está muerto, no hace nada más.
	if current_state == State.DEFEATED:
		velocity = Vector2.ZERO # Asegurarse de que no se deslice
		move_and_slide()
		return # No ejecutar el resto de la lógica

	# (El resto de tu lógica de cooldown sigue aquí)
	if current_state == State.COOLDOWN:
		cooldown_counter += delta
		if cooldown_counter >= attack_cooldown:
			cooldown_counter = 0.0
			current_state = State.IDLE
			
	var new_state = get_new_state()
	
	if new_state != current_state:
		current_state = new_state

	# --- Actuar según el estado ---
	match current_state:
		State.IDLE:
			animated_sprite.play("idle")
			velocity = Vector2.ZERO
			
		State.CHASING:
			animated_sprite.play("walk") 
			var direction = global_position.direction_to(player.global_position)
			velocity = direction * speed
			
			if direction.x > 0.1:
				animated_sprite.flip_h = false 
			elif direction.x < -0.1:
				animated_sprite.flip_h = true 
			
		State.ATTACKING:
			velocity = Vector2.ZERO 
			
			if not is_attacking:
				is_attacking = true
				animated_sprite.play("attack")
				_do_damage()
			
		State.COOLDOWN:
			velocity = Vector2.ZERO
			animated_sprite.play("idle") 
		
		# --- AÑADIDO: Estado de Muerte ---
		State.DEFEATED:
			velocity = Vector2.ZERO
			

	move_and_slide()

# --- MODIFICADO ---
func get_new_state() -> State:
	# ¡Si está muerto, atacando o en cooldown, NO interrumpir!
	if current_state == State.DEFEATED or is_attacking or current_state == State.COOLDOWN:
		return current_state
		
	if not is_instance_valid(player):
		return State.IDLE
	
	var distance_to_player = global_position.distance_to(player.global_position)
	
	if distance_to_player <= attack_range:
		return State.ATTACKING
	else:
		return State.CHASING

func _do_damage():
	if is_instance_valid(player):
		var distance = global_position.distance_to(player.global_position)
		if distance <= attack_range * 1.2: 
			player.take_damage(attack_damage)
			print("Enemigo: ¡GOLPE!")

# --- MODIFICADO ---
func _on_animation_finished():
	if animated_sprite.animation == "attack":
		current_state = State.COOLDOWN
		is_attacking = false
	
	# --- AÑADIDO ---
	# Si la animación de "defeated" (derrotado) termina...
	if animated_sprite.animation == "defeated":
		queue_free() # ...elimina al enemigo de la escena.

# (Las funciones de Area2D siguen igual)
func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player = body 
		print("Enemigo: ¡Te veo!")

func _on_area_2d_body_exited(body: Node2D) -> void:
	if body == player:
		player = null 
		print("Enemigo: ¿A dónde fue?")

# ---
# --- ¡NUEVA FUNCIÓN DE MORIR! ---
# ---
# Esta función puede ser llamada por una bala o cualquier otra cosa
func die():
	# Solo puede morir una vez
	if current_state == State.DEFEATED:
		return

	# 1. Poner el estado en DEFEATED
	current_state = State.DEFEATED
	
	# 2. Desactivar colisiones para que el jugador pase
	$CollisionShape2D.disabled = true
	# 3. Desactivar el área de detección
	detection_area.monitoring = false
	
	# 4. Reproducir la animación de muerte
	animated_sprite.play("defeated")
	
	# La función _on_animation_finished() se encargará
	# de llamar a queue_free() cuando termine.
