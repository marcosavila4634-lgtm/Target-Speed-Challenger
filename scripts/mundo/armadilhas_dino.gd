class_name ArmadilhasDino
extends Armadilhas
## Armadilhas do Extinction Day (percursos.N.armadilhas). Todas com ritmo fixo e aviso antes:
## - raptores: dois raptores de tocaia nos nichos das bordas saltam de um lado ao outro da estrada,
##   um de cada vez (faixa por faixa); o salto mata;
## - mordidas: o T-Rex sai do covil na parede do túnel e morde atravessando a estrada inteira;
## - rochas: pedras despencam do teto do túnel (ou de um arco de rocha) numa faixa de cada vez e o
##   entulho fica na pista um tempo antes de afundar;
## - lavas: gêiseres de lava saem das grades no piso, uma faixa de cada vez;
## - lajes: lajes de basalto sobre a lava que racham com o peso do carro e caem (como o gelo fino);
## - pontes: tábuas da ponte suspensa entre as árvores gigantes, que quebram com o peso;
## - eletricas: raios da cerca elétrica caem numa faixa de cada vez — não mata, corta o motor;
## - manadas: um titanossauro atravessa a estrada devagar e volta; as patas matam, embaixo da
##   barriga passa;
## - portoes: portão do recinto que fecha a estrada inteira (as folhas de aço esmagam);
## - estouros: estouro de manada descendo a estrada contra quem sobe, numa faixa de cada vez;
## - meteoros: pedaços do meteoro caem em pontos marcados (o alvo vermelho acende antes) e deixam a
##   cratera em chamas na faixa por alguns segundos;
## - avalanche: nuvem de cinza e rocha em brasa que desce o trecho atrás dos carros; quem estiver
##   dentro dela é engolido. Volta em ciclos.
## - pteros_plataforma: bando de pterossauros voando por cima da plataforma dos buracos e soltando ovos
##   ao acaso; o ovo que acerta deixa o carro escorregando e com a direção invertida (pteros_ovos.gd).
## - pteros_estrada: o mesmo bando por cima de um pedaço de estrada ([{trecho, de, ate, ...}]).

const PTEROS := preload("res://scripts/mundo/pteros_ovos.gd")

var _rocha: ShaderMaterial
var _estouros: Array = []
var _avalanches: Array = []
var _cerca_t := 0.0


func montar(p_sub: ComplexoSubida, cfg: Dictionary, terreno: Terreno) -> void:
	sub = p_sub
	_terreno = terreno
	gelo = false
	_mat_ouro = ComplexoLancamento._material_metal(Color(0.7, 0.72, 0.75), 1.0, 0.3)
	_mat_obsidiana = StandardMaterial3D.new()
	_mat_obsidiana.albedo_color = Color(0.05, 0.045, 0.06)
	_rocha = ShaderMaterial.new()
	_rocha.shader = load("res://shaders/rocha_vulcao.gdshader")
	_rocha.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 331))
	_rocha.set_shader_parameter("ruido_fino", Terreno._textura_ruido(0.08, 4, 337))
	_rocha.set_shader_parameter("brasa", 0.35)
	for item in cfg.get("raptores", []):
		_montar_raptores(item, cfg.get("raptor", {}))
	for item in cfg.get("mordidas", []):
		_montar_mordida(item, cfg.get("mordida", {}))
	for item in cfg.get("rochas", []):
		_montar_rochas(item, cfg.get("rocha", {}))
	for item in cfg.get("lavas", []):
		_montar_lava(item, cfg.get("lava", {}))
	for item in cfg.get("lajes", []):
		_montar_tabuas(item, cfg.get("laje", {}), true)
	for item in cfg.get("pontes", []):
		_montar_tabuas(item, cfg.get("ponte", {}), false)
	for item in cfg.get("eletricas", []):
		_montar_eletrica(item, cfg.get("eletrica", {}))
	for item in cfg.get("manadas", []):
		_montar_manada(item, cfg.get("manada", {}))
	for item in cfg.get("portoes", []):
		_montar_portao(item, cfg.get("portao", {}))
	for item in cfg.get("estouros", []):
		_montar_estouro(item, cfg.get("estouro", {}))
	for item in cfg.get("meteoros", []):
		_montar_meteoro(item, cfg.get("meteoro", {}))
	for item in cfg.get("avalanches", []):
		_montar_avalanche(item, cfg.get("avalanche", {}))
	if cfg.has("pteros_plataforma") and sub.plataforma and OS.get_environment("TSC_SEM_PTEROS") == "":   # TSC_SEM_PTEROS: medir o custo deles
		var pteros: Node3D = PTEROS.new()
		pteros.name = "PterosOvos"
		add_child(pteros)
		pteros.montar(sub.plataforma, cfg.pteros_plataforma)
	if OS.get_environment("TSC_SEM_PTEROS") == "":
		for item: Dictionary in cfg.get("pteros_estrada", []):
			var bando: Node3D = PTEROS.new()
			bando.name = "PterosEstrada"
			add_child(bando, true)
			bando.montar_estrada(sub, terreno, item)
	_portoes.sort_custom(func(a, b): return a.s < b.s)
	for k in _portoes.size():
		_portoes[k].id = k
	_atualizar()
	if OS.get_environment("TSC_SUB_LOG") != "":
		for g: Dictionary in _portoes:
			print("[ARMADILHA] %s em s=%.0f %s" % [g.tipo, g.s, str(sub.amostra(g.i).snapped(Vector3.ONE))])


# ------------------------------------------------------------------ comum

func _no(nome: String) -> Node3D:
	var no := Node3D.new()
	no.name = "%s%d" % [nome, _portoes.size()]
	add_child(no)
	return no


## Pedra/laje de basalto (caixa) com o material de rocha do vulcão.
func _bloco(pai: Node3D, tam: Vector3, xf: Transform3D) -> void:
	_malha(pai, _caixa(tam), _rocha, xf)


## Coluna de rocha do ponto até o chão (nada flutua).
func _ao_chao(pai: Node3D, topo: Vector3, lado: float, colunas: Array[Transform3D]) -> void:
	var chao := _terreno.altura_em(topo.x, topo.z)
	if topo.y - chao > 2.0:
		colunas.append(Transform3D(Basis.from_scale(Vector3(lado, topo.y - chao, lado)), Vector3(topo.x, (topo.y + chao) * 0.5, topo.z)))


