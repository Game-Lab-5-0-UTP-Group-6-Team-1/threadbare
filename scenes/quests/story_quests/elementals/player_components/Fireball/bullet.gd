extends RigidBody2D

var speed: float = 600.0
var direction: Vector2 = Vector2.ZERO # El jugador (Jozu) asignará esto

@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var animated_sprite: AnimatedSprite2D = $VisibleThings/AnimatedSprite2D

func _ready():
	# --- ¡CONECTA ESTAS SEÑALES EN EL EDITOR! ---
	# 1. Conecta 'body_entered' (del RigidBody2D) a '_on_body_entered'
	# 2. Conecta 'timeout' (del LifetimeTimer) a '_on_lifetime_timer_timeout'
	
	animated_sprite.play("default")
	lifetime_timer.start()
	linear_velocity = direction * speed

func _physics_process(delta):
	pass # El motor de física hace el trabajo

func _on_lifetime_timer_timeout():
	queue_free() # Destruye el proyectil

# --- ¡FUNCIÓN MODIFICADA! ---
func _on_body_entered(body):
	
	# 1. Ignorar al jugador
	if body.is_in_group("player"):
		return 
	
	if body.is_in_group("walls"):
		print("Bala: Choqué con un muro. Desapareceré en 2 segundos.")
		
		
		# 3. Reiniciamos el temporizador a 2 segundos
		lifetime_timer.stop() # Detiene el temporizador de vida original
		lifetime_timer.wait_time = 0.2 # Establece el nuevo tiempo
		lifetime_timer.start() # Inicia la cuenta atrás de 2 segundos
		
		return # No seguir comprobando
	# 3. Comprobar si es un ENEMIGO (usando el grupo "enemy")
	if body.is_in_group("enemy"):
		print("Bala: ¡Le di a un enemigo!")
		
	if body.has_method("take_damage"):
		body.take_damage(1)  # 🔹 Le resta 1 de vida
	elif body.has_method("die"):
		body.die()           # 🔹 Si no tiene salud, usa die() directo
	
	queue_free()
	return
		
	# 4. Si choca con cualquier otra cosa (que no sea el jugador)
	queue_free()
