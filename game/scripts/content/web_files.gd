

extends RefCounted


const CHUNK := 4 * 1024 * 1024

static var _installed := false


static func active() -> bool:
	return OS.has_feature("web")


static func _install() -> void:
	if _installed or not active():
		return
	_installed = true
	JavaScriptBridge.eval("""
window.__pocketra_files = (function () {
	var api = {
		state: 'idle',      // idle | waiting | ready | cancel | error
		name: '', size: 0, error: '',
		file: null,
		chunk: null, chunk_busy: false,
		quota: -1, usage: -1
	};
	api.reset = function () {
		api.state = 'idle'; api.name = ''; api.size = 0; api.error = '';
		api.file = null; api.chunk = null; api.chunk_busy = false;
	};
	api.pick = function (accept) {
		api.reset();
		api.state = 'waiting';
		var input = document.createElement('input');
		input.type = 'file';
		if (accept) { input.accept = accept; }
		input.style.position = 'fixed';
		input.style.left = '-10000px';
		document.body.appendChild(input);
		var done = false;
		input.addEventListener('change', function () {
			done = true;
			if (input.files && input.files.length > 0) {
				api.file = input.files[0];
				api.name = api.file.name;
				api.size = api.file.size;
				api.state = 'ready';
			} else {
				api.state = 'cancel';
			}
			input.remove();
		});
		// Chrome und Firefox melden den Abbruch; Safari tut es nicht — dort bleibt es bei
		// 'waiting', bis der Nutzer erneut auf den Knopf tippt. Das ist kein Fehler, nur kein
		// Rückweg: die Seite lässt den Knopf deshalb bedienbar.
		input.addEventListener('cancel', function () {
			if (!done) { api.state = 'cancel'; input.remove(); }
		});
		try {
			input.click();
		} catch (e) {
			api.state = 'error';
			api.error = String(e);
			input.remove();
		}
	};
	api.read = function (offset, length) {
		if (!api.file) { return false; }
		api.chunk = null;
		api.chunk_busy = true;
		api.file.slice(offset, offset + length).arrayBuffer().then(function (buf) {
			api.chunk = new Uint8Array(buf);
			api.chunk_busy = false;
		}, function (err) {
			api.state = 'error';
			api.error = String(err);
			api.chunk_busy = false;
		});
		return true;
	};
	api.take = function () {
		var c = api.chunk;
		api.chunk = null;
		return c;
	};
	api.measure = function () {
		if (navigator.storage && navigator.storage.estimate) {
			navigator.storage.estimate().then(function (e) {
				api.quota = (typeof e.quota === 'number') ? e.quota : -1;
				api.usage = (typeof e.usage === 'number') ? e.usage : -1;
			}, function () { api.quota = -1; });
		}
	};
	api.measure();
	return api;
})();
""", true)


static func page_dir_url() -> String:
	if not active():
		return ""
	_install()
	var v = JavaScriptBridge.eval("location.href.split('#')[0].split('?')[0].replace(/[^/]*$/, '')", true)
	return str(v) if v != null else ""


static func download(url: String, filename: String = "") -> void:
	if not active():
		return
	_install()
	JavaScriptBridge.eval("""
(function (url, name) {
	var a = document.createElement('a');
	a.href = url;
	if (name) { a.download = name; }
	a.rel = 'noopener';
	a.style.display = 'none';
	document.body.appendChild(a);
	a.click();
	setTimeout(function () { a.remove(); }, 0);
})(%s, %s);
""" % [JSON.stringify(url), JSON.stringify(filename)], true)


static func pick(accept: String = "") -> void:
	if not active():
		return
	_install()
	JavaScriptBridge.eval("window.__pocketra_files.pick(%s)" % JSON.stringify(accept), true)


static func pick_state() -> Dictionary:
	if not active() or not _installed:
		return {"state": "idle", "name": "", "size": 0, "error": ""}
	var v = JavaScriptBridge.eval("JSON.stringify({state: window.__pocketra_files.state,"
			+ " name: window.__pocketra_files.name, size: window.__pocketra_files.size,"
			+ " error: window.__pocketra_files.error})", true)
	var d = JSON.parse_string(str(v)) if v != null else null
	return d if d is Dictionary else {"state": "idle", "name": "", "size": 0, "error": ""}


static func pick_reset() -> void:
	if active() and _installed:
		JavaScriptBridge.eval("window.__pocketra_files.reset()", true)


static func read_chunk(offset: int, length: int) -> bool:
	if not active() or not _installed:
		return false
	return bool(JavaScriptBridge.eval("window.__pocketra_files.read(%d, %d)" % [offset, length], true))


static func take_chunk() -> PackedByteArray:
	if not active() or not _installed:
		return PackedByteArray()
	var v = JavaScriptBridge.eval("window.__pocketra_files.take()", true)
	return v if v is PackedByteArray else PackedByteArray()


static func storage_estimate() -> Dictionary:
	if not active():
		return {"quota": -1, "usage": -1}
	_install()
	var v = JavaScriptBridge.eval("JSON.stringify({quota: window.__pocketra_files.quota,"
			+ " usage: window.__pocketra_files.usage})", true)
	var d = JSON.parse_string(str(v)) if v != null else null
	return d if d is Dictionary else {"quota": -1, "usage": -1}


static func measure_storage() -> void:
	if active():
		_install()
		JavaScriptBridge.eval("window.__pocketra_files.measure()", true)
