extends Node
## SFX autoload. Plays one of five CC0 sounds keyed by name.
## Add .ogg files to res://assets/audio/{deal,place,pass,win,lose}.ogg.
## Missing files are silently skipped so the game works before assets exist.

const _KEYS := ["deal", "place", "pass", "win", "lose"]
const _CFG_PATH := "user://gaple.cfg"
const _CFG_SECTION := "audio"

var muted := false :
	set(v):
		muted = v
		_save_config()

var _players: Dictionary = {}   # key -> AudioStreamPlayer


func _ready() -> void:
	_load_config()
	for k: String in _KEYS:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players[k] = p
		var path := "res://assets/audio/%s.ogg" % k
		if ResourceLoader.exists(path):
			p.stream = load(path)


func play(key: String) -> void:
	if muted:
		return
	var p: AudioStreamPlayer = _players.get(key)
	if p and p.stream:
		p.play()


func toggle_mute() -> void:
	muted = not muted


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_CFG_PATH) == OK:
		muted = cfg.get_value(_CFG_SECTION, "muted", false)


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_CFG_PATH)   # preserve other sections (player name, etc.)
	cfg.set_value(_CFG_SECTION, "muted", muted)
	cfg.save(_CFG_PATH)
