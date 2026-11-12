extends Node3D
## Galería 3D mínima. Lee las imágenes de la carpeta "cuadros" y cuelga un cuadro por imagen.
## - Medidas reales opcionales en el nombre del archivo: paisaje__80x60.jpg (cm, ancho x alto).
## - Colecciones: cuadros/colección/<Nombre>/*.jpg -> un pasillo con cartel que sale de la sala principal.
## Flujo: carga en hilo -> distribución -> sala + pasillos -> cuadros -> jugador.

# ---------- CONFIGURACIÓN ----------
const MAX_TEX_SIZE := 2048          # lado mayor máximo de cada textura de pared (px)
const HIRES_TEX_SIZE := 4096        # lado mayor máximo del detalle cargado con zoom (px)
const HIRES_DISTANCE := 8.0         # distancia máxima para cargar el detalle con zoom (m)
const DEFAULT_SIDE_CM := 120.0      # lado mayor de las imágenes sin medidas en el nombre (cm)
const MIN_SIDE_CM := 5.0            # lado mayor mínimo admitido (cm)
const MAX_SIDE_CM := 600.0          # lado mayor máximo admitido (cm)
const ASPECT_TOLERANCE := 0.1       # diferencia admitida entre medidas e imagen (10 %)
const HANG_HEIGHT := 1.55           # altura del centro de los cuadros (m)
const FLOOR_CLEARANCE := 0.1        # distancia mínima del borde inferior al piso (m)
const CEILING_CLEARANCE := 0.2      # distancia mínima del borde superior al techo (m)
const GAP_FACTOR := 0.625           # separación = factor * ancho medio de los vecinos...
const GAP_MIN := 0.3                # ...limitada a este mínimo (m)
const GAP_MAX := 1.0                # ...y a este máximo (m)
const CORNER_MARGIN := 0.6          # distancia mínima de un marco a una esquina o puerta (m)
const WALL_T := 0.2                 # espesor de paredes, piso y techo (m)
const ROOM_HEIGHT := 3.2            # altura mínima de la galería (m); crece si hay obras altas
const ROOM_RATIO := 1.5             # largo / ancho de la sala principal
const MIN_PERIMETER := 28.0         # perímetro mínimo de la sala principal (m)
const FRAME_THICKNESS := 0.04       # borde visible máximo del marco (m)
const FRAME_DEPTH := 0.05           # profundidad máxima del marco (m)
const VIEW_DISTANCE := 2.5          # distancia máxima para ampliar con E (m)
const VIEW_TOLERANCE := 0.25        # margen máximo extra al apuntar al cuadro (m)
const ZOOM_MARGIN := 0.05           # margen de la vista ampliada (0.05 = ocupa 90 %)
const CORRIDOR_WIDTH := 3.2         # ancho interior de pasillos y de sus puertas (m)
const DOOR_HEIGHT := 2.3            # altura de la puerta de cada pasillo (m)
const CORRIDOR_ENTRY_MARGIN := 1.2  # distancia de la entrada al primer cuadro (m)
const CORRIDOR_END_MARGIN := 1.2    # distancia del último cuadro al fondo (m)
const CORRIDOR_MIN_LENGTH := 6.0    # largo mínimo de un pasillo (m)
const SIGN_HEIGHT := 0.6            # alto del cartel sobre la puerta (m)
const SIGN_TEXT_HEIGHT := 0.34      # alto del texto del cartel (m); se reduce si el nombre es largo
const COLLECTION_FOLDERS := ["coleccion", "colecciones"]   # nombres de carpeta (minúsculas, sin tilde)
const EXTENSIONS := ["jpg", "jpeg", "png", "webp", "bmp", "tga"]
const COLOR_WALL := Color("EDEAE4")
const COLOR_FLOOR := Color("8A7F73")
const COLOR_CEILING := Color("F5F4F1")
const COLOR_FRAME := Color("2B2622")
const COLOR_SIGN := Color("2B2622")
const COLOR_SIGN_TEXT := Color("F5F4F1")
const CORRIDOR_PITCH := CORRIDOR_WIDTH + 2.0 * WALL_T   # distancia entre ejes de pasillos contiguos

enum State { LOADING, PLAY, ZOOM, PAUSE }

var state := State.LOADING
var _dir_path := ""
var _files: Array = []              # {path, coll}: coll = -1 (sala principal) o índice en _collections
var _collections: Array = []        # {name, ids}
var _room_h := ROOM_HEIGHT
var _runs: Array = []               # tramos de pared con cuadros: {origin, dir, normal, length, items}
var _main_runs := 0                 # los primeros _main_runs tramos son de la sala; el resto, de pasillos
var _corridors: Array = []          # {name, wall, s, o, out, r, length}

# Hilo de carga inicial
var _thread: Thread
var _mutex := Mutex.new()
var _queue: Array = []              # {name, image, ...} listos para crear textura
var _attempted := 0
var _worker_done := false

# Hilo de detalle (zoom Z): como máximo un original en memoria a la vez
var _hires_thread: Thread
var _hires_result = null            # {idx, image} o null (protegido por _mutex)
var _hires_idx := -1                # cuadro que muestra el detalle
var _hires_loading := -1            # cuadro cuyo detalle se está cargando

var _paintings: Array = []          # datos por imagen cargada
var _placed: Array = []             # {name, tex, mat, path, hires, center, normal, right, ow, oh, tol, wall, offset}
var _player: Player
var _target := -1

