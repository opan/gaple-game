extends SceneTree
## Dev tool: boot the game table, render a few frames, save a PNG, and quit.
## Run (needs a display):
##   godot -s tools/screenshot.gd -- --out=/tmp/gaple_table.png --players=3 --seed=42

var _frames := 0
var _out := "/tmp/gaple_table.png"
var _players := 3
var _seed := 42
var _table


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr("--out=".length())
		elif arg.begins_with("--players="):
			_players = arg.substr("--players=".length()).to_int()
		elif arg.begins_with("--seed="):
			_seed = arg.substr("--seed=".length()).to_int()


func _process(_delta: float) -> bool:
	_frames += 1
	# Build the scene only once the tree is actually running (frame 1).
	if _frames == 1:
		get_root().set_content_scale_size(Vector2i(1280, 720))
		_table = GameTable.new()
		_table.bot_delay = Vector2.ZERO        # bots play instantly (board fills)
		get_root().add_child(_table)
		_table.start_game(_players, _seed)
	elif _frames >= 6:
		var img := get_root().get_texture().get_image()
		img.save_png(_out)
		print("[screenshot] saved %s" % _out)
		quit()
	return false