## Material emissivo cuja energia é trocada a cada quadro (avisos, luzes piscando).
static func _brilho(cor: Color, energia := 4.0, aditivo := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = cor
	m.emission_enabled = true
	m.emission = cor
	m.emission_energy_multiplier = energia
	if aditivo:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = Gelo._textura_floco()
	return m


## Mancha de aviso no piso de uma faixa (brilha mais quanto mais perto do perigo).
func _aviso(pai: Node3D, centro: Vector3, b: Basis, tam: Vector2, cor := Color(1.0, 0.15, 0.05)) -> StandardMaterial3D:
	var m := _brilho(cor, 0.0, true)
	var q := QuadMesh.new()
	q.size = tam
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(b * Basis(Vector3.RIGHT, -PI * 0.5), centro + b.y * 0.08)
	pai.add_child(mi)
	return m


## Nuvem de poeira/fumaça de um disparo (impacto de pedra, cratera).
func _poeira(pai: Node3D, raio: float, cor := Color(0.35, 0.3, 0.27, 0.75)) -> GPUParticles3D:
	var part := GPUParticles3D.new()
	part.amount = 36
	part.lifetime = 1.8
	part.one_shot = true
	part.explosiveness = 0.9
	part.emitting = false
	part.local_coords = false
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = raio
	proc.direction = Vector3.UP
	proc.spread = 70.0
	proc.initial_velocity_min = 2.0
	proc.initial_velocity_max = 7.0
	proc.gravity = Vector3(0, -2.0, 0)
	proc.damping_min = 1.0
	proc.damping_max = 2.0
	proc.scale_min = raio * 1.2
	proc.scale_max = raio * 2.6
	var curva := Curve.new()
	curva.add_point(Vector2(0.0, 1.0))
	curva.add_point(Vector2(1.0, 0.0))
	var tc := CurveTexture.new()
	tc.curve = curva
	proc.alpha_curve = tc
	part.process_material = proc
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = cor
	mat.albedo_texture = Selva._textura_nuvem()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.roughness = 1.0
	quad.material = mat
	part.draw_pass_1 = quad
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pai.add_child(part)
	return part


## Fagulhas (lava espirrando, faíscas elétricas): partículas pequenas e acesas, contínuas.
func _fagulhas(pai: Node3D, cor: Color, raio: float, vel: float, qtd := 40) -> GPUParticles3D:
	var part := GPUParticles3D.new()
	part.amount = qtd
	part.lifetime = 0.9
	part.emitting = false
	part.local_coords = false
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = raio
	proc.direction = Vector3.UP
	proc.spread = 35.0
	proc.initial_velocity_min = vel * 0.5
	proc.initial_velocity_max = vel
	proc.gravity = Vector3(0, -12.0, 0)
	proc.scale_min = 0.15
	proc.scale_max = 0.4
	part.process_material = proc
	var quad := QuadMesh.new()
	quad.material = _brilho(cor, 5.0, true)
	(quad.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	(quad.material as StandardMaterial3D).billboard_keep_scale = true
	part.draw_pass_1 = quad
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pai.add_child(part)
	return part


func _x_faixa(lado: int) -> float:
	return FAIXA if lado == 1 else -FAIXA


# ------------------------------------------------------------------ raptores

## item = [trecho, m, fase, período, no túnel (bool)]
func _montar_raptores(item: Array, cfg: Dictionary) -> void:
	if item.size() > 4 and bool(item[4]):
		_montar_cortina(item, cfg)   # dentro do túnel: queda de lava do teto (pedido do dono)
		return
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var periodo := float(item[3]) if item.size() > 3 and float(item[3]) > 0.0 else float(cfg.get("periodo", 3.6))
	var tunel := bool(item[4]) if item.size() > 4 else false
	var c := sub.amostra(i)
	var b := _base(i)
	var lat := sub.lateral_em(i)
	var meia := sub.largura_em(i) * 0.5
	var no := _no("Raptores")
	var borda := meia + 3.4
	var colunas: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		var pe := c + lat * s * borda
		_bloco(no, Vector3(5.0, 1.4, 5.0), Transform3D(b, pe - Vector3.UP * 0.7))
		_bloco(no, Vector3(3.2, 2.0, 1.6), Transform3D(b * Basis(Vector3.UP, 0.4 * s), pe + lat * s * 1.8 + b.z * 1.6 + Vector3.UP * 0.6))
		if not tunel:
			_ao_chao(no, pe - Vector3.UP * 1.4, 3.6, colunas)
			# (os dois postes de 6 m da "cerca arrebentada" atrás de cada bicho saíram a pedido do dono, 2026-10-04:
			# pilares soltos ao lado da pista, sem cerca nenhuma — em todas as etapas)
	ComplexoLancamento.criar_multimesh(no, colunas, _rocha)
	# Pedido do dono (2026-10-03): no lugar dos raptores que saltavam de um lado para o outro, um
	# dinossauro em cada beirada que VOMITA uma gosma verde na faixa do lado dele, um de cada vez.
	# Não mata: o carro atingido anda muito devagar por `lento_s` segundos (Veiculo.gosma).
	var bichos := []
	var corpos := []
	var jatos := []
	var pocas := []
	var comp_b := float(cfg.get("comprimento_cuspidor", 7.0))
	for k in 2:
		var s_k := -1.0 if k == 0 else 1.0
		var d := DinosParque.criar("raptor", comp_b)
		var corpo := _corpo_mortal(no, true)
		corpo.add_child(d.raiz)
		_forma_caixa(corpo, Vector3(1.6, 2.6, comp_b * 0.8), Transform3D(Basis.IDENTITY, Vector3(0, 1.4, 0.0)))
		var pe := c + lat * s_k * (borda + 0.6)
		corpo.global_transform = Transform3D(Basis.looking_at(-lat * s_k, Vector3.UP), pe)
		bichos.append(d)
		corpos.append(corpo)
		# Jato de gosma da boca até o meio da faixa
		var jato := GPUParticles3D.new()
		jato.amount = 230
		jato.lifetime = 0.6
		jato.local_coords = false
		jato.emitting = false
		var pm := ParticleProcessMaterial.new()
		pm.direction = (-lat * s_k * 1.0 + Vector3.DOWN * 0.28).normalized()
		pm.spread = 4.5
		pm.initial_velocity_min = 12.0
		pm.initial_velocity_max = 16.5
		pm.gravity = Vector3(0.0, -9.0, 0.0)
		pm.scale_min = 0.45
		pm.scale_max = 1.35
		# Meleca, não bolas (pedido do dono): nacos compridos alinhados com o voo, que o shader amassa e afina
		# atrás num fio — juntos formam um jorro grosso e irregular; nascem finos na boca e engrossam
		pm.particle_flag_align_y = true
		var engrossa := Curve.new()
		engrossa.add_point(Vector2(0.0, 0.35))
		engrossa.add_point(Vector2(0.25, 1.0))
		engrossa.add_point(Vector2(1.0, 0.8))
		var tc_e := CurveTexture.new()
		tc_e.curve = engrossa
		pm.scale_curve = tc_e
		jato.process_material = pm
		var gota := SphereMesh.new()
		gota.radius = 0.26
		gota.height = 1.5
		gota.radial_segments = 14
		gota.rings = 10
		var mat_gosma := ShaderMaterial.new()
		mat_gosma.shader = load("res://shaders/gosma_jato.gdshader")
		gota.material = mat_gosma
		jato.draw_pass_1 = gota
		jato.position = pe + Vector3.UP * (comp_b * 0.36) - lat * s_k * (comp_b * 0.42)
		no.add_child(jato)
		jatos.append(jato)
		# Baba: fios finos escorrendo da boca enquanto ele cospe
		var baba := GPUParticles3D.new()
		baba.amount = 26
		baba.lifetime = 0.7
		baba.local_coords = false
		baba.emitting = false
		var pb := ParticleProcessMaterial.new()
		pb.direction = (-lat * s_k * 0.5 + Vector3.DOWN).normalized()
		pb.spread = 14.0
		pb.initial_velocity_min = 1.5
		pb.initial_velocity_max = 4.0
		pb.gravity = Vector3(0.0, -9.0, 0.0)
		pb.scale_min = 0.25
		pb.scale_max = 0.55
		pb.particle_flag_align_y = true
		baba.process_material = pb
		baba.draw_pass_1 = gota
		jato.add_child(baba)
		jato.set_meta("baba", baba)
		jato.set_meta("lado", s_k)
		# Poça verde na faixa (acende enquanto ele cospe)
		var poca := MeshInstance3D.new()
		var pl := PlaneMesh.new()
		pl.size = Vector2(5.6, 8.0)
		poca.mesh = pl
		var mp := ShaderMaterial.new()
		mp.shader = load("res://shaders/gosma_poca.gdshader")
		mp.set_shader_parameter("ruido", Terreno._textura_ruido(0.02, 3, 431))
		mp.set_shader_parameter("semente", 0.37 * (k + 1) + 0.11 * i)
		poca.material_override = mp
		poca.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		poca.transform = Transform3D(b, c + lat * _x_faixa(k) + Vector3.UP * 0.05)
		no.add_child(poca)
		pocas.append(mp)
	_portoes.append({"tipo": "cuspe", "i": i, "s": sub.progresso_amostra(i), "comp": 6.4, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": periodo, "ativo": float(cfg.get("cuspe_s", 1.4)), "lento": float(cfg.get("lento_s", 5.0)), "c": c, "lat": lat, "tan": -b.z,
		"bichos": bichos, "corpos": corpos, "jatos": jatos, "pocas": pocas, "poca_a": [0.0, 0.0], "total": false})


## Queda de lava (túnel do vulcão): a lava despenca do teto do tubo de parede a parede — em cima da
## pista e dos dois lados dela, até o rio de lava lá embaixo. Ciclo: a boca incha (`aviso_s`, já dentro
## do tempo livre), a lava cai (`desce_s`) e escorre até completar `corre_s`; aí a boca fecha, o fio
## estrangula e a cauda cai atrás (`some_s`); depois fica `livre_s` sem lava. Cada fio é um cilindro que
## o shader lava_cortina molda (gota na frente, caroços, cauda fina). Mortal enquanto a lava alcança a pista.
func _montar_cortina(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var c := sub.amostra(i)
	var b := _base(i)
	var lat := sub.lateral_em(i)
	var meia := sub.largura_em(i) * 0.5
	# Seção do tubo neste ponto (sem túnel por perto: as medidas padrão dele)
	var meia_t := 9.0
	var topo := 13.0
	var ombro := 4.0
	var fundo := -4.9
	if is_inside_tree():
		for no_t in get_tree().get_nodes_in_group("tunel_vulcao"):
			var tun := no_t as TunelVulcao
			var sec: Array = tun.secao_em(c) if tun else []
			if not sec.is_empty():
				meia_t = float(sec[0])
				topo = float(sec[1])
				ombro = tun.ombro
				fundo = tun.lava_y - 0.3
	if OS.get_environment("TSC_DINO_LOG") != "":
		print("[LAVA] queda em %s lat %s tan %s tubo %.1f x %.1f pista %.1f" % [str(c), str(lat), str(-b.z), meia_t * 2.0, topo, meia * 2.0])
	var na_rocha := 2.4   # o fio nasce dentro da rocha do teto (ela avança até 2,3 m para fora do arco)
	var no := _no("QuedaLava")
	var shader: Shader = load("res://shaders/lava_cortina.gdshader")
	var ruido := Terreno._textura_ruido(0.05, 4, 331)
	var rng := RandomNumberGenerator.new()
	rng.seed = 977 + i
	var cil := CylinderMesh.new()
	cil.top_radius = 1.0
	cil.bottom_radius = 1.0
	cil.height = 1.0
	cil.radial_segments = 14
	cil.rings = 36
	var n := maxi(int(round(meia_t * 2.0 / 1.3)), 7)
	var passo := meia_t * 2.0 / n
	var fios := []
	var alt_max := 0.0
	for k in n:
		var x := -meia_t + passo * (k + 0.5 + rng.randf_range(-0.25, 0.25))
		var u := clampf(absf(x) / meia_t, 0.0, 1.0)
		var y_teto := ombro + (topo - ombro) * sqrt(1.0 - u * u) + na_rocha
		var y_chao := 0.0 if absf(x) < meia + 0.4 else fundo   # fora da pista a lava cai até o rio
		var alt := y_teto - y_chao
		alt_max = maxf(alt_max, alt)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("ruido", ruido)
		mat.set_shader_parameter("altura", alt)
		mat.set_shader_parameter("raio", passo * rng.randf_range(0.7, 1.05))
		mat.set_shader_parameter("semente", rng.randf())
		mat.set_shader_parameter("velocidade", rng.randf_range(4.8, 6.4))
		var mi := MeshInstance3D.new()
		mi.mesh = cil
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0
		mi.visible = false
		mi.transform = Transform3D(Basis.from_scale(Vector3(1.0, alt, 1.0)), c + lat * x - b.z * rng.randf_range(-0.6, 0.6) + Vector3.UP * (y_chao + alt * 0.5))
		no.add_child(mi)
		fios.append({"mi": mi, "mat": mat, "alt": alt, "atraso": rng.randf_range(0.0, 0.3)})
	var corpo := _corpo_mortal(no, true)
	_forma_caixa(corpo, Vector3(meia_t * 2.0, topo, 2.0), Transform3D(Basis.IDENTITY, Vector3(0, topo * 0.5, 0)))
	corpo.global_transform = Transform3D(b, c)
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.42, 0.1)
	luz.omni_range = 30.0
	luz.position = c + Vector3.UP * 5.0
	no.add_child(luz)
	# Poça em brasa onde a lava bate na pista (deitada na rampa da estrada)
	var tg := sub.tangente_em(i).normalized()
	var poca := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(meia * 2.0 + 0.6, 9.0)
	poca.mesh = pl
	var mat_poca := ShaderMaterial.new()
	mat_poca.shader = load("res://shaders/lava_poca.gdshader")
	mat_poca.set_shader_parameter("ruido", ruido)
	poca.material_override = mat_poca
	poca.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	poca.visible = false
	poca.transform = Transform3D(Basis(lat, (-tg).cross(lat).normalized(), -tg), c + Vector3.UP * 0.08)
	no.add_child(poca)
	var resp := _fagulhas(no, Color(1.0, 0.5, 0.1), meia, 5.0, 50)
	resp.position = c + Vector3.UP * 0.3
	var corre := float(cfg.get("corre_s", 4.0))
	var livre := float(cfg.get("livre_s", 3.0))
	var some := float(cfg.get("some_s", 2.2))
	_portoes.append({"tipo": "cortina", "i": i, "s": sub.progresso_amostra(i), "comp": 2.0, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": corre + some + livre, "corre": corre, "desce": minf(float(cfg.get("desce_s", 2.0)), corre), "some": some,
		"aviso": minf(float(cfg.get("aviso_s", 1.0)), livre), "alt": topo + na_rocha, "alt_max": alt_max, "bojo": na_rocha + 0.8,
		"c": c, "b": b, "fios": fios, "corpo": corpo, "luz": luz, "resp": resp, "poca": poca, "total": true})


## Estado da queda no instante t, em metros abaixo da boca: x = até onde a frente da lava já desceu,
## y = de onde o fio já soltou do teto (0 = ainda preso). Sem lava: (0, 0).
func _cortina(g: Dictionary, t: float, atraso := 0.15) -> Vector2:
	var periodo: float = g.periodo
	var f := fposmod(t + float(g.fase) - atraso, periodo)
	var corre: float = g.corre
	var bojo: float = g.bojo
	var fim: float = float(g.alt_max) + 2.5
	if f >= periodo - float(g.aviso):
		# A boca incha devagar antes de despencar
		return Vector2(bojo * smoothstep(0.0, 1.0, (f - (periodo - float(g.aviso))) / float(g.aviso)), 0.0)
	if f < float(g.desce):
		var q := f / float(g.desce)
		return Vector2(lerpf(bojo, fim, q * q), 0.0)   # queda acelerando
	if f < corre:
		return Vector2(fim, 0.0)
	if f < corre + float(g.some):
		return Vector2(fim, (fim + 2.0) * pow((f - corre) / float(g.some), 1.7))
	return Vector2.ZERO


## A lava está a menos de `folga` metros da pista (ou nela) no instante t?
func _cortina_fechada(g: Dictionary, t: float, folga: float) -> bool:
	var e := _cortina(g, t)
	return e.x > float(g.alt) - folga and e.y < float(g.alt) - 0.3


func _animar_cortina(g: Dictionary) -> void:
	for fio: Dictionary in g.fios:
		var e := _cortina(g, _t, float(fio.atraso))
		var mat: ShaderMaterial = fio.mat
		mat.set_shader_parameter("frente", e.x)
		mat.set_shader_parameter("cauda", e.y)
		(fio.mi as MeshInstance3D).visible = e.x > 0.01 and e.y < float(fio.alt) + 4.0
	var e0 := _cortina(g, _t)
	var alt: float = g.alt
	var fechado := _cortina_fechada(g, _t, 2.5)
	(g.corpo as AnimatableBody3D).global_transform = Transform3D(g.b as Basis, (g.c as Vector3) + (Vector3.ZERO if fechado else Vector3.DOWN * 400.0))
	(g.luz as OmniLight3D).light_energy = 0.4 + 6.0 * clampf(e0.x / alt, 0.0, 1.0) * (1.0 - clampf(e0.y / alt, 0.0, 1.0))
	# Poça: acende quando a frente bate na pista e esfria depois que a cauda passa
	var f := fposmod(_t + float(g.fase), float(g.periodo))
	var fim_s: float = float(g.corre) + float(g.some)
	var quente := smoothstep(float(g.desce) * 0.8, float(g.desce) + 0.5, f) * (1.0 - smoothstep(fim_s * 0.95, fim_s + 1.5, f))
	var poca: MeshInstance3D = g.poca
	poca.visible = quente > 0.01
	(poca.material_override as ShaderMaterial).set_shader_parameter("quente", quente)
	(g.resp as GPUParticles3D).emitting = quente > 0.6 and e0.y < alt


## O cuspidor k (0 = esquerda, 1 = direita) está cuspindo no instante t? Devolve também o preparo (0..1) antes do jato.
func _cuspe(g: Dictionary, k: int, t: float) -> Array:
	var per: float = g.periodo
	var f := fposmod(t + float(g.fase) + k * per * 0.5, per)
	return [f < float(g.ativo), smoothstep(per - 0.8, per, f)]


func _perigo_cuspe(g: Dictionary, lado: int, t: float) -> bool:
	return bool(_cuspe(g, lado, t)[0])


func _animar_cuspe(g: Dictionary) -> void:
	var lat: Vector3 = g.lat
	var tan: Vector3 = g.tan
	for k in 2:
		var r := _cuspe(g, k, _t)
		var ativo: bool = r[0]
		var jato := g.jatos[k] as GPUParticles3D
		jato.emitting = ativo
		(jato.get_meta("baba") as GPUParticles3D).emitting = ativo
		# O jorro sai da BOCA: ponta do focinho medida no osso da cabeça a cada quadro (o bicho levanta, baixa e
		# estica o pescoço para cuspir; um ponto fixo no ar ficava fora da boca)
		var bicho: Dictionary = g.bichos[k]
		var esq := bicho.get("esq") as Skeleton3D
		if esq != null and int(bicho.get("cabeca", -1)) >= 0:
			var comp_c := float(bicho.get("comp", 7.0))
			var cab := esq.global_transform * esq.get_bone_global_pose(int(bicho.cabeca)).origin
			var frente_b := -lat * float(jato.get_meta("lado"))
			jato.global_position = cab + frente_b * comp_c * 0.085 - Vector3.UP * comp_c * 0.015
		g.poca_a[k] = move_toward(float(g.poca_a[k]), 1.0 if ativo else 0.0, get_physics_process_delta_time() * (3.0 if ativo else 0.4))
		(g.pocas[k] as ShaderMaterial).set_shader_parameter("quanto", float(g.poca_a[k]))
		DinosParque.pose(g.bichos[k], _t * 2.0 + k, 0.15, 1.0 if ativo else float(r[1]) * 0.6, 0.7 if ativo else float(r[1]))
		if not ativo:
			continue
		for no_v in get_tree().get_nodes_in_group("veiculo"):
			var v := no_v as Veiculo
			if v == null or v.eliminado or v.fantasma():
				continue
			var q: Vector3 = v.global_position - (g.c as Vector3)
			if absf(q.dot(tan)) < 3.6 and absf(q.dot(lat) - _x_faixa(k)) < 2.6 and absf(q.y) < 3.0:
				v.gosma(float(g.lento))


## Estado do raptor k no instante t: [x lateral, y, saltando, lado de onde sai, preparo 0..1].
func _raptor(g: Dictionary, k: int, t: float) -> Array:
	var per: float = g.periodo
	var tk := t + float(g.fase) + k * per * 0.5
	var n := floori(tk / per)
	var f := tk - n * per
	var de := -1.0 if posmod(n + k, 2) == 0 else 1.0
	var salto: float = g.salto
	var borda: float = g.borda
	if f < salto:
		var u := f / salto
		return [lerpf(de * borda, -de * borda, u), 4.0 * float(g.altura) * u * (1.0 - u), true, de, 0.0]
	return [-de * borda, 0.0, false, -de, smoothstep(per - 0.7, per, f)]


func _perigo_raptor(g: Dictionary, lado: int, t: float) -> bool:
	for k in 2:
		var r := _raptor(g, k, t)
		if r[2] and float(r[1]) < 2.4 and absf(float(r[0]) - _x_faixa(lado)) < 1.7 + MEIA_CARRO + 0.3:
			return true
	return false


func _animar_raptores(g: Dictionary) -> void:
	var lat: Vector3 = g.lat
	for k in 2:
		var r := _raptor(g, k, _t)
		var d: Dictionary = g.bichos[k]
		var corpo: AnimatableBody3D = g.corpos[k]
		var x: float = r[0]
		var de: float = r[3]
		var frente := -lat * de * (-1.0 if not r[2] else 1.0)
		if r[2]:
			frente = lat * -de
		var p: Vector3 = (g.c as Vector3) + lat * x + Vector3.UP * float(r[1])
		var b := Basis.looking_at(frente, Vector3.UP)
		if r[2]:
			# No ar: corpo acompanha a parábola
			var u := (x / float(g.borda) * -de + 1.0) * 0.5
			b = b * Basis(Vector3.RIGHT, (0.5 - u) * 0.6)
			DinosParque.pose(d, 1.2, 0.0, 0.9, 0.6)
		else:
			var prep: float = r[4]
			DinosParque.pose(d, _t * 3.0 + k, 0.15, 0.2 + prep * 0.8, prep)
			p += Vector3.DOWN * prep * 0.35
		corpo.global_transform = Transform3D(b, p)


# ------------------------------------------------------------------ mordida do T-Rex

## Rocha irregular do covil do T-Rex (pedido do dono: boca de caverna, toda desnivelada, no lugar da sala
## quadrada): um tubo torto que entra de lado na parede — arco de teto e paredes com a rocha avançando e
## recuando (ruído), chão ondulado — ou, sem teto, a laje de rocha bruta entre a estrada e a boca, com as
## beiradas tortas descendo até a lava. x = metros para o lado do covil a partir do eixo da estrada.
func _caverna(no: Node3D, c: Vector3, eixo_x: Vector3, eixo_z: Vector3, x_a: float, x_b: float, meia_z: float, alto: float, teto: bool, semente: int) -> void:
	var ruido := FastNoiseLite.new()
	ruido.seed = semente
	ruido.frequency = 0.13
	ruido.fractal_octaves = 3
	var grande := FastNoiseLite.new()
	grande.seed = semente + 5
	grande.frequency = 0.045
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const ARCO := 18
	const CHAO := 8
	var n_est := maxi(int((x_b - x_a) / 1.3), 2)
	var n_anel := 0
	for e in n_est + 1:
		var x := lerpf(x_a, x_b, float(e) / n_est)
		var w := meia_z * (0.9 + 0.3 * grande.get_noise_2d(x * 2.0, 3.0))
		var h := alto * (0.85 + 0.25 * grande.get_noise_2d(x * 2.0, 40.0))
		var desvio := meia_z * 0.25 * grande.get_noise_2d(x * 1.5, 90.0)   # o tubo serpenteia
		var fecha := 1.0 - 0.75 * smoothstep(0.75, 1.0, float(e) / n_est) if teto else 1.0   # afunila no fundo
		var anel := []   # [z, y, normal (z, y)]
		if teto:
			for k in ARCO + 1:
				var a := PI * float(k) / ARCO
				var r := 1.0 + 0.22 * ruido.get_noise_2d(x * 3.0, k * 9.0) + 0.12 * ruido.get_noise_2d(x * 9.0 + 50.0, k * 23.0)
				anel.append([desvio + w * fecha * cos(a) * r, h * fecha * sin(a) * r - 0.4, Vector2(-cos(a), -sin(a))])
		else:
			anel.append([desvio + w * (1.9 + 0.3 * ruido.get_noise_2d(x * 4.0, 11.0)), -7.0, Vector2(1, 0)])
			anel.append([desvio + w * (1.35 + 0.25 * ruido.get_noise_2d(x * 5.0, 13.0)), -3.6, Vector2(1, 0)])
			anel.append([desvio + w * (1.0 + 0.1 * ruido.get_noise_2d(x * 6.0, 7.0)), -1.2, Vector2(1, 0)])
		for k in CHAO + 1:
			var z := lerpf(w, -w, float(k) / CHAO) * (-1.0 if teto else 1.0) * fecha * (1.0 + (0.12 * ruido.get_noise_2d(x * 5.0, 77.0 + k) if k == 0 or k == CHAO else 0.0))
			var borda := absf(float(k) / CHAO - 0.5) * 2.0
			# O meio do chão quase plano (o bicho pisa ali); as beiradas sobem e descem
			anel.append([desvio + z, -0.12 + 0.5 * borda * borda * ruido.get_noise_2d(x * 7.0, k * 31.0) + 0.1 * ruido.get_noise_2d(x * 14.0, k * 57.0), Vector2(0, 1)])
		if not teto:
			anel.append([desvio - w * (1.0 + 0.1 * ruido.get_noise_2d(x * 6.0, 19.0)), -1.2, Vector2(-1, 0)])
			anel.append([desvio - w * (1.35 + 0.25 * ruido.get_noise_2d(x * 5.0, 29.0)), -3.6, Vector2(-1, 0)])
			anel.append([desvio - w * (1.9 + 0.3 * ruido.get_noise_2d(x * 4.0, 23.0)), -7.0, Vector2(-1, 0)])
		n_anel = anel.size()
		for q: Array in anel:
			var nrm: Vector2 = q[2]
			st.set_normal((eixo_z * nrm.x + Vector3.UP * nrm.y).normalized())
			st.set_uv(Vector2(float(q[0]) * 0.1, x * 0.1))
			st.set_uv2(Vector2(0.0, 30.0))
			st.add_vertex(c + eixo_x * x + eixo_z * float(q[0]) + Vector3.UP * float(q[1]))
	# Fundo da caverna: fecha no último anel
	var centro_fundo := -1
	if teto:
		st.set_normal(-eixo_x)
		st.set_uv(Vector2.ZERO)
		st.set_uv2(Vector2(0.0, 30.0))
		st.add_vertex(c + eixo_x * (x_b + 0.6) + Vector3.UP * alto * 0.12)
		centro_fundo = (n_est + 1) * n_anel
	# As duas ordens de cada triângulo: a rocha aparece de dentro e de fora, com a normal que demos
	for e in n_est:
		for k in n_anel:
			var k2 := (k + 1) % n_anel
			if not teto and k2 == 0:
				continue
			var v0 := e * n_anel + k
			var v1 := e * n_anel + k2
			var v2 := v0 + n_anel
			var v3 := v1 + n_anel
			for tri: Array in [[v0, v2, v1], [v1, v2, v3], [v0, v1, v2], [v1, v3, v2]]:
				for v: int in tri:
					st.add_index(v)
	if centro_fundo >= 0:
		for k in n_anel:
			var v0 := n_est * n_anel + k
			var v1 := n_est * n_anel + (k + 1) % n_anel
			for v: int in [v0, v1, centro_fundo, v1, v0, centro_fundo]:
				st.add_index(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _rocha
	no.add_child(mi)


## item = [trecho, m, fase, lado do covil (+1 = direita)]
func _montar_mordida(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var periodo := float(cfg.get("periodo", 6.5))
	var lado := float(item[3]) if item.size() > 3 else 1.0
	var c := sub.amostra(i)
	var b := _base(i)
	var lat := sub.lateral_em(i)
	var meia := sub.largura_em(i) * 0.5
	var no := _no("Mordida")
	var comp := float(cfg.get("comprimento", 24.0))   # com 13 m a cabeça era menor que o carro, que ficava em cima dela
	# Covil: caverna atrás do buraco na parede (o túnel deixa a abertura), com brasas no chão
	var fundo := meia + 9.0 + comp + 2.0
	var meia_z := 7.0
	var alto := maxf(10.0, comp * 0.5)
	# Laje de rocha bruta da estrada até a parede e a caverna torta parede adentro
	var boca_x := meia + 3.6
	_caverna(no, c, lat * lado, b.z, meia - 0.6, boca_x + 1.0, meia_z * 0.95, alto, false, 311 + i)
	_caverna(no, c, lat * lado, b.z, boca_x - 1.4, fundo + 2.0, meia_z * 1.15, alto, true, 517 + i)
	# Paredão de rocha em volta da boca (pedido do dono: as pedras ficavam suspensas): vai do rio de lava ao
	# teto e pega a lateral toda, emendando na parede do túnel; incha em volta da abertura
	var meia_t := 9.0
	var topo_t := 13.0
	if is_inside_tree():
		for no_t in get_tree().get_nodes_in_group("tunel_vulcao"):
			var sec: Array = (no_t as TunelVulcao).secao_em(c)
			if not sec.is_empty():
				meia_t = float(sec[0])
				topo_t = float(sec[1])
	var w_boca := meia_z * 1.15
	var meia_f := meia_z * 3.4
	var ruido_f := FastNoiseLite.new()
	ruido_f.seed = 733 + i
	ruido_f.frequency = 0.11
	ruido_f.fractal_octaves = 3
	# x (para o lado do covil) do paredão no ponto (z ao longo da estrada, y acima dela)
	var ruido_g := FastNoiseLite.new()
	ruido_g.seed = 739 + i
	ruido_g.frequency = 0.035
	var x_parede := func(z: float, y: float) -> float:
		var u := clampf((y - 4.0) / (topo_t - 4.0), 0.0, 0.93)
		var x_t := meia_t * sqrt(1.0 - u * u)
		var e := sqrt(pow(z / w_boca, 2.0) + pow((y + 0.4) / alto, 2.0))
		# Lábio de rocha em volta da abertura: mais grosso em uns pontos que em outros (não é um aro)
		var em_volta := atan2(y + 0.4, z)
		var labio := (2.2 + 2.2 * (ruido_g.get_noise_2d(cos(em_volta) * 40.0, sin(em_volta) * 40.0) * 0.5 + 0.5)) * exp(-absf(e - 1.0) * minf(w_boca, alto) / 4.0)
		# Blocos grandes, saliências e degraus de estrato (a rocha quebra em camadas)
		var blocos := 1.6 * (ruido_g.get_noise_2d(z * 1.3 + 90.0, y * 2.2) * 0.5 + 0.5)
		var fino := 0.9 * absf(ruido_f.get_noise_2d(z * 2.0, y * 2.0))
		var estrato := 0.45 * absf(fposmod(y * 0.42 + ruido_g.get_noise_2d(z, 5.0) * 1.5, 1.0) - 0.5)
		var x := x_t - 0.4 - labio - blocos - fino - estrato
		return maxf(lerpf(x, x_t + 2.5, smoothstep(0.7, 1.0, absf(z) / meia_f)), meia + 1.3)
	const NZ := 84
	const NY := 40
	var y_a := -7.0
	var y_b := topo_t * 0.97
	var pts := PackedVector3Array()
	for jy in NY + 1:
		for iz in NZ + 1:
			var z := lerpf(-meia_f, meia_f, float(iz) / NZ)
			var y := lerpf(y_a, y_b, float(jy) / NY)
			pts.append(c + lat * lado * float(x_parede.call(z, y)) + b.z * z + Vector3.UP * y)
	var st_f := SurfaceTool.new()
	st_f.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vw := NZ + 1
	for jy in NY + 1:
		for iz in vw:
			var e1: Vector3 = pts[jy * vw + mini(iz + 1, NZ)] - pts[jy * vw + maxi(iz - 1, 0)]
			var e2: Vector3 = pts[mini(jy + 1, NY) * vw + iz] - pts[maxi(jy - 1, 0) * vw + iz]
			var nrm := e1.cross(e2).normalized()
			st_f.set_normal(nrm if nrm.dot(lat * lado) < 0.0 else -nrm)
			st_f.set_uv(Vector2(iz, jy) * 0.3)
			st_f.set_uv2(Vector2(0.0, maxf(lerpf(y_a, y_b, float(jy) / NY) + 4.6, 0.05)))
			st_f.add_vertex(pts[jy * vw + iz])
	for jy in NY:
		for iz in NZ:
			var zc := lerpf(-meia_f, meia_f, (iz + 0.5) / NZ)
			var yc := lerpf(y_a, y_b, (jy + 0.5) / NY)
			if yc > -0.4 and pow(zc / (w_boca * 0.9), 2.0) + pow((yc + 0.4) / (alto * 0.9), 2.0) < 1.0:
				continue   # a abertura da caverna
			var v0 := jy * vw + iz
			for v: int in [v0, v0 + vw, v0 + 1, v0 + 1, v0 + vw, v0 + vw + 1, v0, v0 + 1, v0 + vw, v0 + 1, v0 + vw + 1, v0 + vw]:
				st_f.add_index(v)
	var mi_f := MeshInstance3D.new()
	mi_f.mesh = st_f.commit()
	mi_f.material_override = _rocha
	no.add_child(mi_f)
	var brasas := OmniLight3D.new()
	brasas.light_color = Color(1.0, 0.4, 0.12)
	brasas.light_energy = 2.5
	brasas.omni_range = 18.0
	brasas.position = c + lat * lado * (fundo - 4.0) + Vector3.UP * 2.0
	no.add_child(brasas)
	var lampadas: Array = []
	for s: float in [-1.0, 1.0]:
		lampadas.append(_lampada(no, c + lat * lado * (float(x_parede.call(s * (w_boca + 3.0), 5.0)) - 0.35) + b.z * s * (w_boca + 3.0) + Vector3.UP * 5.0, 0.5))
	var d := DinosParque.criar("tiranossauro", comp)
	var corpo := _corpo_mortal(no, true)
	corpo.add_child(d.raiz)
	# Só o corpo tem colisão mortal; a cabeça PEGA o carro (ver _animar_mordida): fica 3 s com ele na boca,
	# um carro por bote, e depois ele explode e volta ao checkpoint (pedido do dono)
	_forma_caixa(corpo, Vector3(3.0, float(d.get("altura", 5.0)) * 0.8, comp * 0.35), Transform3D(Basis.IDENTITY, Vector3(0, float(d.get("altura", 5.0)) * 0.45, 0.0)))
	_portoes.append({"tipo": "mordida", "i": i, "s": sub.progresso_amostra(i), "comp": 4.0, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": periodo, "bote": float(cfg.get("bote_s", 0.5)), "fechada": float(cfg.get("fechada_s", 0.9)), "volta": float(cfg.get("volta_s", 1.4)),
		"c": c, "lat": lat, "lado": lado, "meia": meia, "comp_t": comp, "bicho": d, "corpo": corpo, "lampadas": lampadas, "total": true,
		"recuo": meia + 9.0 + comp * 0.5, "avanco": meia - 0.5 - comp * 0.5, "tan": -b.z, "presa": null, "presa_t": 0.0, "atraso": 0.0,
		"segura": float(cfg.get("segura_s", 3.0)), "alt": float(d.get("altura", 5.0)), "presa_de": c,
		"boca_y": float(cfg.get("boca_y", -comp * BOCA_Y)), "boca_z": float(cfg.get("boca_z", comp * BOCA_Z))})
	if OS.get_environment("TSC_BOCA_TESTE") != "":
		# Conferência: bola verde onde o carro fica preso e o bicho parado no bote
		var marca := MeshInstance3D.new()
		var bola := BoxMesh.new()
		bola.size = Vector3(2.1, 2.1, 4.6)
		marca.mesh = bola
		marca.material_override = _brilho(Color(0.2, 1.0, 0.2), 3.0)
		no.add_child(marca)
		_portoes[-1]["marca"] = marca
		var luz_t := OmniLight3D.new()
		luz_t.light_energy = 5.0
		luz_t.omni_range = 60.0
		luz_t.position = c - lat * lado * 3.0 + Vector3.UP * 7.0
		no.add_child(luz_t)
		print("[BOCA] mordida em %s lat %s lado %.0f tan %s" % [str(c), str(lat), lado, str(-b.z)])


## Distância (lateral, do lado do covil) do meio do T-Rex ao eixo da estrada, e a boca (0..1).
func _trex(g: Dictionary, t: float) -> Array:
	var f := fposmod(t + float(g.fase), float(g.periodo))
	var bote: float = g.bote
	var fechada: float = g.fechada
	var volta: float = g.volta
	var recuo: float = g.recuo
	var avanco: float = -float(g.avanco)   # quanto a cabeça passa do eixo para o outro lado
	var x := recuo
	var boca := 0.15
	var prep := smoothstep(float(g.periodo) - 1.0, float(g.periodo), f)
	if f < bote:
		var u := f / bote
		x = lerpf(recuo, -avanco + float(g.comp_t) * 0.5 - float(g.meia) * 0.0, u * u * (3.0 - 2.0 * u))
		x = lerpf(recuo, float(g.comp_t) * 0.5 - float(g.meia) + 0.5, u * u * (3.0 - 2.0 * u))
		boca = 1.0
		prep = 1.0
	elif f < bote + fechada:
		x = float(g.comp_t) * 0.5 - float(g.meia) + 0.5
		boca = maxf(0.0, 1.0 - (f - bote) / 0.15)
		prep = 1.0
	elif f < bote + fechada + volta:
		var u := (f - bote - fechada) / volta
		x = lerpf(float(g.comp_t) * 0.5 - float(g.meia) + 0.5, recuo, u * u * (3.0 - 2.0 * u))
		boca = 0.1
		prep = 1.0 - u
	else:
		boca = 0.15 + prep * 0.85
	return [x, boca, prep]


func _perigo_mordida(g: Dictionary, t: float) -> bool:
	if g.get("presa") != null:
		return false   # de boca cheia: quem vem atrás passa
	var r := _trex(g, t - float(g.get("atraso", 0.0)))
	# Ponta do focinho a comp/2 do meio, na direção da estrada
	return float(r[0]) - float(g.comp_t) * 0.5 < float(g.meia) + 1.5


## Corpo do bicho em `p`, inclinado/sacudido por `giro` EM VOLTA DOS PÉS. Girando em volta da origem (o meio do
## corpo, uns 2 m atrás dos pés) eles saíam do chão quando ele levantava a cabeça com o carro na boca.
func _inclinado(base: Basis, p: Vector3, bicho: Dictionary, giro: Basis) -> Transform3D:
	var pes := Vector3(0.0, 0.0, float(bicho.get("pes_z", 0.0)))
	return Transform3D(base, p) * Transform3D(giro, pes - giro * pes)


## Meio da boca a partir da dobradiça da mandíbula, em fração do comprimento: para baixo e para a frente.
## (Eram 0,1 e 0,085 com o bicho andando 13° de focinho para baixo: nivelado, com isso o carro ficava na frente
## do focinho, fora da boca — reclamação do dono. Conferir com TSC_BOCA_TESTE=1: caixa verde do tamanho do carro.)
const BOCA_Y := 0.045
const BOCA_Z := 0.058

## Boca do T-Rex: [meio da boca (entre as mandíbulas), base do corpo girada junto com a cabeça]. O ponto é
## marcado uma vez com o bicho de cabeça neutra (à frente e abaixo da dobradiça da mandíbula, na POSE — o
## descanso do esqueleto deste modelo não bate com a pose) e guardado no referencial do osso da cabeça:
## daí em diante acompanha a cabeça quando ela levanta, baixa ou sacode. Sem esqueleto ou antes de
## marcar: [`reserva`, base do corpo].
func _boca_trex(g: Dictionary, xf: Transform3D, reserva: Vector3, marcar := false) -> Array:
	var bicho: Dictionary = g.bicho
	var esq := bicho.get("esq") as Skeleton3D
	var cab := int(bicho.cabeca)
	if esq == null or cab < 0:
		return [reserva, xf.basis]
	var pose := esq.global_transform * esq.get_bone_global_pose(cab)
	if marcar and not g.has("boca_local"):
		var dob := int(bicho.mandibula) if int(bicho.mandibula) >= 0 else cab
		# Frente e cima pelo nó do próprio bicho (no primeiro quadro ele ainda não está virado como o corpo)
		var base_b := (bicho.raiz as Node3D).global_transform.basis.orthonormalized()
		var boca_m := esq.global_transform * esq.get_bone_global_pose(dob).origin + base_b * Vector3(0.0, float(g.boca_y), -float(g.boca_z))
		g.boca_local = pose.affine_inverse() * boca_m
		g.boca_base = pose.basis.orthonormalized().inverse() * base_b
	if not g.has("boca_local"):
		return [reserva, xf.basis]
	return [pose * (g.boca_local as Vector3), pose.basis.orthonormalized() * (g.boca_base as Basis)]


func _animar_mordida(g: Dictionary) -> void:
	var dt := get_physics_process_delta_time()
	var presa: Veiculo = g.presa
	if presa != null and (not is_instance_valid(presa) or presa.eliminado or not presa.preso):
		presa = null
		g.presa = null
	if presa != null:
		g.atraso = float(g.atraso) + dt   # o relógio do bote para enquanto ele segura o carro
		g.presa_t = float(g.presa_t) + dt
	var tl := _t - float(g.atraso)
	if g.has("marca"):
		tl = float(g.bote) + 0.4 - float(g.fase)   # TSC_BOCA_TESTE: parado no fim do bote, de boca fechada
	var r := _trex(g, tl)
	var lat: Vector3 = g.lat
	var lado: float = g.lado
	var frente := -lat * lado
	var p: Vector3 = (g.c as Vector3) + lat * lado * float(r[0])
	# O corpo mergulha no bote (tronco inclinado para a frente) e levanta com a presa na boca
	var u_seg := clampf(float(g.presa_t) / 0.5, 0.0, 1.0) if presa != null else (1.0 if g.has("marca") else 0.0)
	var inclina := -0.3 * float(r[2]) * (1.0 - u_seg) + 0.22 * u_seg
	var sacode := sin(_t * 17.0) * 0.16 * u_seg
	var xf := _inclinado(Basis.looking_at(frente, Vector3.UP), p, g.bicho, Basis(Vector3.UP, sacode) * Basis(Vector3.RIGHT, inclina))
	(g.corpo as AnimatableBody3D).global_transform = xf
	# Passada presa ao chão (os pés não patinam mais), boca e pescoço pelo bote
	var boca := 1.55 + 0.08 * sin(_t * 20.0) if presa != null or g.has("marca") else float(r[1])
	DinosParque.andar(g.bicho, Transform3D(Basis.looking_at(frente, Vector3.UP), p), dt, 1.6, boca, float(r[2]) * (1.0 - u_seg))
	if not g.has("boca_local") and float(r[2]) * (1.0 - u_seg) < 0.05:
		_boca_trex(g, xf, p, true)   # cabeça neutra: marca o ponto da boca no osso
	var comp: float = g.comp_t
	var alt: float = g.alt
	var f_ciclo := fposmod(tl + float(g.fase), float(g.periodo))
	if presa == null and f_ciclo > float(g.bote) * 0.55 and f_ciclo < float(g.bote) + 0.2:
		# Bote: pega UM carro (o mais perto do focinho) que esteja na frente da boca
		var focinho := p + frente * (comp * 0.5 - 1.0)
		var melhor: Veiculo = null
		var melhor_d := INF
		for no_v in get_tree().get_nodes_in_group("veiculo"):
			var v := no_v as Veiculo
			if v == null or v.eliminado or v.fantasma() or v.preso or v.travado:
				continue
			var q: Vector3 = v.global_position - (g.c as Vector3)
			if absf(q.dot(g.tan)) > 3.4 or absf(q.y) > 3.5 or absf(q.dot(lat)) > float(g.meia) + 1.0:
				continue
			var dist := v.global_position.distance_to(focinho)
			if dist < melhor_d and dist < 7.5:
				melhor_d = dist
				melhor = v
		if melhor:
			melhor.agarrar()
			g.presa = melhor
			g.presa_t = 0.0
			g.presa_de = melhor.global_position
			presa = melhor
	if presa != null:
		# O carro vai na boca: preso ao osso da mandíbula (acompanha o bote, o tronco e o chacoalhão);
		# nos primeiros 0,15 s vai de onde foi pego até os dentes
		var bt := _boca_trex(g, xf, p + xf.basis * Vector3(0.0, alt * lerpf(0.34, 0.78, u_seg), -(comp * 0.5 - 1.6)))
		var boca_p := (g.presa_de as Vector3).lerp(bt[0], clampf(float(g.presa_t) / 0.15, 0.0, 1.0))
		# Atravessado na boca, girando junto com a cabeça
		presa.global_transform = Transform3D((bt[1] as Basis) * Basis(Vector3.UP, PI * 0.5), boca_p)
		presa.reset_physics_interpolation()
		if float(g.presa_t) >= float(g.segura):
			presa.devorar()
			g.presa = null
			g.presa_t = 0.0
	if g.has("marca"):
		var bt_m := _boca_trex(g, xf, p)
		(g.marca as Node3D).global_transform = Transform3D((bt_m[1] as Basis) * Basis(Vector3.UP, PI * 0.5), (bt_m[0] as Vector3) + (bt_m[1] as Basis).y * 1.05)
	var perigo := _perigo_mordida(g, _t + 1.0) or _perigo_mordida(g, _t)
	for m: StandardMaterial3D in g.lampadas:
		m.emission = Color(1.0, 0.08, 0.04) if perigo else Color(0.25, 1.0, 0.35)


# ------------------------------------------------------------------ rochas caindo

## Rocha solta irregular (cabe numa esfera de raio ~1): esfera amassada por ruído em três escalas, com
## uma base mais chata. Cinco variações, guardadas.
static var _pedras_malha: Array[ArrayMesh] = []
static var _pedra_mat: ShaderMaterial


static func malha_pedra(k: int) -> ArrayMesh:
	if _pedras_malha.is_empty():
		for v in 5:
			var esf := SphereMesh.new()
			esf.radius = 1.0
			esf.height = 2.0
			esf.radial_segments = 28
			esf.rings = 14
			var arr := esf.get_mesh_arrays()
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var ruido := FastNoiseLite.new()
			ruido.seed = 700 + v * 31
			ruido.frequency = 0.55
			ruido.fractal_octaves = 4
			var rng := RandomNumberGenerator.new()
			rng.seed = 40 + v
			var achata := Vector3(rng.randf_range(0.8, 1.15), rng.randf_range(0.6, 0.85), rng.randf_range(0.8, 1.2))
			var corte := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.6), rng.randf_range(-1, 1)).normalized()
			for q in vs.size():
				var d := vs[q].normalized()
				var r := 1.0 + 0.42 * ruido.get_noise_3dv(d * 1.6) + 0.12 * ruido.get_noise_3dv(d * 5.0 + Vector3.ONE * 9.0)
				var p := d * r
				# Uma face lascada (plano de quebra) e a base assentada
				var fora := p.dot(corte) - 0.62
				if fora > 0.0:
					p -= corte * fora * 0.85
				if p.y < -0.55:
					p.y = lerpf(p.y, -0.55, 0.7)
				vs[q] = p * achata
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_smooth_group(0)
			for q in idx:
				st.add_vertex(vs[q])
			st.index()
			st.generate_normals()
			_pedras_malha.append(st.commit())
	return _pedras_malha[k % _pedras_malha.size()]


static func material_pedra_solta() -> ShaderMaterial:
	if _pedra_mat == null or not is_instance_valid(_pedra_mat):
		_pedra_mat = ShaderMaterial.new()
		_pedra_mat.shader = load("res://shaders/pedra_caida.gdshader")
		_pedra_mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 331))
		_pedra_mat.set_shader_parameter("ruido_fino", Terreno._textura_ruido(0.08, 4, 337))
	return _pedra_mat


