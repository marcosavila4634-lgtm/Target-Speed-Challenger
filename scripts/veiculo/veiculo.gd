class_name Veiculo
extends RigidBody3D
## Veículo do Target Flight.
## - Suspensão por raios nas 4 rodas, aderência lateral e tração conforme o modelo.
## - Estados separados (dossiê, cap. 4): apoiado, balístico, planeio (paraquedas) e eliminado.
## - Ao tocar o alvo com qualquer parte: motor, nitro e ejetor bloqueados até o fim da etapa,
##   e o paraquedas fecha automaticamente.

signal tocou_alvo(v: Veiculo)
signal foi_eliminado(v: Veiculo)
signal ejetor_usado(v: Veiculo)
signal paraquedas_mudou(v: Veiculo, aberto: bool)
signal velame_murchou(v: Veiculo)
signal impulso_usado(v: Veiculo)
signal ressurgiu(v: Veiculo)

enum Estado { APOIADO, BALISTICO, PLANEIO, ELIMINADO }

const MASCARA_RAIO := 1 | 2


class Roda:
	var ancora := Vector3.ZERO
	var raio := 0.3
	var dianteira := false
	var tracionada := false
	var pivo: Node3D
	var compressao := 0.0
	var contato := false
	var giro := 0.0


# Identidade
var dados: Dictionary = {}
var nome_piloto := ""
var avatar_dados: Dictionary = {}   # piloto sentado ao volante (config/avatares.json)
var indice_equipe := 0
var cor_equipe := Color.WHITE
var eh_jogador := false
var terreno: Terreno
var complexo: ComplexoLancamento

## Comandos contínuos, preenchidos pelo controlador (jogador ou bot) a cada quadro.
var entrada := {"acelerar": 0.0, "freiar": 0.0, "re": 0.0, "direcao": 0.0, "nitro": false}

# Estado
var estado := Estado.APOIADO
var travado := false            # tocou o alvo nesta etapa
var eliminado := false
var paraquedas_aberto := false
var paraquedas_ja_aberto := false
var carga_nitro := 0.0
var nitro_ativo := false
var recarga_ejetor := 0.0
var tempo_no_ar := 0.0
var rodas_no_chao := 0
var contato_corpo := false
var contato_veiculo: Veiculo = null  # outro carro encostado neste passo de física (som de batida)
var no_alvo_agora := false
var relogio := 0.0
var ultimo_contato_alvo := -100.0
var rumo := 0.0                 # direção do planeio (radianos, 0 = -Z)
var saiu_da_rampa := false
var pq_bloqueado_ate := -100.0  # velame murcho por batida: só reabre depois deste instante (relógio)
var _impulso_espera := 0.0      # um tranco por seta (não repete enquanto passa por cima)
## Climb to Death: último ponto de checagem que passou (-1 = nenhum) e fantasma depois de ressurgir
## (pisca transparente, anda, mas não bate em outros carros).
var checkpoint := -1
var _fantasma := false
var _fantasma_ate := 0.0
var _geo_fantasma: Array = []
var _de_cabeca_t := 0.0          # tempo de cabeça para baixo parado (mapa com checkpoint: volta no último)
const DE_CABECA_S := 4.0
var _bateu_mortal := false       # encostou em peça do grupo "mortal" (túnel-atalho): explode

# Telemetria (resultado e teste automático)
var telemetria := {"altura_max": 0.0}
var na_largada := false         # só depois de preparar(): antes disso o carro está sendo montado (sem som)
## Drag Racing: o carro é só visual (congelado, movido pela simulação DragMotor). Sem o som
## daqui (o drag tem o seu, pela rotação real) e as rodas giram com esta velocidade (m/s) quando >= 0.
var sem_som := false
var vel_rodas_externa := -1.0

# Parâmetros
var curso := 0.2
var rigidez := 30000.0
var amortecimento := 2000.0
var aderencia := 1.1
var aceleracao := 5.0
var vel_max := 45.0
var freio := 9.0
## Pista de provas (TSC_TESTE_CURVA, ver Partida._teste_curva): quanto cada eixo está no limite
## de aderência, carga e giro pedido pelo volante. Só é preenchido nesse teste.
var diag := {}
static var _com_diag := OS.get_environment("TSC_TESTE_CURVA") != ""
var freando := false        # S segurado com freio instalado (o som não trata como ré)
var forca_re := 0.6          # fração da aceleração normal (a ré também é o "freio")
var vel_re := 8.0            # m/s
var zz_ganho := 1.1          # m/s² de desaceleração por unidade de "volante alternando" no alvo
var zz_max := 8.0            # desaceleração máxima do zigue-zague (m/s²)
var _volante_ant := 0.0
var _atividade_volante := 0.0
var direcao_max := deg_to_rad(32)
var _fator_peso := 1.0       # massa de fábrica / massa atual (upgrade de chassi)
var arrasto := 0.002
var g := 9.8

# Montagem
var modelo: Node3D
var rodas: Array[Roda] = []
var caixa_corpo := AABB()
var paraquedas: Paraquedas
var som: SomVeiculo
var piloto: Avatar
var _pontos_proj := PackedVector3Array()
var _direcao_suave := 0.0
var _entre_eixos := 2.6
## W+S juntos no chão (como no GTA): rodas de tração patinando no lugar; com A/D gira (cavalo de pau).
var borrachao := false
var _fumaca_pneus: Array[GPUParticles3D] = []
var _taxa_giro := 0.0
var _acc_frente := 0.0
var _vel_frente_ant := 0.0
var _pedido_ejetor := false
var _pedido_paraquedas := false
var _cfg := {}


