extends PanelContainer


const REFRESH_S := 0.5

const LOG_S := 10.0

var world: Node = null

var name_of: Callable = Callable()
var _text: RichTextLabel
var _accum := 0.0
var _log_accum := 0.0
var _log := OS.get_cmdline_user_args().has("--ki-log")


func _init() -> void:
	name = "CommanderPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", HudTheme.panel(HudTheme.PANEL_BG, HudTheme.BORDER_DIM, 4.0, 1.0))
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", int(Dp.px(11)))
	_text.add_theme_font_size_override("bold_font_size", int(Dp.px(11)))
	_text.add_theme_color_override("default_color", HudTheme.TEXT)
	add_child(_text)


func _process(delta: float) -> void:
	if _log:
		_log_accum += delta
		if _log_accum >= LOG_S:
			_log_accum = 0.0
			refresh()
			print("KOMMANDEUR-ANZEIGE ", _text.get_parsed_text().replace("\n", " | "))
	if not visible:
		return
	_accum += delta
	if _accum < REFRESH_S and _text.text != "":
		return
	_accum = 0.0
	refresh()


func refresh() -> void:
	_text.text = build_text()

	size = get_combined_minimum_size()


func build_text() -> String:
	if world == null or world.commander_client == null:
		return ""
	var c: Node = world.commander_client
	var gold := HudTheme.GOLD.to_html(false)
	var dim := HudTheme.TEXT_DIM.to_html(false)
	var st := str(c.state()) if c.has_method("state") else "ok"
	var st_col: String = {"ok": "5fd35f", "wartet": dim, "pause": HudTheme.MODE_SELL.to_html(false)}.get(st, dim)
	var lat := int(c.get("last_latency_ms")) if c.get("last_latency_ms") != null else -1
	var head := "[b][color=#%s]%s[/color][/b]  [color=#%s]%s[/color]  [color=#%s]%s[/color]" % [
		gold, tr("commander.panel.title"), dim, _short_url(str(c.get("url"))), st_col, tr("commander.panel.state_" + st)]
	head += "  " + tr("commander.panel.counts") % [int(c.get("successes")), _fallbacks_total(c)]
	if lat >= 0:
		head += "  %d ms" % lat
	var err := str(c.get("last_error")) if c.get("last_error") != null else ""
	if err != "":
		head += "  [color=#%s](%s)[/color]" % [dim, err]
	var lines := PackedStringArray([head])
	var sim = world.sim
	if sim == null or not sim.has_method("bot_commander_directive"):
		return "\n".join(lines)
	var fb: Dictionary = c.get("fallbacks_by_player") if c.get("fallbacks_by_player") is Dictionary else {}
	for e in world.player_roster:
		if str(e.get("kind", "human")) != "bot":
			continue
		var pl := int(e.get("sim", -1))
		if pl < 0 or not sim.bot_enabled(pl):
			continue
		var d: Dictionary = sim.bot_commander_directive(pl)
		var col: Color = e.get("color", HudTheme.TEXT)
		var src := str(d.get("source", "none"))
		var src_txt := tr("commander.panel.src_laya") if src == "external" else (
			tr("commander.panel.src_rule") if src == "rule" else tr("commander.panel.src_none"))
		var src_col := gold if src == "external" else dim
		var line := "[color=#%s]■[/color] %s  [color=#%s]%s[/color]  %s · %s" % [
			col.to_html(false), _bb(_name(e)), src_col, src_txt,
			_opt("commander.doctrine.", str(d.get("doctrine", "?"))), _opt("commander.stance.", str(d.get("stance", "?")))]
		if src == "external":
			line += " · %d ms" % int(d.get("latency_ms", 0))
		line += "  [color=#%s]%s[/color]" % [dim, tr("commander.panel.fallbacks") % int(fb.get(pl, 0))]
		lines.append(line)
	return "\n".join(lines)


func _name(e: Dictionary) -> String:
	if name_of.is_valid():
		return str(name_of.call(e))
	var n := str(e.get("name", ""))
	return n if n != "" else tr("lobby.ai") % int(e.get("bot_no", 0))


func _fallbacks_total(c: Node) -> int:
	var n := 0
	var fb = c.get("fallbacks_by_player")
	if fb is Dictionary:
		for k in fb:
			n += int(fb[k])
	return n


func _opt(prefix: String, id: String) -> String:
	var t := tr(prefix + id)
	return id if t == prefix + id else t


static func _short_url(u: String) -> String:
	return u.trim_prefix("http://").trim_prefix("https://")


static func _bb(s: String) -> String:
	return s.replace("[", "[lb]")