## Pórtico em ruína de onde as pedras caem (pedido do dono, pela arte de referência em
## assets/DINOSSAUROS/extruturas — tudo em geometria, nada de imagem): dois pilares de blocos de pedra
## que afinam para cima, com pedregulhos no pé; lintel de pedra maciço em balanço, preso por duas cintas
## de ferro rebitadas; forro de pranchas de madeira por baixo dele (o alçapão de onde as pedras se
## soltam), com longarinas de ferro; em cada face dos pilares uma viga de madeira presa por três
## ferragens com rebites e uma tocha de ferro acesa; musgo na pedra e cipós com folhas escorrendo do
## lintel e dos pilares. Pilares até o chão por baixo.
## Estática (o alvo-ninho da etapa 2 usa o mesmo pórtico): devolve as caixas de colisão [pilar, pilar, lintel].
static func portico_ruina(no: Node3D, c: Vector3, b: Basis, meia: float, alto: float, comp: float, semente: int, terreno: Terreno) -> Array[Transform3D]:
	var lat := b.x
	var cima := b.y
	var rng := RandomNumberGenerator.new()
	rng.seed = 8100 + semente
	var ruido := Terreno._textura_ruido(0.05, 4, 71)
	var pedra_m := ShaderMaterial.new()
	pedra_m.shader = load("res://shaders/muro_pedra.gdshader")
	pedra_m.set_shader_parameter("ruido", ruido)
	pedra_m.set_shader_parameter("cor_pedra", Color(0.33, 0.31, 0.26))
	pedra_m.set_shader_parameter("cor_argamassa", Color(0.09, 0.09, 0.07))
	pedra_m.set_shader_parameter("fiada", 2.3)
	pedra_m.set_shader_parameter("altura_chao", c.y - 60.0)
	pedra_m.set_shader_parameter("musgo", 0.5)
	pedra_m.set_shader_parameter("rachaduras", 1.0)
	var ferro_m := ShaderMaterial.new()
	ferro_m.shader = load("res://shaders/metal_gasto.gdshader")
	ferro_m.set_shader_parameter("ruido", Terreno._textura_ruido(0.03, 4, 61))
	ferro_m.set_shader_parameter("ferrugem", 0.8)
	ferro_m.set_shader_parameter("cor_tinta", Color(0.13, 0.11, 0.1))
	ferro_m.set_shader_parameter("cor_ferrugem", Color(0.24, 0.11, 0.05))
	ferro_m.set_shader_parameter("cor_ferrugem_clara", Color(0.42, 0.22, 0.1))
	ferro_m.set_shader_parameter("cor_poeira", Color(0.25, 0.2, 0.15))
	ferro_m.set_shader_parameter("altura_chao", c.y - 60.0)
	var madeira_v := ShaderMaterial.new()
	madeira_v.shader = load("res://shaders/madeira_via.gdshader")
	madeira_v.set_shader_parameter("ruido", ruido)
	madeira_v.set_shader_parameter("eixo_veio", Vector3(0.06, 1.0, 0.0).normalized())   # (exatamente para cima o shader divide por zero)
	var madeira_h: ShaderMaterial = madeira_v.duplicate()
	madeira_h.set_shader_parameter("eixo_veio", lat)
	var verde := StandardMaterial3D.new()
	verde.albedo_color = Color(0.1, 0.24, 0.07)
	verde.roughness = 0.8
	verde.backlight_enabled = true
	verde.backlight = Color(0.12, 0.2, 0.05)
	var verde_talo := StandardMaterial3D.new()
	verde_talo.albedo_color = Color(0.13, 0.11, 0.06)
	verde_talo.roughness = 0.95
	var rebite := SphereMesh.new()
	rebite.radius = 0.5
	rebite.height = 0.6
	rebite.radial_segments = 8
	rebite.rings = 4
	var cesto := CylinderMesh.new()
	cesto.top_radius = 0.5
	cesto.bottom_radius = 0.2
	cesto.height = 1.0
	cesto.radial_segments = 6
	cesto.rings = 1
	var pedra: Array[Transform3D] = []
	var colunas: Array[Transform3D] = []
	var ferro: Array[Transform3D] = []
	var rebites: Array[Transform3D] = []
	var cestos: Array[Transform3D] = []
	var vigas: Array[Transform3D] = []
	var pranchas: Array[Transform3D] = []
	var talos: Array[Transform3D] = []
	var folhas: Array[Transform3D] = []
	var pedregulhos: Array = [[], [], []]
	var colisao: Array[Transform3D] = []
	const FIADAS := 7
	var alt_pilar := alto + 1.2
	var w0 := 5.4            # largura do pilar no pé e no alto (para o lado)
	var w1 := 3.9
	var d0 := comp + 2.4     # e ao longo da estrada
	var d1 := comp + 0.8
	var dentro := meia + 1.0  # face de dentro do pilar
	var cipo := func(topo: Vector3, comp_c: float) -> void:
		# Talo torto em três lances e folhas em volta dele
		var p0 := topo
		for lance in 3:
			var p1 := p0 + Vector3.DOWN * comp_c / 3.0 + Vector3(rng.randf_range(-0.18, 0.18), 0.0, rng.randf_range(-0.18, 0.18))
			talos.append(ComplexoLancamento._viga(p0, p1, 0.07))
			p0 = p1
		for q in int(comp_c * 3.5) + 2:
			var giro := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.8, 0.8))
			folhas.append(Transform3D(giro * Basis.from_scale(Vector3(rng.randf_range(0.3, 0.62), 0.03, rng.randf_range(0.22, 0.4))), topo + Vector3.DOWN * rng.randf_range(0.0, comp_c) + Vector3(rng.randf_range(-0.22, 0.22), 0.0, rng.randf_range(-0.22, 0.22))))
	for s: float in [-1.0, 1.0]:
		# Pilar: fiadas de blocos cada vez menores, levemente desalinhadas
		var y1 := -0.8
		var h := (alt_pilar + 0.8) / FIADAS
		for k in FIADAS:
			var u := float(k) / (FIADAS - 1)
			var w := lerpf(w0, w1, u) + rng.randf_range(-0.12, 0.12)
			var d := lerpf(d0, d1, u) + rng.randf_range(-0.12, 0.12)
			pedra.append(Transform3D(b * Basis(Vector3.UP, rng.randf_range(-0.02, 0.02)) * Basis.from_scale(Vector3(w, h + 0.03, d)), c + lat * s * (dentro + w * 0.5) + cima * (y1 + h * 0.5)))
			y1 += h
		colisao.append(Transform3D(b * Basis.from_scale(Vector3((w0 + w1) * 0.5, alt_pilar + 0.8, d0)), c + lat * s * (dentro + (w0 + w1) * 0.25) + cima * (alt_pilar * 0.5 - 0.4)))
		var pe := c + lat * s * (dentro + w0 * 0.5) - cima * 0.8
		var chao_pe := (terreno.altura_em(pe.x, pe.z) if terreno else pe.y) - 1.0
		if pe.y - chao_pe > 0.5:
			colunas.append(Transform3D(b * Basis.from_scale(Vector3(w0 + 0.4, pe.y - chao_pe, d0 + 0.4)), Vector3(pe.x, (pe.y + chao_pe) * 0.5, pe.z)))
		# Pedregulhos encostados no pé (em cima de uma soleira de pedra que sai do pilar)
		pedra.append(Transform3D(b * Basis.from_scale(Vector3(w0 + 2.6, 1.0, d0 + 2.6)), c + lat * s * (dentro + w0 * 0.5 + 0.6) - cima * 0.5))
		for face: float in [-1.0, 1.0]:
			for q in 3:
				var tam := rng.randf_range(0.9, 1.7)
				var pp := c + lat * s * (dentro + rng.randf_range(0.6, w0 + 0.6)) + b.z * face * (d0 * 0.5 + rng.randf_range(0.2, 0.9)) + cima * (tam * 0.45)
				(pedregulhos[q % 3] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * tam), pp))
		for face: float in [-1.0, 1.0]:
			# Viga de madeira em pé na face, acompanhando a inclinação do pilar, com três ferragens rebitadas
			var x_v := dentro + 1.15
			var pe_v := c + lat * s * x_v + b.z * face * (d0 * 0.5 + 0.2) + cima * 0.4
			var topo_v := c + lat * s * x_v + b.z * face * (d1 * 0.5 + 0.2) + cima * (alt_pilar - 0.3)
			vigas.append(ComplexoLancamento._viga(pe_v, topo_v, 0.62))
			for fy: float in [0.2, 0.52, 0.84]:
				var pf := pe_v.lerp(topo_v, fy)
				ferro.append(Transform3D(b * Basis.from_scale(Vector3(1.25, 0.95, 0.5)), pf + b.z * face * 0.2))
				for dx: float in [-0.38, 0.38]:
					rebites.append(Transform3D(b * Basis.from_scale(Vector3(0.24, 0.24, 0.24)), pf + lat * dx + b.z * face * 0.47))
			# Tocha: braço de ferro saindo da pedra, cesto de ferro de seis faces e o fogo
			var pt := pe_v.lerp(topo_v, 0.64) + lat * s * 1.55 + b.z * face * 0.75
			ferro.append(Transform3D(b * Basis.from_scale(Vector3(0.22, 0.22, 1.1)), pt - b.z * face * 0.5 - cima * 0.45))
			ferro.append(Transform3D(b * Basis(Vector3.RIGHT, face * 0.6) * Basis.from_scale(Vector3(0.16, 0.16, 1.0)), pt - b.z * face * 0.45 - cima * 0.85))
			cestos.append(Transform3D(b * Basis.from_scale(Vector3(1.5, 1.3, 1.5)), pt))
			for q in 6:
				var aq := TAU * q / 6.0
				ferro.append(Transform3D(b * Basis(Vector3.UP, aq) * Basis.from_scale(Vector3(0.1, 0.5, 0.1)), pt + b * Vector3(cos(aq) * 0.72, 0.85, sin(aq) * 0.72)))
			Fogo.criar(no, pt + cima * 0.7, 0.35, 1.7, 18, 0.85, false)
			if face < 0.0:
				var luz := OmniLight3D.new()
				luz.light_color = Color(1.0, 0.55, 0.2)
				luz.light_energy = 2.2
				luz.omni_range = 16.0
				luz.shadow_enabled = false
				luz.position = pt + cima * 1.2 + b.z * face * 0.6
				no.add_child(luz)
			# Cipós descendo pela face do pilar
			for q in 7:
				var u := rng.randf_range(0.35, 1.0)
				cipo.call(c + lat * s * (dentro + rng.randf_range(0.3, lerpf(w0, w1, u) - 0.2)) + cima * (alt_pilar * u) + b.z * face * (lerpf(d0, d1, u) * 0.5 + 0.14), rng.randf_range(2.0, 6.5))
		# ... e pela face de fora
		for q in 6:
			var u := rng.randf_range(0.4, 1.0)
			cipo.call(c + lat * s * (dentro + lerpf(w0, w1, u) + 0.14) + cima * (alt_pilar * u) + b.z * rng.randf_range(-d1 * 0.45, d1 * 0.45), rng.randf_range(2.0, 6.0))
	# Lintel: bloco maciço em balanço sobre os pilares, com uma capa um pouco menor em cima (pedra rachada)
	var larg_l := (dentro + w1) * 2.0 + 3.0
	var prof_l := d1 + 2.6
	var y_l := alt_pilar + 1.9
	var lintel := Transform3D(b * Basis.from_scale(Vector3(larg_l, 3.8, prof_l)), c + cima * y_l)
	pedra.append(lintel)
	colisao.append(lintel)
	pedra.append(Transform3D(b * Basis(Vector3.UP, 0.015) * Basis.from_scale(Vector3(larg_l - 2.2, 0.9, prof_l - 1.6)), c + cima * (y_l + 2.3)))
	# Duas cintas de ferro abraçando o lintel, com rebites na frente e atrás
	for s: float in [-1.0, 1.0]:
		var x_c := dentro + w1 * 0.5
		ferro.append(Transform3D(b * Basis.from_scale(Vector3(1.0, 4.1, prof_l + 0.3)), c + lat * s * x_c + cima * y_l))
		for face: float in [-1.0, 1.0]:
			for dy: float in [-1.3, -0.45, 0.45, 1.3]:
				rebites.append(Transform3D(b * Basis.from_scale(Vector3(0.32, 0.32, 0.32)), c + lat * s * x_c + cima * (y_l + dy) + b.z * face * (prof_l * 0.5 + 0.17)))
	# Forro de pranchas por baixo do lintel, entre os pilares, com longarinas de ferro nas bordas
	var vao := dentro * 2.0 + 0.6
	var n_p := int(prof_l / 1.15)
	for k in n_p:
		var z := lerpf(-prof_l * 0.5 + 0.6, prof_l * 0.5 - 0.6, float(k) / (n_p - 1))
		pranchas.append(Transform3D(b * Basis(Vector3.UP, rng.randf_range(-0.01, 0.01)) * Basis.from_scale(Vector3(vao, 0.3, 1.05)), c + cima * (alt_pilar - 0.2 + rng.randf_range(-0.03, 0.03)) + b.z * z))
	for face: float in [-1.0, 1.0]:
		ferro.append(Transform3D(b * Basis.from_scale(Vector3(vao + 0.4, 0.5, 0.5)), c + cima * (alt_pilar - 0.25) + b.z * face * (prof_l * 0.5 - 0.1)))
		for k in 6:
			rebites.append(Transform3D(b * Basis.from_scale(Vector3(0.22, 0.22, 0.22)), c + lat * lerpf(-vao * 0.45, vao * 0.45, k / 5.0) + cima * (alt_pilar - 0.25) + b.z * face * (prof_l * 0.5 + 0.17)))
		# Cipós pendurados da beirada do lintel (longe do meio: não tapam a visão da pista) e moitas em cima
		for q in 12:
			var x := rng.randf_range(meia * 0.55, larg_l * 0.5 - 0.3) * (1.0 if q % 2 == 0 else -1.0)
			cipo.call(c + lat * x + cima * (y_l + rng.randf_range(-1.6, 1.9)) + b.z * face * (prof_l * 0.5 + 0.12), rng.randf_range(1.5, 6.0))
	for q in 40:
		var giro := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-1.0, 1.0))
		folhas.append(Transform3D(giro * Basis.from_scale(Vector3(rng.randf_range(0.4, 0.8), 0.03, rng.randf_range(0.3, 0.5))), c + lat * rng.randf_range(-larg_l * 0.48, larg_l * 0.48) + cima * (y_l + 2.9 + rng.randf_range(0.0, 0.35)) + b.z * rng.randf_range(-prof_l * 0.42, prof_l * 0.42)))
	ComplexoLancamento.criar_multimesh(no, pedra, pedra_m)
	ComplexoLancamento.criar_multimesh(no, colunas, pedra_m)
	ComplexoLancamento.criar_multimesh(no, ferro, ferro_m)
	ComplexoLancamento.criar_multimesh(no, vigas, madeira_v)
	ComplexoLancamento.criar_multimesh(no, pranchas, madeira_h)
	ComplexoLancamento.criar_multimesh(no, talos, verde_talo, false)
	ComplexoLancamento.criar_multimesh(no, folhas, verde, false)
	Gelo._instancias(no, rebite, rebites, ferro_m)
	Gelo._instancias(no, cesto, cestos, ferro_m)
	for q in 3:
		var lista: Array[Transform3D] = []
		lista.assign(pedregulhos[q])
		Gelo._instancias(no, malha_pedra(q + 1), lista, material_pedra_solta())
	return colisao