func _ready() -> void:
	g = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	mass = float(dados.get("massa", 1000))
	collision_layer = 2
	collision_mask = 1 | 2
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = true
	can_sleep = false
	# Sem o amortecimento padrão da engine: a resistência vem só do arrasto do ar e do rolamento.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.55
	pm.bounce = 0.05
	physics_material_override = pm

	curso = float(dados.get("suspensao_curso", 0.2))
	aderencia = float(dados.get("aderencia", 1.1)) * float(Config.valor("fisica.aderencia_mult", 1.0))
	aceleracao = float(dados.get("aceleracao", 5.0))
	# Peso: as forças daqui são proporcionais à massa, então o peso só pesa em relação ao de
	# fábrica (upgrade de chassi): mais leve = mais arrancada e menos afundamento no paraquedas.
	_fator_peso = float(dados.get("massa_fabrica", mass)) / mass
	aceleracao *= _fator_peso
	vel_max = float(dados.get("velocidade_max_kmh", 160)) / 3.6
	freio = float(dados.get("freio", 9.0))
	forca_re = float(Config.valor("fisica.re_forca", 0.6))
	vel_re = float(Config.valor("fisica.re_velocidade_max_kmh", 30)) / 3.6
	zz_ganho = float(Config.valor("fisica.zigue_zague_ganho", 1.1))
	zz_max = float(Config.valor("fisica.zigue_zague_max", 8.0))
	direcao_max = deg_to_rad(float(dados.get("direcao_graus", 32)) * float(Config.valor("fisica.direcao_mult", 1.0)))
	arrasto = float(Config.valor("fisica.arrasto_ar", 0.002)) * float(dados.get("arrasto_mult", 1.0))
	_cfg = {
		"freios": Config.valor("regras.freios_instalados", true),
		"nitro": Config.valor("regras.nitro_instalado", true),
		"bloquear_ejetor": Config.valor("regras.bloquear_ejetor_no_alvo", true),
		"ejetor_sempre": bool(Config.valor("regras.ejetor_sempre", false)),
		# Nitro e ejetor: valor do carro (com upgrades, ver Progresso.aplicar) ou o padrão do jogo.json
		"ejetor_impulso": float(dados.get("ejetor_impulso", Config.valor("fisica.ejetor_impulso", 12))),
		"ejetor_recarga": float(Config.valor("fisica.ejetor_recarga", 1.0)),
		"nitro_duracao": float(dados.get("nitro_duracao", Config.valor("fisica.nitro_duracao", 4.0))),
		"nitro_acel": float(dados.get("nitro_aceleracao", Config.valor("fisica.nitro_aceleracao", 9.0))),
		"nitro_planeio": float(Config.valor("fisica.nitro_extra_planeio", 10)),
		"limite_fator": float(Config.valor("fisica.limite_velocidade.fator", 1.0)),
		"colisao_extra": float(Config.valor("fisica.colisao_mult", 1.0)) - 1.0,
		"direcao_minimo": float(Config.valor("fisica.direcao_minimo_alta", 0.22)),
		"direcao_resposta": float(Config.valor("fisica.direcao_resposta", 4.0)),
		"prioridade_lateral": bool(Config.valor("fisica.prioridade_lateral", false)),
		"estabilidade": float(Config.valor("fisica.estabilidade", 0.0)),
		"giro_max_fator": float(OS.get_environment("TSC_GIRO_FATOR")) if OS.get_environment("TSC_GIRO_FATOR") != "" else float(Config.valor("fisica.giro_max_fator", 0.85)),
		"giro_borrachao":deg_to_rad(float(Config.valor("fisica.borrachao_giro_graus_s", 130))),
		"limite_nitro": float(Config.valor("fisica.limite_velocidade.margem_nitro", 0.15)),
		"limite_rigidez": float(Config.valor("fisica.limite_velocidade.rigidez", 2.0)),
		"controle_aereo":deg_to_rad(float(Config.valor("fisica.controle_aereo_graus_s", 90))),
		"pq": Config.valor("fisica.paraquedas", {}),
		"nivel_agua": float(Config.valor("mapa.nivel_agua", 4)),
		"velame_bloqueio": float(Config.valor("regras.velame_bloqueio_s", 0.0)) if Config.valor("regras.velame_murcha", false) else 0.0,
	}

	_montar_modelo()
	var z_min := INF
	var z_max := -INF
	for r in rodas:
		z_min = minf(z_min, r.ancora.z)
		z_max = maxf(z_max, r.ancora.z)
	_entre_eixos = maxf(z_max - z_min, 1.5)
	# Suspensão: compressão estática de ~35% do curso.
	var carga_roda := mass * g / 4.0
	rigidez = carga_roda / (0.35 * curso) * float(dados.get("suspensao_rigidez", 1.0))
	amortecimento = 2.0 * 0.45 * sqrt(rigidez * mass / 4.0)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, rodas[0].raio + 0.12, 0)
	_montar_colisao()
	_montar_listra()
	paraquedas = Paraquedas.new()
	add_child(paraquedas)
	paraquedas.montar(self, cor_equipe, caixa_corpo)
	if not sem_som:
		som = SomVeiculo.new()
		add_child(som)
		som.montar(self)
	ChamaNitro.montar(self)
	if not avatar_dados.is_empty():
		piloto = Avatar.criar(avatar_dados)
		add_child(piloto)
		piloto.sentar_em(self)


# ---------------------------------------------------------------- montagem

func _montar_modelo() -> void:
	var suporte := Node3D.new()
	suporte.name = "Modelo"
	add_child(suporte)
	modelo = (load(dados.modelo) as PackedScene).instantiate()
	modelo.scale = Vector3.ONE * float(dados.get("escala", 1.0))   # modelos exportados em cm etc.
	suporte.add_child(modelo)

	# Rodas: pelo nome (…Wheel…_FL, …Whell_RR001) ou, se o modelo foge do padrão,
	# pela lista "rodas" do veiculos.json ({"FL": "no" ou ["no1", "no2"], ...}).
	var nos := {}
	var mapa: Dictionary = dados.get("rodas", {})
	if mapa.is_empty():
		var re := RegEx.create_from_string("(?i)(wheel|whell).*_(FL|FR|RL|RR)\\d*$")
		for n in modelo.find_children("*", "Node3D", true, false):
			var m := re.search(String(n.name))
			if m and not nos.has(m.get_string(2).to_upper()):
				nos[m.get_string(2).to_upper()] = [n]
	else:
		for k in mapa:
			var lista: Array = []
			for nome in (mapa[k] if mapa[k] is Array else [mapa[k]]):
				var n := modelo.find_child(nome, true, false)
				if n:
					lista.append(n)
			if not lista.is_empty():
				nos[k] = lista
	if nos.size() < 4:
		push_error("Modelo sem as 4 rodas nomeadas (FL/FR/RL/RR): " + str(dados.modelo))
		return

	# Orienta o modelo: frente para -Z, centro entre os eixos na origem, pneus tocando y = 0.
	var centros := {}
	for k in nos:
		centros[k] = _aabb_lista(nos[k]).get_center()
	var c_frente: Vector3 = (centros.FL + centros.FR) * 0.5
	var c_tras: Vector3 = (centros.RL + centros.RR) * 0.5
	var fwd := c_frente - c_tras
	fwd.y = 0.0
	fwd = fwd.normalized()
	suporte.basis = Basis(Vector3.UP, atan2(fwd.x, -fwd.z))
	var centro := suporte.basis * ((c_frente + c_tras) * 0.5)
	var raio_ref := _aabb_lista(nos.FL).size.y * 0.5
	var fundo := centro.y - raio_ref
	suporte.position = Vector3(-centro.x, -fundo, -centro.z)

	for k in nos:
		_alinhar_roda(nos[k])

	var tracao: String = dados.get("tracao", "4x4")
	for k in ["FL", "FR", "RL", "RR"]:
		var aabb := _aabb_lista(nos[k])
		var r := Roda.new()
		r.raio = aabb.size.y * 0.5
		r.dianteira = k.begins_with("F")
		r.tracionada = tracao == "4x4" or (tracao == "dianteira") == r.dianteira
		r.pivo = Node3D.new()
		r.pivo.name = "Roda" + k
		add_child(r.pivo)
		r.pivo.position = aabb.get_center()
		for no: Node3D in nos[k]:
			no.reparent(r.pivo, true)
		r.ancora = aabb.get_center() + Vector3.UP * curso * 0.65
		rodas.append(r)

	caixa_corpo = _aabb_local(modelo)
	# Camada 2 recebe a faixa da equipe; vidros, faróis e interior ficam de fora
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 1 if _sem_faixa(mi) else 1 | 2
	Placa.aplicar(modelo)   # depois das camadas: a placa não recebe a faixa
	Placa.aplicar_extras(modelo, dados.get("placas", []), float(dados.get("escala", 1.0)))
	_medir_superficie()


