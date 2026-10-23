# The built-in functions the shaders call, as methods of their first value with the names Zap's
# numbers and the language's vectors give them on the CPU (x.floor(), v.normalized(),
# a.lerp(b, t), y.atan2(x), t.sample(uv)): what each is called and how it takes its arguments
# (component by component, a number spread over a vector; the vector ones: cross, length,
# normalized, reflect; derivatives and the texture reads), its type mc's. The writers write each
# as SPIR-V (mc/irspirv.zap) and HLSL (mc/irhlsl.zap) have it.

# A built-in function: its name in Zap (a method) and in HLSL; its instruction of GLSL.std.450
# (-1: a core instruction; min, max, clamp and abs a float's, see mc/irspirv.zap's std450Of); the
# order of its arguments (0 the value the method is called on, 1 its first argument...).
pub type Builtin:
	zap str
	hlsl str
	std450 i64
	order i64[]

fn row(zap str, hlsl str, std450 i64, order i64[]):
	Builtin(zap = zap.copy(), hlsl = hlsl.copy(), std450, order = order.copy())

pub builtinFunctions = [
	row("abs", "abs", 4, [0]),
	row("sign", "sign", 6, [0]),
	row("floor", "floor", 8, [0]),
	row("ceil", "ceil", 9, [0]),
	row("round", "round", 1, [0]),
	row("trunc", "trunc", 3, [0]),
	row("fract", "frac", 10, [0]),
	row("sqrt", "sqrt", 31, [0]),
	row("inverseSqrt", "rsqrt", 32, [0]),
	row("exp", "exp", 27, [0]),
	row("exp2", "exp2", 29, [0]),
	row("ln", "log", 28, [0]),
	row("log2", "log2", 30, [0]),
	row("sin", "sin", 13, [0]),
	row("cos", "cos", 14, [0]),
	row("tan", "tan", 15, [0]),
	row("asin", "asin", 16, [0]),
	row("acos", "acos", 17, [0]),
	row("atan", "atan", 18, [0]),
	row("sinh", "sinh", 19, [0]),
	row("cosh", "cosh", 20, [0]),
	row("tanh", "tanh", 21, [0]),
	row("radians", "radians", 11, [0]),
	row("degrees", "degrees", 12, [0]),
	row("length", "length", 66, [0]),
	row("normalized", "normalize", 69, [0]),
	row("transpose", "transpose", -1, [0]),
	row("ddx", "ddx", -1, [0]),
	row("ddy", "ddy", -1, [0]),
	row("fwidth", "fwidth", -1, [0]),
	row("atan2", "atan2", 25, [0, 1]),
	row("pow", "pow", 26, [0, 1]),
	row("min", "min", 37, [0, 1]),
	row("max", "max", 40, [0, 1]),
	row("cross", "cross", 68, [0, 1]),
	row("distance", "distance", 67, [0, 1]),
	row("reflect", "reflect", 71, [0, 1]),
	row("clamp", "clamp", 43, [0, 1, 2]),
	row("refract", "refract", 72, [0, 1, 2]),
	row("lerp", "lerp", 46, [0, 1, 2]),
	row("step", "step", 48, [1, 0]),
	row("smoothstep", "smoothstep", 49, [1, 2, 0]),
	row("mulAdd", "mad", 50, [0, 1, 2])]

# An operation across the lanes that run together (a subgroup, a wave): its name in Zap (a
# method of a number, a vector or a bool), in HLSL, its SPIR-V instruction for
# floats, ints and uints (a GroupNonUniform one), its group operation (0 reduce, 2 the exclusive
# scan, -1 none) and the capability it needs.
pub type LaneFunction:
	zap str
	hlsl str
	spirv i64[]
	operation i64
	capability i64

fn lane(zap str, hlsl str, spirv i64[], operation i64, capability i64):
	LaneFunction(zap = zap.copy(), hlsl = hlsl.copy(), spirv = spirv.copy(), operation, capability)

pub laneFunctions = [
	lane("laneSum", "WaveActiveSum", [350, 349, 349], 0, 63),
	lane("lanePrefixSum", "WavePrefixSum", [350, 349, 349], 2, 63),
	lane("laneMin", "WaveActiveMin", [355, 353, 354], 0, 63),
	lane("laneMax", "WaveActiveMax", [358, 356, 357], 0, 63),
	lane("laneFirst", "WaveReadLaneFirst", [338, 338, 338], -1, 64),
	lane("laneAt", "WaveReadLaneAt", [345, 345, 345], -1, 65),
	lane("laneAny", "WaveActiveAnyTrue", [335, 335, 335], -1, 62),
	lane("laneAll", "WaveActiveAllTrue", [334, 334, 334], -1, 62)]