var _msg: Label
var _hint: Label
var _pause: Label
var _zoom_lbl: Label
var _zoom_bg: ColorRect
var _zoom_tex: TextureRect
var _zoom_name: Label


func _ready() -> void:
	_build_hud()
	_setup_environment()
	_dir_path = _gallery_dir()
	if not DirAccess.dir_exists_absolute(_dir_path):
		DirAccess.make_dir_recursive_absolute(_dir_path)
	_scan_folders()
	_player = Player.new()
	if _files.is_empty():
		_build_gallery()
	else:
		_thread = Thread.new()
		_thread.start(_worker)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	if _hires_thread != null and _hires_thread.is_started():
		_hires_thread.wait_to_finish()


# ---------- CARPETAS E IMÁGENES ----------

func _gallery_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://cuadros")
	return OS.get_executable_path().get_base_dir().path_join("cuadros")


func _list_images(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var names: Array = Array(DirAccess.get_files_at(dir_path))
	names.sort_custom(func(x, y): return String(x).naturalnocasecmp_to(String(y)) < 0)
	for n in names:
		if String(n).get_extension().to_lower() in EXTENSIONS:
			result.append(dir_path.path_join(n))
	return result


func _sorted_dirs(path: String) -> Array:
	var dirs: Array = Array(DirAccess.get_directories_at(path))
	dirs.sort_custom(func(x, y): return String(x).naturalnocasecmp_to(String(y)) < 0)
	return dirs


## "Colección" / "coleccion" / "COLECCIONES" -> minúsculas sin tilde.
static func _plain(s: String) -> String:
	return s.replace("Ó", "o").replace("ó", "o").to_lower()


## Imágenes sueltas de cuadros\ -> sala principal.
## cuadros\colección\<Nombre>\ -> una colección por subcarpeta (las vacías se ignoran).
func _scan_folders() -> void:
	for path in _list_images(_dir_path):
		_files.append({"path": path, "coll": -1})
	for folder in _sorted_dirs(_dir_path):
		if not (_plain(folder) in COLLECTION_FOLDERS):
			continue
		var root := _dir_path.path_join(folder)
		for sub in _sorted_dirs(root):
			if String(sub).begins_with("."):
				continue
			var imgs := _list_images(root.path_join(sub))
			if imgs.is_empty():
				push_warning("Colección sin imágenes, se omite: " + sub)
				continue
			_collections.append({"name": String(sub), "ids": []})
			for path in imgs:
				_files.append({"path": path, "coll": _collections.size() - 1})


## "paisaje__80x60" / "paisaje__42,5x30cm" -> nombre sin medidas + ancho y alto en cm (0 si no hay).
static func _parse_name(base: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("(?i)__(\\d+(?:[.,]\\d+)?)x(\\d+(?:[.,]\\d+)?)(?:cm)?$")
	var m := re.search(base)
	if m == null:
		return {"name": base, "w": 0.0, "h": 0.0}
	var clean := base.substr(0, m.get_start()).strip_edges()
	return {
		"name": clean if clean != "" else base,
		"w": m.get_string(1).replace(",", ".").to_float(),
		"h": m.get_string(2).replace(",", ".").to_float(),
	}


## Reduce al máximo indicado, quita alfa si no se usa y genera mipmaps. No toca el archivo original.
static func _prepare_image(img: Image, max_size: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var m := maxi(w, h)
	if m > max_size:
		var s := float(max_size) / float(m)
		img.resize(maxi(1, roundi(w * s)), maxi(1, roundi(h * s)), Image.INTERPOLATE_LANCZOS)
	if img.detect_alpha() == Image.ALPHA_NONE:
		img.convert(Image.FORMAT_RGB8)
	else:
		img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()


## Hilo secundario de carga inicial.
func _worker() -> void:
	for f in _files:
		var path: String = f.path
		var item = null
		var img: Image = Image.load_from_file(path)
		if img != null and not img.is_empty():
			var orig_max := maxi(img.get_width(), img.get_height())
			_prepare_image(img, MAX_TEX_SIZE)
			var info := _parse_name(path.get_file().get_basename())
			item = {"name": info.name, "w_cm": info.w, "h_cm": info.h, "path": path, "coll": f.coll,
				"orig_max": orig_max, "image": img}
		else:
			push_warning("No se pudo cargar: " + path)
		_mutex.lock()
		_attempted += 1
		if item != null:
			_queue.append(item)
		_mutex.unlock()
	_mutex.lock()
	_worker_done = true
	_mutex.unlock()


func _process(_delta: float) -> void:
	if state == State.LOADING:
		_poll_loading()
	elif state == State.PLAY:
		_update_target()
		_update_hires()


func _poll_loading() -> void:
	var items: Array = []
	_mutex.lock()
	for i in mini(2, _queue.size()):
		items.append(_queue.pop_front())
	var attempted := _attempted
	var finished := _worker_done and _queue.is_empty()
	_mutex.unlock()
	for it in items:
		var img: Image = it.image
		_paintings.append({
			"name": it.name, "tex": ImageTexture.create_from_image(img),
			"aspect": float(img.get_width()) / float(img.get_height()),
			"path": it.path, "coll": it.coll, "w_cm": it.w_cm, "h_cm": it.h_cm,
			"hires": it.orig_max > MAX_TEX_SIZE,
		})
	_msg.text = "Cargando %d/%d" % [attempted, _files.size()]
	if finished:
		_thread.wait_to_finish()
		_build_gallery()


# ---------- CONSTRUCCIÓN DE LA GALERÍA ----------

func _build_gallery() -> void:
	var layout := _compute_layout()
	_build_room(layout.a, layout.b, layout.door_s)
	_hang_paintings()
	_player.position = Vector3(0.0, 0.02, 0.0)
	add_child(_player)
	if _paintings.is_empty():
		_msg.text = "Copie imágenes en la carpeta cuadros y reinicie\n" + _dir_path
	else:
		_msg.text = ""
	_set_state(State.PLAY)
	if "--selftest" in OS.get_cmdline_user_args():
		_selftest(layout.a, layout.b)


## Separación entre dos cuadros vecinos, proporcional a su tamaño.
func _gap(ow_a: float, ow_b: float) -> float:
	return clampf(GAP_FACTOR * (ow_a + ow_b) * 0.5, GAP_MIN, GAP_MAX)


## Calcula el tamaño real (m) de un cuadro a partir de las medidas del nombre o del valor por defecto.
func _size_painting(p: Dictionary) -> void:
	var asp: float = p.aspect
	var wc: float
	var hc: float
	var declared: bool = p.w_cm > 0.0 and p.h_cm > 0.0
	if declared:
		wc = p.w_cm
		hc = p.h_cm
		var decl := wc / hc
		if absf(decl / asp - 1.0) > ASPECT_TOLERANCE:
			if absf(1.0 / decl / asp - 1.0) <= ASPECT_TOLERANCE:
				var t := wc                      # medidas declaradas al revés
				wc = hc
				hc = t
			else:
				push_warning("%s: las medidas no coinciden con la proporción de la imagen; se usa el ancho." % p.name)
		hc = wc / asp                            # la imagen nunca se deforma
	elif asp >= 1.0:
		wc = DEFAULT_SIDE_CM
		hc = wc / asp
	else:
		hc = DEFAULT_SIDE_CM
		wc = hc * asp
	var big := maxf(wc, hc)
	var s := clampf(big, MIN_SIDE_CM, MAX_SIDE_CM) / big
	if declared and s != 1.0:
		push_warning("%s: medida fuera de %d-%d cm; se ajusta." % [p.name, int(MIN_SIDE_CM), int(MAX_SIDE_CM)])
	p.w = wc * s / 100.0
	p.h = hc * s / 100.0
	var small := minf(p.w, p.h)
	p.ft = clampf(small * 0.06, 0.012, FRAME_THICKNESS)     # marco proporcional
	p.fd = clampf(small * 0.15, 0.02, FRAME_DEPTH)
	p.ow = p.w + 2.0 * p.ft
	p.oh = p.h + 2.0 * p.ft
	p.cy = maxf(HANG_HEIGHT, p.oh * 0.5 + FLOOR_CLEARANCE)  # obras altas: centro más arriba
	p.tol = clampf(minf(p.ow, p.oh) * 0.25, 0.03, VIEW_TOLERANCE)


## Dimensiona los cuadros, reparte las colecciones en puertas norte/sur y busca la sala más chica
## (relación ROOM_RATIO) donde caben los cuadros de la sala. Llena _runs y _corridors.
func _compute_layout() -> Dictionary:
	_room_h = ROOM_HEIGHT
	var total := 0.0
	var main_ids: Array = []
	for c in _collections:
		c.ids = []
	for i in _paintings.size():
		var p: Dictionary = _paintings[i]
		_size_painting(p)
		_room_h = maxf(_room_h, p.cy + p.oh * 0.5 + CEILING_CLEARANCE)
		if p.coll < 0:
			main_ids.append(i)
			total += p.ow + _gap(p.ow, p.ow)
		else:
			_collections[p.coll].ids.append(i)
	var door_wall: Array = [[], [], [], []]       # colecciones que abren en cada pared (solo 0 = norte y 2 = sur)
	var n_active := 0
	for ci in _collections.size():
		if _collections[ci].ids.is_empty():
			continue
		door_wall[0 if n_active % 2 == 0 else 2].append(ci)
		n_active += 1
	var n_doors := maxi(door_wall[0].size(), door_wall[2].size())
	var min_a := (n_doors * CORRIDOR_PITCH + 2.0 * CORNER_MARGIN) if n_doors > 0 else 0.0
	var perimeter := maxf(MIN_PERIMETER, total + 8.0 * CORNER_MARGIN)
	for _guard in 400:
		var b := perimeter / (2.0 * (1.0 + ROOM_RATIO))
		var a := maxf(b * ROOM_RATIO, min_a)
		var door_s := _door_positions(a, door_wall)
		var segs := _main_segments(a, b, door_s)
		var packed = _pack_segments(segs, main_ids)
		if packed != null:
			_make_runs(a, b, segs, packed, door_wall, door_s)
			return {"a": a, "b": b, "door_s": door_s}
		perimeter *= 1.05
	push_error("No se pudo distribuir la galería")
	return {}


## Posición (m, a lo largo de la pared) del centro de cada puerta; centradas y a distancia CORRIDOR_PITCH.
func _door_positions(a: float, door_wall: Array) -> Dictionary:
	var result := {}
	for w in [0, 2]:
		var n: int = door_wall[w].size()
		var list: Array = []
		for i in n:
			list.append(a * 0.5 + (i - (n - 1) * 0.5) * CORRIDOR_PITCH)
		result[w] = list
	return result


## Divide cada pared de la sala en tramos libres de puertas.
func _main_segments(a: float, b: float, door_s: Dictionary) -> Array:
	var lens := [a, b, a, b]
	var segs: Array = []
	for w in 4:
		var cur := 0.0
		for s in door_s.get(w, []):
			segs.append({"wall": w, "start": cur, "length": s - CORRIDOR_WIDTH * 0.5 - cur})
			cur = s + CORRIDOR_WIDTH * 0.5
		segs.append({"wall": w, "start": cur, "length": lens[w] - cur})
	return segs


## Reparte los cuadros en secuencia por los tramos. Ninguno cruza una esquina ni una puerta.
## Devuelve una lista de índices por tramo, o null si no caben.
func _pack_segments(segs: Array, ids: Array):
	var packed: Array = []
	for s in segs:
		packed.append([])
	var k := 0
	var used := 0.0
	for i in ids:
		var ow: float = _paintings[i].ow
		while k < segs.size():
			var need := ow
			if not packed[k].is_empty():
				need = used + _gap(_paintings[packed[k][-1]].ow, ow) + ow
			if need + 2.0 * CORNER_MARGIN <= segs[k].length:
				packed[k].append(i)
				used = need
				break
			k += 1
			used = 0.0
		if k >= segs.size():
			return null
	return packed


## Posiciones consecutivas (con separación) a partir de `start`. `end` = borde del último cuadro.
func _stack(ids: Array, start: float) -> Dictionary:
	var items: Array = []
	var s := start
	var prev := -1.0
	for i in ids:
		var ow: float = _paintings[i].ow
		if prev >= 0.0:
			s += _gap(prev, ow)
		items.append({"idx": i, "s": s})
		s += ow
		prev = ow
	return {"items": items, "end": s}


## Arma los tramos de pared (sala y pasillos). Cada tramo: origen, dirección (derecha de quien mira),
## normal hacia el interior, largo y cuadros con su posición `s` a lo largo del tramo.
func _make_runs(a: float, b: float, segs: Array, packed: Array, door_wall: Array, door_s: Dictionary) -> void:
	_runs.clear()
	_corridors.clear()
	var defs := _wall_defs(a, b)
	for k in segs.size():
		var ids: Array = packed[k]
		if ids.is_empty():
			continue
		var seg: Dictionary = segs[k]
		var d: Dictionary = defs[seg.wall]
		var st := _stack(ids, 0.0)
		var shift: float = (seg.length - st.end) * 0.5       # grupo centrado en el tramo
		var items: Array = []
		for it in st.items:
			items.append({"idx": it.idx, "s": it.s + shift})
		_runs.append({"origin": d.origin + d.dir * seg.start, "dir": d.dir, "normal": d.normal,
			"length": seg.length, "items": items})
	_main_runs = _runs.size()
	for w in [0, 2]:
		var d: Dictionary = defs[w]
		for n in door_wall[w].size():
			var col: Dictionary = _collections[door_wall[w][n]]
			var s: float = door_s[w][n]
			var o: Vector3 = d.origin + d.dir * s
			var out: Vector3 = -d.normal                    # hacia afuera de la sala
			var r: Vector3 = out.cross(Vector3.UP)          # derecha de quien camina hacia adentro
			var left: Array = []
			var right: Array = []
			for j in col.ids.size():
				if j % 2 == 0:
					left.append(col.ids[j])
				else:
					right.append(col.ids[j])
			var sl := _stack(left, CORRIDOR_ENTRY_MARGIN)
			var sr := _stack(right, CORRIDOR_ENTRY_MARGIN)
			var length := maxf(CORRIDOR_MIN_LENGTH, maxf(sl.end, sr.end) + CORRIDOR_END_MARGIN)
			_runs.append({"origin": o - r * (CORRIDOR_WIDTH * 0.5), "dir": out, "normal": r,
				"length": length, "items": sl.items})
			var items_r: Array = []
			for it in sr.items:
				items_r.append({"idx": it.idx, "s": length - it.s - _paintings[it.idx].ow})
			_runs.append({"origin": o + r * (CORRIDOR_WIDTH * 0.5) + out * length, "dir": -out, "normal": -r,
				"length": length, "items": items_r})
			_corridors.append({"name": col.name, "wall": w, "s": s, "o": o, "out": out, "r": r, "length": length})


## Origen, dirección (derecha de quien mira) y normal interior de cada pared de la sala.
func _wall_defs(a: float, b: float) -> Array:
	return [
		{"origin": Vector3(-a / 2.0, 0.0, -b / 2.0), "dir": Vector3(1, 0, 0), "normal": Vector3(0, 0, 1), "length": a},
		{"origin": Vector3(a / 2.0, 0.0, -b / 2.0), "dir": Vector3(0, 0, 1), "normal": Vector3(-1, 0, 0), "length": b},
		{"origin": Vector3(a / 2.0, 0.0, b / 2.0), "dir": Vector3(-1, 0, 0), "normal": Vector3(0, 0, -1), "length": a},
		{"origin": Vector3(-a / 2.0, 0.0, b / 2.0), "dir": Vector3(0, 0, -1), "normal": Vector3(1, 0, 0), "length": b},
	]


func _build_room(a: float, b: float, door_s: Dictionary) -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var t := WALL_T
	var h := _room_h
	_slab(body, Vector3(0, -t / 2.0, 0), Vector3(a + 2 * t, t, b + 2 * t), COLOR_FLOOR)
	_slab(body, Vector3(0, h + t / 2.0, 0), Vector3(a + 2 * t, t, b + 2 * t), COLOR_CEILING)
	var defs := _wall_defs(a, b)
	for w in 4:
		var d: Dictionary = defs[w]
		var ext := t if w % 2 == 0 else 0.0                  # norte y sur cubren las esquinas
		var cur := -ext
		for s in door_s.get(w, []):
			var s0: float = s - CORRIDOR_WIDTH * 0.5
			var s1: float = s + CORRIDOR_WIDTH * 0.5
			_wall_slab(body, d, cur, s0, 0.0, h)
			_wall_slab(body, d, s0, s1, DOOR_HEIGHT, h)      # dintel sobre la puerta
			cur = s1
		_wall_slab(body, d, cur, d.length + ext, 0.0, h)
	for c in _corridors:
		_build_corridor(body, c, h)
		_build_sign(defs[c.wall], c.s, c.name)


## Tramo de pared exterior entre las posiciones s0 y s1 (a lo largo de la pared) y las alturas y0..y1.
func _wall_slab(body: StaticBody3D, d: Dictionary, s0: float, s1: float, y0: float, y1: float) -> void:
	var n: Vector3 = d.normal
	var dir: Vector3 = d.dir
	var ln := s1 - s0
	var center: Vector3 = d.origin + dir * ((s0 + s1) * 0.5) - n * (WALL_T * 0.5) + Vector3(0, (y0 + y1) * 0.5, 0)
	var size := Vector3(absf(dir.x) * ln + absf(n.x) * WALL_T, y1 - y0, absf(dir.z) * ln + absf(n.z) * WALL_T)
	_slab(body, center, size, COLOR_WALL)


func _slab(body: StaticBody3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _flat_material(color)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	body.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	body.add_child(col)


func _flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.metallic_specular = 0.0
	return m


## Pasillo: piso, techo, dos paredes y fondo. u = distancia hacia afuera desde el plano interior de la
## pared de la sala (0..length); l = desplazamiento lateral desde el eje del pasillo.
func _build_corridor(body: StaticBody3D, c: Dictionary, h: float) -> void:
	var half := CORRIDOR_WIDTH * 0.5
	var t := WALL_T
	var len: float = c.length
	_corridor_box(body, c, t, len + t, -half - t, half + t, -t, 0.0, COLOR_FLOOR)
	_corridor_box(body, c, t, len + t, -half - t, half + t, h, h + t, COLOR_CEILING)
	_corridor_box(body, c, t, len, -half - t, -half, 0.0, h, COLOR_WALL)
	_corridor_box(body, c, t, len, half, half + t, 0.0, h, COLOR_WALL)
	_corridor_box(body, c, len, len + t, -half - t, half + t, 0.0, h, COLOR_WALL)


func _corridor_box(body: StaticBody3D, c: Dictionary, u0: float, u1: float, l0: float, l1: float,
		y0: float, y1: float, color: Color) -> void:
	var out: Vector3 = c.out
	var r: Vector3 = c.r
	var center: Vector3 = c.o + out * ((u0 + u1) * 0.5) + r * ((l0 + l1) * 0.5) + Vector3(0, (y0 + y1) * 0.5, 0)
	var du := u1 - u0
	var dl := l1 - l0
	var size := Vector3(absf(out.x) * du + absf(r.x) * dl, y1 - y0, absf(out.z) * du + absf(r.z) * dl)
	_slab(body, center, size, color)


## Cartel con el nombre de la colección, sobre la puerta y mirando hacia la sala.
func _build_sign(d: Dictionary, s: float, text: String) -> void:
	var n: Vector3 = d.normal
	var dir: Vector3 = d.dir
	var base: Vector3 = d.origin + dir * s + Vector3(0, DOOR_HEIGHT + 0.12 + SIGN_HEIGHT * 0.5, 0)
	var plaque := BoxMesh.new()
	plaque.size = Vector3(absf(dir.x) * CORRIDOR_WIDTH + absf(n.x) * 0.04, SIGN_HEIGHT,
		absf(dir.z) * CORRIDOR_WIDTH + absf(n.z) * 0.04)
	plaque.material = _flat_material(COLOR_SIGN)
	var pm := MeshInstance3D.new()
	pm.mesh = plaque
	pm.position = base + n * 0.02
	add_child(pm)
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.outline_size = 0
	label.modulate = COLOR_SIGN_TEXT
	label.double_sided = false
	var px := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
	var ps := SIGN_TEXT_HEIGHT / float(label.font_size)
	var max_w := CORRIDOR_WIDTH * 0.9
	if px > 0.0 and px * ps > max_w:
		ps = max_w / px                        # nombres largos: texto más chico
	label.pixel_size = ps
	label.position = base + n * 0.05
	label.rotation.y = atan2(n.x, n.z)
	add_child(label)


## Cuelga cuadros: todos los marcos van en un único MultiMesh (1 draw call).
func _hang_paintings() -> void:
	if _paintings.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = _flat_material(COLOR_FRAME)
	var frames := MultiMesh.new()
	frames.transform_format = MultiMesh.TRANSFORM_3D
	frames.mesh = box
	frames.instance_count = _paintings.size()
	var k := 0
	for ri in _runs.size():
		var run: Dictionary = _runs[ri]
		var n: Vector3 = run.normal
		var yaw := atan2(n.x, n.z)
		var rot := Basis(Vector3.UP, yaw)
		for it in run.items:
			var p: Dictionary = _paintings[it.idx]
			var base: Vector3 = run.origin + run.dir * (it.s + p.ow * 0.5) + Vector3(0, p.cy, 0)
			var frame_pos: Vector3 = base + n * (p.fd * 0.5)
			frames.set_instance_transform(k, Transform3D(rot * Basis.from_scale(Vector3(p.ow, p.oh, p.fd)), frame_pos))
			k += 1
			var quad := QuadMesh.new()
			quad.size = Vector2(p.w, p.h)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_texture = p.tex
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = mat
			mi.position = base + n * (p.fd + 0.003)
			mi.rotation.y = yaw
			add_child(mi)
			_placed.append({"name": p.name, "tex": p.tex, "mat": mat, "path": p.path, "hires": p.hires,
				"center": frame_pos, "normal": n, "right": run.dir,
				"ow": p.ow, "oh": p.oh, "tol": p.tol, "wall": ri, "offset": it.s})
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = frames
	add_child(mmi)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.08, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Una luz direccional sin sombras da relieve a la arquitectura a costo mínimo.
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.45
	sun.shadow_enabled = false
	sun.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
	add_child(sun)


# ---------- ENTRADA, ESTADOS Y VISTA AMPLIADA ----------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F11:
				var w := get_window()
				w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
			KEY_Z:
				if state == State.PLAY:
					_player.cycle_zoom()
					_refresh_zoom_label()
			KEY_E:
				if state == State.ZOOM:
					_set_state(State.PLAY)
				elif state == State.PLAY and _target >= 0:
					_open_zoom(_placed[_target])
			KEY_ESCAPE:
				if state == State.PLAY:
					_set_state(State.PAUSE)
				elif state == State.ZOOM or state == State.PAUSE:
					_set_state(State.PLAY)
			KEY_Q:
				if state == State.PAUSE:
					get_tree().quit()
	elif event is InputEventMouseButton and event.pressed and state == State.PAUSE:
		_set_state(State.PLAY)


func _set_state(new_state: State) -> void:
	state = new_state
	var playing := state == State.PLAY
	_player.enabled = playing
	_pause.visible = state == State.PAUSE
	_zoom_bg.visible = state == State.ZOOM
	if not playing:
		_hint.visible = false
	if state == State.PLAY or state == State.ZOOM:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _open_zoom(p: Dictionary) -> void:
	_zoom_tex.texture = p.mat.albedo_texture      # incluye el detalle si ya está cargado
	_zoom_name.text = p.name
	_set_state(State.ZOOM)


## Rayo desde la cámara: devuelve el cuadro apuntado más cercano que no queda tapado por una pared, o -1.
func _raycast_painting(max_dist: float, use_tolerance: bool) -> int:
	var cam := _player.camera
	var origin := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var wall_dist := max_dist
	var query := PhysicsRayQueryParameters3D.create(origin, origin + fwd * max_dist)
	query.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		wall_dist = origin.distance_to(hit.position)
	var best := -1
	var best_t := wall_dist
	for i in _placed.size():
		var p: Dictionary = _placed[i]
		var denom := fwd.dot(p.normal)
		if denom >= -0.001:
			continue
		var t: float = (p.center - origin).dot(p.normal) / denom
		if t < 0.0 or t > best_t:
			continue
		var hit_pt: Vector3 = origin + fwd * t - p.center
		var tol: float = p.tol if use_tolerance else 0.0
		if absf(hit_pt.dot(p.right)) <= p.ow * 0.5 + tol and absf(hit_pt.y) <= p.oh * 0.5 + tol:
			best = i
			best_t = t
	return best


func _update_target() -> void:
	_target = _raycast_painting(VIEW_DISTANCE, true)
	_hint.visible = _target >= 0


# ---------- DETALLE DE ALTA RESOLUCIÓN (zoom Z) ----------

## Con zoom activo, carga el original (hasta HIRES_TEX_SIZE) del cuadro apuntado.
## Se libera al volver al zoom normal o al pasar a otro cuadro.
func _update_hires() -> void:
	_collect_hires()
	if _player.zoom_level == 0:
		_revert_hires()
		return
	var want := _raycast_painting(HIRES_DISTANCE, false)
	if want >= 0 and want != _hires_idx and want != _hires_loading and _hires_thread == null and _placed[want].hires:
		_revert_hires()
		_hires_loading = want
		_hires_thread = Thread.new()
		_hires_thread.start(_hires_worker.bind(want, _placed[want].path))
	_refresh_zoom_label()


func _hires_worker(idx: int, path: String) -> void:
	var img: Image = Image.load_from_file(path)
	var result = null
	if img != null and not img.is_empty():
		_prepare_image(img, HIRES_TEX_SIZE)
		result = {"idx": idx, "image": img}
	_mutex.lock()
	_hires_result = result
	_mutex.unlock()


func _collect_hires() -> void:
	if _hires_thread == null or _hires_thread.is_alive():
		return
	_hires_thread.wait_to_finish()
	_hires_thread = null
	_mutex.lock()
	var res = _hires_result
	_hires_result = null
	_mutex.unlock()
	_hires_loading = -1
	if res != null and _player.zoom_level > 0:
		_revert_hires()
		_placed[res.idx].mat.albedo_texture = ImageTexture.create_from_image(res.image)
		_hires_idx = res.idx


func _revert_hires() -> void:
	if _hires_idx >= 0:
		var p: Dictionary = _placed[_hires_idx]
		p.mat.albedo_texture = p.tex
		_hires_idx = -1


func _refresh_zoom_label() -> void:
	_zoom_lbl.visible = _player.zoom_level > 0
	if _zoom_lbl.visible:
		_zoom_lbl.text = "Zoom %d×" % int(_player.zoom_magnification())
		if _hires_loading >= 0:
			_zoom_lbl.text += "  (cargando detalle)"


# ---------- HUD ----------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_msg = _make_label(layer, 28, VERTICAL_ALIGNMENT_CENTER, 0.0)
	_msg.text = "Cargando..."
	_hint = _make_label(layer, 20, VERTICAL_ALIGNMENT_BOTTOM, -70.0)
	_hint.text = "E: ver"
	_hint.visible = false
	_zoom_lbl = _make_label(layer, 18, VERTICAL_ALIGNMENT_TOP, 0.0)
	_zoom_lbl.offset_top = 14.0
	_zoom_lbl.visible = false
	_pause = _make_label(layer, 26, VERTICAL_ALIGNMENT_CENTER, 0.0)
	_pause.text = "Pausa\n\nEsc o clic: continuar\nQ: salir"
	_pause.visible = false
	_zoom_bg = ColorRect.new()
	_zoom_bg.color = Color(0, 0, 0, 0.88)
	_zoom_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_zoom_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_bg.visible = false
	layer.add_child(_zoom_bg)
	_zoom_tex = TextureRect.new()
	_zoom_tex.anchor_left = ZOOM_MARGIN
	_zoom_tex.anchor_right = 1.0 - ZOOM_MARGIN
	_zoom_tex.anchor_top = ZOOM_MARGIN
	_zoom_tex.anchor_bottom = 1.0 - ZOOM_MARGIN
	_zoom_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_zoom_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_zoom_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_zoom_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_bg.add_child(_zoom_tex)
	_zoom_name = _make_label(_zoom_bg, 16, VERTICAL_ALIGNMENT_BOTTOM, -8.0)


func _make_label(parent: Node, font_size: int, valign: VerticalAlignment, bottom_offset: float) -> Label:
	var l := Label.new()
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.offset_bottom = bottom_offset
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = valign
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


# ---------- AUTOPRUEBA (godot --headless --path . -- --selftest) ----------

func _selftest(a: float, b: float) -> void:
	var ok := true
	var notes: Array[String] = []
	# 1) Tramos: márgenes, alturas y separación mínima
	for ri in _runs.size():
		var run: Dictionary = _runs[ri]
		var items := _placed.filter(func(p): return p.wall == ri)
		items.sort_custom(func(x, y): return x.offset < y.offset)
		for k in items.size():
			var p: Dictionary = items[k]
			if p.offset < CORNER_MARGIN - 0.001 or p.offset + p.ow > run.length - CORNER_MARGIN + 0.001:
				ok = false
				notes.append("margen tramo %d" % ri)
			if p.center.y - p.oh * 0.5 < FLOOR_CLEARANCE - 0.001 or p.center.y + p.oh * 0.5 > _room_h - CEILING_CLEARANCE + 0.001:
				ok = false
				notes.append("altura tramo %d" % ri)
			if k > 0 and p.offset - (items[k - 1].offset + items[k - 1].ow) < _gap(items[k - 1].ow, p.ow) - 0.001:
				ok = false
				notes.append("separación tramo %d" % ri)
	# 2) Pasillos: ningún pasillo invade la sala ni a otro pasillo
	var rects: Array = [Rect2(-a / 2.0 - WALL_T, -b / 2.0 - WALL_T, a + 2.0 * WALL_T, b + 2.0 * WALL_T)]
	for c in _corridors:
		var p0: Vector3 = c.o + c.out * WALL_T - c.r * (CORRIDOR_WIDTH * 0.5 + WALL_T)
		var p1: Vector3 = c.o + c.out * (c.length + WALL_T) + c.r * (CORRIDOR_WIDTH * 0.5 + WALL_T)
		rects.append(Rect2(Vector2(minf(p0.x, p1.x), minf(p0.z, p1.z)), Vector2(absf(p1.x - p0.x), absf(p1.z - p0.z))))
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].grow(-0.005).intersects(rects[j].grow(-0.005)):
				ok = false
				notes.append("pasillos %d y %d se superponen" % [i, j])
	# 3) Nombres con medidas
	var t1 := _parse_name("paisaje__80x60")
	var t2 := _parse_name("otra__42,5X30cm")
	var t3 := _parse_name("sin medidas 1920x1080")
	if t1.name != "paisaje" or t1.w != 80.0 or t1.h != 60.0:
		ok = false
		notes.append("parseo 1")
	if t2.name != "otra" or t2.w != 42.5 or t2.h != 30.0:
		ok = false
		notes.append("parseo 2")
	if t3.name != "sin medidas 1920x1080" or t3.w != 0.0:
		ok = false
		notes.append("parseo 3")
	# 4) Zoom con detalle de alta resolución
	var detail := "n/a"
	for i in _placed.size():
		if _placed[i].hires:
			var d_ok: bool = await _test_hires(i)
			detail = "OK" if d_ok else "FALLA"
			if not d_ok:
				ok = false
			break
	# 5) Pasillos: se cruza la puerta y la selección no atraviesa paredes
	var walk := "n/a"
	var occl := "n/a"
	if not _corridors.is_empty():
		var w_ok: bool = await _test_walk()
		walk = "OK" if w_ok else "FALLA"
		var o_ok: bool = await _test_occlusion()
		occl = "OK" if o_ok else "FALLA"
		ok = ok and w_ok and o_ok
	# 6) Agacharse (Ctrl) y correr (Shift)
	var move_ok: bool = await _test_movement()
	ok = ok and move_ok
	print("SELFTEST ", "PASS" if ok else "FAIL", " cuadros=", _placed.size(), "/", _files.size(),
		" colecciones=", _corridors.size(), " sala=", snappedf(a, 0.1), "x", snappedf(b, 0.1), "x", snappedf(_room_h, 0.1),
		" detalle_zoom=", detail, " puerta=", walk, " oclusion=", occl, " movimiento=", "OK" if move_ok else "FALLA")
	for n in notes:
		print("  - ", n)
	get_tree().quit(0 if ok else 1)


func _key_press(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


## Se para frente a un cuadro con original grande, activa zoom y espera el detalle; luego vuelve a normal.
func _test_hires(idx: int) -> bool:
	var p: Dictionary = _placed[idx]
	_stand_facing(p, 2.0)
	_player.cycle_zoom()
	var t0 := Time.get_ticks_msec()
	while _hires_idx != idx and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	var loaded: bool = _hires_idx == idx and p.mat.albedo_texture.get_width() > MAX_TEX_SIZE
	for i in _player.ZOOM_LEVELS.size():
		_player.cycle_zoom()
	await get_tree().process_frame
	var reverted: bool = _hires_idx == -1 and _player.zoom_level == 0 and p.mat.albedo_texture == p.tex
	return loaded and reverted


## Coloca al jugador a `dist` metros frente al cuadro, mirándolo.
func _stand_facing(p: Dictionary, dist: float) -> void:
	var pos: Vector3 = p.center + p.normal * dist
	_player.position = Vector3(pos.x, 0.02, pos.z)
	_player.rotation.y = atan2(p.normal.x, p.normal.z)
	_player.camera.rotation.x = 0.0


## Camina desde la sala hacia el primer pasillo: debe atravesar la puerta sin trabarse.
func _test_walk() -> bool:
	var c: Dictionary = _corridors[0]
	var start: Vector3 = c.o - c.out * 1.5
	_player.position = Vector3(start.x, 0.02, start.z)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = atan2(-c.out.x, -c.out.z)
	_player.camera.rotation.x = 0.0
	_key_press(KEY_W, true)
	await get_tree().create_timer(1.6).timeout
	_key_press(KEY_W, false)
	var flat := Vector3(_player.position.x - c.o.x, 0.0, _player.position.z - c.o.z)
	return flat.dot(c.out) > 1.0 and absf(flat.dot(c.r)) < CORRIDOR_WIDTH * 0.5


## Un cuadro de pasillo visto desde adentro se selecciona; visto desde afuera, a través de la pared, no.
func _test_occlusion() -> bool:
	var target := -1
	for i in range(_placed.size() - 1, -1, -1):
		if _placed[i].wall >= _main_runs:
			target = i
			break
	if target < 0:
		return true
	var p: Dictionary = _placed[target]
	_stand_facing(p, 1.5)
	await get_tree().physics_frame
	var inside := _raycast_painting(HIRES_DISTANCE, false)
	_stand_facing(p, 5.0)
	await get_tree().physics_frame
	var outside := _raycast_painting(HIRES_DISTANCE, false)
	return inside == target and outside != target


## Ctrl baja cámara y cápsula y reduce la velocidad; Shift acelera.
func _test_movement() -> bool:
	_player.position = Vector3(0.0, 0.02, 1.0)
	_player.rotation.y = 0.0
	_player.camera.rotation.x = 0.0
	_player.velocity = Vector3.ZERO
	_key_press(KEY_SHIFT, true)
	_key_press(KEY_W, true)
	await get_tree().create_timer(0.6).timeout
	var run_speed := _player.velocity.length()
	_key_press(KEY_SHIFT, false)
	_key_press(KEY_W, false)
	await get_tree().create_timer(0.6).timeout
	_player.position = Vector3(0.0, 0.02, 1.0)
	_key_press(KEY_CTRL, true)
	_key_press(KEY_W, true)
	await get_tree().create_timer(1.0).timeout
	var crouch_speed := _player.velocity.length()
	var low_eye := _player.camera.position.y
	var low_shape := _player.shape.height
	_key_press(KEY_CTRL, false)
	_key_press(KEY_W, false)
	await get_tree().create_timer(1.0).timeout
	var high_eye := _player.camera.position.y
	var high_shape := _player.shape.height
	var walk_ok := run_speed > Player.WALK_SPEED + 1.0
	var crouch_ok := crouch_speed < Player.WALK_SPEED - 0.5 and low_eye < Player.EYE_HEIGHT - 0.5 \
		and low_shape < Player.HEIGHT - 0.4 and high_eye > Player.EYE_HEIGHT - 0.05 and high_shape > Player.HEIGHT - 0.05
	print("  movimiento: correr=", snappedf(run_speed, 0.01), " m/s agachado=", snappedf(crouch_speed, 0.01),
		" m/s ojo agachado=", snappedf(low_eye, 0.01), " m ojo de pie=", snappedf(high_eye, 0.01), " m")
	return walk_ok and crouch_ok