## Vidro, luzes e interior não recebem a faixa (pelo nome do nó/pais ou do material, ou material transparente).
func _sem_faixa(mi: MeshInstance3D) -> bool:
	var chaves := ["glass", "window", "windshield", "vidro", "light", "lamp", "interior"]
	var n: Node = mi
	while n != null and n != modelo and n != self:  # a raiz do modelo tem o nome do carro ("lightbody")
		var nome := String(n.name).to_lower()
		for k in chaves:
			if k in nome:
				return true
		n = n.get_parent()
	if mi.mesh == null:
		return false
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s)
		if m == null:
			continue
		var nome_m := m.resource_name.to_lower()
		for k in chaves:
			if k in nome_m:
				return true
		if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
	return false


## Mapa de alturas da carroceria vista de cima (vértices reais do modelo), para prender
## peças exatamente sobre a lataria, como as presilhas do paraquedas.
const _GRADE := 24
var _alturas_topo := PackedFloat32Array()

func _medir_superficie() -> void:
	_alturas_topo.resize(_GRADE * _GRADE)
	_alturas_topo.fill(-INF)
	var inv := global_transform.affine_inverse()
	for n in modelo.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for p in verts:
				var q := xf * p
				var i := _celula(q.x, q.z)
				if i >= 0 and q.y > _alturas_topo[i]:
					_alturas_topo[i] = q.y


func _celula(x: float, z: float) -> int:
	var u := inverse_lerp(caixa_corpo.position.x, caixa_corpo.end.x, x)
	var w := inverse_lerp(caixa_corpo.position.z, caixa_corpo.end.z, z)
	if u < 0.0 or u > 1.0 or w < 0.0 or w > 1.0:
		return -1
	return mini(int(w * _GRADE), _GRADE - 1) * _GRADE + mini(int(u * _GRADE), _GRADE - 1)


## Altura da lataria no ponto (x, z) do espaço do carro.
func altura_superficie(x: float, z: float) -> float:
	var i := _celula(x, z)
	if i < 0 or _alturas_topo[i] == -INF:
		return caixa_corpo.end.y
	return _alturas_topo[i]


## Altura exata da lataria em (x, z): raio de cima para baixo contra os triângulos do modelo.
## Peças pequenas (antenas, luzes, retrovisores) ficam de fora. Retorna -INF se não acertar nada.
var _malhas_teto: Array = []   # [TriangleMesh, Transform3D do carro para a malha, Transform3D da malha para o carro]

func altura_real(x: float, z: float) -> float:
	return superficie_abaixo(x, caixa_corpo.end.y + 1.0, z)


## Primeira superfície do modelo abaixo do ponto (x, y, z): de dentro do carro é o banco ou o
## assoalho (usado para o piloto não atravessar o fundo). -INF se não houver nada.
func superficie_abaixo(x: float, y: float, z: float) -> float:
	if _malhas_teto.is_empty():
		var inv := global_transform.affine_inverse()
		for n in modelo.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var xf := inv * mi.global_transform
			var caixa := xf * mi.mesh.get_aabb()
			if caixa.size.x < 0.3 or caixa.size.z < 0.3:
				continue
			var tm := mi.mesh.generate_triangle_mesh()
			if tm:
				_malhas_teto.append([tm, xf.affine_inverse(), xf])
	var melhor := -INF
	var origem := Vector3(x, y, z)
	for m: Array in _malhas_teto:
		var para_malha: Transform3D = m[1]
		var r: Dictionary = (m[0] as TriangleMesh).intersect_ray(para_malha * origem, para_malha.basis * Vector3.DOWN)
		if not r.is_empty():
			melhor = maxf(melhor, ((m[2] as Transform3D) * (r.position as Vector3)).y)
	return melhor


## Centro do teto: a faixa mais alta e mais larga no meio do carro, ignorando antenas e luzes.
func centro_teto() -> Vector3:
	var melhor_z := caixa_corpo.get_center().z
	var melhor_h := -INF
	var cx := caixa_corpo.get_center().x
	for k in _GRADE:
		var z := lerpf(caixa_corpo.position.z, caixa_corpo.end.z, (k + 0.5) / _GRADE)
		# Altura mínima numa faixa de 40% da largura: teto de verdade, não um ponto isolado
		var h := INF
		for j in 5:
			h = minf(h, altura_superficie(cx + lerpf(-0.2, 0.2, j / 4.0) * caixa_corpo.size.x, z))
		if h > melhor_h + 0.02:
			melhor_h = h
			melhor_z = z
	return Vector3(cx, melhor_h, melhor_z)


## Alguns modelos vêm com as rodas da frente já esterçadas (a French Van, 20°): girando em torno do
## eixo do carro elas bamboleavam. O eixo real da roda é a menor dimensão da maior malha dela;
## a roda é girada em torno do próprio centro até esse eixo ficar alinhado com o X do carro.
func _alinhar_roda(nos_roda: Array) -> void:
	var maior: MeshInstance3D = null
	for n: Node in nos_roda:
		var lista := n.find_children("*", "MeshInstance3D", true, false)
		if n is MeshInstance3D:
			lista.append(n)
		for mi: MeshInstance3D in lista:
			if mi.mesh and (maior == null or mi.get_aabb().get_volume() > maior.get_aabb().get_volume()):
				maior = mi
	if maior == null:
		return
	var t := maior.get_aabb().size
	var eixo_local := Vector3.ZERO
	eixo_local[t.min_axis_index()] = 1.0
	var eixo := (global_transform.affine_inverse() * maior.global_transform).basis * eixo_local
	eixo.y = 0.0
	if eixo.length() < 0.001:
		return
	eixo = eixo.normalized() * signf(eixo.x if absf(eixo.x) > 0.001 else 1.0)
	var desvio := atan2(-eixo.z, eixo.x)   # ângulo do eixo da roda em relação ao X do carro
	if absf(desvio) < deg_to_rad(1.0) or absf(desvio) > deg_to_rad(45.0):
		return
	var centro := global_transform * _aabb_lista(nos_roda).get_center()
	var giro := Transform3D(Basis(global_transform.basis.y.normalized(), -desvio), Vector3.ZERO)
	for n: Node3D in nos_roda:
		var rel := n.global_transform
		rel.origin -= centro
		n.global_transform = (giro * rel).translated(centro)


