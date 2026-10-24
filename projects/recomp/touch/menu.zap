# The overlay's menu: the frame darkened, the program's items as a column of pills in its middle
# and below them its level row when it has one, a bar filled to the level; a finger landing on an
# item chooses it, one on the bar sets the level where it touches (and follows while it stays),
# anywhere else closes the menu.

# the items' columns: two once one would not fit the frame's height
fn menuColumns(o Overlay):
	1 if o.items.len <= 4 else 2

# the rows: the items', then the level's
fn menuRows(o Overlay):
	(o.items.len + o.menuColumns() - 1) / o.menuColumns() + (0 if o.levelName.isEmpty else 1)

# the pill of item i in the frame, the level's bar when i is the items' count (a row of its own,
# in the middle)
fn itemShape(o Overlay, i i64):
	fh = f64(o.frame.height)
	gap = fh * 0.17
	top = fh / 2.0 - gap * (o.menuRows() - 1) / 2.0
	columns = o.menuColumns()
	row = i / columns if i < o.items.len else o.menuRows() - 1
	column = f64(i % columns) - (columns - 1) / 2.0 if i < o.items.len else 0.0
	Capsule(
		x = o.frame.width / 2.0 + column * fh * 0.6,
		y = top + gap * row,
		half = fh * 0.22,
		r = fh * 0.06
	)

fn readMenu(mut o Overlay, fingers Vec2[]):
	for b in 0..o.held.len:
		o.held[b] = false
	if fingers.isEmpty:
		o.dragging = false
		return
	x = f64(fingers[0].x)
	y = f64(fingers[0].y)
	landing = o.fingers == 0
	if not o.levelName.isEmpty:
		bar = o.itemShape(o.items.len)
		if o.dragging or (landing and bar.edgeDistance(x, y) < 0.0):
			o.dragging = true
			o.level = ((x - bar.x + bar.half) / (2.0 * bar.half) * 20.0).round().clamp(0.0, 20.0) /
				20.0
			o.levelChanged = true
			return
	if not landing: return
	for i in 0..o.items.len:
		if o.itemShape(i).edgeDistance(x, y) < 0.0:
			o.chosen = i
	o.menuOpen = false
	o.touched = []

fn paintMenu(mut o Overlay):
	for y in 0..o.frame.height:
		for x in 0..o.frame.width:
			o.frame.blend(x, y, 0.0, 0.6)
	for i, item in o.items:
		shape = o.itemShape(i)
		o.frame.paintCapsule(shape, 0.35, 0.7, shape.r * 0.08, false)
		o.frame.paintText(item.upper(), shape.x, shape.y, shape.r * 0.6, 0.9)
	if o.levelName.isEmpty: return
	bar = o.itemShape(o.items.len)
	o.frame.paintCapsule(bar, 0.35, 0.7, bar.r * 0.08, false)
	if o.level > 0.0:
		filled = Capsule(
			x = bar.x - bar.half + bar.half * o.level,
			y = bar.y,
			half = bar.half * o.level,
			r = bar.r * 0.8
		)
		o.frame.paintCapsule(filled, 0.3, 0.0, 0.0, true)
	label = "{o.levelName.upper()} {i64((o.level * 100.0).round())}%"
	o.frame.paintText(label, bar.x, bar.y, bar.r * 0.6, 0.9)
