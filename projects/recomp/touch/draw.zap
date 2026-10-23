# The controls laid over the frame, at the settings' opacity, a held one lit; only PAD and MENU
# while the pad is hidden.

fn paintControls(mut o Overlay, cs Control[]):
	a = o.settings.opacity
	for c in cs:
		if not o.shown and c.kind < toggleControl: continue
		if c.isStick():
			lean = o.push[c.kind - stickControl]
			o.frame.paintCapsule(c.shape, 0.12 * a, 0.3 * a, c.shape.r * 0.05, false)
			reach = c.stickReach()
			knob = Capsule(
				x = c.shape.x + f64(lean.x) * reach,
				y = c.shape.y + f64(lean.y) * reach,
				r = c.shape.r * 0.42
			)
			o.frame.paintCapsule(
				knob,
				0.3 * a,
				0.45 * a,
				knob.r * 0.12,
				lean.x != 0.0 or lean.y != 0.0
			)
			continue
		lit = c.kind < o.held.len and o.held[c.kind]
		o.frame.paintCapsule(c.shape, 0.18 * a, 0.35 * a, c.shape.r * 0.1, lit)
		size = c.shape.r * (0.75 if c.label.len == 1 else 0.6)
		o.frame.paintText(c.label, c.shape.x, c.shape.y, size, 0.6 * a)