func _aabb_lista(nos_roda: Array) -> AABB:
	var total := _aabb_local(nos_roda[0])
	for n in nos_roda.slice(1):
		total = total.merge(_aabb_local(n))
	return total


func _aabb_local(raiz: Node) -> AABB:
	var inv := global_transform.affine_inverse()
	var total := AABB()
	var primeiro := true
	var lista := raiz.find_children("*", "MeshInstance3D", true, false)
	if raiz is MeshInstance3D:
		lista.append(raiz)
	for n in lista:
		var mi := n as MeshInstance3D
		var aabb := (inv * mi.global_transform) * mi.get_aabb()
		total = aabb if primeiro else total.merge(aabb)
		primeiro = false
	return total


func _montar_colisao() -> void:
	var ymin := maxf(caixa_corpo.position.y, rodas[0].raio * 0.8)
	var ymax := caixa_corpo.end.y
	var forma := BoxShape3D.new()
	forma.size = Vector3(caixa_corpo.size.x * 0.94, ymax - ymin, caixa_corpo.size.z * 0.96)
	var cs := CollisionShape3D.new()
	cs.shape = forma
	var c := caixa_corpo.get_center()
	cs.position = Vector3(c.x, (ymin + ymax) * 0.5, c.z)
	add_child(cs)
	# Grade de pontos para calcular a área projetada sobre o alvo
	for ix in 5:
		for iz in 9:
			var x := lerpf(-forma.size.x * 0.5, forma.size.x * 0.5, ix / 4.0)
			var z := lerpf(-forma.size.z * 0.5, forma.size.z * 0.5, iz / 8.0)
			_pontos_proj.append(cs.position + Vector3(x, 0, z))


## Faixa da equipe sobre capô, teto e traseira (DEC-05), como adesivo de vinil:
## duas faixas paralelas com contorno branco, filete interno claro, filete central, sombra fina
## de espessura na borda e acabamento brilhante. Vidros, luzes e interior não recebem (camada 2).
func _montar_listra() -> void:
	var larg := 160
	var comp := 16
	var img := Image.create(larg, comp, true, Image.FORMAT_RGBA8)
	var cor := cor_equipe
	var clara := cor_equipe.lightened(0.35)
	var branco := Color(0.95, 0.95, 0.93)
	var faixas := [Vector2(0.04, 0.43), Vector2(0.57, 0.96)]
	for x in larg:
		var u := (x + 0.5) / larg
		var c := Color(0, 0, 0, 0)
		for f: Vector2 in faixas:
			var d := minf(u - f.x, f.y - u)            # distância até a borda da faixa (fração da largura)
			if d >= 0.0:
				if d < 0.03:
					c = branco
				elif d > 0.075 and d < 0.09:
					c = clara
				else:
					c = cor
			elif d > -0.012:
				c = Color(0.0, 0.0, 0.0, 0.45)       # sombra da espessura do vinil
		if absf(u - 0.5) < 0.012:
			c = clara
		for y in comp:
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var orm := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	orm.fill(Color(1.0, 0.22, 0.0))   # oclusão 1, rugosidade baixa (brilho), sem metal
	var decal := Decal.new()
	decal.texture_albedo = ImageTexture.create_from_image(img)
	decal.texture_orm = ImageTexture.create_from_image(orm)
	decal.size = Vector3(caixa_corpo.size.x * 0.46, caixa_corpo.size.y * 0.6, caixa_corpo.size.z * 1.05)
	var meio := caixa_corpo.get_center()
	decal.position = Vector3(meio.x, caixa_corpo.end.y - decal.size.y * 0.5 + 0.05, meio.z)
	decal.cull_mask = 2
	decal.upper_fade = 0.0
	decal.lower_fade = 0.05
	decal.normal_fade = 0.35
	add_child(decal)


func pontos_projecao() -> PackedVector3Array:
	return _pontos_proj


# ---------------------------------------------------------------- comandos

func pedir_ejetor() -> void:
	_pedido_ejetor = true


func alternar_paraquedas() -> void:
	_pedido_paraquedas = true


func ejetor_disponivel() -> bool:
	return not ejetor_bloqueado() and recarga_ejetor <= 0.0 and rodas_no_chao > 0


## Bloqueado até o fim da etapa (não é só recarga). Com regras.ejetor_sempre, abrir o
## paraquedas não bloqueia: vale a corrida inteira.
func ejetor_bloqueado() -> bool:
	return eliminado or (paraquedas_ja_aberto and not _cfg.ejetor_sempre) or (travado and _cfg.bloquear_ejetor)


func esta_voando() -> bool:
	return not eliminado and tempo_no_ar > 0.3


## Quanto o volante está sendo alternado (trocas de lado por segundo, suavizado): zigue-zague no alvo.
func atividade_volante() -> float:
	return _atividade_volante


func velocidade_kmh() -> float:
	return linear_velocity.length() * 3.6


## Recoloca o veículo na largada para uma nova etapa.
func preparar(t: Transform3D) -> void:
	na_largada = true
	eliminado = false
	travado = false
	estado = Estado.APOIADO
	paraquedas_aberto = false
	paraquedas_ja_aberto = false
	carga_nitro = _cfg.nitro_duracao
	nitro_ativo = false
	recarga_ejetor = 0.0
	tempo_no_ar = 0.0
	no_alvo_agora = false
	ultimo_contato_alvo = -100.0
	saiu_da_rampa = false
	pq_bloqueado_ate = -100.0
	_impulso_espera = 0.0
	checkpoint = -1
	_de_cabeca_t = 0.0
	_bateu_mortal = false
	_sair_fantasma()
	telemetria = {"altura_max": 0.0}
	for k in entrada:
		entrada[k] = false if k == "nitro" else 0.0
	paraquedas.fechar(true)
	visible = true
	freeze = true
	global_transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	_zerar_movimento()
	reset_physics_interpolation()   # teletransporte: não desenhar o carro "voando" da posição antiga


