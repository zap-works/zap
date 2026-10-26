-- The original, frame by frame: Mesen 2 plays the cartridge from power-on with a scripted route
-- and writes what the Zap build writes for the same route, for compare.zap and the like. Always
-- headless, the buttons given by the script:
--
--   Mesen.exe --testRunner --timeout=600 --snes.ramPowerOnState=AllZeros
--     --snes.port1.type=SnesController --snes.disableFrameSkipping=true tools/oracle.lua <rom.sfc>
--
-- The settings make the run the Zap build's: memories cleared at power-on (Mesen's default fills
-- them at random), a joypad in port 1 (the test runner has none, so a route would press nothing),
-- and every frame drawn (running fast, Mesen skips drawing frames by a timer, the buffer then
-- holding an earlier one; the PNGs of SNESRECOMP_SHOTS still come a frame late, the hashes do not). The
-- battery RAM is cleared before the first frame too: Mesen keeps the last run's in its Saves
-- folder. The route's buttons are given when the game's joypad is read (inputPolled): set at the
-- end of frame n, the vertical blank's read of that frame takes them.
--
-- With, in the environment: SNESRECOMP_FRAMES (how many), SNESRECOMP_OUT (the file written), SNESRECOMP_ROUTE (a file
-- of lines "frame buttons", the buttons held from that frame on: "120 start", "300 right,b") and
-- SNESRECOMP_MODE, what is written. SNESRECOMP_POLLS instead of a route: lines "n buttons" keyed by the frames
-- that read the joypads (tools/bk2Route.zap writes them from a BizHawk movie), the buttons held
-- from the game's n-th such frame on; a frame that reads none (a lag frame) takes no buttons, so
-- a movie whose lag frames fall elsewhere in Mesen still reaches the game at the same reads. The
-- route so played, keyed by frame, is written to SNESRECOMP_ROUTE. The modes:
--   hashes (the default)  a line a frame, "frame screenHash wramHash": FNV-1a over the picture and
--                         over the first 8 KB of WRAM (main.zap --hashes); SNESRECOMP_SHOTS ("200,400")
--                         saves those frames' pictures as PNG beside the file
--   wram                  the work RAM (128 KB) as it is at the end of frame SNESRECOMP_FRAMES, raw bytes to
--                         SNESRECOMP_OUT (to set against main.zap --memory's prefix-wram.bin)
--   ports                 each CPU access to the APU's ports with the master clock at its end,
--                         "R clock port value" or "W ...", and "F frame clock" (main.zap --ports),
--                         from frame SNESRECOMP_FROMFRAME on
--   trace                 each instruction run between the master clocks SNESRECOMP_FROM and SNESRECOMP_TO, "clock
--                         address a= x= y= p=" (main.zap --steps)
--   played                where the jumps and calls through memory of SNESRECOMP_JUMPS (prepare writes
--                         recomp/jumps.txt) went, as tables/played.cfg's records
-- Needs Script->Settings->Allow access to I/O and OS (settings.json: Debug.ScriptWindow.AllowIoOsAccess).

local frames = tonumber(os.getenv("SNESRECOMP_FRAMES") or "600")
local mode = os.getenv("SNESRECOMP_MODE") or "hashes"
local outPath = os.getenv("SNESRECOMP_OUT") or (mode .. ".txt")
local routePath = os.getenv("SNESRECOMP_ROUTE")
if routePath == "" then routePath = nil end

-- a route's steps in order, each { at, held (a set of buttons), names (as the file wrote them) }
local function readRoute(path)
  local steps = {}
  for line in io.lines(path) do
    local at, buttons = string.match(line, "^%s*(%d+)%s+(%S+)")
    if at then
      local held = {}
      for b in string.gmatch(buttons, "[%a]+") do if b ~= "none" then held[b] = true end end
      steps[#steps + 1] = { at = tonumber(at), held = held, names = buttons }
    end
  end
  table.sort(steps, function(a, b) return a.at < b.at end)
  return steps
end

local pollsPath = os.getenv("SNESRECOMP_POLLS")
local route = {}
if routePath and not pollsPath then route = readRoute(routePath) end

for a = 0, 0x7FF do emu.write(a, 0, emu.memType.snesSaveRam) end

local out = io.open(outPath, "wb")
local frame = 0
local held = {}
local onFrame = {}   -- what the mode does at each frame's end
local onEnd = {}     -- and at the run's

-- FNV-1a over 32-bit words, kept in 32 bits
local function fnv(hash, v)
  hash = hash ~ (v & 0xFF)
  hash = (hash * 16777619) & 0xFFFFFFFF
  hash = hash ~ ((v >> 8) & 0xFF)
  hash = (hash * 16777619) & 0xFFFFFFFF
  hash = hash ~ ((v >> 16) & 0xFF)
  return (hash * 16777619) & 0xFFFFFFFF
end

local function hashes()
  -- SNESRECOMP_EVERY: a line every n frames (hashing in Lua is most of a run's time); compare.zap
  -- compares the frames both files have
  local every = tonumber(os.getenv("SNESRECOMP_EVERY") or "1")
  local shots = {}
  for f in string.gmatch(os.getenv("SNESRECOMP_SHOTS") or "", "%d+") do shots[tonumber(f)] = true end
  onFrame[#onFrame + 1] = function()
    if frame % every ~= 0 and not shots[frame] then return end
    local buf = emu.getScreenBuffer()
    local screen = 2166136261
    for i = 1, #buf do screen = fnv(screen, buf[i]) end
    local wram = 2166136261
    for a = 0, 0x1FFF do
      wram = (wram ~ emu.read(a, emu.memType.snesWorkRam)) * 16777619 & 0xFFFFFFFF
    end
    out:write(string.format("%d %08x %08x\n", frame, screen, wram))
    if shots[frame] then
      local png = io.open(string.gsub(outPath, "%.txt$", "") .. "-" .. frame .. ".png", "wb")
      png:write(emu.takeScreenshot())
      png:close()
    end
  end
end

local function wram()
  onEnd[#onEnd + 1] = function()
    local bytes = {}
    for a = 0, 0x1FFFF do bytes[#bytes + 1] = string.char(emu.read(a, emu.memType.snesWorkRam)) end
    out:write(table.concat(bytes))
  end
end

-- screen: the picture at the end of frame SNESRECOMP_FRAMES, its pixels' red, green and blue bytes
-- row by row as the hash reads them (to set against main.zap --memory's prefix-screen.bin)
local function screen()
  onEnd[#onEnd + 1] = function()
    local buf = emu.getScreenBuffer()
    local bytes = {}
    for i = 1, #buf do
      local c = buf[i]
      bytes[#bytes + 1] = string.char((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF)
    end
    out:write(table.concat(bytes))
  end
end

local function ports()
  local fromFrame = tonumber(os.getenv("SNESRECOMP_FROMFRAME") or "0")
  local function logged(kind)
    return function(addr, value)
      if frame < fromFrame then return end
      out:write(string.format("%s %d %d %02x\n", kind, emu.getState()["masterClock"], addr & 3, value))
    end
  end
  for bank = 0, 0xBF do
    if bank < 0x40 or bank >= 0x80 then
      local at = bank * 0x10000 + 0x2140
      emu.addMemoryCallback(logged("R"), emu.callbackType.read, at, at + 3)
      emu.addMemoryCallback(logged("W"), emu.callbackType.write, at, at + 3)
    end
  end
  onFrame[#onFrame + 1] = function()
    out:write(string.format("F %d %d\n", frame, emu.getState()["masterClock"]))
  end
end

-- writes: each write to the addresses SNESRECOMP_LO to SNESRECOMP_HI of banks 00-3F and 80-BF (hex:
-- the B bus registers 2100-21FF; below 2000, work RAM, its bank 7E too), the CPU's or a DMA's,
-- "W clock address value pc=", and "F frame clock" at each frame's end, from frame
-- SNESRECOMP_FROMFRAME on (main.zap's --writes lists the build's the same way); reads: the reads
-- of those addresses, "R clock ..." the same way
local function accesses(kind, label)
  local fromFrame = tonumber(os.getenv("SNESRECOMP_FROMFRAME") or "0")
  local lo = tonumber(os.getenv("SNESRECOMP_LO") or "2100", 16)
  local hi = tonumber(os.getenv("SNESRECOMP_HI") or "21FF", 16)
  local function logged(addr, value)
    if frame < fromFrame then return end
    local s = emu.getState()
    out:write(string.format("%s %d %04X %02X pc=%02X%04X\n", label, s["masterClock"], addr & 0xFFFF, value, s["cpu.k"], s["cpu.pc"]))
  end
  for bank = 0, 0xBF do
    if bank < 0x40 or bank >= 0x80 then
      emu.addMemoryCallback(logged, kind, bank * 0x10000 + lo, bank * 0x10000 + hi)
    end
  end
  if hi < 0x2000 then emu.addMemoryCallback(logged, kind, 0x7E0000 + lo, 0x7E0000 + hi) end
  onFrame[#onFrame + 1] = function()
    if frame >= fromFrame then out:write(string.format("F %d %d\n", frame, emu.getState()["masterClock"])) end
  end
end

-- the instructions' callback added only from the frame before SNESRECOMP_FROM, Mesen's getState being slow
local function trace()
  local from = tonumber(os.getenv("SNESRECOMP_FROM"))
  local to = tonumber(os.getenv("SNESRECOMP_TO"))
  local added = false
  local function onExec(address)
    local s = emu.getState()
    local c = s["masterClock"]
    if c >= from and c <= to then
      out:write(string.format("%d %06X a=%04X x=%04X y=%04X s=%04X p=%02X\n", c, address, s["cpu.a"], s["cpu.x"], s["cpu.y"], s["cpu.sp"], s["cpu.ps"]))
    elseif c > to then
      frame = frames
    end
  end
  onFrame[#onFrame + 1] = function()
    if not added and emu.getState()["masterClock"] >= from - 400000 then
      added = true
      emu.addMemoryCallback(onExec, emu.callbackType.exec, 0, 0xFFFFFF)
    end
  end
end

local function played()
  local function read8(addr) return emu.read(addr, emu.memType.snesMemory) end
  local function read16(bank, at)
    return read8(bank | (at & 0xFFFF)) | (read8(bank | ((at + 1) & 0xFFFF)) << 8)
  end
  local seen = {}   -- site -> { calls, targets }
  for line in io.lines(os.getenv("SNESRECOMP_JUMPS") or "jumps.txt") do
    local at, name, how, operand = string.match(line, "^0x(%x+) (%a+) (%S+) 0x(%x+)")
    if at then
      local site = tonumber(at, 16)
      local value = tonumber(operand, 16)
      -- the game may run the site from the mirror bank (00-7D or 80-FF): the record is the bank it ran in
      local sites = { site }
      if site >= 0x800000 then sites[2] = site - 0x800000 else sites[2] = site + 0x800000 end
      for _, pc in ipairs(sites) do
       local bank = pc & 0xFF0000
       seen[pc] = { calls = name == "jsr", targets = {} }
       emu.addMemoryCallback(function()
        local target
        if how == "(w,x)" then
          target = bank | read16(bank, value + emu.getState()["cpu.x"])
        elseif how == "(w)" then
          target = bank | read16(0, value)
        else
          target = read16(0, value) | (read8((value + 2) & 0xFFFF) << 16)
        end
        seen[pc].targets[target] = true
       end, emu.callbackType.exec, pc, pc)
      end
    end
  end
  local function writeCfg()
    local file = out
    file:seek("set", 0)   -- the records only grow, so each rewrite covers the last
    local banks = {}
    for site, s in pairs(seen) do
      local list = {}
      for t in pairs(s.targets) do list[#list + 1] = string.format("%06X", t) end
      if #list > 0 then
        table.sort(list)
        local bank = site >> 16
        banks[bank] = banks[bank] or {}
        local kind = s.calls and "ptrcall" or "ptrtail"
        table.insert(banks[bank], string.format("indirect_dispatch %04X 0 %s targets:%s", site & 0xFFFF, kind, table.concat(list, ",")))
      end
    end
    file:write("# Where the game's jumps and calls through memory went in Mesen 2 over the routes of\n")
    file:write("# tests/routes (tools/oracle.lua's played), added to the banks' tables; a bank's records after its line.\n")
    local keys = {}
    for b in pairs(banks) do keys[#keys + 1] = b end
    table.sort(keys)
    for _, b in ipairs(keys) do
      file:write(string.format("\nbank = 0x%02X\n", b))
      table.sort(banks[b])
      for _, l in ipairs(banks[b]) do file:write(l .. "\n") end
    end
    file:flush()
  end
  -- rewritten every 5,000 frames: a long route that stops keeps what it found
  onFrame[#onFrame + 1] = function() if frame % 5000 == 0 then writeCfg() end end
  onEnd[#onEnd + 1] = writeCfg
end

({ hashes = hashes, wram = wram, ports = ports, trace = trace, played = played, writes = function() accesses(emu.callbackType.write, "W") end, reads = function() accesses(emu.callbackType.read, "R") end, screen = screen })[mode]()

-- the buttons of a frame's end: the route's step for it, or, from SNESRECOMP_POLLS, the step of the
-- joypad reads made so far (the frame just ended counts when it read them)
local nextButtons
if pollsPath then
  local polls = readRoute(pollsPath)
  local played = io.open(routePath, "w")
  local reads, step, names = 0, 0, "none"
  local read = false
  for bank = 0, 0xBF do
    if bank < 0x40 or bank >= 0x80 then
      local at = bank * 0x10000
      emu.addMemoryCallback(function() read = true end, emu.callbackType.read, at + 0x4016, at + 0x4017)
      emu.addMemoryCallback(function() read = true end, emu.callbackType.read, at + 0x4218, at + 0x421F)
    end
  end
  nextButtons = function()
    if read then reads = reads + 1 end
    read = false
    while step < #polls and polls[step + 1].at <= reads do step = step + 1 end
    if step > 0 and polls[step].names ~= names then
      names = polls[step].names
      held = polls[step].held
      played:write(string.format("%d %s\n", frame, names))
      played:flush()
    end
  end
  onEnd[#onEnd + 1] = function() played:close() end
else
  local next = 1   -- the route's steps are in order: the next one not yet taken
  nextButtons = function()
    while next <= #route and route[next].at <= frame do
      if route[next].at == frame then held = route[next].held end
      next = next + 1
    end
  end
end

emu.addEventCallback(function()
  frame = frame + 1
  nextButtons()
  for _, f in ipairs(onFrame) do f() end
  if frame >= frames then
    for _, f in ipairs(onEnd) do f() end
    out:close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)
emu.addEventCallback(function() emu.setInput(held, 0) end, emu.eventType.inputPolled)
