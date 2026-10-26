-- BizHawk's side of bk2Route.zap: plays the movie it was started with, in the core that recorded
-- it, and writes (to SNESRECOMP_POLLS) the buttons of each frame that read the joypads, a line "n
-- buttons" when they change, n counting only those frames from 0. A lag frame's buttons reach
-- nothing, so they are left out: tools/oracle.lua gives these at Mesen 2's own reads.

local names = { "Up", "Down", "Left", "Right", "Select", "Start", "Y", "B", "X", "A", "L", "R" }
local out = io.open(os.getenv("SNESRECOMP_POLLS"), "wb")
client.speedmode(6400)
local length = movie.length()
local reads, last = 0, nil
while true do
  emu.frameadvance()
  local f = emu.framecount()
  if not emu.islagged() then
    -- the frame just run took the movie's row f - 1
    local input = movie.getinput(f - 1)
    local held = {}
    for _, n in ipairs(names) do
      if input["P1 " .. n] then held[#held + 1] = string.lower(n) end
    end
    local line = #held > 0 and table.concat(held, ",") or "none"
    if line ~= last then
      out:write(string.format("%d %s\n", reads, line))
      last = line
    end
    reads = reads + 1
  end
  if f >= length then
    out:close()
    client.exit()
  end
end