func _zerar_movimento() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)


func congelar(sim: bool) -> void:
	if eliminado:
		return
	freeze = sim
	if not sim:
		_zerar_movimento()


func eliminar(motivo := "") -> void:
	if eliminado or not na_largada:   # carro ainda sendo montado no carregamento: sem explosão/som
		return
	# Climb to Death: quem cai antes de sair da rampa final volta no último checkpoint
	if motivo != "tempo" and complexo:
		var t = complexo.ressurgimento(self)
		if t is Transform3D:
			var estouro := Explosao.new()
			get_parent().add_child(estouro)
			estouro.global_position = global_position + Vector3.UP * 0.8
			estouro.reset_physics_interpolation()
			telemetria.quedas = int(telemetria.get("quedas", 0)) + 1
			ressurgir(t, float(Config.valor("mapa.subida.checkpoints.fantasma_s", 3.0)))
			return
	telemetria.motivo = motivo
	telemetria.tempo_eliminado = relogio
	telemetria.pos_eliminado = global_position
	eliminado = true
	estado = Estado.ELIMINADO
	nitro_ativo = false
	paraquedas.fechar(true)
	Destrocos.criar.call_deferred(self)  # fora do passo de física
	var explosao := Explosao.new()
	get_parent().add_child(explosao)
	explosao.global_position = global_position + Vector3.UP * 0.8
	explosao.reset_physics_interpolation()
	visible = false
	set_deferred("freeze", true)
	foi_eliminado.emit(self)


## Volta à pista em `t` parado, como fantasma por `duracao` segundos.
func ressurgir(t: Transform3D, duracao: float) -> void:
	# Pode ter caído depois de saltar da rampa final ou de tocar o alvo: volta a correr do zero
	travado = false
	saiu_da_rampa = false
	ultimo_contato_alvo = -100.0
	paraquedas_aberto = false
	paraquedas.fechar(true)
	estado = Estado.APOIADO
	tempo_no_ar = 0.0
	nitro_ativo = false
	borrachao = false
	no_alvo_agora = false
	_impulso_espera = relogio + 1.0
	for r in rodas:
		r.compressao = 0.0
	global_transform = t
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	_zerar_movimento()
	reset_physics_interpolation()
	_fantasma = true
	_fantasma_ate = relogio + duracao
	collision_layer = 0      # ninguém bate nele...
	collision_mask = 1       # ...e ele só encosta em estruturas
	_geo_fantasma = find_children("*", "GeometryInstance3D", true, false)
	ressurgiu.emit(self)


func fantasma() -> bool:
	return _fantasma


func _sair_fantasma() -> void:
	if not _fantasma:
		return
	_fantasma = false
	collision_layer = 2
	collision_mask = 1 | 2
	for gi in _geo_fantasma:
		if is_instance_valid(gi):
			gi.transparency = 0.0
	_geo_fantasma.clear()


## Algo bateu no velame aberto (outro carro, outra cobertura ou estrutura): murcha e, na fase
## em que isso vale como ataque, só reabre depois do bloqueio.
func murchar_velame() -> void:
	if not paraquedas_aberto:
		return
	fechar_paraquedas()
	pq_bloqueado_ate = relogio + float(_cfg.velame_bloqueio)
	velame_murchou.emit(self)


func fechar_paraquedas() -> void:
	if paraquedas_aberto:
		paraquedas_aberto = false
		paraquedas.fechar()
		paraquedas_mudou.emit(self, false)


# ---------------------------------------------------------------- física