## item = [trecho, m, fase, no túnel (bool)]
func _montar_rochas(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var periodo := float(cfg.get("periodo", 5.2))
	var comp := float(cfg.get("comprimento", 10.0))
	var tunel := bool(item[3]) if item.size() > 3 else false
	var alto := float(cfg.get("altura", 11.0 if tunel else 16.0))
	var i_meio := sub.indice_adiante(i, comp * 0.5)
	var c := sub.amostra(i_meio)
	var t := sub.tangente_em(i_meio)
	var lat := sub.lateral_em(i_meio)
	var nrm := lat.cross(t).normalized()
	var b := Basis(lat, nrm, -t)
	var meia := sub.largura_em(i_meio) * 0.5
	var no := _no("Rochas")
	if not tunel:
		ComplexoLancamento.adicionar_colisoes(_corpo_mortal(no), portico_ruina(no, c, b, meia, alto, comp, i, _terreno).slice(0, 2))
	var corpos := []
	var avisos := []
	var poeiras := []
	var pedrinhas := []
	var rng := RandomNumberGenerator.new()
	rng.seed = i
	for lado in 2:
		var s := -1.0 if lado == 0 else 1.0
		var corpo := _corpo_mortal(no, true)
		var largura := meia - 0.5
		_forma_caixa(corpo, Vector3(largura, 2.2, comp - 1.0), Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 0)))
		# Rochas irregulares (eram caixas): cinco ou seis grandes e um monte de cascalho entre elas
		var grandes: Array = [[], [], []]
		for k in 6:
			var tam := rng.randf_range(1.05, 1.75)
			var pos := Vector3(rng.randf_range(-largura * 0.32, largura * 0.32), tam * 0.5, lerpf(-comp * 0.36, comp * 0.36, k / 5.0) + rng.randf_range(-0.5, 0.5))
			(grandes[k % 3] as Array).append(Transform3D(Basis(Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized(), rng.randf() * TAU) * Basis.from_scale(Vector3(tam, tam * rng.randf_range(0.8, 1.1), tam)), pos))
		for k in 3:
			var l_g: Array[Transform3D] = []
			l_g.assign(grandes[k])
			_instancias_de(corpo, malha_pedra(k + lado), l_g, material_pedra_solta())
		var cascalho: Array[Transform3D] = []
		for k in 22:
			var tam_c := rng.randf_range(0.25, 0.6)
			cascalho.append(Transform3D(Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * tam_c), Vector3(rng.randf_range(-largura * 0.46, largura * 0.46), tam_c * 0.4, rng.randf_range(-comp * 0.44, comp * 0.44))))
		_instancias_de(corpo, malha_pedra(4), cascalho, material_pedra_solta())
		corpos.append([corpo, s * (meia * 0.5 + 0.1)])
		avisos.append(_aviso(no, c + lat * s * (meia * 0.5), b, Vector2(largura, comp - 1.0), Color(1.0, 0.3, 0.08)))
		var pd := _poeira(no, 2.4)
		pd.position = c + lat * s * (meia * 0.5) + nrm * 1.0
		poeiras.append(pd)
		var pq := _fagulhas(no, Color(0.35, 0.3, 0.28), 1.5, 2.0, 20)
		(pq.process_material as ParticleProcessMaterial).gravity = Vector3(0, -9.8, 0)
		(pq.process_material as ParticleProcessMaterial).direction = Vector3.DOWN
		pq.position = c + lat * s * (meia * 0.5) + nrm * (alto - 1.0)
		pedrinhas.append(pq)
	_portoes.append({"tipo": "rocha", "i": i, "s": sub.progresso_amostra(i), "comp": comp, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": periodo, "cai": float(cfg.get("queda_s", 0.55)), "fica": float(cfg.get("fica_s", 2.2)), "corpos": corpos, "centro": c, "base": b,
		"nrm": nrm, "lat": lat, "alto": alto, "avisos": avisos, "poeiras": poeiras, "pedrinhas": pedrinhas, "caiu": [false, false], "total": false})


## Altura (acima do piso) das pedras de uma faixa no instante t, e se estão visíveis.
func _rocha_y(g: Dictionary, lado: int, t: float) -> Array:
	var per: float = g.periodo
	var f := fposmod(t + float(g.fase) + (per * 0.5 if lado == 1 else 0.0), per)
	var cai: float = g.cai
	var fica: float = g.fica
	if f < cai:
		var u := f / cai
		return [float(g.alto) * (1.0 - u * u), true, f]
	if f < cai + fica:
		return [0.0, true, f]
	if f < cai + fica + 0.6:
		return [-2.6 * (f - cai - fica) / 0.6, true, f]
	return [float(g.alto) + 30.0, false, f]


func _perigo_rocha(g: Dictionary, lado: int, t: float) -> bool:
	var r := _rocha_y(g, lado, t)
	return bool(r[1]) and float(r[0]) < 3.0 and float(r[0]) > -1.8


func _animar_rochas(g: Dictionary) -> void:
	for lado in 2:
		var r := _rocha_y(g, lado, _t)
		var par: Array = g.corpos[lado]
		var corpo: AnimatableBody3D = par[0]
		corpo.visible = bool(r[1])
		var y: float = r[0]
		corpo.global_transform = Transform3D(g.base, (g.centro as Vector3) + (g.lat as Vector3) * float(par[1]) + (g.nrm as Vector3) * y)
		var f: float = r[2]
		var per: float = g.periodo
		# Aviso: acende no último 1,4 s antes de cair e fica aceso enquanto o entulho está na pista
		var aviso := 0.0
		if f > per - 1.4:
			aviso = smoothstep(per - 1.4, per, f) * (0.6 + 0.4 * sin(_t * 18.0))
		elif f < float(g.cai) + float(g.fica):
			aviso = 0.5
		(g.avisos[lado] as StandardMaterial3D).emission_energy_multiplier = aviso * 3.0
		(g.avisos[lado] as StandardMaterial3D).albedo_color.a = aviso
		var pq: GPUParticles3D = g.pedrinhas[lado]
		var cair := f > per - 1.3
		if pq.emitting != cair:
			pq.emitting = cair
		var caiu: bool = f >= float(g.cai) and f < float(g.cai) + 0.2
		if caiu and not g.caiu[lado]:
			(g.poeiras[lado] as GPUParticles3D).restart()
		g.caiu[lado] = caiu


# ------------------------------------------------------------------ gêiseres de lava

## item = [trecho, m, fase]
func _montar_lava(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var periodo := float(cfg.get("periodo", 4.2))
	var c := sub.amostra(i)
	var t := sub.tangente_em(i)
	var lat := sub.lateral_em(i)
	var nrm := lat.cross(t).normalized()
	var b := Basis(lat, nrm, -t)
	var meia := sub.largura_em(i) * 0.5
	var no := _no("Lava")
	var grade_mat := StandardMaterial3D.new()
	grade_mat.albedo_color = Color(0.08, 0.07, 0.07)
	grade_mat.metallic = 0.8
	grade_mat.roughness = 0.5
	grade_mat.emission_enabled = true
	var colunas := []
	var corpos := []
	var luzes := []
	var respingos := []
	var grades := []
	for lado in 2:
		var s := -1.0 if lado == 0 else 1.0
		var pc := c + lat * s * (meia * 0.5)
		var gm := grade_mat.duplicate() as StandardMaterial3D
		_malha(no, _caixa(Vector3(meia - 1.2, 0.12, 4.6)), gm, Transform3D(b, pc + nrm * 0.02))
		for k in 5:
			_malha(no, _caixa(Vector3(0.25, 0.16, 4.4)), Gelo.material(Gelo.Mat.ACO), Transform3D(b, pc + lat * (k - 2) * 0.8 + nrm * 0.06))
		grades.append(gm)
		# Coluna de lava (cilindro com a lava escorrendo para baixo), escalada na altura
		var col := MeshInstance3D.new()
		var cil := CylinderMesh.new()
		cil.top_radius = 1.0
		cil.bottom_radius = 1.6
		cil.height = 1.0
		cil.radial_segments = 20
		col.mesh = cil
		col.material_override = Dino.material_lava(1, 3.0, 1.0, 5.0, 7.0, 8.0)
		col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		col.visible = false
		no.add_child(col)
		colunas.append(col)
		var corpo := _corpo_mortal(no, true)
		_forma_caixa(corpo, Vector3(meia - 0.8, 13.0, 4.4), Transform3D(Basis.IDENTITY, Vector3(0, 6.5, 0)))
		corpos.append([corpo, pc])
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.45, 0.12)
		luz.omni_range = 26.0
		luz.light_energy = 0.0
		luz.position = pc + nrm * 4.0
		no.add_child(luz)
		luzes.append(luz)
		var rp := _fagulhas(no, Color(1.0, 0.45, 0.1), 1.2, 14.0, 70)
		rp.position = pc + nrm * 0.5
		respingos.append(rp)
	_portoes.append({"tipo": "lava_jato", "i": i, "s": sub.progresso_amostra(i), "comp": 5.0, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": periodo, "ligado": float(cfg.get("ligado_s", 1.4)), "base": b, "nrm": nrm, "colunas": colunas, "corpos": corpos, "luzes": luzes,
		"respingos": respingos, "grades": grades, "total": false})


## Altura do jato de lava (0 = desligado) da faixa no instante t, e a fase dentro do ciclo.
func _lava_h(g: Dictionary, lado: int, t: float) -> Array:
	var per: float = g.periodo
	var f := fposmod(t + float(g.fase) + (per * 0.5 if lado == 1 else 0.0), per)
	var lig: float = g.ligado
	var h := 0.0
	if f < lig:
		h = 12.0 * smoothstep(0.0, 0.22, f) * (1.0 - smoothstep(lig - 0.3, lig, f) * 0.85)
	return [h, f]


func _perigo_lava(g: Dictionary, lado: int, t: float) -> bool:
	var per: float = g.periodo
	var f := fposmod(t + float(g.fase) + (per * 0.5 if lado == 1 else 0.0), per)
	return f < float(g.ligado) + 0.1


func _animar_lava(g: Dictionary) -> void:
	for lado in 2:
		var r := _lava_h(g, lado, _t)
		var h: float = r[0]
		var f: float = r[1]
		var col: MeshInstance3D = g.colunas[lado]
		var par: Array = g.corpos[lado]
		var pc: Vector3 = par[1]
		col.visible = h > 0.2
		if col.visible:
			col.transform = Transform3D(g.base * Basis.from_scale(Vector3(1.0 + sin(_t * 23.0) * 0.06, h, 1.0 + cos(_t * 19.0) * 0.06)), pc + (g.nrm as Vector3) * (h * 0.5))
		(par[0] as AnimatableBody3D).global_transform = Transform3D(g.base, pc + (Vector3.DOWN * 60.0 if not _perigo_lava(g, lado, _t) else Vector3.ZERO))
		var per: float = g.periodo
		var aviso := smoothstep(per - 1.1, per, f) + (1.0 if h > 0.2 else 0.0)
		var gm: StandardMaterial3D = g.grades[lado]
		gm.emission = Color(1.0, 0.35, 0.05)
		gm.emission_energy_multiplier = aviso * (2.0 + sin(_t * 30.0))
		(g.luzes[lado] as OmniLight3D).light_energy = h * 0.5 + aviso * 1.2
		var rp: GPUParticles3D = g.respingos[lado]
		var espirra := aviso > 0.05
		if rp.emitting != espirra:
			rp.emitting = espirra


# ------------------------------------------------------------------ lajes de basalto / tábuas da ponte

## Zona sem laje (o ComplexoSubida já deixou sem piso): placas que racham com o peso e caem, e voltam
## depois. Lajes de basalto sobre a lava (com a lava embaixo, fora do túnel) ou tábuas de uma ponte
## suspensa entre árvores gigantes. item = [trecho, m0, m1, no túnel (bool)]
func _montar_tabuas(item: Array, cfg: Dictionary, basalto: bool) -> void:
	var i0 := sub.indice_trecho(str(item[0]), float(item[1]))
	var i1 := sub.indice_trecho(str(item[0]), float(item[2]))
	var tunel := bool(item[3]) if item.size() > 3 else false
	var passo := float(cfg.get("comprimento", 4.0 if basalto else 2.2))
	var s0 := sub.progresso_amostra(i0)
	var total := sub.progresso_amostra(i1) - s0
	var n := maxi(int(round(total / passo)), 1)
	passo = total / n
	var no := Node3D.new()
	no.name = "Tabuas%d" % _placas.size()
	add_child(no)
	var madeira := StandardMaterial3D.new()
	madeira.albedo_color = Color(0.36, 0.25, 0.15)
	madeira.roughness = 0.9
	var corpos: Array = []
	var xfs: Array = []
	var apoio: Array[Transform3D] = []
	var lava_pts := []
	for k in n:
		var j := sub.indice_adiante(i0, (k + 0.5) * passo)
		var t := sub.tangente_em(j)
		var lat := sub.lateral_em(j)
		var nrm := lat.cross(t).normalized()
		var bp := Basis(lat, nrm, -t)
		var larg := sub.largura_em(j)
		var corpo := AnimatableBody3D.new()
		corpo.sync_to_physics = true
		corpo.collision_layer = 1
		corpo.collision_mask = 0
		corpo.add_to_group("estrutura")
		corpo.set_meta("aderencia", float(cfg.get("aderencia", 0.85)))
		var cs := CollisionShape3D.new()
		var forma := BoxShape3D.new()
		forma.size = Vector3(larg, 0.5, passo - 0.08)
		cs.shape = forma
		cs.position = Vector3(0, -0.25, 0)
		corpo.add_child(cs)
		if basalto:
			_malha(corpo, _caixa(Vector3(larg - 0.12, 0.9, passo - 0.12)), _rocha, Transform3D(Basis.IDENTITY, Vector3(0, -0.45, 0)))
		else:
			for p in 3:
				var w := (larg - 0.2) / 3.0
				_malha(corpo, _caixa(Vector3(w - 0.06, 0.22, passo - 0.12)), madeira, Transform3D(Basis.IDENTITY, Vector3((p - 1) * w, -0.11, 0)))
		no.add_child(corpo)
		var xf := Transform3D(bp, sub.amostra(j))
		corpo.global_transform = xf
		corpos.append(corpo)
		xfs.append(xf)
		for s: float in [-1.0, 1.0]:
			if basalto:
				apoio.append(Transform3D(bp * Basis.from_scale(Vector3(0.9, 1.2, passo + 0.05)), sub.amostra(j) + lat * s * (larg * 0.5 + 0.2) - nrm * 1.0))
			else:
				# Corrimão de corda e postes
				apoio.append(Transform3D(bp * Basis.from_scale(Vector3(0.12, 0.12, passo + 0.05)), sub.amostra(j) + lat * s * (larg * 0.5 + 0.3) + nrm * 1.1))
				if k % 3 == 0:
					apoio.append(Transform3D(bp * Basis.from_scale(Vector3(0.22, 1.4, 0.22)), sub.amostra(j) + lat * s * (larg * 0.5 + 0.3) + nrm * 0.5))
		lava_pts.append(sub.amostra(j))
	ComplexoLancamento.criar_multimesh(no, apoio, _rocha if basalto else madeira)
	# Lava embaixo das lajes (fora do túnel, que já tem o rio de lava)
	if basalto and not tunel and lava_pts.size() > 1:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in range(1, lava_pts.size()):
			var a: Vector3 = lava_pts[k - 1]
			var bq: Vector3 = lava_pts[k]
			var lat := Vector3(bq.x - a.x, 0.0, bq.z - a.z).normalized().cross(Vector3.UP)
			var q := [a - lat * 9.0, a + lat * 9.0, bq + lat * 9.0, bq - lat * 9.0]
			for v: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(0.0 if v in [0, 3] else 1.0, (k - (1 if v < 2 else 0)) * passo))
				st.add_vertex(q[v] + Vector3.DOWN * 7.0)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = Dino.material_lava(0, 0.4, 0.9, 10.0, 5.0, 18.0)
		no.add_child(mi)
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.42, 0.12)
		luz.light_energy = 3.0
		luz.omni_range = total + 20.0
		luz.position = lava_pts[lava_pts.size() / 2] + Vector3.DOWN * 3.0
		no.add_child(luz)
	var i_meio := sub.indice_adiante(i0, total * 0.5)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitorable = false
	_forma_caixa(area, Vector3(sub.largura_em(i_meio) + 1.0, 3.0, total))
	var tm := sub.tangente_em(i_meio)
	var lm := sub.lateral_em(i_meio)
	area.transform = Transform3D(Basis(lm, lm.cross(tm).normalized(), -tm), sub.amostra(i_meio) + Vector3.UP * 1.2)
	no.add_child(area)
	var estado := PackedInt32Array()
	estado.resize(n)
	var t_ev := PackedFloat32Array()
	t_ev.resize(n)
	_placas.append({"corpos": corpos, "xf": xfs, "estado": estado, "t_ev": t_ev, "area": area, "p0": sub.amostra(i0), "tan": sub.tangente_em(i0),
		"passo": passo, "tempo": float(cfg.get("tempo_s", 0.75 if basalto else 0.6)), "volta": float(cfg.get("volta_s", 5.0))})
	_portoes.append({"tipo": "placas", "i": i0, "s": s0, "comp": total, "fase": 0.0, "periodo": 1.0, "total": true, "zona": _placas.size() - 1})


# ------------------------------------------------------------------ cerca elétrica (raios)

## item = [trecho, m, fase]
func _montar_eletrica(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var periodo := float(cfg.get("periodo", 3.6))
	var c := sub.amostra(i)
	var b := _base(i)
	var lat := sub.lateral_em(i)
	var t := sub.tangente_em(i)
	var nrm := lat.cross(t).normalized()
	var meia := sub.largura_em(i) * 0.5
	var no := _no("Eletrica")
	var alto := 10.0
	# Pórtico de treliça com isoladores e as duas bobinas (uma sobre cada faixa)
	var aco: Array[Transform3D] = []
	var col: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		var pe := c + lat * s * (meia + 2.2)
		aco.append_array(ComplexoLancamento.trelica(pe, pe + Vector3.UP * alto, 1.8, 2.4, 0.22, 0.09))
		col.append(Transform3D(b * Basis.from_scale(Vector3(1.8, alto, 1.8)), pe + Vector3.UP * alto * 0.5))
	var e := c - lat * (meia + 3.2) + Vector3.UP * (alto + 0.6)
	var d := c + lat * (meia + 3.2) + Vector3.UP * (alto + 0.6)
	aco.append_array(ComplexoLancamento.trelica(e, d, 1.8, 2.4, 0.22, 0.09))
	col.append(Transform3D(b * Basis.from_scale(Vector3(meia * 2.0 + 6.0, 1.8, 1.8)), c + Vector3.UP * (alto + 0.6)))
	ComplexoLancamento.criar_multimesh(no, aco, Gelo.material(Gelo.Mat.ACO))
	var est := _corpo_mortal(no)
	ComplexoLancamento.adicionar_colisoes(est, col)
	var placa := Label3D.new()
	placa.text = "⚡ 10.000 VOLTS ⚡"
	placa.font_size = 160
	placa.pixel_size = 1.6 / 160.0
	placa.modulate = Color(1.0, 0.85, 0.15)
	placa.outline_size = 16
	placa.outline_modulate = Color(0.05, 0.05, 0.05)
	placa.double_sided = false
	placa.transform = Transform3D(Basis.looking_at(t, Vector3.UP), c + Vector3.UP * (alto + 2.6) - t * 1.1)
	no.add_child(placa)
	var listras := ShaderMaterial.new()
	listras.shader = load("res://shaders/listras_perigo.gdshader")
	listras.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 7))
	_malha(no, _caixa(Vector3(meia * 2.0 + 6.0, 0.6, 2.0)), listras, Transform3D(b, c + Vector3.UP * (alto - 0.6)))
	var bobinas := []
	var raios := []
	var areas := []
	var luzes := []
	var placas_chao := []
	for lado in 2:
		var s := -1.0 if lado == 0 else 1.0
		var topo := c + lat * s * (meia * 0.5) + Vector3.UP * (alto - 1.0)
		# Bobina: pilha de anéis isoladores e a esfera do eletrodo
		for k in 5:
			var anel := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 0.25
			tor.outer_radius = 0.7
			anel.mesh = tor
			anel.material_override = Gelo.material(Gelo.Mat.VERMELHO) if k % 2 == 0 else _mat_ouro
			anel.position = topo + Vector3.UP * (0.4 - k * 0.35)
			no.add_child(anel)
		var esf_m := _brilho(Color(0.55, 0.75, 1.0), 1.0)
		var esf := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.6
		sm.height = 1.2
		esf.mesh = sm
		esf.material_override = esf_m
		esf.position = topo + Vector3.DOWN * 1.4
		no.add_child(esf)
		bobinas.append(esf_m)
		# Placa de metal no piso (onde o raio bate)
		var pm := _brilho(Color(0.4, 0.6, 1.0), 0.0)
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		pm.albedo_color = Color(0.2, 0.22, 0.25)
		pm.metallic = 0.8
		_malha(no, _caixa(Vector3(meia - 1.0, 0.08, 4.0)), pm, Transform3D(b, c + lat * s * (meia * 0.5) + nrm * 0.03))
		placas_chao.append(pm)
		# Raio: segmentos que se refazem a cada quadro (MultiMesh de caixas finas)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _caixa(Vector3(0.12, 1.0, 0.12))
		mm.instance_count = 14
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _brilho(Color(0.7, 0.85, 1.0), 9.0)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visible = false
		no.add_child(mmi)
		raios.append([mmi, topo + Vector3.DOWN * 1.4, c + lat * s * (meia * 0.5)])
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		area.monitorable = false
		_forma_caixa(area, Vector3(meia, 3.0, 5.0))
		area.transform = Transform3D(b, c + lat * s * (meia * 0.5) + Vector3.UP * 1.5)
		no.add_child(area)
		areas.append(area)
		var luz := OmniLight3D.new()
		luz.light_color = Color(0.6, 0.75, 1.0)
		luz.omni_range = 22.0
		luz.light_energy = 0.0
		luz.position = c + lat * s * (meia * 0.5) + Vector3.UP * 3.0
		no.add_child(luz)
		luzes.append(luz)
	_portoes.append({"tipo": "eletrica", "i": i, "s": sub.progresso_amostra(i), "comp": 5.0, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": periodo, "ligado": float(cfg.get("ligado_s", 1.3)), "corte": float(cfg.get("corte_s", 2.0)), "bobinas": bobinas, "raios": raios,
		"areas": areas, "luzes": luzes, "placas": placas_chao, "faisca": _fagulhas(no, Color(0.6, 0.8, 1.0), 1.0, 9.0, 60), "total": false})


func _eletrica_ligada(g: Dictionary, lado: int, t: float) -> bool:
	var per: float = g.periodo
	var f := fposmod(t + float(g.fase) + (per * 0.5 if lado == 1 else 0.0), per)
	return f < float(g.ligado)


func _animar_eletrica(g: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_t * 30.0)
	for lado in 2:
		var lig := _eletrica_ligada(g, lado, _t)
		var per: float = g.periodo
		var f := fposmod(_t + float(g.fase) + (per * 0.5 if lado == 1 else 0.0), per)
		var carga := smoothstep(per - 1.2, per, f)
		var bm: StandardMaterial3D = g.bobinas[lado]
		bm.emission_energy_multiplier = 1.0 + carga * 6.0 + (8.0 if lig else 0.0)
		(g.placas[lado] as StandardMaterial3D).emission_energy_multiplier = (3.0 + rng.randf() * 3.0) if lig else carga * 1.5
		var r: Array = g.raios[lado]
		var mmi: MultiMeshInstance3D = r[0]
		mmi.visible = lig and rng.randf() < 0.85
		(g.luzes[lado] as OmniLight3D).light_energy = (5.0 + rng.randf() * 6.0) if mmi.visible else carga * 0.8
		if mmi.visible:
			var a: Vector3 = r[1]
			var bb: Vector3 = r[2]
			var mm := mmi.multimesh
			var n := mm.instance_count
			var ant := a
			for k in n:
				var u := float(k + 1) / n
				var p := a.lerp(bb, u)
				if k < n - 1:
					p += Vector3(rng.randf_range(-0.9, 0.9), 0.0, rng.randf_range(-0.9, 0.9))
				var seg := p - ant
				var comp := seg.length()
				var y := seg / maxf(comp, 0.001)
				var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
				mm.set_instance_transform(k, Transform3D(Basis(x, y * comp, x.cross(y)), (ant + p) * 0.5))
				ant = p
		if lig:
			for corpo in (g.areas[lado] as Area3D).get_overlapping_bodies():
				var v := corpo as Veiculo
				if v and not v.fantasma() and v.relogio >= v.motor_cortado_ate:
					v.motor_cortado_ate = v.relogio + float(g.corte)
					var fa: GPUParticles3D = g.faisca
					fa.global_position = v.global_position + Vector3.UP
					fa.restart()
					fa.emitting = true


# ------------------------------------------------------------------ titanossauro atravessando

