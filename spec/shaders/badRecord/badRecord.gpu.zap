# A storage buffer's record whose Vec4 follows a scalar: std430 puts it at byte 16, Direct3D's
# structured buffer at byte 4 (the shader tests expect the error).

pub type Record:
	weight f32
	tint Vec4

pub type Records:
	records Record[]

pub fn pixel(uv Vec2, p Records) Vec4:
	which = i32(uv.x)
	p.records[which].tint * p.records[which].weight