func _integrate_forces(s: PhysicsDirectBodyState3D) -> void:
	if eliminado or freeze:
		return
	var dt := s.step
	relogio += dt
	var xf := s.transform
	var cima := xf.basis.y
	var frente := -xf.basis.z
	var direita := xf.basis.x
	var v := s.linear_velocity
	var espaco := s.get_space_state()

	contato_corpo = false
	contato_veiculo = null
	var alvo_tocado := false
	for i in s.get_contact_count():
		contato_corpo = true
		var obj := s.get_contact_collider_object(i)
		if obj is Node and (obj as Node).is_in_group("alvo"):
			alvo_tocado = true
		elif obj is Node and (obj as Node).is_in_group("mortal"):
			_bateu_mortal = true
		elif obj is Veiculo:
			contato_veiculo = obj as Veiculo
			if _cfg.colisao_extra > 0.0:
				_empurrao_extra(s, obj as Veiculo)

	_direcao_suave = move_toward(_direcao_suave, float(entrada.direcao), dt * _cfg.direcao_resposta)
	var angulo_direcao := -_direcao_suave * direcao_max * lerpf(1.0, _cfg.direcao_minimo, clampf(v.length() / 45.0, 0.0, 1.0))
	# Ré: mesma regra do motor (bloqueada depois de tocar o alvo), mais fraca e limitada a vel_re.
	# Sem freio: com o carro andando para a frente, a ré é que segura o carro.
	# Com freio (regras.freios_instalados, ex.: Climb to Death): andando para a frente S freia; quase
	# parado ou já de ré, S volta a ser ré. Tocar o alvo bloqueia os dois, como o motor.
	freando = _cfg.freios and not travado and float(entrada.freiar) > 0.05 and v.dot(frente) > 1.5
	var v_re := maxf(-v.dot(frente), 0.0)
	var re := 0.0 if travado or freando else float(entrada.re) * forca_re * clampf(1.0 - pow(v_re / vel_re, 2.0), 0.0, 1.0)
	var motor := 0.0 if travado else float(entrada.acelerar)
	# Borrachão: W+S no chão — o motor gira as rodas de tração sem sair do lugar
	borrachao = not travado and rodas_no_chao > 0 and motor > 0.5 and float(entrada.re) > 0.5
	if borrachao:
		motor = 0.0
		re = 0.0
		freando = false
	var v_frente := v.dot(frente)
	var fator_vel := clampf(1.0 - pow(maxf(v_frente, 0.0) / vel_max, 2.0), 0.0, 1.0)
	var n_tracao := 0
	for r in rodas:
		if r.tracionada:
			n_tracao += 1
	var forca_motor := mass * aceleracao * (motor * fator_vel - re) / maxf(n_tracao, 1)
	var massa_roda := mass / 4.0
	var vel_apoio := Vector3.ZERO   # velocidade do alvo sob as rodas (alvo móvel)

	rodas_no_chao = 0
	if _com_diag:
		diag = {"sat_f": 0.0, "sat_t": 0.0, "carga_f": 0.0, "carga_t": 0.0, "w_pedido": v_frente * tan(angulo_direcao) / _entre_eixos}
	for r in rodas:
		var origem := xf * r.ancora
		var alcance := curso + r.raio
		var q := PhysicsRayQueryParameters3D.create(origem, origem - cima * alcance, 1 if _fantasma else MASCARA_RAIO, [get_rid()])
		var hit := espaco.intersect_ray(q)
		if hit.is_empty():
			r.contato = false
			r.compressao = 0.0
			continue
		r.contato = true
		rodas_no_chao += 1
		var col = hit.collider
		if col is Node and (col as Node).is_in_group("alvo"):
			alvo_tocado = true
		elif col is Node and (col as Node).is_in_group("mortal"):
			_bateu_mortal = true   # caiu da estrada do túnel no piso dele
		var comp := alcance - origem.distance_to(hit.position)
		var vel_comp := (comp - r.compressao) / dt
		r.compressao = comp
		var f_susp := rigidez * minf(comp, curso) + amortecimento * vel_comp
		if comp > curso:
			f_susp += rigidez * 12.0 * (comp - curso)  # batente
		f_susp = maxf(f_susp, 0.0)
		s.apply_force(cima * f_susp, origem - xf.origin)

		# Pneu
		var normal: Vector3 = hit.normal
		var dir_roda := frente.rotated(cima, angulo_direcao) if r.dianteira else frente
		var lado := direita.rotated(cima, angulo_direcao) if r.dianteira else direita
		dir_roda = (dir_roda - normal * dir_roda.dot(normal)).normalized()
		lado = (lado - normal * lado.dot(normal)).normalized()
		var ponto_forca := xf * (r.ancora - Vector3.UP * (curso * 0.65 - 0.1)) - xf.origin
		var vp := s.get_velocity_at_local_position(ponto_forca)
		if col is Alvo:
			vp -= (col as Alvo).velocidade_atual  # pneus agarram na plataforma móvel
			vel_apoio = (col as Alvo).velocidade_atual
		var v_long := vp.dot(dir_roda)
		var v_lat := vp.dot(lado)
		var f_long := -v_long * massa_roda * 0.03
		if r.tracionada:
			f_long += forca_motor
		if freando:
			f_long -= signf(v_long) * minf(mass * freio / 4.0, absf(v_long) * massa_roda / dt)
		var f_lat := -v_lat * massa_roda * 14.0
		if borrachao:
			f_long = -v_long * massa_roda * 6.0   # segura no lugar
			if r.tracionada:
				f_lat *= 0.12                      # patinando: a tração perde a aderência de lado
		var limite := f_susp * aderencia
		if _com_diag:
			var eixo := "f" if r.dianteira else "t"
			diag["sat_" + eixo] = maxf(diag["sat_" + eixo], absf(f_lat) / maxf(limite, 1.0))
			diag["carga_" + eixo] += f_susp
		if _cfg.prioridade_lateral and not borrachao:
			# O pneu segura a curva primeiro; o motor/freio usa o que sobra (sempre um mínimo de tração)
			f_lat = clampf(f_lat, -limite, limite)
			var sobra := maxf(sqrt(maxf(limite * limite - f_lat * f_lat, 0.0)), limite * 0.35)
			f_long = clampf(f_long, -sobra, sobra)
		var f := Vector2(f_long, f_lat)
		if not _cfg.prioridade_lateral or borrachao:
			if f.length() > limite:
				f = f.normalized() * limite
		s.apply_force(dir_roda * f.x + lado * f.y, ponto_forca)

	if borrachao:
		# Cavalo de pau: A/D gira o carro no próprio eixo, com a traseira escorregando
		var w_y := s.angular_velocity.dot(cima)
		s.apply_torque(cima * (-_direcao_suave * _cfg.giro_borrachao - w_y) * mass * 18.0)
	elif _cfg.estabilidade > 0.0 and rodas_no_chao >= 3 and not travado and absf(v_frente) > 3.0:
		# Estabilidade (como um controle de estabilidade): puxa o giro do carro para o que o volante
		# pede, mas nunca além do que os pneus aguentam nessa velocidade (giro máx. = aceleração
		# lateral máx. / velocidade). Sem esse teto, com o volante todo virado ela forçava um giro
		# impossível e era ela que rodava o carro (a traseira escapava).
		var w_pedido := v_frente * tan(angulo_direcao) / _entre_eixos
		var w_max: float = aderencia * 9.8 * float(_cfg.giro_max_fator) / maxf(absf(v_frente), 1.0)
		var w_alvo := clampf(w_pedido, -w_max, w_max)
		var w_y := s.angular_velocity.dot(cima)
		s.apply_torque(cima * clampf(w_alvo - w_y, -2.0, 2.0) * mass * 8.0 * _cfg.estabilidade)
	s.apply_central_force(-v * v.length() * arrasto * mass)
	# Limitador: com rodas no chão o carro não passa da velocidade limite dele (a gravidade na
	# descida levava todos a ~253 km/h). O nitro libera uma margem acima do limite.
	if rodas_no_chao > 0 and not travado:
		var limite: float = vel_max * _cfg.limite_fator * (1.0 + _cfg.limite_nitro if nitro_ativo else 1.0)
		if v_frente > limite:
			s.apply_central_force(-frente * mass * minf((v_frente - limite) * float(_cfg.limite_rigidez), 12.0))
	_zigue_zague(s, dt, v - vel_apoio)

	var no_chao := rodas_no_chao > 0 or contato_corpo
	tempo_no_ar = 0.0 if no_chao else tempo_no_ar + dt
	no_alvo_agora = alvo_tocado
	if alvo_tocado:
		ultimo_contato_alvo = relogio
		if not travado:
			telemetria.toque_alvo_kmh = v.length() * 3.6
			telemetria.toque_alvo_tempo = relogio
			travado = true
			nitro_ativo = false
			fechar_paraquedas()
			tocou_alvo.emit(self)
	if paraquedas_aberto and no_chao:
		fechar_paraquedas()

	if _pedido_ejetor:
		_pedido_ejetor = false
		if ejetor_disponivel():
			s.apply_central_impulse(Vector3.UP * mass * float(_cfg.ejetor_impulso))
			recarga_ejetor = _cfg.ejetor_recarga
			ejetor_usado.emit(self)
	if _pedido_paraquedas:
		_pedido_paraquedas = false
		if paraquedas_aberto:
			fechar_paraquedas()
		elif rodas_no_chao == 0 and tempo_no_ar > 0.1 and relogio >= pq_bloqueado_ate:
			paraquedas_aberto = true
			paraquedas_ja_aberto = true
			if not telemetria.has("paraquedas_tempo"):
				telemetria.paraquedas_tempo = relogio
				telemetria.paraquedas_altura = xf.origin.y
				telemetria.paraquedas_pos = xf.origin
			var vh := Vector3(v.x, 0, v.z)
			var ref := vh if vh.length() > 2.0 else Vector3(frente.x, 0, frente.z)
			rumo = atan2(-ref.x, -ref.z)
			_taxa_giro = 0.0
			_acc_frente = 0.0
			_vel_frente_ant = vh.dot(Vector3(-sin(rumo), 0.0, -cos(rumo)))
			paraquedas.abrir()
			paraquedas_mudou.emit(self, true)

	nitro_ativo = bool(entrada.nitro) and _cfg.nitro and carga_nitro > 0.0 and not travado
	if nitro_ativo:
		carga_nitro = maxf(carga_nitro - dt, 0.0)

	if paraquedas_aberto:
		estado = Estado.PLANEIO
		_planeio(s, v)
	elif tempo_no_ar > 0.12:
		estado = Estado.BALISTICO
		_controle_aereo(s, xf)
		if nitro_ativo:
			s.apply_central_force(frente * mass * float(_cfg.nitro_acel))
	else:
		estado = Estado.APOIADO
		if nitro_ativo:
			s.apply_central_force(frente * mass * float(_cfg.nitro_acel))

	# Ponto de aceleração da arena: tranco violento para onde o CARRO aponta (não importa o
	# desenho da placa). Quem é empurrado para cima dela virado para um buraco vai direto nele.
	if complexo and rodas_no_chao > 0 and not travado and relogio >= _impulso_espera:
		var dir_imp := complexo.impulso_em(xf.origin)
		if dir_imp != Vector3.ZERO:
			var ref := frente if complexo.impulso_segue_carro(xf.origin) else dir_imp
			dir_imp = Vector3(ref.x, 0.0, ref.z).normalized()
			var ao_longo := v.dot(dir_imp)
			s.linear_velocity = v + dir_imp * (maxf(ao_longo, 0.0) + complexo.velocidade_impulso(xf.origin) - ao_longo)
			_impulso_espera = relogio + 1.0
			impulso_usado.emit.call_deferred(self)


