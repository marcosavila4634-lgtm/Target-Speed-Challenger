class_name SerpenteBote
extends SerpenteGigante
## Cobras que dão o bote no Serpent's Climb (pedido do dono, 2026-10-05). Mesmo modelo e mesma cor da
## serpente gigante; o bote estica o pescoço até o carro e ele explode (volta ao último checkpoint).
## - ARENA (cobra 2, selva.cobra_arena): ronda dentro da plataforma dos buracos por uma volta fechada;
##   bote no carro que chegar a menos de `alcance` m da cabeça e depois descansa `descanso` s.
## - TOCA (cobra 3, selva.cobra_toca): mora numa toca da montanha colada na pista; num ciclo fixo
##   [escondida, saindo, fora, voltando] sai pela laje de pedra, atravessa a estrada (a cabeça passa da
##   beirada de lá, erguida) e volta. Com a cabeça fora é muito agressiva: bote em quem passar perto e
##   quem encosta no corpo em cima da pista também explode. O ciclo não muda com o bote: os bots
##   planejam a passagem (toca_adiante / livre_entre).
## Corpo da ARENA sólido (cápsulas que acompanham os ossos: o carro bate e é empurrado; só o bote
## mata); o da TOCA mata quem encosta. Log: TSC_COBRA_LOG.

enum Modo { ARENA, TOCA }

static var ativas: Array[SerpenteBote] = []

const BOTE_S := 0.22          # a cabeça vai até o carro
const BOTE_VOLTA_S := 0.35    # e volta
const BOTE_TOCA_S := 0.15     # a da toca é mais rápida

var modo := Modo.ARENA
var alcance := 13.0
var descanso := 3.0
var _espera := 0.0            # até o próximo bote poder sair
var _bote_t := -1.0           # tempo do bote em curso (-1 = nenhum)
var _bote_dur := BOTE_S
var _bote_alvo: Veiculo
var _bote_de := Vector3.ZERO  # deslocamento da cabeça quando o bote acabou (volta dele)
var _volta_t := -1.0
var _log := false
# Toca
var _ciclo: Array[float] = [3.0, 1.5, 1.6, 2.1]
var _periodo := 8.2
var _s_esc := 0.0             # cabeça escondida (m da trilha)
var _s_boca := 0.0            # boca da toca
var _s_fora := 0.0            # cabeça no ponto mais longe (passou da beirada de lá)
var _relogio := 0.0
var _varre := Vector3.ZERO    # balanço da cabeça ao longo da pista quando está fora
var i_pista := -1             # amostra da estrada na travessia
var meia_zona := 17.0         # metros de estrada de cada lado da travessia onde ela alcança
var _sub: ComplexoSubida
var _corpos: Array[AnimatableBody3D] = []   # colisão do corpo da arena, um pedaço a cada PASSO_CORPO ossos
const PASSO_CORPO := 4


func _enter_tree() -> void:
	if not self in ativas:
		ativas.append(self)


func _exit_tree() -> void:
	ativas.erase(self)


## Cobra 2: volta fechada dentro da plataforma (cfg.volta: [x da frente, lateral] da plataforma).
func montar_arena(plat: Recinto, cfg: Dictionary) -> void:
	name = "CobraArena"
	modo = Modo.ARENA
	alcance = float(cfg.get("alcance", 13.0))
	descanso = float(cfg.get("descanso", 3.0))
	_log = OS.get_environment("TSC_COBRA_LOG") != ""
	var curva := Curve3D.new()
	curva.bake_interval = 0.5
	var ctrl: Array = cfg.get("volta", [])
	var n := ctrl.size()
	for i in n + 1:
		var q := plat.pa(float(ctrl[i % n][0]), float(ctrl[i % n][1]), plat.piso_y + 0.05)
		var ant := plat.pa(float(ctrl[(i - 1 + n) % n][0]), float(ctrl[(i - 1 + n) % n][1]), plat.piso_y + 0.05)
		var prox := plat.pa(float(ctrl[(i + 1) % n][0]), float(ctrl[(i + 1) % n][1]), plat.piso_y + 0.05)
		curva.add_point(q, -(prox - ant) / 6.0, (prox - ant) / 6.0)
	var pts := curva.get_baked_points()
	pts.remove_at(pts.size() - 1)
	var c := cfg.duplicate()
	c["ossos"] = 64
	c["alcance_visivel"] = 1500.0
	montar_pontos(pts, c, true)
	_bote_pescoco = 0.35   # o bote leva o pescoço inteiro, não só a ponta (esticava como borracha)
	for k in range(0, _ossos - PASSO_CORPO, PASSO_CORPO):
		var corpo := AnimatableBody3D.new()
		corpo.sync_to_physics = false
		var forma := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = _gross * 0.42
		cap.height = maxf(_z[k + PASSO_CORPO] - _z[k] + cap.radius * 2.0, cap.radius * 2.0 + 0.1)
		forma.shape = cap
		corpo.add_child(forma)
		add_child(corpo)
		_corpos.append(corpo)
	_mover_corpos()


