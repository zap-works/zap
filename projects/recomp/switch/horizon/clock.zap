# time:u, time:a and time:s (switchbrew: PSC services): the clocks and the time zone. The
# console's date starts at 2026-01-01 UTC and moves with the counter, so a run repeats; its time
# zone is UTC. The clocks of one source (a made-up steady clock id) agree, so a context never
# looks stale.

import date
import recomp.switch.cpu

firstOfJanuary2026 = 1_767_225_600
timeZoneName = "UTC"
secondsPerDay = 86_400

# the seconds since the epoch, on the console's clock
fn posixNow(mut k Kernel):
	firstOfJanuary2026 + k.now() / cpu.counterHz

# a CalendarTime (year i16, month, day, hour, minute, second, a pad byte) and its additional info
# (day of week from Sunday, day of the year, the zone's name, is daylight time, UTC offset)
fn calendarOf(time i64, mut res Response):
	days = time / secondsPerDay - (1 if time % secondsPerDay < 0 else 0)
	secs = time - days * secondsPerDay
	civil = date.civilOfDay(days)
	year = civil.year
	month = civil.month
	day = civil.day
	res.data.pushU16le(year)
	for v in [month, day, secs / 3600, secs / 60 % 60, secs % 60, 0]:
		res.u8(v)
	res.u32((days + 4) % 7 if (days + 4) % 7 >= 0 else (days + 4) % 7 + 7)
	res.u32(days - date.daysFromCivil(year, 1, 1))
	res.bytes(timeZoneName.bytes())
	res.align(8 + 8)
	res.u32(0)
	res.u32(0)

# a SteadyClockTimePoint: the time and the id of the clock it is read from
fn steadyTimePoint(mut k Kernel, mut res Response):
	res.u64(k.now() / cpu.counterHz)
	res.u64(0x5EAD_C10C)
	res.u64(0)

fn staticService(mut k Kernel, i i64, req Request, mut res Response):
	names = {
		0: "ISystemClock",
		1: "ISystemClock",
		2: "ISteadyClock",
		3: "ITimeZoneService",
		4: "ISystemClock",
		5: "ISystemClock"
	}
	match req.command:
		20: res.copied.push(k.newSharedMemory(0x1000, zeros(0x1000)))
		_:
			if names.get(req.command) is name: k.offer(res, name)
			else: k.unwritten(i, req)

fn systemClock(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0: res.u64(k.posixNow())
		2:
			res.u64(0)
			k.steadyTimePoint(res)
		_: k.unwritten(i, req)

fn steadyClock(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0: k.steadyTimePoint(res)
		_: k.unwritten(i, req)

fn timeZoneService(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0:
			res.bytes(timeZoneName.bytes())
			res.align(0x24)
		2: res.u32(1)
		4:
			req.receive(0).putBuffer(zeros(0x4000))
		5:
			res.u64(0)
			res.u64(0)
		100, 101: calendarOf(req.arg(0, 8), res)
		201, 202:
			year = req.arg(0, 2)
			days = date.daysFromCivil(year, req.data[2], req.data[3])
			time = days * secondsPerDay + i64(req.data[4]) * 3600 + i64(req.data[5]) * 60 +
				i64(req.data[6])
			bytes = []
			bytes.pushU64le(time)
			req.receive(0).putBuffer(bytes)
			res.u32(1)
		_: k.unwritten(i, req)
