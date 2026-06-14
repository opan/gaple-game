class_name NetConfig
extends RefCounted
## Server URL selection per build type (ADR-005, PHASE_4_PLAN.md §6).
## Debug → localhost; Release → production host; overridable via ?server= param.

const RELEASE_URL := "wss://gaple.yourdomain.com"   # replace with your Cloudflare Tunnel hostname
const DEBUG_URL   := "ws://localhost:9000"


static func server_url() -> String:
	# In a web export the JavaScript bridge lets us read the query string.
	if OS.has_feature("web"):
		var js_result: Variant = JavaScriptBridge.eval(
			"(new URLSearchParams(window.location.search)).get('server') || ''", true)
		if typeof(js_result) == TYPE_STRING and (js_result as String).length() > 0:
			return js_result as String
	return DEBUG_URL if OS.is_debug_build() else RELEASE_URL
