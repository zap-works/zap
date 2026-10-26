# IMGS: an image space, how the game grades the picture of a cell (XCIM names it): its HDR (HNAM:
# eye adaptation, bloom, white), its cinematic (CNAM: saturation, brightness, contrast) and its
# tint (TNAM: how much, its color).

# the image space the game falls back on where a cell names none
pub defaultImageSpace = 0x167

pub type ImageSpace:
	editorId str
	eyeAdaptSpeed f32
	bloomBlurRadius f32
	bloomThreshold f32
	bloomScale f32
	receiveBloomThreshold f32
	white f32
	sunlightScale f32
	skyScale f32
	eyeAdaptStrength f32
	saturation f32
	brightness f32
	contrast f32
	tintAmount f32
	tint Vec3

fn floatsOf(body u8[], fields Field[], tag str, n i64):
	for f in fields:
		if f.tag == tag and f.size >= n * 4: return (0..n).map(body.f32le(f.at + it * 4))
	fill(n, 0.0)

# The image space with this form id, none when the plugin has none of that id or it lacks the
# HDR and cinematic fields (the old ENAM layout).
pub fn imageSpaceOf(mut e Esm, formId i64) ImageSpace?:
	r = try e.recordOf(formId)
	if r.kind != "IMGS" or dataOf(r.fields, "HNAM") == none: return none
	hdr = floatsOf(r.body, r.fields, "HNAM", 9)
	cinematic = floatsOf(r.body, r.fields, "CNAM", 3)
	tint = floatsOf(r.body, r.fields, "TNAM", 4)
	ImageSpace(
		editorId = textOf(r.body, r.fields, "EDID"),
		eyeAdaptSpeed = hdr[0],
		bloomBlurRadius = hdr[1],
		bloomThreshold = hdr[2],
		bloomScale = hdr[3],
		receiveBloomThreshold = hdr[4],
		white = hdr[5],
		sunlightScale = hdr[6],
		skyScale = hdr[7],
		eyeAdaptStrength = hdr[8],
		saturation = cinematic[0],
		brightness = cinematic[1],
		contrast = cinematic[2],
		tintAmount = tint[0],
		tint = Vec3(tint[1], tint[2], tint[3])
	)

# The image spaces added up with their weights, field by field (the executable's 0x141536ac0 adds
# each into a zeroed one): the hour's blend of the weather's.
pub fn mixedSpaces(spaces ImageSpace[], weights f32[]) ImageSpace:
	mixed = spaces[0].copy()
	mixed.eyeAdaptSpeed = 0.0
	mixed.bloomBlurRadius = 0.0
	mixed.bloomThreshold = 0.0
	mixed.bloomScale = 0.0
	mixed.receiveBloomThreshold = 0.0
	mixed.white = 0.0
	mixed.sunlightScale = 0.0
	mixed.skyScale = 0.0
	mixed.eyeAdaptStrength = 0.0
	mixed.saturation = 0.0
	mixed.brightness = 0.0
	mixed.contrast = 0.0
	mixed.tintAmount = 0.0
	mixed.tint = Vec3(0.0, 0.0, 0.0)
	for k, s in spaces:
		w = weights[k]
		mixed.eyeAdaptSpeed += s.eyeAdaptSpeed * w
		mixed.bloomBlurRadius += s.bloomBlurRadius * w
		mixed.bloomThreshold += s.bloomThreshold * w
		mixed.bloomScale += s.bloomScale * w
		mixed.receiveBloomThreshold += s.receiveBloomThreshold * w
		mixed.white += s.white * w
		mixed.sunlightScale += s.sunlightScale * w
		mixed.skyScale += s.skyScale * w
		mixed.eyeAdaptStrength += s.eyeAdaptStrength * w
		mixed.saturation += s.saturation * w
		mixed.brightness += s.brightness * w
		mixed.contrast += s.contrast * w
		mixed.tintAmount += s.tintAmount * w
		mixed.tint += s.tint * w
	mixed