## item = [trecho, m, fase, lado de onde começa]
func _montar_manada(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var c := sub.amostra(i)
	var lat := sub.lateral_em(i)
	var meia := sub.largura_em(i) * 0.5
	var no := _no("Manada")
	var comp := float(cfg.get("comprimento", 34.0))
	# manada.bicho: "titanossauro" (travessia lenta) ou "tiranossauro" (pedido do dono: fica indo e vindo
	# pela estrada, de boca aberta, dando botes em quem passa)
	var especie := str(cfg.get("bicho", "titanossauro"))
	var longe := meia + comp * 0.3 + 10.0
	# Passarela de fauna atravessando a estrada na mesma altura (o parque liga os recintos por cima do
	# vale): laje de concreto dos dois lados da pista, pilares até o chão, guarda-corpo nas bordas e as
	# placas TRAVESSIA DE TITANOSSAUROS. A estrada continua sendo o piso no meio.
	var b := _base(i)
	var plano := b   # na horizontal: é nele que o bicho anda
	var cercado := especie != "titanossauro"
	if cercado:
		# Passarela cercada (ver _cercado_trex): acompanha a rampa da pista — com quase 30 m ao longo da estrada,
		# na horizontal ela ficava um degrau acima da pista numa ponta e abaixo na outra
		var tg := sub.tangente_em(i)
		b = Basis(lat, (-tg).cross(lat).normalized(), -tg).orthonormalized()
	var concreto := sub.material_concreto(c.y - 40.0)
	var laje: Array[Transform3D] = []
	var colunas: Array[Transform3D] = []
	var grade: Array[Transform3D] = []
	# (cercado: o bicho dá meia-volta lá dentro — 24 m de comprimento girando pedem folga dos lados e no fundo)
	var larg_p := comp * 1.2 if cercado else 16.0
	var alcance := longe + comp * (0.6 if cercado else 0.35)
	for s: float in [-1.0, 1.0]:
		var ini := meia + 0.2
		var meio := c + lat * s * (ini + alcance) * 0.5
		laje.append(Transform3D(b * Basis.from_scale(Vector3(alcance - ini, 1.6, larg_p)), meio - b.y * 0.85))
		var x := ini + 6.0
		while x < alcance:
			for z: float in [-1.0, 1.0]:
				_ao_chao(no, c + lat * s * x + b.z * z * (larg_p * 0.5 - 1.5) + Vector3.DOWN * 1.6, 2.2, colunas)
			x += 14.0
		for z: float in ([] if cercado else [-1.0, 1.0]):
			grade.append(Transform3D(b * Basis.from_scale(Vector3(alcance - ini, 1.1, 0.25)), meio + b.z * z * (larg_p * 0.5 - 0.2) + Vector3.UP * 0.55))
	ComplexoLancamento.criar_multimesh(no, laje, concreto)
	ComplexoLancamento.criar_multimesh(no, colunas, concreto)
	ComplexoLancamento.criar_multimesh(no, grade, Gelo.material(Gelo.Mat.ACO))
	var est := StaticBody3D.new()
	est.collision_layer = 1
	est.collision_mask = 0
	est.add_to_group("estrutura")
	no.add_child(est)
	ComplexoLancamento.adicionar_colisoes(est, laje)
	if cercado:
		_cercado_trex(no, Transform3D(b, c - b.y * 0.05), meia, alcance, larg_p * 0.5, 7300 + i, est)
	for face: float in ([] if cercado else [-1.0, 1.0]):
		var placa := Label3D.new()
		placa.text = "TRAVESSIA DE TITANOSSAUROS" if especie == "titanossauro" else "ZONA DO TIRANOSSAURO"
		placa.font_size = 180
		placa.pixel_size = 1.3 / 180.0
		placa.modulate = Color(1.0, 0.85, 0.2)
		placa.outline_size = 16
		placa.outline_modulate = Color(0.05, 0.05, 0.05)
		placa.double_sided = false
		placa.transform = Transform3D(Basis.looking_at(-b.z * face, Vector3.UP), c + lat * (meia + 6.0) + Vector3.UP * 3.2 + b.z * face * (larg_p * 0.5 + 0.2))
		no.add_child(placa)
	var d := DinosParque.criar(especie, comp)
	var corpo := _corpo_mortal(no, true)
	corpo.add_child(d.raiz)
	var alt: float = float(d.get("altura", 14.0))
	var pernas := [[0.24, 1.0], [0.24, -1.0], [-0.2, 1.0], [-0.2, -1.0]]
	if especie != "titanossauro":
		# Bípede: as duas pernas no quadril e a cabeça abaixada na frente (o bote pega quem passa rente)
		# (a cabeça não tem colisão mortal: ela PEGA o carro, como o T-Rex do covil — ver _animar_manada)
		pernas = [[0.02, 1.0], [0.02, -1.0], [0.36, 0.0]]
	for p: Array in pernas:
		if float(p[1]) != 0.0:
			_forma_caixa(corpo, Vector3(2.0, alt * 0.42, 2.0), Transform3D(Basis.IDENTITY, Vector3(float(p[1]) * comp * 0.075, alt * 0.21, -float(p[0]) * comp)))
	var travessia := float(cfg.get("travessia_s", 15.0))
	var vira := float(cfg.get("vira_s", 4.0))
	_portoes.append({"tipo": "manada", "i": i, "s": sub.progresso_amostra(i), "comp": comp * 0.18, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": (travessia + vira) * 2.0, "travessia": travessia, "vira": vira, "c": c, "lat": lat, "lado": float(item[3]) if item.size() > 3 else 1.0,
		"meia": meia, "comp_t": comp, "pernas": pernas, "bicho": d, "corpo": corpo, "longe": longe, "total": false, "ataca": especie != "titanossauro",
		"tan": -plano.z, "presa": null, "presa_t": 0.0, "atraso": 0.0, "segura": float(cfg.get("segura_s", 3.0)), "alt": alt, "presa_de": c,
		"boca_y": float(cfg.get("boca_y", -comp * BOCA_Y)), "boca_z": float(cfg.get("boca_z", comp * BOCA_Z))})
	if OS.get_environment("TSC_BOCA_TESTE") != "" and especie != "titanossauro":
		# Conferência: caixa verde do tamanho do carro onde ele fica preso; o bicho para no meio da pista, segurando
		var marca := MeshInstance3D.new()
		var caixa_m := BoxMesh.new()
		caixa_m.size = Vector3(2.1, 1.3, 4.6)
		marca.mesh = caixa_m
		marca.material_override = _brilho(Color(0.2, 1.0, 0.2), 3.0)
		no.add_child(marca)
		_portoes[-1]["marca"] = marca
		print("[BOCA] travessia em %s lat %s" % [str(c), str(lat)])


## [x do meio do bicho (lateral), sentido para onde anda (+1/-1 na lateral), girando 0..1, andando]
func _manada(g: Dictionary, t: float) -> Array:
	var f := fposmod(t + float(g.fase), float(g.periodo))
	var tr: float = g.travessia
	var vira: float = g.vira
	var longe: float = g.longe
	var lado: float = g.lado
	if f < tr:
		return [lerpf(lado * longe, -lado * longe, f / tr), -lado, 0.0, true]
	if f < tr + vira:
		return [-lado * longe, -lado, (f - tr) / vira, false]
	if f < tr * 2.0 + vira:
		return [lerpf(-lado * longe, lado * longe, (f - tr - vira) / tr), lado, 0.0, true]
	return [lado * longe, lado, (f - tr * 2.0 - vira) / vira, false]


func _perigo_manada(g: Dictionary, lado: int, t: float) -> bool:
	if g.get("presa") != null:
		return false   # de boca cheia: quem vem atrás passa
	var r := _manada(g, t - float(g.get("atraso", 0.0)))
	if float(r[2]) > 0.0:
		return false
	var x: float = r[0]
	var sentido: float = r[1]
	for p: Array in g.pernas:
		var xp := x + sentido * float(p[0]) * float(g.comp_t)
		if absf(xp - _x_faixa(lado)) < 1.0 + MEIA_CARRO + 0.5:
			return true
	return false


func _animar_manada(g: Dictionary) -> void:
	var dt := get_physics_process_delta_time()
	var presa: Veiculo = g.get("presa")
	if presa != null and (not is_instance_valid(presa) or presa.eliminado or not presa.preso):
		presa = null
		g.presa = null
	if presa != null:
		g.atraso = float(g.atraso) + dt   # para de andar enquanto segura o carro
		g.presa_t = float(g.presa_t) + dt
	var r := _manada(g, _t - float(g.get("atraso", 0.0)))
	if g.has("marca") and _t > 4.0:
		r = _manada(g, float(g.travessia) * 0.5 - float(g.fase))   # TSC_BOCA_TESTE: parado no meio da pista
	var lat: Vector3 = g.lat
	var sentido: float = r[1]
	var frente := lat * sentido
	var vira: float = r[2]
	if vira > 0.0:
		frente = frente.rotated(Vector3.UP, PI * vira)
	var p: Vector3 = (g.c as Vector3) + lat * float(r[0])
	var xf := Transform3D(Basis.looking_at(frente, Vector3.UP), p)
	if not g.get("ataca", false):
		(g.corpo as AnimatableBody3D).global_transform = xf
		# Passada pelo chão percorrido (pelo relógio, os pés patinavam na travessia e na meia-volta)
		DinosParque.andar(g.bicho, xf, dt, 1.0, 0.1 + 0.1 * sin(_t * 0.5))
		return
	# Tiranossauro: morde como o do covil da etapa 1 (pedido do dono) — a cabeça pega UM carro, levanta com
	# ele atravessado na boca, sacode por `segura` s e só então ele explode e volta ao checkpoint
	var comp: float = g.comp_t
	var alt: float = g.alt
	var u_seg := clampf(float(g.presa_t) / 0.5, 0.0, 1.0) if presa != null else (1.0 if g.has("marca") and _t > 6.0 else 0.0)
	var bote := pow(maxf(sin(_t * 2.1), 0.0), 2.0) * (1.0 - u_seg)
	var corpo_xf := _inclinado(xf.basis, p, g.bicho, Basis(Vector3.UP, sin(_t * 17.0) * 0.16 * u_seg) * Basis(Vector3.RIGHT, 0.22 * u_seg))
	(g.corpo as AnimatableBody3D).global_transform = corpo_xf
	var boca := 1.55 + 0.08 * sin(_t * 20.0) if presa != null or u_seg > 0.0 else 0.55 + 0.45 * sin(_t * 4.2)
	DinosParque.andar(g.bicho, xf, dt, 1.0, boca, bote)
	if g.has("marca"):
		var bt_m := _boca_trex(g, corpo_xf, p)
		(g.marca as Node3D).global_transform = Transform3D((bt_m[1] as Basis) * Basis(Vector3.UP, PI * 0.5), (bt_m[0] as Vector3) + (bt_m[1] as Basis).y * 0.65)
	if not g.has("boca_local") and bote < 0.05 and presa == null:
		_boca_trex(g, corpo_xf, p, true)   # cabeça neutra: marca o ponto da boca no osso
	if presa == null and vira <= 0.0:
		var focinho := p + frente * (comp * 0.5 - 1.0)
		var melhor: Veiculo = null
		var melhor_d := INF
		for no_v in get_tree().get_nodes_in_group("veiculo"):
			var v := no_v as Veiculo
			if v == null or v.eliminado or v.fantasma() or v.preso or v.travado:
				continue
			var q: Vector3 = v.global_position - (g.c as Vector3)
			if absf(q.dot(g.tan)) > 6.0 or absf(q.y) > 3.5 or absf(q.dot(lat)) > float(g.meia) + 1.0:
				continue
			var dist := Vector2(v.global_position.x - focinho.x, v.global_position.z - focinho.z).length()
			if dist < melhor_d and dist < 6.5:
				melhor_d = dist
				melhor = v
		if melhor:
			melhor.agarrar()
			g.presa = melhor
			g.presa_t = 0.0
			g.presa_de = melhor.global_position
			presa = melhor
	if presa != null:
		var bt := _boca_trex(g, corpo_xf, p + corpo_xf.basis * Vector3(0.0, alt * lerpf(0.34, 0.78, u_seg), -(comp * 0.5 - 1.6)))
		var boca_p := (g.presa_de as Vector3).lerp(bt[0], clampf(float(g.presa_t) / 0.15, 0.0, 1.0))
		presa.global_transform = Transform3D((bt[1] as Basis) * Basis(Vector3.UP, PI * 0.5), boca_p)
		presa.reset_physics_interpolation()
		if float(g.presa_t) >= float(g.segura):
			presa.devorar()
			g.presa = null
			g.presa_t = 0.0


## Placa TIRANOSSAURO REX em cima do lintel dos portões do cercado (arte do dono, preparada por
## tools/extinction_day/placa_trex.gd): a arte em relevo nas duas faces (TunelVulcao.montar_arte: iluminada
## pela cena, com espessura e paredes) e, saindo dos quatro cestos de ferro dela, fogo de verdade
## (shaders/fogo_tocha.gdshader) com a luz dele. `pe` = meio do apoio da placa; sem a arte na pasta, fica
## o letreiro simples.
const PLACA_TREX := "res://assets/dino/portao/placa_tiranossauro_rex.png"
# Bocas dos cestos na arte (UV) e tamanho da labareda em fração da largura da placa: [u, v, largura, altura]
const PLACA_TREX_FOGOS := [[0.0635, 0.335, 0.2, 0.36], [0.9358, 0.335, 0.2, 0.36], [0.054, 0.7, 0.085, 0.15], [0.952, 0.7, 0.085, 0.15]]

func _placa_trex(no: Node3D, pe: Vector3, frente: Vector3, larg: float, semente: int) -> void:
	var para_fora := Vector3(frente.x, 0.0, frente.z).normalized()
	const Y0 := -0.06   # a franja de cipós de baixo da arte desce um pouco na frente do lintel
	var alt := TunelVulcao.montar_arte(no, PLACA_TREX, [], [], pe, para_fora, larg, Y0 * larg, true, 0.3)
	if alt <= 0.0:
		for face: float in [-1.0, 1.0]:
			var letreiro := Label3D.new()
			letreiro.text = "TIRANOSSAURO REX"
			letreiro.font_size = 160
			letreiro.pixel_size = 0.9 / 160.0
			letreiro.modulate = Color(1.0, 0.8, 0.25)
			letreiro.outline_size = 14
			letreiro.outline_modulate = Color(0.05, 0.04, 0.03)
			letreiro.double_sided = false
			letreiro.transform = Transform3D(Basis.looking_at(-para_fora * face, Vector3.UP), pe + Vector3.UP * 0.7 + para_fora * face * 0.1)
			no.add_child(letreiro)
		return
	var dir := Basis.looking_at(-para_fora, Vector3.UP).x
	var chama := QuadMesh.new()
	chama.size = Vector2(1.0, 1.0)
	chama.center_offset = Vector3(0.0, 0.5, 0.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fogo_tocha.gdshader")
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.08, 3, 71))
	for k in PLACA_TREX_FOGOS.size():
		var f: Array = PLACA_TREX_FOGOS[k]
		var boca := pe + dir * ((float(f[0]) - 0.5) * larg) + Vector3.UP * (Y0 * larg + alt * (1.0 - float(f[1])))
		var mi := MeshInstance3D.new()
		mi.mesh = chama
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(Basis.from_scale(Vector3(float(f[2]) * larg, float(f[3]) * larg, 1.0)), boca)
		mi.set_instance_shader_parameter("fase", 0.37 * k + 0.11 * semente)
		no.add_child(mi)
		if k < 2:
			var luz := OmniLight3D.new()
			luz.light_color = Color(1.0, 0.5, 0.16)
			luz.light_energy = 3.0
			luz.omni_range = larg * 1.3
			luz.shadow_enabled = false
			luz.position = boca + Vector3.UP * float(f[3]) * larg * 0.35
			no.add_child(luz)


