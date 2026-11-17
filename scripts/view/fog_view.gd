## FogView
##
## Zeichnet den Kriegsnebel des Spielers über die Welt: eine Textur mit einem Pixel je Kachel
## (Wert = Zustand aus FogSystem: 0 unerforscht, 1 erkundet, 2 sichtbar), über einen Shader
## zu Schwarz bzw. Abdunklung umgerechnet. Lineare Filterung macht die Ränder weich.
## Die Textur teilt sich die Minikarte (Minimap.setup_fog). Neu hochgeladen wird nur, wenn
## das FogSystem das Raster neu berechnet hat.
class_name FogView
extends Sprite2D

const SHADER_CODE := """
shader_type canvas_item;
uniform float explored_alpha = 0.55;
uniform float unexplored_alpha = 1.0;
void fragment() {
	float s = texture(TEXTURE, UV).r * 255.0;
	float a = s <= 1.0 ? mix(unexplored_alpha, explored_alpha, s) : mix(explored_alpha, 0.0, clamp(s - 1.0, 0.0, 1.0));
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""

var game: Node
var fog_texture: ImageTexture
var _image: Image
var _shader: Shader


func setup(p_game: Node) -> void:
	game = p_game
	name = "FogView"
	centered = false
	z_index = int(DataDB.cfg("fog.view_z_index", 27))
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var world: WorldData = game.world
	scale = Vector2(world.tile_size, world.tile_size)
	_image = Image.create(world.width, world.height, false, Image.FORMAT_R8)
	_image.fill(Color(0, 0, 0))
	fog_texture = ImageTexture.create_from_image(_image)
	texture = fog_texture
	material = make_material(float(DataDB.cfg("fog.explored_alpha", 0.55)),
			float(DataDB.cfg("fog.unexplored_alpha", 1.0)))
	(game.fog_system as FogSystem).updated.connect(_on_fog_updated)
	_on_fog_updated(game.player.id if game.player != null else 0)


## Shader-Material mit den Abdunklungen (auch für die Minikarte)
func make_material(explored_alpha: float, unexplored_alpha: float) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("explored_alpha", explored_alpha)
	mat.set_shader_parameter("unexplored_alpha", unexplored_alpha)
	return mat


func _on_fog_updated(kingdom_id: int) -> void:
	if game == null or game.player == null or kingdom_id != game.player.id:
		return
	var fog: FogSystem = game.fog_system
	visible = fog.has_grid(game.player)
	if not visible:
		return
	var world: WorldData = game.world
	_image.set_data(world.width, world.height, false, Image.FORMAT_R8, fog.grids[game.player.id])
	fog_texture.update(_image)
