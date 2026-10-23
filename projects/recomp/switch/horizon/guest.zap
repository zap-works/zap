# Bytes moved between the host and the guest's memory.

import recomp.switch.cpu

pub fn putBytes(at i64, bytes u8[]):
	cpu.memory.write(at, bytes)

pub fn getBytes(at i64, n i64) u8[]:
	cpu.memory.read(at, n)

# the bytes written into the buffer, cut to its size
pub fn putBuffer(buf Buffer, bytes u8[]):
	putBytes(buf.at, bytes[..bytes.len.min(buf.size)])
