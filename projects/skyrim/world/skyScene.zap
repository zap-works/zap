# The exterior's sky in a cell scene: the sky drawn behind everything, the sun's light, the ambient
# cube, the fog and the exterior parts' emittance taken from it, and the hour's image space.

import engine
import skyrim.esm
import world.shaders

# the scene draws this sky (once, when the scene opens)
pub fn showSky(mut sc CellScene, move draw SkyDraw):
	sc.skyDraw = draw

# The ambient cube in the order the pixel stage reads it (+x -x +y -y +z -z of the renderer, whose
# y is the game's z and z the game's -y) from the sky's, in the game's axes.
fromGameAxes = [0, 1, 4, 5, 3, 2]

# The scene lit, fogged and graded by this sky: the sun's color times the image space's sunlight
# scale, from where the sky puts it; the weather's ambient cube; its fog and the colors it fades
# between; the color its externally lit parts take; the image space of the hour. `days` turns the
# stars.
pub fn setSky(mut sc CellScene, sky Sky, space esm.ImageSpace, days f32):
	sc.params.lightBy(sky, space)
	sc.picture.space = space.copy()
	sc.skyScale = space.skyScale
	sc.skyDays = days
	sc.sky = sky.copy()

# the light, fog and emittance of a pixel stage's parameters set from the sky and its image space
pub fn lightBy(mut p shaders.CellParams, sky Sky, space esm.ImageSpace):
	for i in 0..6:
		p.ambient[i] = sky.ambient[fromGameAxes[i]].withW(1.0)
	toward = sky.sunToward
	p.sunToward = Vec3(toward.x, toward.z, -toward.y).withW(0.0)
	p.sunColor = (sky.colors[esm.sunlightColor] * space.sunlightScale).withW(1.0)
	p.fogNearColor = sky.colors[esm.fogNearColor].withW(1.0)
	p.fogFarColor = sky.colors[esm.fogFarColor].withW(1.0)
	p.fog = Vec4(sky.fogNear, sky.fogFar, sky.fogPower, sky.fogMax)
	p.emittance = sky.colors[esm.effectLightingColor].withW(1.0)

# the sky drawn first after the target is cleared, when the scene has one
fn drawSkyBehind(mut r engine.Renderer, sc CellScene, projection Mat4, view Mat4):
	if sc.skyDraw is draw and sc.sky is sky:
		r.drawSky(draw, sky, projection, view, sc.skyScale, sc.skyDays)

# the sky's clouds and precipitation `dt` seconds on (the scene's advance)
pub fn stepSky(mut sc CellScene, dt f32):
	if sc.skyDraw is mut draw and sc.sky is sky:
		draw.advanceSky(sky, dt)

# the rain or snow falling in the sky, over what the scene drew (finishCell)
fn drawFalling(mut r engine.Renderer, sc CellScene):
	if sc.skyDraw is draw and sc.sky is sky:
		r.drawPrecipitation(
			draw,
			sky,
			sc.params.projection,
			sc.params.view,
			sc.picture.scene.width,
			sc.picture.scene.height
		)
