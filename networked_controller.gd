extends NetworkedController
# Take cares to control the player and propagate the motion on the other peers


const MAX_PLAYER_DISTANCE: float = 20.0

var _position_id := -1
var _rotation_id := -1


func _ready():
	# Notify the NetworkSync who is controlling parent nodes.
	NetworkSync.set_node_as_controlled_by(get_parent(), self)
	NetworkSync.register_variable(get_parent(), "translation")
	NetworkSync.register_variable(get_parent(), "horizontal_velocity")
	if not get_tree().is_network_server():
		set_physics_process(false)


func _physics_process(_delta):
	for character in get_tree().get_nodes_in_group("characters"):
		if character != get_parent():
			var delta_distance = character.get_global_transform().origin - get_parent().get_global_transform().origin

			var is_far_away = delta_distance.length_squared() > (MAX_PLAYER_DISTANCE * MAX_PLAYER_DISTANCE)
			set_doll_peer_active(character.get_network_master(), !is_far_away);


func collect_inputs(delta: float, db: DataBuffer):
	# Collects the player inputs.

	var input_direction := Vector3()

	if get_parent().is_on_floor():
		if Input.is_action_pressed("forward"):
			input_direction -= get_parent().camera.global_transform.basis.z
		if Input.is_action_pressed("backward"):
			input_direction += get_parent().camera.global_transform.basis.z
		if Input.is_action_pressed("left"):
			input_direction -= get_parent().camera.global_transform.basis.x
		if Input.is_action_pressed("right"):
			input_direction += get_parent().camera.global_transform.basis.x
		input_direction.y = 0
		input_direction = input_direction.normalized()

	var has_input = input_direction.length_squared() > 0.0
	db.add_bool(has_input)
	if has_input:
		db.add_normalized_vector2(Vector2(input_direction.x, input_direction.z), DataBuffer.COMPRESSION_LEVEL_3)


func controller_process(delta: float, db: DataBuffer):
	# Process the controller.

	# Take the inputs
	var input_direction := Vector2()

	var has_input = db.read_bool()
	if has_input:
		input_direction = db.read_normalized_vector2(DataBuffer.COMPRESSION_LEVEL_3)

	# Process the character
	get_parent().step_body(delta, Vector3(input_direction.x, 0.0, input_direction.y))


func count_input_size(inputs: DataBuffer) -> int:
	# Count the input buffer size.
	var size: int = 0
	size += inputs.get_bool_size()
	if inputs.read_bool():
		size += inputs.get_normalized_vector2_size(DataBuffer.COMPRESSION_LEVEL_3)

	return size


func are_inputs_different(inputs_A: DataBuffer, inputs_B: DataBuffer) -> bool:
	# Compare two inputs, returns true when those are different or false when are close enough.
	var inp_A_has_i = inputs_A.read_bool()
	var inp_B_has_i = inputs_B.read_bool()
	if inp_A_has_i != inp_B_has_i:
		return true

	if inp_A_has_i:
		var inp_A_dir = inputs_A.read_normalized_vector2(DataBuffer.COMPRESSION_LEVEL_3)
		var inp_B_dir = inputs_B.read_normalized_vector2(DataBuffer.COMPRESSION_LEVEL_3)
		if (inp_A_dir - inp_B_dir).length_squared() > 0.0001:
			return true

	return false


func collect_epoch_data(buffer: DataBuffer):
	# Called on server when the collect state is triggered.
	# The collected `DataBuffer` is sent to the client that parse it using the
	# function `parse_epoch_data` and puts the data into the interpolator.
	# Later the function `apply_epoch` is called to apply the epoch
	# (already interpolated) data.
	buffer.add_vector3(get_parent().global_transform.origin, DataBuffer.COMPRESSION_LEVEL_2)
	buffer.add_vector3(get_parent().mesh_container.rotation, DataBuffer.COMPRESSION_LEVEL_2)


func setup_interpolator(interpolator: Interpolator):
	# Called only on client doll to initialize the `Intepolator`.
	_position_id = interpolator.register_variable(Vector3(), Interpolator.FALLBACK_NEW_OR_NEAREST)
	_rotation_id = interpolator.register_variable(Vector3(), Interpolator.FALLBACK_NEW_OR_NEAREST)


func parse_epoch_data(interpolator: Interpolator, buffer: DataBuffer):
	# Called locally to parse the `DataBuffer` and store the data into the `Interpolator`.
	var position := buffer.read_vector3(DataBuffer.COMPRESSION_LEVEL_2)
	var rotation := buffer.read_vector3(DataBuffer.COMPRESSION_LEVEL_2)
	interpolator.epoch_insert(_position_id, position)
	interpolator.epoch_insert(_rotation_id, rotation)


func apply_epoch(_delta: float, interpolated_data: Array):
	# Happens only on doll client each frame. Here is necessary to apply the _already interpolated_ values.
	get_parent().global_transform.origin = interpolated_data[_position_id]
	get_parent().mesh_container.rotation = interpolated_data[_rotation_id]
