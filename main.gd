extends Node
## Bootstrap entry point (PLAN.md Phase 0).
##
## With `--server` in the user args (i.e. after `--` on the command line) this
## process acts as the authoritative headless game server; otherwise it boots
## the client UI. Phase 0 only prints placeholders for each branch — the real
## server (Phase 3) and main menu (Phase 4) replace these.

const DEFAULT_PORT := 9000


func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--server"):
		_run_server(user_args)
	else:
		_run_client()


func _run_server(args: PackedStringArray) -> void:
	var port := _parse_port(args)
	print("[Gaple] Server placeholder — would listen on port %d (real server: Phase 3)." % port)
	print("[Gaple] Running. Press Ctrl-C to stop.")
	# The headless SceneTree keeps the process alive until SIGINT / quit().


func _run_client() -> void:
	# Phase 2: the local practice-vs-bots client shell. Phase 4 expands this
	# into the full menu/lobby/network flow.
	add_child(AppRoot.new())


## Parse `--port=NNNN` from the user args, falling back to DEFAULT_PORT.
func _parse_port(args: PackedStringArray) -> int:
	for arg in args:
		if arg.begins_with("--port="):
			var value := arg.substr("--port=".length())
			if value.is_valid_int():
				return value.to_int()
	return DEFAULT_PORT
