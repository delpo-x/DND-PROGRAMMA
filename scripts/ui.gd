class_name UI
extends RefCounted
## Small helpers to build big, touch-friendly controls in code.

# "Candlelit tavern" palette: dark leather, antique gold, parchment text,
# wine red for the big actions.
const GOLD := Color(0.86, 0.69, 0.38)
const GOLD_DIM := Color(0.52, 0.39, 0.2)
const RED := Color(0.72, 0.2, 0.18)
const WINE := Color(0.45, 0.09, 0.1)
const GREEN := Color(0.33, 0.62, 0.36)
const TEXT := Color(0.94, 0.88, 0.76)
# secondary text: at least 4.5:1 on every panel (WCAG AA)
const DIM := Color(0.72, 0.655, 0.56)
# keyboard focus ring and field borders: at least 3:1 on the background
const FOCUS := Color(1.0, 0.85, 0.5)
const FIELD_LINE := Color(0.6, 0.46, 0.27)
const BG := Color(0.075, 0.055, 0.045)
const PANEL := Color(0.15, 0.105, 0.08)
const PANEL2 := Color(0.21, 0.15, 0.11)

static var _display: Font


## Engraved serif for titles, tabs and big buttons. Uses fonts already on the
## device (Windows: Palatino / Book Antiqua / Georgia; Android: Noto Serif).
static func display_font() -> Font:
	if _display == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Palatino Linotype", "Book Antiqua", "Georgia", "Noto Serif", "serif"])
		f.font_weight = 600
		_display = f
	return _display


## Gives a control the display font.
static func engrave(c: Control, size := 0) -> Control:
	c.add_theme_font_override("font", display_font())
	if size > 0:
		c.add_theme_font_size_override("font_size", size)
	return c