func _physics_process(_delta: float) -> void:
	_mover_corpos()


## Cápsulas de colisão em cima dos ossos (eixo da cápsula = Y, deitado ao longo do corpo).
func _mover_corpos() -> void:
	for n in _corpos.size():
		var a := _p[n * PASSO_CORPO]
		var b := _p[n * PASSO_CORPO + PASSO_CORPO]
		var eixo := b - a
		if eixo.length_squared() < 0.01:
			continue
		eixo = eixo.normalized()
		var lado := eixo.cross(Vector3.UP)
		if lado.length_squared() < 0.01:
			lado = Vector3.RIGHT
		lado = lado.normalized()
		var centro := (a + b) * 0.5 + Vector3.UP * _alto * 0.42
		_corpos[n].global_transform = Transform3D(Basis(lado, eixo, lado.cross(eixo)), centro)


## Cobra 3: toca na montanha ao lado da pista (cfg: trecho, metros, lado, alem, ciclo).
func montar_toca(sub: ComplexoSubida, terreno: Terreno, cfg: Dictionary) -> void:
	name = "CobraToca"
	modo = Modo.TOCA
	_sub = sub
	alcance = float(cfg.get("alcance", 14.0))
	descanso = 0.35
	_log = OS.get_environment("TSC_COBRA_LOG") != ""
	var cic: Array = cfg.get("ciclo", _ciclo)
	_ciclo.assign(cic.map(func(x): return float(x)))
	_periodo = _ciclo[0] + _ciclo[1] + _ciclo[2] + _ciclo[3]
	i_pista = sub.indice_trecho(str(cfg.get("trecho", "C")), float(cfg.get("metros", 0)))
	meia_zona = alcance + 3.0
	var c := sub.amostra(i_pista)
	var t := sub.tangente_em(i_pista)
	t = Vector3(t.x, 0.0, t.z).normalized()
	var lado := float(cfg.get("lado", -1))
	var n := sub.lateral_em(i_pista) * lado   # da pista para a montanha
	n = Vector3(n.x, 0.0, n.z).normalized()
	var meia := sub.largura_em(i_pista) * 0.5
	var y := c.y + 0.1
	# Parede da montanha: onde o terreno passa da altura da pista
	var parede := meia + 8.0
	var d := meia + 1.0
	while d < 80.0:
		var q := c + n * d
		if terreno.altura_em(q.x, q.z) >= c.y + 3.0:
			parede = d
			break
		d += 0.5
	var comp := float(cfg.get("comprimento", 95.0))
	var alem := float(cfg.get("alem", 9.0))
	# Trilha: de dentro da montanha (corpo inteiro escondido) até passar da beirada de lá, com um "S" leve
	var pts := PackedVector3Array()
	var de := parede + comp + 10.0
	var ate := -(meia + alem)
	var passos := int((de - ate) / 1.0)
	for k in passos + 1:
		var dd := lerpf(de, ate, float(k) / passos)
		var s_lado := 2.5 * sin(dd * 0.16) * smoothstep(parede + 4.0, parede - 2.0, dd)
		pts.append(c + n * dd + t * s_lado + Vector3(0.0, y - c.y, 0.0))
	var cfg2 := cfg.duplicate()
	cfg2["ossos"] = 64
	cfg2["alcance_visivel"] = 1800.0
	montar_pontos(pts, cfg2, false)
	_s_boca = de - parede
	_s_esc = _s_boca - 5.0
	_s_fora = _total
	_pos = _s_esc
	_erguer = 1.6
	_posar()
	_montar_toca_pedra(c, n, t, meia, parede, y)
	if OS.get_environment("TSC_SUB_LOG") != "" or _log:
		print("[COBRA] toca em %s, parede a %.1f m do eixo (meia pista %.1f), sai %.0f m, ciclo %s" % [str(c.snapped(Vector3.ONE)), parede, meia, _s_fora - _s_boca, str(_ciclo)])


