class_name PilotoBot
extends Node
## Piloto automático dos rivais: espera um pouco na plataforma, desce acelerando,
## pode usar nitro e ejetor na saída, abre o paraquedas perto do ápice e plana até o alvo
## controlando a razão de planeio. Cada etapa sorteia habilidade e mira diferentes.

signal falou(bot: PilotoBot, texto: String)

var veiculo: Veiculo
var alvo: Alvo
var ativo := false
var rng := RandomNumberGenerator.new()

var _t := 0.0
var _espera := 0.0
var _usa_nitro := false
var _usa_ejetor := false
var _ejetou := false
var _mira := Vector2.ZERO
var _abre_com_vy := 0.0
var _falou_pouso := false
var _espiral := false

const FRASES_LARGADA := ["Vou no alvo 5!", "Bora, equipe!", "Hoje é zona 5.", "Segura essa!"]
const FRASES_PARAQUEDAS := ["Paraquedas aberto!", "Planando...", "Vento bom hoje."]


func iniciar_etapa(p_alvo: Alvo) -> void:
	alvo = p_alvo
	_t = 0.0
	_ejetou = false
	_falou_pouso = false
	_espiral = false
	_espera = rng.randf_range(0.3, 5.0)
	_usa_nitro = rng.randf() < 0.65
	_usa_ejetor = rng.randf() < 0.55
	if OS.get_environment("TSC_EJETOR") != "":
		_usa_ejetor = OS.get_environment("TSC_EJETOR") == "1"
		_usa_nitro = false
	_abre_com_vy = rng.randf_range(-6.0, 6.0)
	var habilidade := rng.randf_range(0.55, 0.97)
	var erro := (1.0 - habilidade) * alvo.raio * 0.8
	_mira = Vector2(rng.randf_range(-erro, erro), rng.randf_range(-erro, erro))
	if rng.randf() < 0.3:
		_falar(FRASES_LARGADA[rng.randi() % FRASES_LARGADA.size()])


func _falar(texto: String) -> void:
	falou.emit(self, texto)


func _physics_process(delta: float) -> void:
	if not ativo or veiculo == null or veiculo.eliminado:
		return
	_t += delta
	var e := veiculo.entrada
	e.acelerar = 0.0
	e.freiar = 0.0
	e.direcao = 0.0
	e.nitro = false
	match veiculo.estado:
		Veiculo.Estado.APOIADO:
			_dirigir(e)
		Veiculo.Estado.BALISTICO:
			_balistico(e)
		Veiculo.Estado.PLANEIO:
			_planar(e)


func _dirigir(e: Dictionary) -> void:
	if veiculo.travado:
		# Sem freio: alterna o volante rapidamente para segurar o carro no alvo. Não para ao
		# quase parar: o zigue-zague demora a pegar força e o desnível do alvo faria o carro
		# voltar a escorregar; mantido o tempo todo, funciona como um freio de estacionamento.
		if veiculo.rodas_no_chao > 0:
			e.direcao = 1.0 if fmod(_t, 0.28) < 0.14 else -1.0
		if not _falou_pouso and rng.randf() < 0.02:
			_falou_pouso = true
		return
	if _t < _espera:
		e.freiar = 1.0
		return
	e.acelerar = 1.0
	var cx := veiculo.complexo
	var p := veiculo.global_position
	var xp := cx.x_perfil(p)
	var eixo := cx.ponto(xp, p.y)
	var desvio := (p - eixo).dot(cx.lateral)
	var erro_rumo := (-veiculo.global_transform.basis.z).dot(cx.lateral)
	e.direcao = clampf(-desvio * 0.12 - erro_rumo * 2.5, -1.0, 1.0)
	if _usa_nitro and xp > cx.perfil.pontos[cx.perfil.indice_base].x - 60.0:
		e.nitro = true
	if _usa_ejetor and not _ejetou and xp > cx.perfil.comprimento_horizontal - 4.0 and veiculo.ejetor_disponivel():
		_ejetou = true
		veiculo.pedir_ejetor()


func _balistico(e: Dictionary) -> void:
	if veiculo.travado:
		return
	# Mantém o carro nivelado durante o salto
	var frente := -veiculo.global_transform.basis.z
	var inclinacao := asin(clampf(frente.y, -1.0, 1.0))
	if inclinacao > 0.3:
		e.acelerar = 1.0
	elif inclinacao < -0.3:
		e.freiar = 1.0
	if not veiculo.paraquedas_ja_aberto and veiculo.linear_velocity.y < _abre_com_vy and veiculo.tempo_no_ar > 0.8:
		veiculo.alternar_paraquedas()
		if rng.randf() < 0.25:
			_falar(FRASES_PARAQUEDAS[rng.randi() % FRASES_PARAQUEDAS.size()])
	elif veiculo.paraquedas_ja_aberto and not veiculo.paraquedas_aberto and veiculo.tempo_no_ar > 0.5:
		veiculo.alternar_paraquedas()


func _planar(e: Dictionary) -> void:
	var p := veiculo.global_position
	var destino := alvo.centro_superior() + Vector3(_mira.x, 0.0, _mira.y)
	var d := destino - p
	var dist_h := Vector2(d.x, d.z).length()
	if alvo.movel:
		# Antecipa o movimento do alvo pelo tempo estimado até a chegada
		destino = alvo.centro_futuro(dist_h / maxf(Vector2(veiculo.linear_velocity.x, veiculo.linear_velocity.z).length(), 8.0)) + Vector3(_mira.x, 0.0, _mira.y)
		d = destino - p
		dist_h = Vector2(d.x, d.z).length()
	var altura := p.y - destino.y
	var desejado := atan2(-d.x, -d.z)
	var erro := wrapf(desejado - veiculo.rumo, -PI, PI)
	e.direcao = clampf(-erro * 2.2, -1.0, 1.0)
	var razao := dist_h / maxf(altura, 0.5)
	if _espiral:
		# Perdendo altura em círculos até a rota voltar a fechar
		e.direcao = 1.0
		e.acelerar = 1.0
		if razao > 6.0 or altura < 10.0:
			_espiral = false
	elif razao < 3.0 and altura > 10.0:
		_espiral = true
	elif dist_h < 80.0:
		e.freiar = 1.0  # aproximação final devagar
	elif razao > 8.5:
		e.nitro = not veiculo.travado
	else:
		e.acelerar = clampf((7.0 - razao) / 2.5, 0.0, 1.0)
