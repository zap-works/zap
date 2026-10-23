# time:u, time:a and time:s (switchbrew: PSC services): the clocks and the time zone. The
# console's date starts at 2026-01-01 UTC and moves with the counter, so a run repeats; its time
# zone is UTC. The clocks of one source (a made-up steady clock id) agree, so a context never
# looks stale.

import recomp.switch.cpu

firstOfJanuary2026 = 1_767_225_600
timeZoneName = "UTC"
secondsPerDay = 86_400

# the seconds since the epoch, on the console's clock
fn posixNow(mut k Kernel) i64:
	firstOfJanuary2026 + k.now() / cpu.counterHz

# days since 1970-01-01 to (year, month 1-12, day 1-31), after Hinnant's civil_from_days
fn civilFromDays(days i64) (i64, i64, i64):
	z = days + 719_468
	era = (z if z >= 0 else z - 146_096) / 146_097
	doe = z - era * 146_097
	yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
	doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp = (5 * doy + 2) / 153
	day = doy - (153 * mp + 2) / 5 + 1
	month = mp + 3 if mp < 10 else mp - 9
	(yoe + era * 400 + (1 if month <= 2 else 0), month, day)

# the inverse: (year, month, day) to days since 1970-01-01
fn daysFromCivil(year i64, month i64, day i64) i64:
	y = year - (1 if month <= 2 else 0)
	era = (y if y >= 0 else y - 399) / 400
	yoe = y - era * 400
	doy = (153 * (month + (-3 if month > 2 else 9)) + 2) / 5 + day - 1
	doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
	era * 146_097 + doe - 719_468

# a CalendarTime (year i16, month, day, hour, minute, second, a pad byte) and its additional info
# (day of week from Sunday, day of the year, the zone's name, is daylight time, UTC offset)
fn calendarOf(time i64, mut res Response):
	days = time / secondsPerDay - (1 if time % secondsPerDay < 0 else 0)
	secs = time - days * secondsPerDay
	year, month, day = civilFromDays(days)
	res.data.pushU16le(year)
	for v in [month, day, secs / 3600, secs / 60 % 60, secs % 60, 0]:
		res.u8(v)
	res.u32((days + 4) % 7 if (days + 4) % 7 >= 0 else (days + 4) % 7 + 7)
	res.u32(days - daysFromCivil(year, 1, 1))
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
			putBuffer(req.receive(0), zeros(0x4000))
		5:
			res.u64(0)
			res.u64(0)
		100, 101: calendarOf(req.arg(0, 8), res)
		201, 202:
			year = req.arg(0, 2)
			days = daysFromCivil(year, i64(req.data[2]), i64(req.data[3]))
			time = days * secondsPerDay + i64(req.data[4]) * 3600 + i64(req.data[5]) * 60 +
				i64(req.data[6])
			bytes u8[] = []
			bytes.pushU64le(time)
			putBuffer(req.receive(0), bytes)
			res.u32(1)
		_: k.unwritten(i, req)