## Boca escura da toca na parede e a laje de pedra (com colisão) da boca até a beirada da pista.
func _montar_toca_pedra(c: Vector3, n: Vector3, t: Vector3, meia: float, parede: float, y: float) -> void:
	var pedra := Selva.material_pedra(0, 0.9)
	var giro := Basis(t, Vector3.UP, n)   # x ao longo da pista, z para a montanha
	var comp_laje := parede - meia + 6.0
	var centro := c + n * (meia + comp_laje * 0.5 - 0.5)
	var laje := MeshInstance3D.new()
	var caixa := BoxMesh.new()
	caixa.size = Vector3(10.0, 3.2, comp_laje)
	laje.mesh = caixa
	laje.material_override = pedra
	laje.transform = Transform3D(giro, Vector3(centro.x, y - 1.7, centro.z))
	add_child(laje)
	var corpo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = caixa.size
	forma.shape = bx
	corpo.add_child(forma)
	corpo.transform = laje.transform
	add_child(corpo)
	# Pedras soltas embaixo da laje, encostadas na parede (a laje não fica "colada no ar")
	for k in 3:
		var bloco := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(7.0 - k * 1.5, 4.0 + k * 2.0, 5.0)
		bloco.mesh = b
		bloco.material_override = pedra
		var q := c + n * (parede - 1.0 - k * 1.5) + t * (k - 1) * 2.5
		bloco.transform = Transform3D(giro.rotated(Vector3.UP, 0.3 * (k - 1)), Vector3(q.x, y - 3.5 - k * 2.5, q.z))
		add_child(bloco)
	# Boca: buraco escuro com aro de pedra
	var boca := c + n * (parede - 0.6)
	var escuro := StandardMaterial3D.new()
	escuro.albedo_color = Color(0.01, 0.01, 0.008)
	escuro.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disco := MeshInstance3D.new()
	var cil := CylinderMesh.new()
	cil.top_radius = 4.6
	cil.bottom_radius = 4.6
	cil.height = 0.3
	cil.radial_segments = 28
	disco.mesh = cil
	disco.material_override = escuro
	disco.transform = Transform3D(giro * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.0, 1.0, 0.85)), Vector3(boca.x, y + 2.6, boca.z))
	add_child(disco)
	var aro := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 4.4
	tor.outer_radius = 6.2
	tor.rings = 24
	aro.mesh = tor
	aro.material_override = pedra
	aro.transform = Transform3D(giro * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.0, 0.6, 0.85)), Vector3(boca.x, y + 2.6, boca.z) - n * 0.4)
	add_child(aro)


# ------------------------------------------------------------------ movimento

func _avancar(delta: float) -> void:
	_relogio += delta
	if modo == Modo.ARENA:
		var lenta := _espera > 0.0 or _bote_t >= 0.0
		_pos += _vel * (0.35 if lenta else 1.0) * delta
	else:
		_pos = _s_cabeca(_relogio)
		# Fora da toca a cabeça varre a pista de um lado para o outro, procurando quem passa
		var fora := clampf((_pos - _s_boca) / maxf(_s_fora - _s_boca, 1.0), 0.0, 1.0)
		var t := _sub.tangente_em(i_pista)
		_varre = Vector3(t.x, 0.0, t.z).normalized() * 5.0 * fora * sin(_relogio * 2.6)
	_atacar(delta)
	_bote = _varre + _deslocamento_bote()


## Onde a cabeça da cobra da toca está na trilha no instante `tempo` (s desde a largada da etapa).
func _s_cabeca(tempo: float) -> float:
	var ph := fposmod(tempo, _periodo)
	if ph < _ciclo[0]:
		return _s_esc
	ph -= _ciclo[0]
	if ph < _ciclo[1]:
		var u := ph / _ciclo[1]
		return lerpf(_s_esc, _s_fora, 1.0 - (1.0 - u) * (1.0 - u))   # sai rápido e freia no fim
	ph -= _ciclo[1]
	if ph < _ciclo[2]:
		return _s_fora - 1.5 * (1.0 - cos(ph * 4.0))
	ph -= _ciclo[2]
	return lerpf(_s_fora, _s_esc, smoothstep(0.0, 1.0, ph / _ciclo[3]))


func _cabeca_fora_em(tempo: float) -> bool:
	return _s_cabeca(tempo) > _s_boca - 1.5


## Bots: a cabeça fica dentro da toca entre daqui a t0 e t1 s?
func livre_entre(t0: float, t1: float) -> bool:
	var tt := maxf(t0, 0.0)
	while tt <= t1:
		if _cabeca_fora_em(_relogio + tt):
			return false
		tt += 0.05
	return true


