# An app run on Android's device (`zap run --target android`): its APK installed over adb (the device
# run.zap picks), started, and its lines read from logcat as they come (runtime/core/linux/app/:
# tag `<package>.out`, stdout's info and stderr's error) until it says its end (`<package>.exit`,
# the code the run ends with), then stopped, as the system starts a top activity whose process ended again;
# an app gone without saying its end crashed, and one past runSeconds is stopped.

import fs

# the logcat lines of the app's tags, one a record: "I/zap.hello.out: text"
fn appLogcat(package str):
	"logcat -d -v tag -s {package}.out:V {package}.exit:V"

# The dir of an app's own files on the device (its externalDataPath, runtime/core/linux/app/)
fn appFilesDirOf(package str):
	"/sdcard/Android/data/{package}/files"

# the app installed and run with the arguments (the lines of `args` in its files dir) and this
# run's ZAP_RUN (`env` there: an app is given no environment), its output printed; its exit code
fn runApp(apk str, stem str, arguments str[]):
	if adbSerial() == "":
		exit(2, "zap: {runnerName()}")
	adb = "{adbPath()} -s {adbSerial()}"
	installed = Process.output("{adb} install -r {quoteArg(hostPath(apk))}")
	if installed.code != 0:
		exit(1, "zap: adb install {apk}: {installed.out.trimmed()}")
	package = appPackage(stem)
	Process.output("{adb} shell am force-stop {package}")
	files = appFilesDirOf(package)
	Process.output("{adb} shell mkdir -p {files}")
	local = "build/{stem}.args"
	_ = fs.writeFile(local, arguments.map("{it}\n").join(""))
	Process.output("{adb} push {quoteArg(hostPath(local))} {files}/args")
	vars = "build/{stem}.env"
	run = runVariable()
	_ = fs.writeFile(vars, "{run.name}={run.value() ?? ""}\n")
	Process.output("{adb} push {quoteArg(hostPath(vars))} {files}/env")
	Process.output("{adb} logcat -c")
	Process.output("{adb} shell am start -W -n {package}/android.app.NativeActivity")
	started = clockMs()
	shown = 0
	gone = false
	first = ""
	loop:
		records = Process.output("{adb} {appLogcat(package)}").out
			.replace("\r\n", "\n")
			.lines()
			.filter(.len > 2 and it[1] == '/')
		for line in records[shown..]:
			said = line.indexOf(": ") ?? continue
			tag = line[2..said].trimmed()
			text = line[said + 2..]
			if tag == "{package}.exit":
				Process.output("{adb} shell am force-stop {package}")   # (else its activity starts again)
				return i64.parse(text) ?? 1
			if line[0] == 'E': eprint(text) else: print(text)
		shown = records.len
		if gone:
			exit(3, "zap: the app ended without its end said: a crash (adb logcat -b crash)")
		if clockMs() - started > runSeconds * 1000:
			Process.output("{adb} shell am force-stop {package}")
			exit(3, "zap: the app still ran after {runSeconds} s: stopped")
		# its process gone, or another (the system starts the activity again): one more look, as its
		# last records may still be on their way to logcat
		now = Process.output("{adb} shell pidof {package}").out.trimmed().copy()
		if first == "": first = now.copy()
		gone = now == "" or now != first
		sleepMs(200)