## Cercado do tiranossauro das travessias ("ZONA DO TIRANOSSAURO"; pedido do dono, pela arte
## assets/DINOSSAUROS/extruturas/gradescercado.png — tudo em geometria, nada de imagem): em toda a volta
## da passarela, mureta de concreto em blocos com musgo, sapata, capa e um contraforte em cada poste;
## postes de aço em I com a ponta dobrada para dentro, isoladores e seis cabos eletrificados (mais dois
## na ponta dobrada); embaixo dos cabos, quadro com tela de arame (nas cabeceiras, chapa rebitada);
## cipós nos postes e na mureta e samambaias no pé. Nos dois lados em que a estrada entra e sai, um
## portão: pilares de concreto com cinta de aço, batente, lintel com faixa amarela e preta e a placa da
## zona (arte do dono em relevo, com fogo de verdade nos cestos: _placa_trex), sinaleiro vermelho em cima de cada pilar, lanternas, painel de comando e as duas folhas de
## correr abertas, recolhidas atrás da cerca no seu trilho. `o` = referencial da passarela (x atravessa a
## estrada, z ao longo dela, origem no eixo da pista); meio_x / meio_z = meias medidas da laje.
func _cercado_trex(no: Node3D, o: Transform3D, meia: float, meio_x: float, meio_z: float, semente: int, est: StaticBody3D) -> void:
	const ALT := 8.0       # altura dos postes
	const MURO := 1.9      # altura da mureta
	const VAO := 8.6       # altura livre do portão
	const PILAR := 10.4    # altura dos pilares do portão
	const CABOS: Array[float] = [4.7, 5.3, 5.9, 6.5, 7.1, 7.7]
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var chao := o.origin.y - 60.0
	var pedra_m := ShaderMaterial.new()
	pedra_m.shader = load("res://shaders/muro_pedra.gdshader")
	pedra_m.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 71))
	pedra_m.set_shader_parameter("cor_pedra", Color(0.33, 0.32, 0.28))
	pedra_m.set_shader_parameter("cor_argamassa", Color(0.11, 0.11, 0.09))
	pedra_m.set_shader_parameter("fiada", 0.95)
	pedra_m.set_shader_parameter("altura_chao", chao)
	pedra_m.set_shader_parameter("musgo", 0.55)
	pedra_m.set_shader_parameter("rachaduras", 1.0)
	var aco := ShaderMaterial.new()
	aco.shader = load("res://shaders/metal_gasto.gdshader")
	aco.set_shader_parameter("ruido", Terreno._textura_ruido(0.03, 4, 61))
	aco.set_shader_parameter("ferrugem", 0.6)
	aco.set_shader_parameter("cor_tinta", Color(0.17, 0.16, 0.15))
	aco.set_shader_parameter("cor_ferrugem", Color(0.24, 0.11, 0.05))
	aco.set_shader_parameter("cor_ferrugem_clara", Color(0.42, 0.22, 0.1))
	aco.set_shader_parameter("cor_poeira", Color(0.25, 0.2, 0.15))
	aco.set_shader_parameter("altura_chao", chao)
	var aco_escuro: ShaderMaterial = aco.duplicate()
	aco_escuro.set_shader_parameter("cor_tinta", Color(0.07, 0.07, 0.075))
	aco_escuro.set_shader_parameter("ferrugem", 0.4)
	var aco_cabo: ShaderMaterial = aco.duplicate()
	aco_cabo.set_shader_parameter("cor_tinta", Color(0.42, 0.43, 0.44))
	aco_cabo.set_shader_parameter("ferrugem", 0.25)
	var listra_m := ShaderMaterial.new()
	listra_m.shader = load("res://shaders/listras_perigo.gdshader")
	listra_m.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 71))
	listra_m.set_shader_parameter("largura_listra", 0.3)
	var tela_m := ShaderMaterial.new()
	tela_m.shader = load("res://shaders/tela_cerca.gdshader")
	var rebite := SphereMesh.new()
	rebite.radius = 0.5
	rebite.height = 0.6
	rebite.radial_segments = 8
	rebite.rings = 4
	var tubo := CylinderMesh.new()
	tubo.top_radius = 0.5
	tubo.bottom_radius = 0.5
	tubo.height = 1.0
	tubo.radial_segments = 10
	tubo.rings = 1
	var cone := CylinderMesh.new()
	cone.top_radius = 0.5
	cone.bottom_radius = 0.08
	cone.height = 1.0
	cone.radial_segments = 8
	cone.rings = 1
	var quadro := QuadMesh.new()
	var pedra: Array[Transform3D] = []
	var ferro: Array[Transform3D] = []
	var escuro: Array[Transform3D] = []
	var cabos: Array[Transform3D] = []
	var listras: Array[Transform3D] = []
	var rebites: Array[Transform3D] = []
	var tubos: Array[Transform3D] = []
	var cones: Array[Transform3D] = []
	var vidros: Array[Transform3D] = []
	var talos: Array[Transform3D] = []
	var folhagem: Array[Transform3D] = []
	var fetos: Array[Transform3D] = []
	var colisao: Array[Transform3D] = []
	var telas := []   # [Transform3D, Vector2 (tamanho em metros)]
	# Caixa de `tam` em `pos` no referencial r (giro opcional)
	var caixa := func(lista: Array[Transform3D], r: Transform3D, tam: Vector3, pos: Vector3, giro := Basis.IDENTITY) -> void:
		lista.append(r * Transform3D(giro * Basis.from_scale(tam), pos))
	# Cipó pendurado a partir de `topo`: talo fino e folhas pelo caminho
	var cipo := func(r: Transform3D, topo: Vector3, comp_c: float) -> void:
		talos.append(r * Transform3D(Basis.from_scale(Vector3(0.07, comp_c, 0.07)), topo + Vector3.DOWN * comp_c * 0.5))
		for q in int(comp_c * 3.0) + 2:
			var giro := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.7, 0.7))
			folhagem.append(r * Transform3D(giro * Basis.from_scale(Vector3(rng.randf_range(0.3, 0.6), 0.04, rng.randf_range(0.22, 0.4))), topo + Vector3.DOWN * rng.randf_range(0.0, comp_c) + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))))
	var dobra := Basis(Vector3.RIGHT, 0.75)   # a ponta do poste inclina para dentro do cercado
	# Um lance de cerca de `a` até `b2` (x, z da passarela); `dentro` aponta para o lado do bicho
	var trecho := func(a: Vector2, b2: Vector2, dentro: Vector2, chapa: bool, pontas: bool) -> void:
		var d3 := Vector3(b2.x - a.x, 0.0, b2.y - a.y).normalized()
		if d3.cross(Vector3.UP).dot(Vector3(dentro.x, 0.0, dentro.y)) < 0.0:
			var troca := a
			a = b2
			b2 = troca
			d3 = -d3
		var comp := a.distance_to(b2)
		# Referencial do lance: x ao longo dele, z para dentro do cercado
		var r := o * Transform3D(Basis(d3, Vector3.UP, d3.cross(Vector3.UP)), Vector3(a.x, 0.0, a.y))
		caixa.call(pedra, r, Vector3(comp, 0.5, 1.7), Vector3(comp * 0.5, 0.25, 0.0))
		caixa.call(pedra, r, Vector3(comp, MURO - 0.5, 1.1), Vector3(comp * 0.5, 0.5 + (MURO - 0.5) * 0.5, 0.0))
		caixa.call(pedra, r, Vector3(comp + 0.04, 0.22, 1.36), Vector3(comp * 0.5, MURO + 0.11, 0.0))
		caixa.call(colisao, r, Vector3(comp, ALT, 1.0), Vector3(comp * 0.5, ALT * 0.5, 0.0))
		var n := maxi(int(round(comp / 5.0)), 1)
		var passo := comp / n
		var y0 := MURO + 0.4
		for j in n + 1:
			if not pontas and (j == 0 or j == n):
				continue
			var x := passo * j
			var torto := Basis(Vector3.UP, rng.randf_range(-0.03, 0.03))
			# Contraforte: dois blocos, o de baixo mais largo, e a capa onde o poste se apoia
			caixa.call(pedra, r, Vector3(1.75, 1.0, 2.3), Vector3(x, 0.5, 0.0), torto)
			caixa.call(pedra, r, Vector3(1.4, MURO - 0.9, 1.8), Vector3(x, 1.0 + (MURO - 0.9) * 0.5, 0.0), torto)
			caixa.call(pedra, r, Vector3(1.55, 0.22, 1.95), Vector3(x, MURO + 0.21, 0.0))
			caixa.call(escuro, r, Vector3(0.9, 0.12, 0.9), Vector3(x, MURO + 0.38, 0.0))
			for qx: float in [-0.33, 0.33]:
				for qz: float in [-0.33, 0.33]:
					caixa.call(rebites, r, Vector3.ONE * 0.16, Vector3(x + qx, MURO + 0.46, qz))
			# Poste em I: alma e duas abas; a ponta dobra para dentro
			caixa.call(ferro, r, Vector3(0.16, ALT - y0, 0.46), Vector3(x, (ALT + y0) * 0.5, 0.0))
			for sz: float in [-1.0, 1.0]:
				caixa.call(ferro, r, Vector3(0.5, ALT - y0, 0.1), Vector3(x, (ALT + y0) * 0.5, sz * 0.25))
			caixa.call(ferro, r, Vector3(0.5, 2.0, 0.16), Vector3(x, ALT - 0.05, 0.0) + dobra * Vector3(0.0, 0.95, 0.0), dobra)
			caixa.call(escuro, r, Vector3(0.62, 0.3, 0.6), Vector3(x, ALT, 0.06))
			# Isoladores: um por cabo, na face de dentro, e dois na ponta dobrada
			for yc: float in CABOS:
				caixa.call(tubos, r, Vector3(0.22, 0.4, 0.22), Vector3(x, yc, 0.48), Basis(Vector3.RIGHT, PI * 0.5))
				caixa.call(tubos, r, Vector3(0.3, 0.07, 0.3), Vector3(x, yc, 0.5), Basis(Vector3.RIGHT, PI * 0.5))
				caixa.call(rebites, r, Vector3.ONE * 0.2, Vector3(x, yc, 0.7))
			for f: float in [0.45, 0.92]:
				caixa.call(tubos, r, Vector3(0.2, 0.36, 0.2), Vector3(x, ALT - 0.05, 0.0) + dobra * Vector3(0.0, 2.0 * f, 0.24), dobra * Basis(Vector3.RIGHT, PI * 0.5))
			# Cipós descendo por alguns postes e samambaia no pé do contraforte (do lado de dentro, na laje)
			if rng.randf() < 0.45:
				for q in rng.randi_range(3, 6):
					var comp_c := rng.randf_range(1.5, 4.5)
					cipo.call(r, Vector3(x + rng.randf_range(-0.3, 0.3), rng.randf_range(4.5, ALT + 0.6), rng.randf_range(-0.35, 0.35)), comp_c)
			if rng.randf() < 0.65:
				var esc := rng.randf_range(1.0, 1.7)
				fetos.append(r * Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * esc), Vector3(x + rng.randf_range(-1.2, 1.2), 0.0, 1.6 + rng.randf_range(0.0, 0.6))))
		# Cabos de ponta a ponta (passam pelos isoladores) e os dois da ponta dobrada
		for yc: float in CABOS:
			caixa.call(cabos, r, Vector3(comp, 0.055, 0.055), Vector3(comp * 0.5, yc, 0.7))
		for f: float in [0.45, 0.92]:
			caixa.call(cabos, r, Vector3(comp, 0.055, 0.055), Vector3(comp * 0.5, ALT - 0.05, 0.0) + dobra * Vector3(0.0, 2.0 * f, 0.44))
		# Quadro de baixo: travessas e, entre os postes, tela de arame (ou chapa rebitada nas cabeceiras)
		var yb := MURO + 0.3
		var yt := 4.15
		for y: float in [yb + 0.08, yt]:
			caixa.call(ferro, r, Vector3(comp, 0.16, 0.14), Vector3(comp * 0.5, y, 0.0))
		for j in n:
			var xm := passo * (j + 0.5)
			var w := passo - 0.52
			var h := yt - yb - 0.24
			var ym := (yb + 0.08 + yt) * 0.5
			if chapa:
				caixa.call(escuro, r, Vector3(w, h, 0.07), Vector3(xm, ym, 0.0))
				caixa.call(ferro, r, Vector3(w, 0.12, 0.13), Vector3(xm, ym, 0.0))
				for face: float in [-1.0, 1.0]:
					for q in 7:
						for y: float in [yb + 0.4, yt - 0.3]:
							caixa.call(rebites, r, Vector3.ONE * 0.13, Vector3(xm - w * 0.5 + 0.2 + q * (w - 0.4) / 6.0, y, face * 0.05))
			else:
				telas.append([r * Transform3D(Basis.from_scale(Vector3(w, h, 1.0)), Vector3(xm, ym, 0.0)), Vector2(w, h)])
		# Mato pendurado na capa da mureta, pelo lado de fora
		for q in int(comp / 2.5):
			if rng.randf() < 0.55:
				cipo.call(r, Vector3(rng.randf_range(0.5, comp - 0.5), MURO + 0.25, -0.62), rng.randf_range(0.6, 1.7))
	var fx := meio_x - 1.25   # eixo da cerca nas cabeceiras
	var fz := meio_z - 1.25   # eixo da cerca nos lados compridos (onde ficam os portões)
	var vao_x := meia + 0.6   # meia largura livre do portão
	for so: float in [-1.0, 1.0]:
		for s: float in [-1.0, 1.0]:
			trecho.call(Vector2(s * (vao_x + 2.55), so * fz), Vector2(s * fx, so * fz), Vector2(0.0, -so), false, true)
	for s: float in [-1.0, 1.0]:
		trecho.call(Vector2(s * fx, -fz + 0.68), Vector2(s * fx, fz - 0.68), Vector2(-s, 0.0), true, false)
	# Portões (um em cada lado comprido, em cima da estrada)
	for so: float in [-1.0, 1.0]:
		# Referencial do portão: x atravessa a estrada, z para FORA do cercado
		var g := o * Transform3D(Basis(Vector3.UP, 0.0 if so > 0.0 else PI), Vector3(0.0, 0.0, so * fz))
		var larg_l := vao_x * 2.0
		var yl := VAO + 0.8
		for s: float in [-1.0, 1.0]:
			var px := s * (vao_x + 1.25)
			# Pilar: sapata, cinco blocos afinando, capa
			caixa.call(pedra, g, Vector3(3.0, 1.2, 3.0), Vector3(px, 0.6, 0.0))
			var hb := (PILAR - 1.2) / 5.0
			for k in 5:
				var w := lerpf(2.5, 2.15, k / 4.0) + rng.randf_range(-0.05, 0.05)
				caixa.call(pedra, g, Vector3(w, hb + 0.02, w), Vector3(px + s * (w - 2.5) * 0.5, 1.2 + hb * (k + 0.5), 0.0), Basis(Vector3.UP, rng.randf_range(-0.02, 0.02)))
			caixa.call(pedra, g, Vector3(2.6, 0.35, 2.6), Vector3(px, PILAR + 0.17, 0.0))
			caixa.call(colisao, g, Vector3(2.5, PILAR, 2.5), Vector3(px, PILAR * 0.5, 0.0))
			caixa.call(ferro, g, Vector3(2.62, 0.4, 2.62), Vector3(px, PILAR * 0.5, 0.0))
			# Batente de aço na face de dentro do vão, rebitado
			caixa.call(ferro, g, Vector3(0.34, VAO, 1.3), Vector3(s * (vao_x - 0.17), VAO * 0.5, 0.0))
			for k in 12:
				for face: float in [-1.0, 1.0]:
					caixa.call(rebites, g, Vector3.ONE * 0.18, Vector3(s * (vao_x - 0.34), 0.5 + k * (VAO - 1.0) / 11.0, face * 0.45))
			# Sinaleiro vermelho no alto do pilar: base, lâmpada, gaiola e tampa
			caixa.call(tubos, g, Vector3(0.9, 0.25, 0.9), Vector3(px, PILAR + 0.47, 0.0))
			(_lampada(no, g * Vector3(px, PILAR + 0.9, 0.0), 0.3) as StandardMaterial3D).emission = Color(1.0, 0.06, 0.03)
			for q in 4:
				var aq := TAU * (q + 0.5) / 4.0
				caixa.call(tubos, g, Vector3(0.05, 0.7, 0.05), Vector3(px + cos(aq) * 0.36, PILAR + 0.95, sin(aq) * 0.36))
			caixa.call(tubos, g, Vector3(0.84, 0.1, 0.84), Vector3(px, PILAR + 1.32, 0.0))
			var alerta := OmniLight3D.new()
			alerta.light_color = Color(1.0, 0.1, 0.05)
			alerta.light_energy = 1.4
			alerta.omni_range = 9.0
			alerta.shadow_enabled = false
			alerta.position = g * Vector3(px, PILAR + 1.6, 0.0)
			no.add_child(alerta)
			# Lanternas nas duas faces: braço, tampa, gaiola de quatro barras, vidro aceso e ponteira
			for face: float in [-1.0, 1.0]:
				var zl := face * 1.72
				caixa.call(escuro, g, Vector3(0.12, 0.12, 0.62), Vector3(px, 7.0, face * 1.5))
				caixa.call(escuro, g, Vector3(0.5, 0.7, 0.1), Vector3(px, 6.8, face * 1.24))
				caixa.call(tubos, g, Vector3(0.66, 0.12, 0.66), Vector3(px, 6.9, zl))
				caixa.call(tubos, g, Vector3(0.3, 0.2, 0.3), Vector3(px, 7.05, zl))
				caixa.call(vidros, g, Vector3(0.44, 0.78, 0.44), Vector3(px, 6.45, zl))
				for q in 4:
					var aq := TAU * (q + 0.5) / 4.0
					caixa.call(tubos, g, Vector3(0.05, 0.8, 0.05), Vector3(px + cos(aq) * 0.27, 6.45, zl + sin(aq) * 0.27))
				caixa.call(tubos, g, Vector3(0.62, 0.08, 0.62), Vector3(px, 6.04, zl))
				caixa.call(cones, g, Vector3(0.56, 0.5, 0.56), Vector3(px, 5.75, zl))
			var lanterna := OmniLight3D.new()
			lanterna.light_color = Color(1.0, 0.6, 0.25)
			lanterna.light_energy = 2.2
			lanterna.omni_range = 15.0
			lanterna.shadow_enabled = false
			lanterna.position = g * Vector3(px, 6.4, 2.6)
			no.add_child(lanterna)
			# Painel de comando do portão: caixa de aço, visor e luz vermelha
			caixa.call(escuro, g, Vector3(0.85, 1.15, 0.26), Vector3(px, 2.5, 1.3))
			caixa.call(ferro, g, Vector3(0.95, 0.1, 0.34), Vector3(px, 3.1, 1.3))
			caixa.call(ferro, g, Vector3(0.1, 1.4, 0.1), Vector3(px - 0.2, 1.4, 1.3))
			(_lampada(no, g * Vector3(px + 0.18, 2.75, 1.45), 0.07) as StandardMaterial3D).emission = Color(1.0, 0.06, 0.03)
			(_lampada(no, g * Vector3(px - 0.18, 2.75, 1.45), 0.07) as StandardMaterial3D).emission = Color(0.9, 0.6, 0.1)
			# Cipós pelo pilar
			for k in 9:
				var face := -1.0 if k % 2 == 0 else 1.0
				cipo.call(g, Vector3(px + rng.randf_range(-1.0, 1.0), rng.randf_range(5.0, PILAR + 0.3), face * 1.3), rng.randf_range(1.5, 4.5))
			cipo.call(g, Vector3(px + s * 1.3, PILAR + 0.3, rng.randf_range(-0.8, 0.8)), rng.randf_range(3.0, 6.0))
			# Folha de correr, aberta: recolhida do lado de dentro, atrás da cerca, pendurada no trilho
			var xc := s * (vao_x + 2.9 + vao_x * 0.5)
			var zf := -1.75
			var lf := vao_x
			for y: float in [0.5, VAO * 0.5, VAO - 0.45]:
				caixa.call(ferro, g, Vector3(lf, 0.3, 0.2), Vector3(xc, y, zf))
			for x: float in [-lf * 0.5 + 0.15, lf * 0.5 - 0.15]:
				caixa.call(ferro, g, Vector3(0.3, VAO - 0.65, 0.2), Vector3(xc + x, VAO * 0.5 + 0.03, zf))
			for y: float in [1.0, VAO - 0.95]:
				caixa.call(listras, g, Vector3(lf - 0.6, 0.45, 0.22), Vector3(xc, y, zf))
			for par: Array in [[1.25, VAO * 0.5 - 0.15], [VAO * 0.5 + 0.15, VAO - 1.2]]:
				var ya: float = par[0]
				var yb: float = par[1]
				telas.append([g * Transform3D(Basis.from_scale(Vector3(lf - 0.6, yb - ya, 1.0)), Vector3(xc, (ya + yb) * 0.5, zf)), Vector2(lf - 0.6, yb - ya)])
				caixa.call(ferro, g, Vector3(0.12, yb - ya, 0.12), Vector3(xc, (ya + yb) * 0.5, zf))
			for x: float in [-lf * 0.5 + 0.6, lf * 0.5 - 0.6]:
				caixa.call(tubos, g, Vector3(0.5, 0.16, 0.5), Vector3(xc + x, 0.28, zf), Basis(Vector3.RIGHT, PI * 0.5))
				caixa.call(tubos, g, Vector3(0.3, 0.14, 0.3), Vector3(xc + x, VAO - 0.1, zf), Basis(Vector3.RIGHT, PI * 0.5))
			caixa.call(colisao, g, Vector3(lf, VAO, 0.3), Vector3(xc, VAO * 0.5, zf))
			# Trilho de cima (do pilar até o fim da folha, em dois pés) e trilho no piso
			var fim_t := vao_x + 3.3 + lf
			caixa.call(escuro, g, Vector3(fim_t - vao_x, 0.3, 0.34), Vector3(s * (vao_x + fim_t) * 0.5, VAO + 0.12, zf))
			caixa.call(escuro, g, Vector3(fim_t - vao_x - 0.7, 0.07, 0.16), Vector3(s * (vao_x + 0.7 + fim_t) * 0.5, 0.035, zf))
			caixa.call(escuro, g, Vector3(0.3, 0.3, 0.7), Vector3(px, VAO + 0.12, -1.5))
			for x: float in [fim_t - 0.15, vao_x + 2.75]:
				caixa.call(ferro, g, Vector3(0.26, VAO, 0.26), Vector3(s * x, VAO * 0.5, zf - 0.32))
				caixa.call(ferro, g, Vector3(0.26, 0.26, 0.5), Vector3(s * x, VAO + 0.12, zf - 0.2))
		# Lintel: caixão de aço com abas e rebites, faixa de advertência e a placa da zona nas duas faces
		caixa.call(ferro, g, Vector3(larg_l + 0.1, 1.6, 1.5), Vector3(0.0, yl, 0.0))
		caixa.call(colisao, g, Vector3(larg_l, 1.6, 1.5), Vector3(0.0, yl, 0.0))
		for dy: float in [-0.8, 0.8]:
			caixa.call(ferro, g, Vector3(larg_l + 0.1, 0.2, 1.9), Vector3(0.0, yl + dy, 0.0))
		for face: float in [-1.0, 1.0]:
			caixa.call(listras, g, Vector3(larg_l - 0.6, 0.8, 0.06), Vector3(0.0, yl, face * 0.78))
			var n_r := int(larg_l / 0.6)
			for k in n_r:
				for dy: float in [-0.62, 0.62]:
					caixa.call(rebites, g, Vector3.ONE * 0.16, Vector3(lerpf(-larg_l * 0.5 + 0.3, larg_l * 0.5 - 0.3, float(k) / (n_r - 1)), yl + dy * 1.12, face * 0.76))
		_placa_trex(no, g * Vector3(0.0, yl + 0.9, 0.0), g.basis.z, minf(larg_l - 1.6, 9.5), 50 + int(so))
		for k in 5:
			cipo.call(g, Vector3(rng.randf_range(-larg_l * 0.45, larg_l * 0.45), yl - 0.9, rng.randf_range(-0.6, 0.6)), rng.randf_range(0.6, 1.6))
	ComplexoLancamento.criar_multimesh(no, pedra, pedra_m)
	ComplexoLancamento.criar_multimesh(no, ferro, aco)
	ComplexoLancamento.criar_multimesh(no, escuro, aco_escuro)
	ComplexoLancamento.criar_multimesh(no, cabos, aco_cabo, false)
	ComplexoLancamento.criar_multimesh(no, listras, listra_m)
	_instancias_de(no, rebite, rebites, aco)
	_instancias_de(no, tubo, tubos, aco_escuro)
	_instancias_de(no, cone, cones, aco_escuro)
	var vidro_m := StandardMaterial3D.new()
	vidro_m.albedo_color = Color(1.0, 0.7, 0.3)
	vidro_m.emission_enabled = true
	vidro_m.emission = Color(1.0, 0.55, 0.15)
	vidro_m.emission_energy_multiplier = 5.0
	_instancias_de(no, tubo, vidros, vidro_m)
	var verde := StandardMaterial3D.new()
	verde.albedo_color = Color(0.13, 0.3, 0.09)
	verde.roughness = 1.0
	var verde_talo := StandardMaterial3D.new()
	verde_talo.albedo_color = Color(0.09, 0.15, 0.06)
	verde_talo.roughness = 1.0
	ComplexoLancamento.criar_multimesh(no, talos, verde_talo, false)
	ComplexoLancamento.criar_multimesh(no, folhagem, verde, false)
	_instancias_de(no, Vegetacao.malhas(Vegetacao.Tipo.SAMAMBAIA)[0], fetos, Vegetacao.material(Vegetacao.Tipo.SAMAMBAIA))
	for par: Array in telas:
		var mi := _malha(no, quadro, tela_m, par[0])
		mi.set_instance_shader_parameter("tamanho", par[1])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ComplexoLancamento.adicionar_colisoes(est, colisao)


# ------------------------------------------------------------------ portão do recinto

## Multimesh de uma malha qualquer (rebites, espetos, dobradiças) em `pai`, em coordenadas locais dele.
func _instancias_de(pai: Node, malha: Mesh, xfs: Array[Transform3D], mat: Material) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = malha
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	pai.add_child(mmi)