## Cobra da toca à frente da amostra `i` (até `alcance_m` m): {falta (m até a zona), comp (m da zona), cobra}.
static func toca_adiante(sub: ComplexoSubida, i: int, alcance_m: float) -> Dictionary:
	for c: SerpenteBote in ativas:
		if c.modo != Modo.TOCA or c._sub != sub or c.i_pista < 0 or sub.trecho_de(i) != sub.trecho_de(c.i_pista):
			continue
		var falta := sub.progresso_amostra(c.i_pista) - sub.progresso_amostra(i) - c.meia_zona
		if falta > -c.meia_zona * 2.0 and falta < alcance_m:
			return {"falta": falta, "comp": c.meia_zona * 2.0, "cobra": c}
	return {}


# ------------------------------------------------------------------ bote

func _deslocamento_bote() -> Vector3:
	if _bote_t >= 0.0 and is_instance_valid(_bote_alvo):
		var u := clampf(_bote_t / _bote_dur, 0.0, 1.0)
		var base := _cabeca_sem_bote()
		var para := (_bote_alvo.global_position + Vector3.UP * 0.8 - base).limit_length(alcance + 3.0)
		return para * (u * u * (3.0 - 2.0 * u))
	if _volta_t >= 0.0:
		return _bote_de * (1.0 - smoothstep(0.0, 1.0, _volta_t / BOTE_VOLTA_S))
	return Vector3.ZERO


func _cabeca_sem_bote() -> Vector3:
	return _na_trilha(_pos) + Vector3.UP * _alto * 0.75 * _erguer + _varre


func _atacar(delta: float) -> void:
	if _volta_t >= 0.0:
		_volta_t += delta
		if _volta_t >= BOTE_VOLTA_S:
			_volta_t = -1.0
	if _bote_t >= 0.0:
		_bote_t += delta
		if not is_instance_valid(_bote_alvo) or _bote_alvo.eliminado or _bote_alvo.fantasma():
			_fim_bote(false)
		elif _bote_t >= _bote_dur:
			var acertou := _bote_alvo.global_position.distance_to(_cabeca_sem_bote()) < alcance + 6.0
			if acertou:
				if _log:
					print("[COBRA] %s mordeu %s" % [name, _bote_alvo.nome_piloto])
				_bote_alvo.eliminar("cobra")
			_fim_bote(acertou)
		return
	if modo == Modo.TOCA:
		_esmagar()
	if _espera > 0.0:
		_espera -= delta
		return
	if modo == Modo.TOCA and _pos < _s_boca + 1.0:
		return   # escondida ou ainda na boca da toca
	var cab := _cabeca_sem_bote()
	var melhor: Veiculo = null
	var melhor_d := alcance
	for no in get_tree().get_nodes_in_group("veiculo"):
		var v := no as Veiculo
		if v == null or not _pode_morder(v):
			continue
		var dv := v.global_position - cab
		if absf(dv.y) > 7.0:
			continue
		var dist := Vector2(dv.x, dv.z).length()
		if dist < melhor_d:
			melhor_d = dist
			melhor = v
	if melhor:
		_bote_alvo = melhor
		_bote_t = 0.0
		_bote_dur = BOTE_TOCA_S if modo == Modo.TOCA else BOTE_S


func _pode_morder(v: Veiculo) -> bool:
	return not v.eliminado and not v.fantasma() and v.visible and v.na_largada


func _fim_bote(acertou: bool) -> void:
	_bote_de = _deslocamento_bote()
	_bote_t = -1.0
	_bote_alvo = null
	_volta_t = 0.0
	_espera = descanso if acertou or modo == Modo.TOCA else 0.8


## Cobra da toca: o corpo atravessado na pista também mata quem encosta.
func _esmagar() -> void:
	if _pos < _s_boca:
		return
	var raio := _gross * 0.5 + 1.6
	for no in get_tree().get_nodes_in_group("veiculo"):
		var v := no as Veiculo
		if v == null or not _pode_morder(v):
			continue
		var p := v.global_position
		for k in range(0, _ossos, 2):
			if _pos - _z[k] < _s_boca:
				break   # daqui para trás está dentro da toca
			var q := _p[k]
			if absf(p.y - q.y) < _alto + 1.5 and Vector2(p.x - q.x, p.z - q.z).length() < raio:
				if _log:
					print("[COBRA] %s esmagou %s" % [name, v.nome_piloto])
				v.eliminar("cobra")
				break