## Sem paraquedas: W/S inclinam para frente/trás, A/D inclinam lateralmente.
func _controle_aereo(s: PhysicsDirectBodyState3D, xf: Transform3D) -> void:
	var taxa: float = _cfg.controle_aereo
	var arfagem := float(entrada.freiar) - float(entrada.acelerar)
	var d := float(entrada.direcao)
	var w_des := xf.basis.x * arfagem * taxa + xf.basis.z * (-d) * taxa * 0.8 + xf.basis.y * (-d) * taxa * 0.35
	_torque_para(s, w_des, 3.0)


## Com paraquedas: W acelera e desce mais, S desacelera e sustenta mais, A/D curvam.
func _planeio(s: PhysicsDirectBodyState3D, v: Vector3) -> void:
	var pq: Dictionary = _cfg.pq
	var w := float(entrada.acelerar)
	var sb := float(entrada.freiar)
	var d := float(entrada.direcao)
	var controle := float(dados.get("paraquedas_controle", 1.0))
	# Curva com inércia: a taxa de giro cresce e diminui aos poucos.
	var giro_max := deg_to_rad(pq.get("giro_graus_s", 28)) * controle
	_taxa_giro = move_toward(_taxa_giro, -d * giro_max, giro_max * 1.6 * s.step)
	rumo += _taxa_giro * s.step
	var fwd_h := Vector3(-sin(rumo), 0.0, -cos(rumo))
	var alvo_v: float = pq.get("velocidade_neutra", 22)
	var alvo_af: float = pq.get("afundamento_neutro", 1.6)
	alvo_v = lerpf(lerpf(alvo_v, pq.get("velocidade_w", 34), w), pq.get("velocidade_s", 13), sb)
	alvo_af = lerpf(lerpf(alvo_af, pq.get("afundamento_w", 5.0), w), pq.get("afundamento_s", 0.8), sb)
	alvo_af /= sqrt(_fator_peso)
	alvo_v *= float(dados.get("paraquedas_velocidade", 1.0))
	alvo_af /= float(dados.get("paraquedas_sustentacao", 1.0))
	if nitro_ativo:
		alvo_v += float(_cfg.nitro_planeio)
	var vh := Vector3(v.x, 0.0, v.z)
	# Curva inclinada perde um pouco de altura (como um parapente).
	alvo_af += absf(_taxa_giro) * vh.length() * 0.06
	var acc_h := ((fwd_h * alvo_v - vh) * float(pq.get("resposta_horizontal", 0.8))).limit_length(14.0)
	var acc_y := clampf((-alvo_af - v.y) * float(pq.get("resposta_vertical", 1.5)) + g, 0.0, g * 2.5)
	s.apply_central_force(Vector3(acc_h.x, acc_y, acc_h.z) * mass)
	# Pêndulo: o carro pendurado inclina para dentro da curva e balança ao acelerar/frear.
	var vel_frente := vh.dot(fwd_h)
	_acc_frente = lerpf(_acc_frente, (vel_frente - _vel_frente_ant) / s.step, 1.0 - exp(-s.step * 3.0))
	_vel_frente_ant = vel_frente
	var inclinacao_curva := clampf(atan(vh.length() * _taxa_giro / g), -0.6, 0.6)
	var arfagem := deg_to_rad(-12.0 * w + 10.0 * sb) - clampf(_acc_frente / g, -0.5, 0.5) * 0.7
	_torque_orientacao(s, Basis.from_euler(Vector3(arfagem, rumo, inclinacao_curva * 0.9)), 2.2, 3.0)


func _torque_para(s: PhysicsDirectBodyState3D, w_des: Vector3, ganho: float) -> void:
	var alfa := (w_des - s.angular_velocity) * ganho
	s.apply_torque(s.inverse_inertia_tensor.inverse() * alfa)


func _torque_orientacao(s: PhysicsDirectBodyState3D, alvo: Basis, kp: float, ganho := 5.0) -> void:
	var q_err := alvo.get_rotation_quaternion() * s.transform.basis.get_rotation_quaternion().inverse()
	if q_err.w < 0.0:
		q_err = -q_err
	var angulo := q_err.get_angle()
	var w_des := Vector3.ZERO if angulo < 0.0005 else q_err.get_axis() * angulo * kp
	_torque_para(s, w_des, ganho)