## Portão do recinto (armadilha; refeito a pedido do dono a partir de uma arte de referência, tudo em
## geometria de verdade): dois pilares de pedra em blocos, mais largos embaixo, com musgo, rachaduras,
## marcas de garra, três tochas de ferro cada e cipós; viga de aço rebitada com espetos e guarda-corpo em
## cima; e duas folhas pesadas de aço enferrujado — moldura, travessas em X, grade de barras, dobradiças,
## rebites e caixa da tranca com luz — que GIRAM nas dobradiças e batem fechando a pista. Sinaleiro
## vermelho/verde na face de dentro de cada pilar. O portão é a frente de uma jaula de aço de 11 m: mais
## dois pilares atrás e paredes laterais de grade (as folhas abrem para dentro dela). item = [trecho, m, fase, nome].
func _montar_portao(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var periodo := float(cfg.get("periodo", 6.5))
	var c := sub.amostra(i)
	var b := _base(i)
	var lat := sub.lateral_em(i)
	var meia := sub.largura_em(i) * 0.5
	var no := _no("Portao")
	var alto := 11.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5200 + i
	var ruido := Terreno._textura_ruido(0.05, 4, 71)
	var pedra_m := ShaderMaterial.new()
	pedra_m.shader = load("res://shaders/muro_pedra.gdshader")
	pedra_m.set_shader_parameter("ruido", ruido)
	pedra_m.set_shader_parameter("cor_pedra", Color(0.3, 0.28, 0.23))
	pedra_m.set_shader_parameter("cor_argamassa", Color(0.1, 0.1, 0.08))
	pedra_m.set_shader_parameter("fiada", 1.4)
	pedra_m.set_shader_parameter("altura_chao", c.y - 60.0)
	pedra_m.set_shader_parameter("musgo", 0.9)
	pedra_m.set_shader_parameter("rachaduras", 1.0)
	var aco := ShaderMaterial.new()
	aco.shader = load("res://shaders/metal_gasto.gdshader")
	aco.set_shader_parameter("ruido", Terreno._textura_ruido(0.03, 4, 61))
	aco.set_shader_parameter("ferrugem", 0.55)
	aco.set_shader_parameter("cor_tinta", Color(0.16, 0.155, 0.15))
	aco.set_shader_parameter("cor_ferrugem", Color(0.2, 0.1, 0.05))
	aco.set_shader_parameter("cor_ferrugem_clara", Color(0.36, 0.2, 0.09))
	aco.set_shader_parameter("cor_poeira", Color(0.25, 0.2, 0.15))
	aco.set_shader_parameter("altura_chao", c.y - 60.0)
	var aco_escuro: ShaderMaterial = aco.duplicate()
	aco_escuro.set_shader_parameter("cor_tinta", Color(0.07, 0.07, 0.07))
	aco_escuro.set_shader_parameter("ferrugem", 0.5)
	var rebite := SphereMesh.new()
	rebite.radius = 0.5
	rebite.height = 0.6
	rebite.radial_segments = 8
	rebite.rings = 4
	var espeto := CylinderMesh.new()
	espeto.top_radius = 0.0
	espeto.bottom_radius = 0.5
	espeto.height = 1.0
	espeto.radial_segments = 4
	espeto.rings = 1
	var tubo := CylinderMesh.new()
	tubo.top_radius = 0.5
	tubo.bottom_radius = 0.5
	tubo.height = 1.0
	tubo.radial_segments = 10
	tubo.rings = 1
	var hx := meia + 0.5          # dobradiça (distância do eixo da estrada)
	var pedra: Array[Transform3D] = []
	var ferro: Array[Transform3D] = []
	var rebites: Array[Transform3D] = []
	var espetos: Array[Transform3D] = []
	var tubos: Array[Transform3D] = []
	var colunas: Array[Transform3D] = []
	var colisao: Array[Transform3D] = []
	var talos: Array[Transform3D] = []
	var folhagem: Array[Transform3D] = []
	var olhos := []
	var alt_pilar := alto + 2.6
	for s: float in [-1.0, 1.0]:
		# Pilar: seis blocos empilhados, cada um mais estreito e um pouco torto (a face de dentro fica a prumo)
		const BLOCOS := 6
		var y0 := -0.6
		for k in BLOCOS:
			var u := float(k) / (BLOCOS - 1)
			var w := lerpf(6.0, 3.4, u) + rng.randf_range(-0.15, 0.15)
			var d := lerpf(5.6, 3.8, u) + rng.randf_range(-0.15, 0.15)
			var h := (alt_pilar + 0.6) / BLOCOS
			var xf := Transform3D(b * Basis(Vector3.UP, rng.randf_range(-0.025, 0.025)) * Basis.from_scale(Vector3(w, h + 0.02, d)), c + lat * s * (hx + 0.9 + w * 0.5) + Vector3.UP * (y0 + h * 0.5))
			pedra.append(xf)
			colisao.append(xf)
			y0 += h
		_ao_chao(no, c + lat * s * (hx + 3.9) - Vector3.UP * 0.6, 5.6, colunas)
		# Batente de aço na face de dentro, com rebites, onde as dobradiças prendem
		ferro.append(Transform3D(b * Basis.from_scale(Vector3(1.0, alto + 0.6, 1.5)), c + lat * s * (hx + 0.45) + Vector3.UP * ((alto + 0.6) * 0.5)))
		for k in 12:
			rebites.append(Transform3D(b * Basis.from_scale(Vector3(0.22, 0.22, 0.22)), c + lat * s * (hx + 0.45) + Vector3.UP * (0.6 + k * (alto - 0.6) / 11.0) - b.z * (-0.78)))
			rebites.append(Transform3D(b * Basis.from_scale(Vector3(0.22, 0.22, 0.22)), c + lat * s * (hx + 0.45) + Vector3.UP * (0.6 + k * (alto - 0.6) / 11.0) + b.z * (-0.78)))
		# Cintas de aço abraçando o pilar e marcas de garra na pedra
		for fy: float in [0.3, 0.62]:
			var wc := lerpf(6.0, 3.4, fy) + 0.25
			ferro.append(Transform3D(b * Basis.from_scale(Vector3(wc, 0.45, lerpf(5.6, 3.8, fy) + 0.25)), c + lat * s * (hx + 0.9 + wc * 0.5 - 0.12) + Vector3.UP * (alt_pilar * fy)))
		for face: float in [-1.0, 1.0]:
			for k in 3:
				_malha(no, _caixa(Vector3(0.16, 2.2 - 0.3 * k, 0.12)), aco_escuro, Transform3D(b * Basis(Vector3.BACK, 0.45 * s * face), c + lat * s * (hx + 2.2 + 0.4 * k) + Vector3.UP * (alt_pilar * 0.78 - 0.2 * k) + b.z * face * 2.02))
		# Sinaleiro vermelho/verde na face de dentro (dos dois lados da pista) e caixa dele
		for face: float in [-1.0, 1.0]:
			ferro.append(Transform3D(b * Basis.from_scale(Vector3(0.5, 1.9, 0.9)), c + lat * s * (hx + 0.7) + Vector3.UP * 5.6 + b.z * face * 1.3))
			olhos.append(_lampada(no, c + lat * s * (hx + 0.7) + Vector3.UP * 6.05 + b.z * face * 1.8, 0.3))
			olhos.append(_lampada(no, c + lat * s * (hx + 0.7) + Vector3.UP * 5.15 + b.z * face * 1.8, 0.3))
		# Tochas: três cestos de ferro por pilar, nas duas faces, com fogo e uma luz
		for k in 3:
			var u := (k + 0.6) / 3.2
			var wq := lerpf(6.0, 3.4, u)
			for face: float in [1.0]:
				var pt := c + lat * s * (hx + 0.9 + wq * 0.55) + Vector3.UP * (alt_pilar * u) + b.z * face * (lerpf(5.6, 3.8, u) * 0.5 + 0.55)
				ferro.append(Transform3D(b * Basis.from_scale(Vector3(0.14, 0.14, 0.7)), pt - b.z * face * 0.35 - Vector3.UP * 0.1))
				tubos.append(Transform3D(Basis.from_scale(Vector3(1.1, 0.14, 1.1)), pt))
				tubos.append(Transform3D(Basis.from_scale(Vector3(1.2, 0.1, 1.2)), pt + Vector3.UP * 0.75))
				for q in 6:
					var aq := TAU * q / 6.0
					tubos.append(Transform3D(Basis.from_scale(Vector3(0.09, 0.8, 0.09)), pt + Vector3(cos(aq), 0.0, sin(aq)) * 0.55 + Vector3.UP * 0.38))
				Fogo.criar(no, pt + Vector3.UP * 0.2, 0.3, 1.5, 16, 0.75, false)
			var luz := OmniLight3D.new()
			luz.light_color = Color(1.0, 0.55, 0.2)
			luz.light_energy = 1.5
			luz.omni_range = 12.0
			luz.shadow_enabled = false
			luz.position = c + lat * s * (hx - 1.0) + Vector3.UP * (alt_pilar * u)
			no.add_child(luz)
		# Fogo grande no alto do pilar
		tubos.append(Transform3D(Basis.from_scale(Vector3(2.0, 0.9, 2.0)), c + lat * s * (hx + 2.6) + Vector3.UP * (alt_pilar + 0.45)))
		Fogo.criar(no, c + lat * s * (hx + 2.6) + Vector3.UP * (alt_pilar + 0.8), 0.6, 3.0, 30, 1.4)
		# Cipós escorrendo pelo pilar
		for k in 16:
			var face := -1.0 if k % 2 == 0 else 1.0
			var u := rng.randf_range(0.45, 1.0)
			var comp_c := rng.randf_range(2.0, 6.0)
			var topo_c := c + lat * s * (hx + 0.9 + rng.randf_range(0.3, lerpf(6.0, 3.4, u) - 0.3)) + Vector3.UP * (alt_pilar * u) + b.z * face * (lerpf(5.6, 3.8, u) * 0.5 + 0.12)
			talos.append(Transform3D(Basis.from_scale(Vector3(0.07, comp_c, 0.07)), topo_c + Vector3.DOWN * comp_c * 0.5))
			for q in int(comp_c * 3.0) + 2:
				var giro := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.7, 0.7))
				folhagem.append(Transform3D(giro * Basis.from_scale(Vector3(rng.randf_range(0.35, 0.7), 0.04, rng.randf_range(0.25, 0.45))), topo_c + Vector3.DOWN * rng.randf_range(0.0, comp_c) + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))))
	# Viga de aço de pilar a pilar: caixão com abas, rebites, espetos em cima e guarda-corpo
	var larg_v := hx * 2.0 + 2.6
	var viga := Transform3D(b * Basis.from_scale(Vector3(larg_v, 1.3, 1.8)), c + Vector3.UP * (alto + 1.25))
	ferro.append(viga)
	colisao.append(viga)
	ferro.append(Transform3D(b * Basis.from_scale(Vector3(larg_v + 0.3, 0.22, 2.2)), c + Vector3.UP * (alto + 0.6)))
	ferro.append(Transform3D(b * Basis.from_scale(Vector3(larg_v + 0.3, 0.22, 2.2)), c + Vector3.UP * (alto + 1.9)))
	ferro.append(Transform3D(b * Basis.from_scale(Vector3(1.3, 1.7, 2.3)), c + Vector3.UP * (alto + 1.25)))
	var n_r := int(larg_v / 0.7)
	for k in n_r:
		var x := lerpf(-larg_v * 0.5 + 0.4, larg_v * 0.5 - 0.4, float(k) / (n_r - 1))
		for face: float in [-1.0, 1.0]:
			for dy: float in [-0.4, 0.4]:
				rebites.append(Transform3D(b * Basis.from_scale(Vector3(0.2, 0.2, 0.2)), c + lat * x + Vector3.UP * (alto + 1.25 + dy) + b.z * face * 0.92))
	var n_e := int(larg_v / 1.1)
	for k in n_e:
		var x := lerpf(-larg_v * 0.5 + 0.7, larg_v * 0.5 - 0.7, float(k) / (n_e - 1))
		espetos.append(Transform3D(b * Basis.from_scale(Vector3(0.7, 1.1, 0.7)), c + lat * x + Vector3.UP * (alto + 2.55)))
	for k in 7:
		var x := lerpf(-larg_v * 0.5 + 0.3, larg_v * 0.5 - 0.3, k / 6.0)
		tubos.append(Transform3D(Basis.from_scale(Vector3(0.16, 2.3, 0.16)), c + lat * x + Vector3.UP * (alto + 3.1) - b.z * 0.9))
	for dy: float in [2.7, 3.4, 4.1]:
		ferro.append(Transform3D(b * Basis.from_scale(Vector3(larg_v - 0.4, 0.09, 0.09)), c + Vector3.UP * (alto + dy) - b.z * 0.9))
	# Jaula (segundo ângulo da referência): o portão é a frente de uma caixa de aço — mais dois pilares
	# atrás, paredes laterais de grade com tubos e travessas em X, viga de trás e guarda-corpo em toda a volta
	const FUNDO := 11.0
	var tras := c - b.z * FUNDO
	for s: float in [-1.0, 1.0]:
		var y1 := -0.6
		for k in 6:
			var u := float(k) / 5.0
			var w := lerpf(6.0, 3.4, u) + rng.randf_range(-0.15, 0.15)
			var d := lerpf(5.6, 3.8, u) + rng.randf_range(-0.15, 0.15)
			var h := (alt_pilar + 0.6) / 6.0
			var xf := Transform3D(b * Basis(Vector3.UP, rng.randf_range(-0.025, 0.025)) * Basis.from_scale(Vector3(w, h + 0.02, d)), tras + lat * s * (hx + 0.9 + w * 0.5) + Vector3.UP * (y1 + h * 0.5))
			pedra.append(xf)
			colisao.append(xf)
			y1 += h
		_ao_chao(no, tras + lat * s * (hx + 3.9) - Vector3.UP * 0.6, 5.6, colunas)
		for fy: float in [0.3, 0.62]:
			var wc := lerpf(6.0, 3.4, fy) + 0.25
			ferro.append(Transform3D(b * Basis.from_scale(Vector3(wc, 0.45, lerpf(5.6, 3.8, fy) + 0.25)), tras + lat * s * (hx + 0.9 + wc * 0.5 - 0.12) + Vector3.UP * (alt_pilar * fy)))
		tubos.append(Transform3D(Basis.from_scale(Vector3(2.0, 0.9, 2.0)), tras + lat * s * (hx + 2.6) + Vector3.UP * (alt_pilar + 0.45)))
		Fogo.criar(no, tras + lat * s * (hx + 2.6) + Vector3.UP * (alt_pilar + 0.8), 0.6, 3.0, 30, 1.4)
		for k in 3:
			var u := (k + 0.6) / 3.2
			var pt := tras + lat * s * (hx + 0.9 + lerpf(6.0, 3.4, u) * 0.55) + Vector3.UP * (alt_pilar * u) - b.z * (lerpf(5.6, 3.8, u) * 0.5 + 0.55)
			ferro.append(Transform3D(b * Basis.from_scale(Vector3(0.14, 0.14, 0.7)), pt + b.z * 0.35 - Vector3.UP * 0.1))
			tubos.append(Transform3D(Basis.from_scale(Vector3(1.1, 0.14, 1.1)), pt))
			tubos.append(Transform3D(Basis.from_scale(Vector3(1.2, 0.1, 1.2)), pt + Vector3.UP * 0.75))
			for q in 6:
				var aq := TAU * q / 6.0
				tubos.append(Transform3D(Basis.from_scale(Vector3(0.09, 0.8, 0.09)), pt + Vector3(cos(aq), 0.0, sin(aq)) * 0.55 + Vector3.UP * 0.38))
			Fogo.criar(no, pt + Vector3.UP * 0.2, 0.3, 1.5, 16, 0.75, false)
		# Parede lateral: moldura, tubos grossos deitados, grade de barras e duas travessas em X
		var xp := hx + 1.5
		var meio_p := c - b.z * (FUNDO * 0.5) + lat * s * xp
		var comp_p := FUNDO - 3.6
		for y: float in [0.4, alto + 0.3]:
			ferro.append(Transform3D(b * Basis.from_scale(Vector3(0.7, 0.8, comp_p + 0.6)), meio_p + Vector3.UP * y))
		for k in 7:
			tubos.append(Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.5, comp_p, 0.5)), meio_p + Vector3.UP * (1.5 + k * (alto - 2.4) / 6.0) + lat * s * 0.2))
		for k in int(comp_p / 0.5):
			ferro.append(Transform3D(b * Basis.from_scale(Vector3(0.08, alto, 0.08)), meio_p - b.z * (-comp_p * 0.5 + 0.25 + k * 0.5) + Vector3.UP * (alto * 0.5 + 0.3)))
		var ang_p := atan2(alto - 0.6, comp_p)
		for sinal: float in [-1.0, 1.0]:
			ferro.append(Transform3D(b * Basis(Vector3.RIGHT, ang_p * sinal) * Basis.from_scale(Vector3(0.4, 0.75, Vector2(comp_p, alto - 0.6).length())), meio_p + Vector3.UP * (alto * 0.5 + 0.35) - lat * s * 0.25))
		colisao.append(Transform3D(b * Basis.from_scale(Vector3(0.9, alto + 0.6, comp_p)), meio_p + Vector3.UP * (alto * 0.5 + 0.3)))
		# Viga de cima ligando os pilares da frente e de trás, com espetos, e o guarda-corpo do lado
		ferro.append(Transform3D(b * Basis.from_scale(Vector3(1.6, 1.3, FUNDO)), meio_p + Vector3.UP * (alto + 1.25) - lat * s * 0.6))
		for k in 9:
			espetos.append(Transform3D(b * Basis.from_scale(Vector3(0.7, 1.1, 0.7)), meio_p - b.z * (-FUNDO * 0.5 + 1.0 + k * (FUNDO - 2.0) / 8.0) + Vector3.UP * (alto + 2.45) - lat * s * 0.6))
		for k in 5:
			tubos.append(Transform3D(Basis.from_scale(Vector3(0.16, 2.3, 0.16)), meio_p - b.z * (-FUNDO * 0.5 + 0.9 + k * (FUNDO - 1.8) / 4.0) + Vector3.UP * (alto + 3.1) - lat * s * 0.1))
		for dy: float in [2.7, 3.4, 4.1]:
			ferro.append(Transform3D(b * Basis.from_scale(Vector3(0.09, 0.09, FUNDO - 1.6)), meio_p + Vector3.UP * (alto + dy) - lat * s * 0.1))
	# Viga de trás (sem folhas: a saída fica livre) com espetos e guarda-corpo
	var viga_t := Transform3D(b * Basis.from_scale(Vector3(larg_v, 1.3, 1.8)), tras + Vector3.UP * (alto + 1.25))
	ferro.append(viga_t)
	colisao.append(viga_t)
	for k in n_e:
		espetos.append(Transform3D(b * Basis.from_scale(Vector3(0.7, 1.1, 0.7)), tras + lat * lerpf(-larg_v * 0.5 + 0.7, larg_v * 0.5 - 0.7, float(k) / (n_e - 1)) + Vector3.UP * (alto + 2.55)))
	for k in 7:
		tubos.append(Transform3D(Basis.from_scale(Vector3(0.16, 2.3, 0.16)), tras + lat * lerpf(-larg_v * 0.5 + 0.3, larg_v * 0.5 - 0.3, k / 6.0) + Vector3.UP * (alto + 3.1) + b.z * 0.9))
	for dy: float in [2.7, 3.4, 4.1]:
		ferro.append(Transform3D(b * Basis.from_scale(Vector3(larg_v - 0.4, 0.09, 0.09)), tras + Vector3.UP * (alto + dy) + b.z * 0.9))
	ComplexoLancamento.criar_multimesh(no, pedra, pedra_m)
	ComplexoLancamento.criar_multimesh(no, colunas, pedra_m)
	ComplexoLancamento.criar_multimesh(no, ferro, aco)
	_instancias_de(no, rebite, rebites, aco)
	_instancias_de(no, espeto, espetos, aco_escuro)
	_instancias_de(no, tubo, tubos, aco_escuro)
	var verde := StandardMaterial3D.new()
	verde.albedo_color = Color(0.13, 0.3, 0.09)
	verde.roughness = 1.0
	var verde_talo := StandardMaterial3D.new()
	verde_talo.albedo_color = Color(0.09, 0.15, 0.06)
	verde_talo.roughness = 1.0
	ComplexoLancamento.criar_multimesh(no, talos, verde_talo, false)
	ComplexoLancamento.criar_multimesh(no, folhagem, verde, false)
	var est := _corpo_mortal(no)
	ComplexoLancamento.adicionar_colisoes(est, colisao)
	# Nome do recinto numa chapa de aço no meio da viga, dos dois lados
	for face: float in [-1.0, 1.0]:
		var nome := Label3D.new()
		nome.text = str(item[3]) if item.size() > 3 else "RECINTO 07"
		nome.font_size = 200
		nome.pixel_size = 0.85 / 200.0
		nome.modulate = Color(1.0, 0.75, 0.4)
		nome.outline_size = 18
		nome.outline_modulate = Color(0.08, 0.04, 0.02)
		nome.double_sided = false
		nome.transform = Transform3D(Basis.looking_at(-b.z * face, Vector3.UP), (c if face > 0.0 else c - b.z * 11.0) + Vector3.UP * (alto + 1.25) + b.z * face * 1.2)
		no.add_child(nome)
	# Folhas: em coordenadas locais — x de 0 (dobradiça) até L (meio da pista), y para cima, espessura em z
	var folhas := []
	var larg_f := hx - 0.06
	var alt_f := alto - 0.2
	for s: float in [-1.0, 1.0]:
		var corpo := _corpo_mortal(no, true)
		var pecas: Array[Transform3D] = []
		var barras: Array[Transform3D] = []
		var reb: Array[Transform3D] = []
		var dob: Array[Transform3D] = []
		# Moldura: dois montantes, travessas de cima, do meio e de baixo
		for x: float in [0.4, larg_f - 0.4]:
			pecas.append(Transform3D(Basis.from_scale(Vector3(0.8, alt_f, 0.5)), Vector3(x, alt_f * 0.5, 0.0)))
		var y_meio := alt_f * 0.42
		for par: Array in [[0.45, 0.9], [y_meio, 1.0], [alt_f - 0.45, 0.9]]:
			pecas.append(Transform3D(Basis.from_scale(Vector3(larg_f, float(par[1]), 0.56)), Vector3(larg_f * 0.5, float(par[0]), 0.0)))
		# Travessas em diagonal nos dois painéis (formam o X com a outra folha)
		for painel: Array in [[0.9, y_meio - 0.5, 1.0], [y_meio + 0.5, alt_f - 0.9, -1.0]]:
			var ya: float = painel[0]
			var yb: float = painel[1]
			var dx := larg_f - 1.6
			var ang := atan2(yb - ya, dx) * float(painel[2])
			pecas.append(Transform3D(Basis(Vector3.BACK, ang) * Basis.from_scale(Vector3(Vector2(dx, yb - ya).length(), 0.75, 0.62)), Vector3(larg_f * 0.5, (ya + yb) * 0.5, 0.0)))
			# Grade: barras em pé e deitadas atrás das travessas
			var n_v := int(dx / 0.42)
			for k in n_v:
				barras.append(Transform3D(Basis.from_scale(Vector3(0.07, yb - ya, 0.07)), Vector3(0.8 + dx * (k + 0.5) / n_v, (ya + yb) * 0.5, 0.0)))
			var n_h := int((yb - ya) / 0.55)
			for k in n_h:
				barras.append(Transform3D(Basis.from_scale(Vector3(dx, 0.09, 0.09)), Vector3(larg_f * 0.5, ya + (yb - ya) * (k + 0.5) / n_h, 0.06)))
		# Chapas de canto, rebites na moldura e nas travessas
		for x: float in [0.75, larg_f - 0.75]:
			for y: float in [0.8, alt_f - 0.8]:
				pecas.append(Transform3D(Basis.from_scale(Vector3(1.5, 1.6, 0.66)), Vector3(x, y, 0.0)))
		for face: float in [-1.0, 1.0]:
			for k in 16:
				for x: float in [0.4, larg_f - 0.4]:
					reb.append(Transform3D(Basis.from_scale(Vector3(0.2, 0.2, 0.2)), Vector3(x, 0.5 + k * (alt_f - 1.0) / 15.0, face * 0.27)))
			for k in 8:
				for y: float in [0.45, y_meio, alt_f - 0.45]:
					reb.append(Transform3D(Basis.from_scale(Vector3(0.2, 0.2, 0.2)), Vector3(1.0 + k * (larg_f - 2.0) / 7.0, y, face * 0.3)))
		# Dobradiças (três, com as abas) e a caixa da tranca com a luz vermelha
		for fy: float in [0.12, 0.5, 0.88]:
			dob.append(Transform3D(Basis.from_scale(Vector3(0.5, 1.3, 0.5)), Vector3(-0.05, alt_f * fy, 0.0)))
			pecas.append(Transform3D(Basis.from_scale(Vector3(1.3, 0.8, 0.7)), Vector3(0.6, alt_f * fy, 0.0)))
		pecas.append(Transform3D(Basis.from_scale(Vector3(0.9, 1.0, 0.9)), Vector3(larg_f - 0.75, y_meio, 0.0)))
		# Espetos (pedido do dono, por captura: "para fazer sentido o carro morrer quando colide"): cinco réguas de
		# aço atravessando o painel de baixo, na altura do carro, cada uma com uma fileira de pontas nas duas faces —
		# maiores na face que recebe quem chega (a mesma que fica virada para a pista com a folha aberta)
		var pontas: Array[Transform3D] = []
		const PONTA_FRENTE := 0.85
		const PONTA_TRAS := 0.6
		var face_frente := -s
		for fila in 5:
			var y := 0.95 + fila * 0.75
			pecas.append(Transform3D(Basis.from_scale(Vector3(larg_f - 1.0, 0.34, 0.7)), Vector3(larg_f * 0.5, y, 0.0)))
			var n_p := 7 - fila % 2
			for k in n_p:
				var x := lerpf(1.0, larg_f - 0.75, (k + 0.5 * (fila % 2)) / 6.0)
				for face: float in [-1.0, 1.0]:
					var comp_p := PONTA_FRENTE if face == face_frente else PONTA_TRAS
					pontas.append(Transform3D(Basis(Vector3.RIGHT, face * PI * 0.5) * Basis.from_scale(Vector3(0.42, comp_p, 0.42)), Vector3(x, y, face * (0.35 + comp_p * 0.5))))
		ComplexoLancamento.criar_multimesh(corpo, pecas, aco)
		ComplexoLancamento.criar_multimesh(corpo, barras, aco_escuro)
		_instancias_de(corpo, rebite, reb, aco)
		_instancias_de(corpo, tubo, dob, aco_escuro)
		_instancias_de(corpo, espeto, pontas, _mat_ouro)   # aço claro: as pontas brilham à luz das tochas
		_forma_caixa(corpo, Vector3(larg_f - 1.2, 3.6, 0.7 + PONTA_FRENTE + PONTA_TRAS), Transform3D(Basis.IDENTITY, Vector3(larg_f * 0.5, 2.45, face_frente * (PONTA_FRENTE - PONTA_TRAS) * 0.5)))
		for face: float in [-1.0, 1.0]:
			(_lampada(corpo, Vector3(larg_f - 0.75, y_meio, face * 0.48), 0.16) as StandardMaterial3D).emission = Color(1.0, 0.08, 0.04)
		_forma_caixa(corpo, Vector3(larg_f, alt_f, 0.6), Transform3D(Basis.IDENTITY, Vector3(larg_f * 0.5, alt_f * 0.5, 0.0)))
		folhas.append([corpo, s])
	_portoes.append({"tipo": "portao_dino", "i": i, "s": sub.progresso_amostra(i), "comp": larg_f + 1.0, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": periodo, "fecha": float(cfg.get("fecha_s", 0.6)), "fechada": float(cfg.get("fechada_s", 1.2)), "abre": float(cfg.get("abre_s", 1.3)),
		"c": c, "b": b, "lat": lat, "meia": meia, "hx": hx, "folhas": folhas, "olhos": olhos, "total": true})


func _portao_e(g: Dictionary, t: float) -> float:
	var f := fposmod(t + float(g.fase), float(g.periodo))
	var fecha: float = g.fecha
	var fechada: float = g.fechada
	var abre: float = g.abre
	if f < fecha:
		return pow(f / fecha, 2.0)
	if f < fecha + fechada:
		return 1.0
	if f < fecha + fechada + abre:
		return 1.0 - smoothstep(fecha + fechada, fecha + fechada + abre, f)
	return 0.0


func _animar_portao(g: Dictionary) -> void:
	var e := _portao_e(g, _t)
	var bb: Basis = g.b
	var adiante := -bb.z
	# As folhas giram nas dobradiças: abertas ficam ao longo da beirada, para a frente; fechando, batem no meio
	var ang := (1.0 - e) * PI * 0.5
	for par: Array in g.folhas:
		var s: float = par[1]
		var eixo_x := (-(g.lat as Vector3) * s * cos(ang) + adiante * sin(ang)).normalized()
		(par[0] as AnimatableBody3D).global_transform = Transform3D(Basis(eixo_x, Vector3.UP, eixo_x.cross(Vector3.UP)), (g.c as Vector3) + (g.lat as Vector3) * s * float(g.hx) + Vector3.UP * 0.1)
	var perigo := _portao_e(g, _t + 1.0) > 0.05 or e > 0.05
	for k in (g.olhos as Array).size():
		var m: StandardMaterial3D = g.olhos[k]
		var vermelha := k % 2 == 0
		m.emission = (Color(1.0, 0.08, 0.04) if vermelha else Color(0.25, 1.0, 0.35)) if vermelha == perigo else Color(0.03, 0.03, 0.03)


# ------------------------------------------------------------------ estouro de manada

