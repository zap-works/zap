# Dates of the proleptic Gregorian calendar as day numbers since 1970-01-01 (Howard Hinnant's
# civil_from_days and days_from_civil).

# a date: the year, the month 1-12 and the day 1-31
pub type Civil:
	year i64
	month i64
	day i64

# the date of a day number
pub fn civilOfDay(days i64) Civil:
	z = days + 719_468
	era = (z if z >= 0 else z - 146_096) / 146_097
	doe = z - era * 146_097
	yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
	doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp = (5 * doy + 2) / 153
	day = doy - (153 * mp + 2) / 5 + 1
	month = mp + 3 if mp < 10 else mp - 9
	Civil(year = yoe + era * 400 + (1 if month <= 2 else 0), month, day)

# the day number of a (year, month, day)
pub fn daysFromCivil(year i64, month i64, day i64) i64:
	y = year - (1 if month <= 2 else 0)
	era = (y if y >= 0 else y - 399) / 400
	yoe = y - era * 400
	doy = (153 * (month + (-3 if month > 2 else 9)) + 2) / 5 + day - 1
	doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
	era * 146_097 + doe - 719_468

test "day numbers and dates agree around the epoch and a leap day":
	expect civilOfDay(0) == Civil(1970, 1, 1)
	expect civilOfDay(-1) == Civil(1969, 12, 31)
	expect civilOfDay(19_782) == Civil(2024, 2, 29)
	expect daysFromCivil(2024, 2, 29) == 19_782
	expect daysFromCivil(1600, 3, 1) == -135_080