static func btn(text: String, cb: Callable = Callable(), min_h := 52, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.focus_mode = Control.FOCUS_ALL  # reachable with Tab, Enter / Space press it
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func color_btn(text: String, col: Color, cb: Callable = Callable(), min_h := 52) -> Button:
	var b := btn(text, cb, min_h)
	# mute bright colours so they sit in the candlelit palette
	col = Color.from_hsv(col.h, col.s * 0.85, col.v * 0.82, col.a)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		var c := col
		if st == "hover":
			c = col.lightened(0.12)
		elif st == "pressed":
			c = col.darkened(0.2)
		sb.bg_color = c
		sb.set_corner_radius_all(6)
		sb.border_color = c.lerp(GOLD, 0.45)
		sb.set_border_width_all(1)
		sb.border_width_bottom = 3 if st != "pressed" else 1
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 3 if st != "pressed" else 0
		sb.shadow_offset = Vector2(0, 2)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	return b


static func lbl(text: String, size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0:
		l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func wrap_lbl(text: String, size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := lbl(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func hbox(children: Array = [], sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	for c in children:
		h.add_child(c)
	return h


static func vbox(children: Array = [], sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	for c in children:
		v.add_child(c)
	return v


static func flow(children: Array = [], sep := 8) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	for c in children:
		f.add_child(c)
	return f


static func expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func spin(minv: int, maxv: int, val: int, cb: Callable = Callable(), w := 120) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minv
	s.max_value = maxv
	s.value = val
	s.step = 1
	s.rounded = true
	s.custom_minimum_size = Vector2(w, 48)
	s.select_all_on_focus = true
	if cb.is_valid():
		s.value_changed.connect(func(v): cb.call(int(v)))
	return s


## Value of a SpinBox including a number typed but not yet confirmed.
static func spin_value(s: SpinBox) -> int:
	s.apply()
	return int(s.value)


static func edit(text: String, placeholder := "", cb: Callable = Callable(), w := 0) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(w, 48)
	if w == 0:
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if cb.is_valid():
		e.text_changed.connect(cb)
	return e


static func option(items: Array, selected := 0, cb: Callable = Callable(), w := 0) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.custom_minimum_size = Vector2(w, 48)
	o.focus_mode = Control.FOCUS_ALL
	if items.size() > 0:
		o.select(clampi(selected, 0, items.size() - 1))
	if cb.is_valid():
		o.item_selected.connect(cb)
	return o


static func check(text: String, pressed := false, cb: Callable = Callable()) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = pressed
	c.focus_mode = Control.FOCUS_ALL
	c.custom_minimum_size = Vector2(0, 44)
	if cb.is_valid():
		c.toggled.connect(cb)
	return c


static func card(content: Control, col := PANEL, pad := 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	sb.border_color = Color(GOLD_DIM, 0.55)
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(content)
	return p


static func scroll(content: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Section heading: engraved gold capitals over a thin gold rule.
static func title(text: String) -> Label:
	var l := lbl(text.to_upper(), 23, GOLD)
	engrave(l)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(GOLD_DIM, 0.8)
	sb.border_width_bottom = 1
	sb.content_margin_top = 10
	sb.content_margin_bottom = 4
	l.add_theme_stylebox_override("normal", sb)
	return l


## Keyboard focus: a bright gold outline drawn over the control (WCAG 2.4.7).
static func focus_ring() -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = FOCUS
	f.set_border_width_all(2)
	f.set_corner_radius_all(6)
	f.expand_margin_left = 2
	f.expand_margin_right = 2
	f.expand_margin_top = 2
	f.expand_margin_bottom = 2
	return f


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color = PANEL2
	sb_n.set_corner_radius_all(6)
	sb_n.border_color = GOLD_DIM
	sb_n.set_border_width_all(1)
	sb_n.border_width_bottom = 3
	sb_n.shadow_color = Color(0, 0, 0, 0.3)
	sb_n.shadow_size = 2
	sb_n.shadow_offset = Vector2(0, 2)
	sb_n.content_margin_left = 14
	sb_n.content_margin_right = 14
	sb_n.content_margin_top = 8
	sb_n.content_margin_bottom = 8
	var sb_h: StyleBoxFlat = sb_n.duplicate()
	sb_h.bg_color = PANEL2.lightened(0.1)
	var sb_p: StyleBoxFlat = sb_n.duplicate()
	sb_p.bg_color = Color(0.4, 0.27, 0.12)
	sb_p.border_color = GOLD
	sb_p.border_width_bottom = 1
	sb_p.shadow_size = 0
	var sb_d: StyleBoxFlat = sb_n.duplicate()
	sb_d.bg_color = PANEL2.darkened(0.3)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, sb_n)
		t.set_stylebox("hover", cls, sb_h)
		t.set_stylebox("pressed", cls, sb_p)
		t.set_stylebox("hover_pressed", cls, sb_p)
		t.set_stylebox("disabled", cls, sb_d)
		t.set_stylebox("focus", cls, focus_ring())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, TEXT)
		t.set_color("font_pressed_color", cls, Color.WHITE)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", TEXT)
	t.set_color("font_pressed_color", "CheckBox", GOLD)
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0.055, 0.04, 0.03)
	le.set_corner_radius_all(4)
	le.border_color = FIELD_LINE
	le.set_border_width_all(1)
	le.content_margin_left = 10
	le.content_margin_right = 10
	le.content_margin_top = 6
	le.content_margin_bottom = 6
	var le_f: StyleBoxFlat = le.duplicate()
	le_f.border_color = GOLD
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_f)
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(GOLD, 0.35))
	t.set_color("font_placeholder_color", "LineEdit", Color(0.64, 0.58, 0.5))
	t.set_color("font_placeholder_color", "TextEdit", Color(0.64, 0.58, 0.5))
	for cls in ["CheckBox", "TabContainer", "SpinBox", "ItemList", "Tree"]:
		t.set_stylebox("focus", cls, focus_ring())
	t.set_stylebox("normal", "TextEdit", le)
	t.set_stylebox("focus", "TextEdit", le_f)
	t.set_color("caret_color", "TextEdit", GOLD)
	t.set_color("selection_color", "TextEdit", Color(GOLD, 0.35))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_color", "TextEdit", TEXT)
	var tab_sel := StyleBoxFlat.new()
	tab_sel.bg_color = PANEL2
	tab_sel.border_color = GOLD
	tab_sel.border_width_bottom = 3
	tab_sel.border_width_top = 1
	tab_sel.border_width_left = 1
	tab_sel.border_width_right = 1
	tab_sel.corner_radius_top_left = 6
	tab_sel.corner_radius_top_right = 6
	tab_sel.content_margin_left = 18
	tab_sel.content_margin_right = 18
	tab_sel.content_margin_top = 12
	tab_sel.content_margin_bottom = 12
	var tab_un: StyleBoxFlat = tab_sel.duplicate()
	tab_un.bg_color = Color(0, 0, 0, 0)
	tab_un.set_border_width_all(0)
	tab_un.border_width_bottom = 1
	tab_un.border_color = Color(GOLD_DIM, 0.5)
	var tab_hov: StyleBoxFlat = tab_un.duplicate()
	tab_hov.bg_color = Color(PANEL2, 0.6)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hov)
	var tpanel := StyleBoxFlat.new()
	tpanel.bg_color = Color(0, 0, 0, 0)
	tpanel.content_margin_left = 10
	tpanel.content_margin_right = 10
	tpanel.content_margin_top = 10
	tpanel.content_margin_bottom = 10
	t.set_stylebox("panel", "TabContainer", tpanel)
	t.set_font_size("font_size", "TabContainer", 21)
	t.set_font("font", "TabContainer", display_font())
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color(GOLD_DIM, 0.55)
	sc.set_corner_radius_all(4)
	var sc_bg := StyleBoxFlat.new()
	sc_bg.bg_color = Color(0, 0, 0, 0.25)
	sc_bg.set_corner_radius_all(4)
	for sb_cls in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("grabber", sb_cls, sc)
		t.set_stylebox("grabber_highlight", sb_cls, sc)
		t.set_stylebox("grabber_pressed", sb_cls, sc)
		t.set_stylebox("scroll", sb_cls, sc_bg)
	var pop := StyleBoxFlat.new()
	pop.bg_color = PANEL
	pop.border_color = GOLD_DIM
	pop.set_border_width_all(1)
	pop.set_corner_radius_all(6)
	pop.set_content_margin_all(8)
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("panel", "PopupPanel", pop)
	t.set_stylebox("panel", "AcceptDialog", pop)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 8)
	return t
