class_name Estilo
extends RefCounted
## Tema visual da interface: painéis azul-marinho translúcidos com borda clara e fonte Bahnschrift.

const FUNDO := Color(0.03, 0.07, 0.15, 0.8)
const BORDA := Color(0.45, 0.65, 1.0, 0.55)
const TEXTO := Color(0.93, 0.95, 1.0)
const TEXTO_FRACO := Color(0.66, 0.72, 0.84)
const DESTAQUE := Color(0.35, 0.6, 1.0)
const PERIGO := Color(1.0, 0.35, 0.3)
const OK := Color(0.45, 0.95, 0.6)


static func fonte(peso := 400) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	f.font_weight = mini(peso, 700)   # Bahnschrift vai até 700; acima disso o Windows troca de fonte
	return f


static func tema() -> Theme:
	var t := Theme.new()
	t.default_font = fonte(500)
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXTO)
	var normal := caixa()
	var foco := caixa(Color(0.08, 0.16, 0.32, 0.92), DESTAQUE)
	var press := caixa(Color(0.12, 0.25, 0.5, 0.95), DESTAQUE)
	for tipo in ["Button", "OptionButton"]:
		t.set_stylebox("normal", tipo, normal)
		t.set_stylebox("hover", tipo, foco)
		t.set_stylebox("focus", tipo, foco)
		t.set_stylebox("pressed", tipo, press)
		t.set_color("font_color", tipo, TEXTO)
		t.set_color("font_hover_color", tipo, Color.WHITE)
	t.set_stylebox("panel", "PanelContainer", caixa())
	t.set_stylebox("normal", "LineEdit", caixa(Color(0.02, 0.05, 0.1, 0.9)))
	t.set_stylebox("focus", "LineEdit", caixa(Color(0.02, 0.05, 0.1, 0.9), DESTAQUE))
	return t


static func caixa(fundo := FUNDO, borda := BORDA, inclinacao := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fundo
	s.border_color = borda
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.skew = Vector2(inclinacao, 0.0)
	return s


static func rotulo(texto: String, tamanho := 22, cor := TEXTO, peso := 500) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_override("font", fonte(peso))
	l.add_theme_font_size_override("font_size", tamanho)
	l.add_theme_color_override("font_color", cor)
	return l


static func painel(inclinacao := 0.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", caixa(FUNDO, BORDA, inclinacao))
	return p


# ------------------------------------------------------------------ estilo do menu (artes do dossiê)

const AZUL_NEON := Color(0.25, 0.55, 1.0)
const PAINEL_ESCURO := Color(0.02, 0.05, 0.11, 0.86)

## Ícones da fonte do Windows (Segoe MDL2 Assets / Segoe Fluent Icons).
const ICONE := {
	"garagem": 0xE80F, "carrinho": 0xE7BF, "loja": 0xE719, "perfil": 0xE77B, "cla": 0xE716,
	"passe": 0xE8EC, "noticias": 0xE7C3, "config": 0xE713, "info": 0xE946, "sair": 0xE7E8,
	"cadeado": 0xE72E, "play": 0xE768, "direita": 0xE76C, "esquerda": 0xE76B, "carro": 0xE804,
}


static func fonte_icones() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe Fluent Icons", "Segoe MDL2 Assets", "Segoe UI Symbol"])
	return f


static func icone(nome: String, tamanho := 26, cor := TEXTO) -> Label:
	var l := Label.new()
	l.text = String.chr(ICONE.get(nome, 0x25CF))
	l.add_theme_font_override("font", fonte_icones())
	l.add_theme_font_size_override("font_size", tamanho)
	l.add_theme_color_override("font_color", cor)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Fonte dos títulos no estilo do logo ("TARGET SPEED CHALLENGER"): Exo 2 itálico pesado
## (assets/fontes, licença SIL OFL 1.1). O peso vem do eixo "wght" da fonte variável.
static func fonte_titulo(peso := 800) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = load("res://assets/fontes/Exo2-Italic.ttf")
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): peso}
	return f


## Painel chanfrado com borda azul e brilho externo opcional.
static func caixa_neon(fundo := PAINEL_ESCURO, borda := Color(0.3, 0.55, 1.0, 0.7), brilho := 0.0, chanfro := 10, inclinacao := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fundo
	s.border_color = borda
	s.set_border_width_all(2)
	s.set_corner_radius_all(chanfro)
	s.corner_detail = 1   # canto reto em 45° (chanfro)
	s.skew = Vector2(inclinacao, 0.0)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	if brilho > 0.0:
		s.shadow_color = Color(AZUL_NEON, 0.55 * brilho)
		s.shadow_size = int(14 * brilho)
	return s


## Faixa de gradiente horizontal (para o item selecionado do menu lateral).
static func caixa_gradiente(esquerda: Color, direita: Color) -> StyleBoxTexture:
	var g := Gradient.new()
	g.set_color(0, esquerda)
	g.set_color(1, direita)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 8
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## Barra segmentada (atributos do carro): `valor` de `total` segmentos acesos.
static func barra_segmentos(valor: int, total := 5, cor := AZUL_NEON, largura := 220.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in total:
		var seg := Panel.new()
		seg.custom_minimum_size = Vector2(largura / total - 4.0, 10)
		var s := StyleBoxFlat.new()
		s.bg_color = cor if i < valor else Color(0.2, 0.25, 0.35, 0.7)
		s.skew = Vector2(0.4, 0)
		if i < valor:
			s.shadow_color = Color(cor, 0.5)
			s.shadow_size = 4
		seg.add_theme_stylebox_override("panel", s)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(seg)
	return h
