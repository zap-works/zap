# Runs inside RenderDoc's qrenderdoc (tools/edenFrame.zap starts it): launches Eden under RenderDoc,
# captures its presented frame at each wanted second and writes it as a PNG. The job is the file
# named by the environment's ZAP_EDEN_FRAMES, one value a line: Eden's exe, its dir, the game, the
# output dir, then the seconds. Eden is stopped after the last frame; the result is in done.txt.
import os, sys, time, traceback
import renderdoc as rd

lines = open(os.environ["ZAP_EDEN_FRAMES"]).read().split("\n")
exe, workdir, game, out = lines[0], lines[1], lines[2], lines[3]
seconds = sorted(float(s) for s in lines[4].split(",") if s)
log = open(out + "/frames.log", "w")

def say(text):
    log.write(text + "\n")
    log.flush()

try:
    res = rd.ExecuteAndInject(exe, workdir, '"' + game + '"', [], out + "/capture", rd.CaptureOptions(), False)
    say("inject %s" % res.result)
    tc = rd.CreateTargetControl("", res.ident, "zap", True)
    pid = tc.GetPID()
    start = time.time()
    taken = 0
    waiting = False
    while taken < len(seconds) and time.time() - start < seconds[-1] + 300:
        if not waiting and time.time() - start >= seconds[taken]:
            tc.TriggerCapture(1)
            waiting = True
        msg = tc.ReceiveMessage(None)
        if msg.type == rd.TargetControlMessageType.Disconnected:
            break
        if msg.type == rd.TargetControlMessageType.NewCapture:
            cap = rd.OpenCaptureFile()
            cap.OpenFile(msg.newCapture.path, "", None)
            thumb = cap.GetThumbnail(rd.FileType.PNG, 0)
            name = "%s/eden-%03d.png" % (out, int(seconds[taken]))
            open(name, "wb").write(bytes(thumb.data))
            say("frame %s" % name)
            cap.Shutdown()
            taken += 1
            waiting = False
        time.sleep(0.2)
    open(out + "/done.txt", "w").write("%d\n" % taken)
    os.kill(pid, 9)
except BaseException:
    say(traceback.format_exc())
os._exit(0)