func _physics_process(delta: float) -> void:
	if eliminado:
		return
	if _fantasma:
		if relogio >= _fantasma_ate:
			_sair_fantasma()
		else:
			var a := 0.8 if fmod(_fantasma_ate - relogio, 0.3) < 0.15 else 0.4   # pisca transparente
			for gi in _geo_fantasma:
				if is_instance_valid(gi):
					gi.transparency = a
	recarga_ejetor = maxf(recarga_ejetor - delta, 0.0)
	_atualizar_rodas(delta)
	if freeze:
		return
	var p := global_position
	telemetria.altura_max = maxf(telemetria.altura_max, p.y)
	# Saída da rampa (telemetria)
	if not saiu_da_rampa and complexo and tempo_no_ar > 0.2 and complexo.saltou_da_rampa(p):
		saiu_da_rampa = true
		telemetria.saida_kmh = velocidade_kmh()
		telemetria.saida_altura = p.y
		telemetria.saida_tempo = relogio
	# Terreno e água são mortais; limites de segurança do mapa.
	if saiu_da_rampa:
		telemetria.apice = maxf(telemetria.get("apice", 0.0), p.y)
	if p.y - 0.2 < terreno.altura_em(p.x, p.z):
		eliminar("terreno")
		return
	if _bateu_mortal:
		_bateu_mortal = false
		eliminar("parede")
		return
	# Mapa com checkpoint: de cabeça para baixo e parado por 4 s, volta no último checkpoint
	if global_transform.basis.y.y < 0.0 and linear_velocity.length() < 3.0 and not travado:
		_de_cabeca_t += delta
		if _de_cabeca_t >= DE_CABECA_S:
			_de_cabeca_t = 0.0
			var t = complexo.ressurgimento(self) if complexo else null
			if t is Transform3D:
				ressurgir(t, float(Config.valor("mapa.subida.checkpoints.fantasma_s", 3.0)))
				return
	else:
		_de_cabeca_t = 0.0
	if complexo and complexo.buraco_mortal(p):
		eliminar("buraco")
		return
	if p.y < _cfg.nivel_agua:
		eliminar("agua")
		return
	if Vector2(p.x, p.z).length() > 6500.0 or p.y > 2500.0:
		eliminar("limite")
		return
	if paraquedas_aberto:
		var topo := paraquedas.global_position
		if topo.y < terreno.altura_em(topo.x, topo.z) + 1.5:
			fechar_paraquedas()


func _atualizar_rodas(delta: float) -> void:
	var angulo := -_direcao_suave * direcao_max * lerpf(1.0, _cfg.direcao_minimo, clampf(linear_velocity.length() / 45.0, 0.0, 1.0))
	var v_frente := linear_velocity.dot(-global_transform.basis.z)
	for r in rodas:
		var queda := curso - clampf(r.compressao, 0.0, curso)
		r.pivo.position = r.ancora - Vector3.UP * queda
		if vel_rodas_externa >= 0.0:
			r.giro -= vel_rodas_externa / r.raio * delta
		elif borrachao and r.tracionada:
			r.giro -= 40.0 * delta
		elif r.contato:
			r.giro -= v_frente / r.raio * delta
		elif r.tracionada and float(entrada.acelerar) > 0.1 and not travado:
			r.giro -= 25.0 * delta
		r.giro = fmod(r.giro, TAU)
		r.pivo.basis = Basis(Vector3.UP, angulo if r.dianteira else 0.0) * Basis(Vector3.RIGHT, r.giro)
	_atualizar_fumaca_pneus()


## Batida em outro carro: soma um empurrão extra (fisica.colisao_mult - 1) ao da física, na
## direção que afasta os dois e proporcional à velocidade com que se aproximavam. Cada carro aplica
## o seu, então a batida inteira fica mais forte e quem é atingido voa mais longe.
func _empurrao_extra(s: PhysicsDirectBodyState3D, outro: Veiculo) -> void:
	var n := s.transform.origin - outro.global_position
	n.y = 0.0
	if n.length_squared() < 0.01:
		return
	n = n.normalized()
	var aproximacao := -(s.linear_velocity - outro.linear_velocity).dot(n)
	if aproximacao < 0.5:
		return
	var m_red := mass * outro.mass / (mass + outro.mass)
	s.apply_central_impulse(n * aproximacao * m_red * 1.3 * _cfg.colisao_extra)


## Fumaça branca saindo das rodas de tração durante o borrachão (criada na primeira vez).
func _atualizar_fumaca_pneus() -> void:
	if not borrachao and _fumaca_pneus.is_empty():
		return
	if _fumaca_pneus.is_empty():
		for r in rodas:
			if not r.tracionada:
				continue
			var p := GPUParticles3D.new()
			p.amount = 36
			p.lifetime = 1.8
			p.local_coords = false
			var m := ParticleProcessMaterial.new()
			m.direction = Vector3.UP
			m.spread = 50.0
			m.initial_velocity_min = 0.6
			m.initial_velocity_max = 2.2
			m.gravity = Vector3(0.0, 0.9, 0.0)
			m.damping_min = 0.8
			m.damping_max = 1.4
			m.scale_min = 0.7
			m.scale_max = 1.3
			m.angle_min = -180.0
			m.angle_max = 180.0
			var curva := Curve.new()
			curva.add_point(Vector2(0, 0.4))
			curva.add_point(Vector2(1, 2.6))
			var ct := CurveTexture.new()
			ct.curve = curva
			m.scale_curve = ct
			var grad := Gradient.new()
			grad.set_color(0, Color(0.9, 0.9, 0.9, 0.0))
			grad.add_point(0.1, Color(0.85, 0.85, 0.85, 0.55))
			grad.set_color(grad.get_point_count() - 1, Color(0.8, 0.8, 0.8, 0.0))
			var rampa := GradientTexture1D.new()
			rampa.gradient = grad
			m.color_ramp = rampa
			p.process_material = m
			p.draw_pass_1 = Explosao.quad_fumaca(1.6)
			r.pivo.add_child(p)
			_fumaca_pneus.append(p)
	for p in _fumaca_pneus:
		p.emitting = borrachao


## Depois de tocar o alvo (sem motor, sem freio): girar o volante para os dois lados seguidamente
## "arrasta" os pneus e segura o carro. A desaceleração cresce com a frequência das trocas de lado.
func _zigue_zague(s: PhysicsDirectBodyState3D, dt: float, v_rel: Vector3) -> void:
	var d := float(entrada.direcao)
	var troca := absf(d - _volante_ant) / dt
	_volante_ant = d
	_atividade_volante = lerpf(_atividade_volante, troca, clampf(dt * 2.5, 0.0, 1.0))
	if not travado or rodas_no_chao == 0:
		return
	var plano := Vector3(v_rel.x, 0.0, v_rel.z)
	var rapidez := plano.length()
	if rapidez < 0.05:
		return
	var desac := minf(_atividade_volante * zz_ganho, zz_max)
	desac = minf(desac, rapidez / dt)
	s.apply_central_force(-plano / rapidez * desac * mass)
