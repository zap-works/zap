# Prints what an HKX file of Skyrim holds: a skeleton's bone tree (and its ragdoll: the bodies,
# their constraints and the skeleton mappers, when it has one), or an animation's duration,
# frames and tracks with the bones they move (named by the install's character skeleton), and with
# --frame n every track's transform at frame n. --all-male reads every animation of the male
# character and counts those that parse.
#
#   zap run projects/skyrim/hkxInfo.zap [--install dir] <key> [--frame n]
#   zap run projects/skyrim/hkxInfo.zap [--install dir] --file path [--frame n]
#   zap run projects/skyrim/hkxInfo.zap [--install dir] --all-male

import fs
import skyrim
import skyrim.hkx
import skyrim.actor

fn printSkeleton(s hkx.Skeleton):
	print("skeleton {s.name}: {s.bones.len} bones")
	depth i64[] = []
	for i, b in s.bones:
		depth.push(0 if b.parent < 0 else depth[b.parent] + 1)
		print("{"  ".repeat(depth[i])}{i} {b.name}")

fn printTransform(t hkx.Transform):
	p = t.translation
	q = t.rotation
	s = t.scale
	print(
		"    at ({p.x}, {p.y}, {p.z}) turn ({q.x}, {q.y}, {q.z}, {q.w}) scale ({s.x}, {s.y}, {s.z})"
	)

fn printRagdoll(r hkx.Ragdoll):
	print(
		"ragdoll: {r.bodies.len} bodies, {r.joints.len} constraints, {r.skeleton.bones.len} bones"
	)
	for b in r.bodies:
		print("  {b.name}: {b.mass:.1} kg, capsule {b.a} {b.b} r {b.radius:.2}, at {b.frame.translation}, filter {b.filter:x}, friction {b.friction} restitution {b.restitution} damping {b.linearDamping} {b.angularDamping}")
	for j in r.joints:
		print("  {j.name}: {r.bodies[j.a].name} on {r.bodies[j.b].name}, {j.limits}, friction {j.maxFriction}")
	for m in [r.toRagdoll.copy(), r.toAnimation.copy()]:
		print("  mapper: {m.simple.len} simple, {m.chains.len} chains, {m.unmapped.len} unmapped, keep local {m.keepUnmappedLocal}")

fn boneName(bones str[], i i64):
	bones[i].copy() if i >= 0 and i < bones.len else "bone {i}"

fn printAnimation(a hkx.Animation, bones str[], frame i64?):
	print("animation of {a.skeletonName}: {a.duration} s, {a.frames} frames ({f32(1.0) / a.frameDuration} fps), {a.trackCount()} tracks, {a.blocks.len} blocks")
	pose = a.frame(frame ?? 0)
	for t in 0..a.trackCount():
		print("  track {t}: {bones.boneName(a.trackToBone[t])}")
		if frame != none: pose[t].printTransform()

# every male animation read: how many parse, which classes are not supported, which fail
fn readAllMale(install skyrim.Install):
	read = 0
	unsupported {str: i64} = {}
	failed = 0
	for key in install.installFind(actor.maleAnimations):
		if not key.endsWith(".hkx"): continue
		bytes = install.installRead(key) ?? fail("{key} vanished")
		className = hkx.animationClass(bytes) ?? ""
		if className != "" and className != "hkaSplineCompressedAnimation":
			unsupported[className] = (unsupported.get(className) ?? 0) + 1
			continue
		match hkx.readAnimation(bytes):
			a: read += 1
			error:
				failed += 1
				print("{key}: {error}")
	print("{read} spline compressed animations read, {failed} failed")
	for className in unsupported.keys().sorted():
		print("{unsupported[className]} of {className}, not supported")
	if failed > 0: fail("{failed} animations failed")

# the bytes of the file with that key in the install
fn installFile(opened skyrim.Install ? str, key str):
	match opened:
		install: return install.installRead(key) ?? fail("{key} is in no archive")
		error: fail(error)

fn readFile(path str):
	fs.readBytes(path) ?? fail("cannot read {path}")

# the names of the install's character skeleton's bones, none without the install
fn characterBones(opened skyrim.Install ? str):
	match opened:
		install:
			character = install.installRead(actor.characterSkeleton) ?? []
			match hkx.readSkeleton(character):
				s: return s.bones.map(.name.copy())
				error: eprint("bones unnamed: {error}")
		error: eprint("bones unnamed: {error}")
	[]

dir = args.option("--install") ?? skyrim.defaultInstall
file = args.option("--file")
frame = args.option("--frame")
args.options(
	[
		skyrim.installOption,
		ArgOption("--file", true, "a file instead of an archive key"),
		ArgOption("--frame", true, "the frame to show")
	]
)
rest = args.positional()
opened = skyrim.openInstall(dir)
if args.hasFlag("--all-male"):
	match opened:
		install: install.readAllMale()
		error: fail(error)
	return
if file == none and rest.isEmpty: fail("give a key, --file path or --all-male")
bytes = opened.installFile(rest[0]) if file == none else readFile(file ?? "")
match hkx.readSkeleton(bytes):
	s:
		s.printSkeleton()
		if hkx.readRagdoll(bytes) is r: r.printRagdoll()
	error:
		a = hkx.readAnimation(bytes) ?? fail
		n = frame ?? ""
		a.printAnimation(opened.characterBones(), i64.parse(n) if frame != none else none)