## item = [trecho, m0, m1, fase]: os bichos descem do m1 até o m0 numa faixa de cada vez.
func _montar_estouro(item: Array, cfg: Dictionary) -> void:
	var i0 := sub.indice_trecho(str(item[0]), float(item[1]))
	var i1 := sub.indice_trecho(str(item[0]), float(item[2]))
	var vel := float(cfg.get("velocidade", 14.0))
	var periodo := float(cfg.get("periodo", 6.0))
	var no := Node3D.new()
	no.name = "Estouro%d" % _estouros.size()
	add_child(no)
	# Cerca do recinto arrebentada no alto do trecho, de onde eles saem em disparada
	var c := sub.amostra(i1)
	var b := _base(i1)
	var lat := sub.lateral_em(i1)
	var meia := sub.largura_em(i1) * 0.5
	var postes: Array[Transform3D] = []
	# Os postes da cerca ficam em cima de uma laje de concreto de cada lado da pista, com pilares até o chão
	# (antes estavam soltos no ar ao lado da estrada elevada)
	var lajes: Array[Transform3D] = []
	var pilares: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		for k in 4:
			postes.append(Transform3D(b * Basis(Vector3.BACK, s * 0.4 * (k % 2)) * Basis.from_scale(Vector3(0.4, 7.0, 0.4)), c + lat * s * (meia + 1.5 + k * 3.0) + Vector3.UP * 3.0))
		lajes.append(Transform3D(b * Basis.from_scale(Vector3(12.4, 1.2, 4.0)), c + lat * s * (meia + 6.2) + Vector3.DOWN * 0.65))
		for x: float in [3.0, 10.0]:
			_ao_chao(no, c + lat * s * (meia + x) + Vector3.DOWN * 1.25, 1.8, pilares)
	ComplexoLancamento.criar_multimesh(no, postes, Gelo.material(Gelo.Mat.ACO))
	var concreto_e := sub.material_concreto(c.y - 40.0)
	ComplexoLancamento.criar_multimesh(no, lajes, concreto_e)
	ComplexoLancamento.criar_multimesh(no, pilares, concreto_e)
	var est_e := StaticBody3D.new()
	est_e.collision_layer = 1
	est_e.collision_mask = 0
	est_e.add_to_group("estrutura")
	no.add_child(est_e)
	ComplexoLancamento.adicionar_colisoes(est_e, lajes)
	var lampadas := []
	for s: float in [-1.0, 1.0]:
		lampadas.append(_lampada(no, c + lat * s * (meia + 1.5) + Vector3.UP * 6.8, 0.5))
	var comp := sub.progresso_amostra(i1) - sub.progresso_amostra(i0)
	if OS.get_environment("TSC_DINO_LOG") != "":
		print("[ESTOURO] de %s até %s (pé), tangente %s" % [str(c), str(sub.amostra(i0)), str(sub.tangente_em(i0))])
	var qtd := int(ceil(comp / vel / periodo)) + 2
	var corpos := []
	var bichos := []
	var especies := ["ceratossauro", "carnotauro", "tiranossauro"]
	for k in qtd:
		var corpo := _corpo_mortal(no, true)
		# (comprimento maior a pedido do dono: os pequenos não se viam descendo a estrada)
		var comp_e := float(cfg.get("comprimento", 5.5))
		var d := DinosParque.criar(especies[k % especies.size()], comp_e)
		corpo.add_child(d.raiz)
		_forma_caixa(corpo, Vector3(1.8, 2.2, 5.0) * (comp_e / 5.5), Transform3D(Basis.IDENTITY, Vector3(0, 1.3 * comp_e / 5.5, 0)))
		# Etapa à noite: uma luz fria acompanha cada bicho (sem ela era um vulto escuro, visto só de perto)
		var luar := OmniLight3D.new()
		luar.light_color = Color(0.8, 0.9, 1.0)
		luar.light_energy = 6.0
		luar.omni_range = comp_e * 2.0
		luar.shadow_enabled = false
		luar.position = Vector3(0.0, comp_e * 0.75, -comp_e * 0.45)
		corpo.add_child(luar)
		corpo.visible = false
		corpos.append(corpo)
		bichos.append(d)
	_estouros.append({"i0": i0, "i1": i1, "s0": sub.progresso_amostra(i0), "s1": sub.progresso_amostra(i1), "fase": float(item[3]) if item.size() > 3 else 0.0,
		"periodo": periodo, "vel": vel, "raio": 1.6, "padrao": str(cfg.get("padrao", "alterna")), "pedras": corpos, "bichos": bichos, "lampadas": lampadas})


func _animar_estouros() -> void:
	for z: Dictionary in _estouros:
		var ativos := _pedras_em(z, _t)
		var usados := {}
		for a: Array in ativos:
			var k: int = posmod(int(a[0]), z.pedras.size())
			usados[k] = true
			var corpo: AnimatableBody3D = z.pedras[k]
			var s: float = a[1]
			var lado := 1.0 if int(a[2]) == 1 else -1.0
			var i := _indice_s(z, s)
			var p := sub.amostra(i) + sub.lateral_em(i) * lado * FAIXA
			# Corpo acompanhando a ladeira (antes ficava sempre na horizontal: as patas de trás entravam no asfalto)
			var frente := -sub.tangente_em(i)
			if a[3]:
				# Passou do pé do trecho: salta pela beirada, de focinho para onde vai, cai no chão lá embaixo e
				# segue correndo mato adentro (antes despencava de lado, na horizontal, e atravessava o chão)
				var tq := (float(z.s0) - s) / float(z.vel)
				var vel_s: Vector3 = sub.lateral_em(z.i0) * lado * float(z.vel) * 0.7 - sub.tangente_em(z.i0) * float(z.vel)
				p = sub.amostra(z.i0) + sub.lateral_em(z.i0) * lado * FAIXA + vel_s * tq + Vector3.UP * (6.0 * tq - 4.9 * tq * tq)
				frente = (vel_s + Vector3.UP * (6.0 - 9.8 * tq)).normalized()
				var chao := _terreno.altura_em(p.x, p.z)
				if p.y <= chao:
					p.y = chao
					frente = Vector3(vel_s.x, 0.0, vel_s.z).normalized()
			var b := Basis.looking_at(frente, Vector3.UP)
			if not corpo.visible:
				corpo.visible = true
				corpo.global_transform = Transform3D(b, p)
				corpo.reset_physics_interpolation()
			else:
				corpo.global_transform = Transform3D(b, p)
			# Passada presa ao chão percorrido (com o relógio os pés patinavam no asfalto)
			# (boca fechada e sem bote, a pedido do dono: os da ladeira não mordem — só os da travessia e do covil)
			DinosParque.andar(z.bichos[k], Transform3D(b, p), get_physics_process_delta_time())
		for k in z.pedras.size():
			if not usados.has(k):
				var corpo: AnimatableBody3D = z.pedras[k]
				if corpo.visible:
					corpo.visible = false
					corpo.global_position = Vector3(0, -500 - k * 10, 0)
		var aviso := false
		for a: Array in _pedras_em(z, _t + 1.2):
			if float(a[1]) > float(z.s1) - 2.0:
				aviso = true
		for m: StandardMaterial3D in z.lampadas:
			m.emission = Color(1.0, 0.08, 0.04) if aviso else Color(0.25, 1.0, 0.35)


## Bichos do estouro e pedras rolando na estrada à frente, para os bots.
func pedras_adiante(i: int, alcance := 200.0) -> Array:
	var lista := super.pedras_adiante(i, alcance)
	var s := sub.progresso_amostra(i)
	var k := sub.trecho_de(i)
	for z: Dictionary in _estouros:
		if sub.trecho_de(z.i0) != k or s > float(z.s1) + 5.0 or s + alcance < float(z.s0):
			continue
		for a: Array in _pedras_em(z, _t):
			if a[3]:
				continue
			var d: float = float(a[1]) - s
			if d > -6.0 and d < alcance:
				lista.append([d, int(a[2])])
	return lista


func em_ladeira(i: int, antes := 80.0) -> bool:
	if super.em_ladeira(i, antes):
		return true
	var s := sub.progresso_amostra(i)
	var k := sub.trecho_de(i)
	for z: Dictionary in _estouros:
		if sub.trecho_de(z.i0) == k and s > float(z.s0) - antes and s < float(z.s1):
			return true
	return false


# ------------------------------------------------------------------ pedaços do meteoro

## item = [trecho, m, fase]
func _montar_meteoro(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var periodo := float(cfg.get("periodo", 6.5))
	var c := sub.amostra(i)
	var t := sub.tangente_em(i)
	var lat := sub.lateral_em(i)
	var nrm := lat.cross(t).normalized()
	var b := Basis(lat, nrm, -t)
	var meia := sub.largura_em(i) * 0.5
	var no := _no("Meteoro")
	var avisos := []
	var crateras := []
	var bolas := []
	var luzes := []
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 3 + 1
	for lado in 2:
		var s := -1.0 if lado == 0 else 1.0
		var pc := c + lat * s * (meia * 0.5)
		avisos.append(_aviso(no, pc, b, Vector2(7.0, 7.0), Color(1.0, 0.1, 0.04)))
		var corpo := _corpo_mortal(no, true)
		_forma_caixa(corpo, Vector3(meia - 0.4, 2.0, 6.5), Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
		for k in 7:
			var tam := Vector3(rng.randf_range(1.0, 2.2), rng.randf_range(0.8, 1.6), rng.randf_range(1.0, 2.4))
			_malha(corpo, _caixa(tam), Dino.material_lava(0, 0.05, 0.35, 3.0, 4.0, 4.0, true) if k % 3 == 0 else _rocha,
				Transform3D(Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU), Vector3(rng.randf_range(-1.6, 1.6), tam.y * 0.4, rng.randf_range(-2.4, 2.4))))
		var fogo := _fagulhas(corpo, Color(1.0, 0.45, 0.1), 2.2, 6.0, 50)
		fogo.emitting = true
		corpo.visible = false
		crateras.append([corpo, pc])
		var bola := Meteoro.new()
		bola.tamanho = 1.8
		no.add_child(bola)
		bola.visible = false
		bolas.append(bola)
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.45, 0.12)
		luz.omni_range = 24.0
		luz.light_energy = 0.0
		luz.position = pc + nrm * 3.0
		no.add_child(luz)
		luzes.append(luz)
	_portoes.append({"tipo": "meteoro_pista", "i": i, "s": sub.progresso_amostra(i), "comp": 7.0, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": periodo, "aviso": float(cfg.get("aviso_s", 1.8)), "queima": float(cfg.get("queima_s", 3.0)), "base": b, "nrm": nrm, "t": t,
		"avisos": avisos, "crateras": crateras, "bolas": bolas, "luzes": luzes, "bateu": [false, false], "total": false})


func _meteoro_f(g: Dictionary, lado: int, t: float) -> float:
	var per: float = g.periodo
	return fposmod(t + float(g.fase) + (per * 0.5 if lado == 1 else 0.0), per)


func _perigo_meteoro(g: Dictionary, lado: int, t: float) -> bool:
	var f := _meteoro_f(g, lado, t)
	var av: float = g.aviso
	return f > av - 0.15 and f < av + float(g.queima) + 0.2


func _animar_meteoro(g: Dictionary) -> void:
	for lado in 2:
		var f := _meteoro_f(g, lado, _t)
		var av: float = g.aviso
		var qm: float = g.queima
		var par: Array = g.crateras[lado]
		var pc: Vector3 = par[1]
		var corpo: AnimatableBody3D = par[0]
		var bola: Meteoro = g.bolas[lado]
		var am: StandardMaterial3D = g.avisos[lado]
		# Queda: de 320 m de altura, inclinada, chegando no fim do aviso
		var caindo := f < av
		bola.visible = caindo
		if caindo:
			var u := f / av
			var dir := ((g.t as Vector3) * 0.6 + Vector3.UP).normalized()
			bola.mover_para(pc + dir * 320.0 * (1.0 - u))
		var a := 0.0
		if caindo:
			a = (0.5 + 0.5 * sin(_t * (8.0 + f * 10.0))) * smoothstep(0.0, av, f)
		am.emission_energy_multiplier = a * 4.0
		am.albedo_color.a = a
		var queimando := f >= av and f < av + qm + 0.5
		corpo.visible = queimando
		var y := 0.0 if f < av + qm else -2.5 * (f - av - qm) / 0.5
		corpo.global_transform = Transform3D(g.base, pc + (g.nrm as Vector3) * (y if queimando else -60.0))
		(g.luzes[lado] as OmniLight3D).light_energy = (6.0 * (1.0 - (f - av) / (qm + 0.5))) if queimando else (a * 2.0)
		var bateu := f >= av and f < av + 0.3
		if bateu and not g.bateu[lado]:
			var ex := Explosao.new()
			add_child(ex)
			ex.global_position = pc + (g.nrm as Vector3)
		g.bateu[lado] = bateu


# ------------------------------------------------------------------ avalanche de cinza em brasa

## item = [trecho, m0, m1, fase]: a nuvem desce do m0 até o m1 (no sentido da corrida, atrás de quem
## foge) a `velocidade` m/s, fica `dissipa_s` em cima do trecho e some até o próximo ciclo.
func _montar_avalanche(item: Array, cfg: Dictionary) -> void:
	var i0 := sub.indice_trecho(str(item[0]), float(item[1]))
	var i1 := sub.indice_trecho(str(item[0]), float(item[2]))
	var no := Node3D.new()
	no.name = "Avalanche%d" % _avalanches.size()
	add_child(no)
	var vel := float(cfg.get("velocidade", 22.0))
	var s0 := sub.progresso_amostra(i0)
	var s1 := sub.progresso_amostra(i1)
	var dur := (s1 - s0) / vel
	var dissipa := float(cfg.get("dissipa_s", 5.0))
	var periodo := maxf(float(cfg.get("periodo", 55.0)), dur + dissipa + 8.0)
	# Pórtico de aviso na entrada do trecho: sirenes e o letreiro
	var c := sub.amostra(i0)
	var b := _base(i0)
	var lat := sub.lateral_em(i0)
	var meia := sub.largura_em(i0) * 0.5
	var aco: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		var pe := c + lat * s * (meia + 1.8)
		aco.append_array(ComplexoLancamento.trelica(pe, pe + Vector3.UP * 11.0, 1.6, 2.4, 0.2, 0.08))
	aco.append_array(ComplexoLancamento.trelica(c - lat * (meia + 2.6) + Vector3.UP * 11.5, c + lat * (meia + 2.6) + Vector3.UP * 11.5, 1.6, 2.4, 0.2, 0.08))
	ComplexoLancamento.criar_multimesh(no, aco, Gelo.material(Gelo.Mat.VERMELHO))
	var nome := Label3D.new()
	nome.text = "ZONA DE FLUXO PIROCLÁSTICO"
	nome.font_size = 200
	nome.pixel_size = 1.5 / 200.0
	nome.modulate = Color(1.0, 0.6, 0.15)
	nome.outline_size = 18
	nome.outline_modulate = Color(0.05, 0.02, 0.0)
	nome.double_sided = false
	var t0 := sub.tangente_em(i0)
	nome.transform = Transform3D(Basis.looking_at(t0, Vector3.UP), c + Vector3.UP * 13.6 - t0 * 1.0)
	no.add_child(nome)
	var sirenes: Array[Transform3D] = []
	var i := i0
	while i < i1:
		var pi := sub.amostra(i)
		for s: float in [-1.0, 1.0]:
			sirenes.append(Transform3D(Basis.from_scale(Vector3(0.6, 0.6, 0.6)), pi + sub.lateral_em(i) * s * (sub.largura_em(i) * 0.5 + 0.4) + Vector3.UP * 0.5))
		i = sub.indice_adiante(i, 60.0)
		if i >= i1 - 1:
			break
	var mat_sirene := _brilho(Color(1.0, 0.12, 0.04), 0.0)
	ComplexoLancamento.criar_multimesh(no, sirenes, mat_sirene, false)
	# A nuvem: emissor que acompanha a frente pela estrada (fumaça grossa, base em brasa, brasas e pedras)
	var frente := Node3D.new()
	frente.name = "Frente"
	no.add_child(frente)
	var fumaca := GPUParticles3D.new()
	fumaca.amount = 220
	fumaca.lifetime = 7.0
	fumaca.local_coords = false
	fumaca.emitting = false
	fumaca.visibility_aabb = AABB(Vector3(-1500, -400, -1500), Vector3(3000, 800, 3000))
	var pf := ParticleProcessMaterial.new()
	pf.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pf.emission_box_extents = Vector3(45.0, 30.0, 10.0)
	pf.direction = Vector3.UP
	pf.spread = 50.0
	pf.initial_velocity_min = 3.0
	pf.initial_velocity_max = 10.0
	pf.gravity = Vector3(0, 1.0, 0)
	pf.damping_min = 0.5
	pf.damping_max = 1.0
	pf.scale_min = 28.0
	pf.scale_max = 55.0
	pf.angle_min = 0.0
	pf.angle_max = 360.0
	pf.angular_velocity_min = -10.0
	pf.angular_velocity_max = 10.0
	var cresce := Curve.new()
	cresce.add_point(Vector2(0.0, 0.5))
	cresce.add_point(Vector2(1.0, 1.8))
	var tc := CurveTexture.new()
	tc.curve = cresce
	pf.scale_curve = tc
	var grad := Gradient.new()
	grad.set_color(0, Color(0.95, 0.42, 0.12, 0.0))
	grad.add_point(0.06, Color(0.7, 0.3, 0.12, 0.95))
	grad.add_point(0.3, Color(0.22, 0.18, 0.16, 0.95))
	grad.set_color(grad.get_point_count() - 1, Color(0.3, 0.28, 0.27, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pf.color_ramp = gt
	fumaca.process_material = pf
	var quad := QuadMesh.new()
	var mf := StandardMaterial3D.new()
	mf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mf.vertex_color_use_as_albedo = true
	mf.albedo_texture = Selva._textura_nuvem()
	mf.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mf.billboard_keep_scale = true
	mf.proximity_fade_enabled = true
	mf.proximity_fade_distance = 10.0
	mf.roughness = 1.0
	quad.material = mf
	fumaca.draw_pass_1 = quad
	fumaca.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frente.add_child(fumaca)
	var brasas := _fagulhas(frente, Color(1.0, 0.5, 0.15), 30.0, 18.0, 260)
	(brasas.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	(brasas.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(40.0, 20.0, 8.0)
	brasas.lifetime = 2.5
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.42, 0.14)
	luz.omni_range = 120.0
	luz.light_energy = 0.0
	frente.add_child(luz)
	_avalanches.append({"i0": i0, "i1": i1, "s0": s0, "s1": s1, "vel": vel, "dur": dur, "dissipa": dissipa, "periodo": periodo,
		"fase": float(item[3]) if item.size() > 3 else 0.0, "frente": frente, "fumaca": fumaca, "brasas": brasas, "luz": luz, "sirene": mat_sirene,
		"trecho": sub.trecho_de(i0)})
	_portoes.append({"tipo": "avalanche", "i": i0, "s": s0, "comp": 12.0, "fase": float(item[3]) if item.size() > 3 else 0.0, "periodo": periodo,
		"z": _avalanches.size() - 1, "total": true})


## Progresso (s) da frente da nuvem no instante t e se ela está no trecho (-1 = sem nuvem).
func _frente_avalanche(z: Dictionary, t: float) -> float:
	var f := fposmod(t + float(z.fase), float(z.periodo))
	if f < float(z.dur):
		return float(z.s0) + f * float(z.vel)
	if f < float(z.dur) + float(z.dissipa):
		return float(z.s1)
	return -1.0


func _perigo_avalanche(g: Dictionary, t: float) -> bool:
	var z: Dictionary = _avalanches[int(g.z)]
	# Entrada do trecho tomada pela nuvem (ou ela vai começar em menos de 1 s)
	return _frente_avalanche(z, t) >= 0.0 or _frente_avalanche(z, t + 1.0) >= 0.0


func _animar_avalanches(delta: float) -> void:
	for z: Dictionary in _avalanches:
		var s := _frente_avalanche(z, _t)
		var ativa := s >= 0.0
		var fum: GPUParticles3D = z.fumaca
		var emite := ativa and s < float(z.s1) - 1.0
		if fum.emitting != emite:
			fum.emitting = emite
			(z.brasas as GPUParticles3D).emitting = emite
		var f := fposmod(_t + float(z.fase), float(z.periodo))
		var vai_vir := f > float(z.periodo) - 6.0
		(z.sirene as StandardMaterial3D).emission_energy_multiplier = (6.0 if fmod(_t, 0.5) < 0.25 else 0.5) if ativa or vai_vir else 0.0
		(z.luz as OmniLight3D).light_energy = move_toward((z.luz as OmniLight3D).light_energy, 8.0 if emite else 0.0, delta * 6.0)
		if not ativa:
			continue
		var i := _indice_s({"i0": z.i0, "i1": z.i1, "s0": z.s0, "s1": z.s1}, s)
		var p := sub.amostra(i)
		var chao := _terreno.altura_em(p.x, p.z)
		var frente: Node3D = z.frente
		var alto := maxf(p.y - chao, 20.0)
		frente.global_position = Vector3(p.x, chao + alto * 0.5 + 10.0, p.z)
		frente.basis = Basis.looking_at(sub.tangente_em(i), Vector3.UP) if sub.tangente_em(i).length() > 0.1 else Basis.IDENTITY
		var pm := fum.process_material as ParticleProcessMaterial
		pm.emission_box_extents = Vector3(55.0, alto * 0.5 + 25.0, 12.0)
		# Engole quem está dentro da nuvem (do começo do trecho até a frente)
		for no in get_tree().get_nodes_in_group("veiculo"):
			var v := no as Veiculo
			if v == null or v.eliminado or v.fantasma() or v.travado:
				continue
			var iv := sub.indice_estrada(v.global_position, 35.0)
			if iv < 0 or sub.trecho_de(iv) != int(z.trecho):
				continue
			var sv := sub.progresso_amostra(iv)
			if sv >= float(z.s0) - 4.0 and sv <= s:
				v.eliminar("avalanche")


# ------------------------------------------------------------------ animação e consultas

func _atualizar() -> void:
	super._atualizar()
	for g: Dictionary in _portoes:
		match g.tipo:
			"raptor": _animar_raptores(g)
			"cuspe": _animar_cuspe(g)
			"cortina": _animar_cortina(g)
			"mordida": _animar_mordida(g)
			"rocha": _animar_rochas(g)
			"lava_jato": _animar_lava(g)
			"eletrica": _animar_eletrica(g)
			"manada": _animar_manada(g)
			"portao_dino": _animar_portao(g)
			"meteoro_pista": _animar_meteoro(g)
	_animar_estouros()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_animar_avalanches(delta)


func _perigo(g: Dictionary, lado: int, t: float) -> bool:
	match g.tipo:
		"raptor": return _perigo_raptor(g, lado, t)
		"cuspe": return _perigo_cuspe(g, lado, t)
		"cortina": return _cortina_fechada(g, t, float(g.alt) - float(g.bojo) * 0.5)
		"mordida": return _perigo_mordida(g, t)
		"rocha": return _perigo_rocha(g, lado, t)
		"lava_jato": return _perigo_lava(g, lado, t)
		"eletrica": return _eletrica_ligada(g, lado, t)
		"manada": return _perigo_manada(g, lado, t)
		"portao_dino": return _portao_e(g, t) > 0.05
		"meteoro_pista": return _perigo_meteoro(g, lado, t)
		"avalanche": return _perigo_avalanche(g, t)
	return super._perigo(g, lado, t)


## Para as câmeras de conferência: inclui os estouros.
func posicoes() -> Array:
	var lista := super.posicoes()
	for z: Dictionary in _estouros:
		var i := sub.indice_adiante(int(z.i0), float(z.s1) - float(z.s0) - 40.0)
		lista.append([sub.amostra(i), sub.lateral_em(i), sub.tangente_em(i)])
	return lista
