# set and set:sys, the system settings (switchbrew: Settings services): the language, region and
# firmware version a console reports. This one is an English-language console of the Americas
# on firmware 22.5.0.

# the languages by their index (nn::settings::Language), as their codes
languageCodes = [
	"ja",
	"en-US",
	"fr",
	"de",
	"it",
	"es",
	"zh-CN",
	"ko",
	"nl",
	"pt",
	"ru",
	"zh-TW",
	"en-GB",
	"fr-CA",
	"es-419",
	"zh-Hans",
	"zh-Hant",
	"pt-BR"
]

regionUsa = 1

# a language code's characters as the u64 the services pass
pub fn languageCode(index i64) i64:
	v = 0
	for k, c in languageCodes[index].bytes():
		v |= i64(c) << (8 * k)
	v

fn settings(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0: res.u64(languageCode(1))
		1, 5:
			out = req.receive(0)
			count = languageCodes.len.min(out.size / 8)
			putBuffer(out, languageCodeBytes(count))
			res.u32(count)
		2: res.u64(languageCode(req.arg(0, 4)))
		3, 6: res.u32(languageCodes.len)
		4: res.u32(regionUsa)
		_: k.unwritten(i, req)

# the firmware version (switchbrew: System Version Title), 0x100 bytes
fn firmwareVersion() u8[]:
	v u8[] = zeros(0x100)
	v[0] = 22
	v[1] = 5
	v[2] = 0
	v[4] = 1
	for k, c in "NX".bytes():
		v[8 + k] = c
	for k, c in "22.5.0".bytes():
		v[0x68 + k] = c
	for k, c in "NintendoSDK Firmware for NX 22.5.0-1.0".bytes():
		v[0x80 + k] = c
	v

fn systemSettings(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		3, 4: putBuffer(req.receive(0), firmwareVersion())
		23: res.u32(0)   # the colour set: basic white
		62: res.u8(0)
		_: k.unwritten(i, req)

# the first n language codes, as the u64s a buffer holds
fn languageCodeBytes(n i64) u8[]:
	out u8[] = []
	for j in 0..n:
		out.pushU64le(languageCode(j))
	out
