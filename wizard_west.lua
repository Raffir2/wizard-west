--[[
  Wizard West tool  (PlaceId 17357719939)
  run:  loadstring(readfile("ww_script.lua"))()
  toggle GUI: RightShift      handle: getgenv().__WW

  Everything here was measured live (2026-09-24), see bottom of file for notes.
]]

local G = getgenv()
if G.__WW and G.__WW.cleanup then pcall(G.__WW.cleanup) end

local Players = game:GetService("Players")
local RS = game:GetService("RunService")
local CS = game:GetService("CollectionService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TS = game:GetService("TeleportService")
local RepS = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer
local Concept = lp:WaitForChild("Concept")
local Events = RepS:WaitForChild("Events")
local Directory = require(RepS.Directory)

local W = { conns = {}, threads = {}, stats = {}, log = {} }
G.__WW = W

local cfg = {
	-- money
	vacuum = true,          -- collect every money/scroll drop on the map
	autoSell = true,        -- walk to a trinket seller when the bag is worth enough
	sellAt = 1,             -- sell when bag holds >= this many trinkets
	sellMinValue = 2500,    -- ...and is worth this much, or a seller is within sellNear studs
	sellNear = 450,
	nobleGrab = true,
	noblePrefer = "Baron",  -- swap to this artifact when it spawns (Baron = Royal Apparate)       -- take noble artifacts (Crown/Baron/Phoenix/Cloak) when they spawn
	bankChests = true,      -- bank chests at artifact missions (trinkets, +200 bounty each -> auto cleared)
	artifactFarm = true,    -- also steal the artifact (+1000 bounty, Diamond $1500 after 30s held)
	heistClear = 500,       -- skip the heist while a rogue is this close to the loot
	workClear = 600,        -- camps/wagons: no rogue/hunter within this (they roam at broom speed)
	heistNeedApparate = true, -- only grab the artifact when Apparate is ready for the escape
	wagonLoot = true,       -- open unlocked wagon loot while farming
	bossFarm = false,       -- bandit mission farm (combat)
	autoMine = false,       -- mine ore veins (needs Vocare Pickaxe)
	autoContracts = true,
	autoHop = true,         -- hostile server (many flees/deaths, low income) -> ask the watchdog to rejoin elsewhere
	-- safety
	avoidPlayers = true,    -- flee from dangerous players
	dangerRadius = 220,     -- a dangerous player this close (and closing in / attacking / <160) -> leave
	fleeHp = 35,            -- HP% at which farming stops and we retreat
	layLow = true,
	autoClearBounty = true, -- RogueEvent: bounty + rogue status wiped after a 40s countdown
	useCloak = true,        -- Invisio / Invisio Maxima (Cloak noble): stay invisible + off the radar except while shooting
	fightBack = true,       -- silent-aim + spells on players who attack us          -- while wanted (bounty), hide far from players until it clears
	autoBuy = false,        -- buy next skill-tree item automatically
	buyOrder = { "ChMiner", "ChWayfarer", "ChCadet", "ChWater", "ChSnatcher", "ChFrost", "ChBlade", "ChFire", "ChMusket", "ChMoL", "ChStorm", "ChIronblood", "ChOcean", "ChVampire", "ChWukong", "ChMind", "ChDeath" },
	keepMoney = 0,          -- never spend below this
	autoEquipSpells = true, -- equip newly bought spells into free slots
	-- travel
	travelSpeed = 55,       -- no-broom safe speed (server rolls back above ~65)
	broomTravel = true,     -- ride broom while travelling -> higher allowed speed
	broomSpeed = 120,       -- smooth flight on the broom: 140 measured clean, 160 knocks you off
	underground = false,    -- experimental: travel below the terrain (glitchy, broom can't run there)
	flyHeight = 22,         -- broom cruise height above ground/roofs
	flyAccel = 25,          -- studs/s^2 while speeding up on the broom
	undergroundDepth = 14,
	fightDistance = 24,     -- bandit farm: stand on the ground this far from the target
	blinkTravel = false,    -- start trips with dash-blinks. OFF: the broom leg after a burst gets rolled back (30-55/s vs 120 clean)
	dismountOnArrive = true, -- get off the broom on arrival so dash stamina refills      -- keep this much dash stamina for emergencies
	useApparate = true,     -- use Apparate spell for trips > apparateMin studs
	apparateMin = 900,
	royalApparateMin = 350, -- Royal Apparate (nobles): 12s cooldown, 22 HP
	-- combat
	silentAim = true,
	aimPlayers = true,
	aimAI = true,
	onlyWanted = true,      -- players: only rogues / bounty targets
	aimFov = 250,           -- px around crosshair (0 = nearest by distance)
	aimRange = 250,
	autoFire = false,
	autoSpells = false,
	autoHeal = true,
	keepArmor = true,       -- keep Vocaralea armor (+25 max HP) up
	healAt = 55,
	farmHeight = 18,        -- hover height above bandits
	-- player
	noAntiSpeed = true,
	walkSpeed = 0,          -- 0 = untouched
	noclip = false,
	antiRagdoll = true,
	infJump = false,
	broomMult = 1,          -- broom flight speed multiplier (1 = off)
	fullbright = false,
	-- esp
	espPlayers = false,
	espAI = false,
	espLoot = false,
}
W.cfg = cfg
-- settings persist in ww_config.json (only keys/types that exist in the defaults are loaded)
local HttpService = game:GetService("HttpService")
local CFG_FILE = "ww_config.json"
pcall(function()
	if not (isfile and isfile(CFG_FILE)) then return end
	local saved = HttpService:JSONDecode(readfile(CFG_FILE))
	for k, v in pairs(saved) do
		if cfg[k] ~= nil and type(cfg[k]) == type(v) and type(v) ~= "table" then cfg[k] = v end
	end
end)
function W.saveCfg()
	local out = {}
	for k, v in pairs(cfg) do if type(v) ~= "table" then out[k] = v end end
	pcall(writefile, CFG_FILE, HttpService:JSONEncode(out))
end

-------------------------------------------------------------------------------
-- utils
-------------------------------------------------------------------------------
local function char() return lp.Character end
local function hrp() local c = char() return c and c.PrimaryPart end
local function hum() local c = char() return c and c:FindFirstChildOfClass("Humanoid") end
local function alive() local h = hum() return h and h.Health > 0 and hrp() ~= nil end
local function money() return Concept.Currencies.Money.Value end
local function conn(sig, f) local c = sig:Connect(f) table.insert(W.conns, c) return c end
local function spawnLoop(name, f)
	local t = task.spawn(function()
		while true do
			local t0 = os.clock()
			if name == "farm" then W.br = nil W.farmIterStart = t0 end
			local ok, err = pcall(f)
			if not ok then W.log[#W.log + 1] = name .. ": " .. tostring(err) task.wait(1) end
			-- which farm step eats the time? (only long iterations)
			if name == "farm" and os.clock() - t0 > 8 then
				W.slowSteps = W.slowSteps or {}
				table.insert(W.slowSteps, 1, string.format("%s %.0fs [%s]", tostring(W.br), os.clock() - t0, tostring(W.status)))
				if #W.slowSteps > 30 then table.remove(W.slowSteps) end
			end
		end
	end)
	W.threads[name] = t
	return t
end
local function status(s) W.status = s if W.statusLabel then W.statusLabel.Text = s end end
-- appendfile errors on a missing file (executor quirk): create it first
local function logf(file, line)
	pcall(function()
		if isfile(file) then appendfile(file, line) else writefile(file, line) end
	end)
end
W.logf = logf
local function mdlPos(m)
	if not m then return nil end
	if m:IsA("BasePart") then return m.Position end
	if m:IsA("Attachment") then return m.WorldPosition end
	local ok, p = pcall(function() return m:GetPivot().Position end)
	if ok and p and p.Magnitude < 5 then return nil end -- streamed-out model without a pivot
	return ok and p or nil
end
local function wand()
	local c = char()
	for _, t in ipairs((c and c:GetChildren()) or {}) do if t:IsA("Tool") and t:FindFirstChild("Spells") then return t end end
	for _, t in ipairs(lp.Backpack:GetChildren()) do if t:IsA("Tool") and t:FindFirstChild("Spells") then return t end end
end
local function equip(tool) local h = hum() if h and tool and tool.Parent ~= char() then h:EquipTool(tool) task.wait(0.25) end end
local rayP = RaycastParams.new()
rayP.FilterType = Enum.RaycastFilterType.Exclude
local terrP = RaycastParams.new()
terrP.FilterType = Enum.RaycastFilterType.Include
terrP.FilterDescendantsInstances = { workspace.Terrain }
local function terrainY(x, z)
	local r = workspace:Raycast(Vector3.new(x, 1500, z), Vector3.new(0, -3000, 0), terrP)
	return r and r.Position.Y
end
local function groundY(x, z)
	rayP.FilterDescendantsInstances = { workspace.Characters, workspace.Entities, workspace.Particles }
	local r = workspace:Raycast(Vector3.new(x, 1500, z), Vector3.new(0, -3000, 0), rayP)
	return r and r.Position.Y
end

-- Land mask from the game's own minimap (run-length rows, 'Z' = void). Raycasts only see the
-- streamed-in area, this covers the whole map. Twice an artifact escape "safe spot" was over the
-- void: hovering held us up, the next trip dropped us to our death with the Diamond.
local LAND = {}
pcall(function()
	local gen = RepS.Modules.Client.SpellBook.Catagories.Map.ClientMapGenerator
	local dims = require(gen.MapDimensions)
	local data = require(gen:FindFirstChild("MinimapModule_" .. game.PlaceId))
	local i = 0
	for row in string.gmatch(data, "[^|]+") do
		i += 1
		local runs, c = {}, 0
		for ch, n in string.gmatch(row, "(%a)(%d+)") do
			n = tonumber(n)
			if ch ~= "Z" then runs[#runs + 1] = { c, c + n - 1 } end
			c += n
		end
		LAND[i] = runs
	end
	-- world -> minimap (rotation 90): row = X axis, column = Z axis
	LAND.n, LAND.half, LAND.ox, LAND.oz = i, dims.X.Max, dims.Offset.X, dims.Offset.Y
end)
local function landAt(x, z)
	local n = LAND.n
	local runs = LAND[math.floor(n * (x - LAND.ox + LAND.half) / (2 * LAND.half))]
	if not runs then return false end
	local c = math.floor(n * (z - LAND.oz + LAND.half) / (2 * LAND.half))
	for _, rr in ipairs(runs) do if c >= rr[1] and c <= rr[2] then return true end end
	return false
end
-- land here and `margin` studs around it
function W.isLand(x, z, margin)
	if not LAND.n then return true end -- no map data: never block
	if not landAt(x, z) then return false end
	margin = margin or 0
	if margin > 0 then
		for _, o in ipairs({ { margin, 0 }, { -margin, 0 }, { 0, margin }, { 0, -margin } }) do
			if not landAt(x + o[1], z + o[2]) then return false end
		end
	end
	return true
end
-- a point `dist` studs from `from`, heading away from `danger`, turned until it's over land
function W.awayPoint(from, danger, dist)
	local away = Vector3.new(from.X - danger.X, 0, from.Z - danger.Z)
	if away.Magnitude < 1 then away = Vector3.new(1, 0, 0) end
	away = away.Unit
	for _, deg in ipairs({ 0, 30, -30, 60, -60, 90, -90, 120, -120 }) do
		local a = math.rad(deg)
		local dir = Vector3.new(away.X * math.cos(a) - away.Z * math.sin(a), 0, away.X * math.sin(a) + away.Z * math.cos(a))
		local p = from + dir * dist
		if W.isLand(p.X, p.Z, 60) then return p end
	end
	return from
end

-------------------------------------------------------------------------------
-- movement / travel
-------------------------------------------------------------------------------
-- The client AntiSpeed module freezes you at >=150 horizontal velocity; neuter it.
local AntiSpeed = require(RepS.Modules.Client.Char.AntiSpeed)
local origAntiSpeed = AntiSpeed.Update
local function applyAntiSpeed() AntiSpeed.Update = cfg.noAntiSpeed and function() end or origAntiSpeed end
applyAntiSpeed()

W.travelToken = 0
W.hoverPos = nil
conn(RS.Heartbeat, function()
	local p = W.hoverPos
	local r = hrp()
	if p and r and not W.travelling then
		r.AssemblyLinearVelocity = Vector3.zero
		r.CFrame = CFrame.new(p) * (r.CFrame - r.CFrame.Position)
	end
end)

function W.broomOff()
	local c = char()
	if not (c and c:GetAttribute("JetPacking")) then return end
	for _, f in ipairs(lp.Backpack:GetChildren()) do
		if f:GetAttribute("FlightModel") and f:FindFirstChild("ToolListnerEvent") then
			c:SetAttribute("JetPacking", nil)
			f.ToolListnerEvent:FireServer("Activate", false)
			return
		end
	end
end
function W.broomOn()
	local c = char()
	if not c or c:GetAttribute("JetPacking") then return c and c:GetAttribute("JetPacking") ~= nil end
	local b = lp.Backpack:FindFirstChild("Wooden Broom") or lp.Backpack:FindFirstChildWhichIsA("Folder")
	for _, f in ipairs(lp.Backpack:GetChildren()) do
		if f:GetAttribute("FlightModel") then b = f break end
	end
	if not (b and b:FindFirstChild("ToolListnerEvent")) then return false end
	if workspace:GetServerTimeNow() < (b:GetAttribute("CooldownExpire") or 0) then return false end
	local h = hum()
	-- the server refuses the broom on the ground (~20% of our mounts failed standing on grass/sand):
	-- get airborne first and fire once we really are
	if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
	local r = hrp()
	if r then r.AssemblyLinearVelocity = Vector3.new(r.AssemblyLinearVelocity.X, 45, r.AssemblyLinearVelocity.Z) end
	for _ = 1, 6 do task.wait(0.05) if h and h.FloorMaterial == Enum.Material.Air then break end end
	task.wait(0.1)
	-- Activate is a server-side toggle: when the server still thinks we fly (the client dropped
	-- JetPacking on its own) the first press turns it off -> press again once the cooldown passed
	for attempt = 1, 2 do
		b.ToolListnerEvent:FireServer("Activate")
		for _ = 1, 10 do task.wait(0.1) if c:GetAttribute("JetPacking") then
			if attempt > 1 then W.stats.broomRetryOk = (W.stats.broomRetryOk or 0) + 1 end
			return true
		end end
		local tw = os.clock()
		while workspace:GetServerTimeNow() < (b:GetAttribute("CooldownExpire") or 0) and os.clock() - tw < 2 do task.wait(0.05) end
		if h and h.FloorMaterial ~= Enum.Material.Air and r then
			h:ChangeState(Enum.HumanoidStateType.Jumping)
			r.AssemblyLinearVelocity = Vector3.new(r.AssemblyLinearVelocity.X, 45, r.AssemblyLinearVelocity.Z)
			task.wait(0.15)
		end
	end
	-- why does the server refuse sometimes? log the state to find the rule
	W.broomFails = W.broomFails or {}
	table.insert(W.broomFails, 1, string.format("[%s] stam %s rogue %s rag %s floor %s hit %.0fs ago shot %.0fs ago cd %.1f cast %s", os.date("%H:%M:%S"),
		tostring(c:GetAttribute("DashStamina")), tostring(c:GetAttribute("Rogued")), tostring(c:GetAttribute("Ragdoll")),
		tostring(h and h.FloorMaterial.Name), os.clock() - (W.lastDamageT or 0), os.clock() - (W.lastShotT or 0), (b:GetAttribute("CooldownExpire") or 0) - workspace:GetServerTimeNow(), tostring(c:GetAttribute("CastingSpell"))))
	if #W.broomFails > 20 then table.remove(W.broomFails) end
	return false
end

-- Blink bursts. After DashEvent("DashForward") the server accepts one ~100 stud jump even when
-- the dash itself is refused (no stamina / on cooldown) - no event = rolled back.
-- Measured: 6-10 jumps of 95-100 studs every ~0.4s pass after a rest (~230 studs/s); keep going
-- and it starts rolling jumps back (sustained ~60/s, no better than the broom). 120+ always fails.
local BLINK_STEP, BLINK_GAP, BURST_MAX, BURST_REFILL = 95, 0.32, 7, 1.8
function W.canBlink()
	local c = char()
	if not c then return false end
	if c:GetAttribute("CastingSpell") or c:GetAttribute("Ragdolled") or lp:GetAttribute("Jailed") then return false end
	return c.PrimaryPart ~= nil and not c.PrimaryPart.Anchored
end
-- jumps available right now (the budget refills while we don't blink)
function W.burstBudget()
	return math.clamp(math.floor((os.clock() - (W.lastBurst or 0)) / BURST_REFILL), 0, BURST_MAX)
end
function W.blinkTo(pos)
	local r = hrp()
	if not r or not W.canBlink() then return false end
	local d = pos - r.Position
	if d.Magnitude > BLINK_STEP then pos = r.Position + d.Unit * BLINK_STEP end
	Events.DashEvent:FireServer("DashForward", false)
	task.wait(0.08)
	r = hrp()
	if not r then return false end
	r.AssemblyLinearVelocity = Vector3.zero
	local flat = Vector3.new(d.X, 0, d.Z)
	r.CFrame = flat.Magnitude > 0.1 and CFrame.new(pos, pos + flat) or CFrame.new(pos) * (r.CFrame - r.CFrame.Position)
	W.stats.blinks = (W.stats.blinks or 0) + 1
	W.lastBurst = os.clock()
	return true
end
-- hop toward goal (ground level) until the budget is used, we're close, or the server pulls one back
function W.blinkBurst(goal, maxN, token)
	local n = 0
	-- a spell cast in progress blocks blinks: give it a moment to finish
	local tw = os.clock()
	while char() and char():GetAttribute("CastingSpell") and os.clock() - tw < 1.2 do task.wait(0.05) end
	local budget = math.min(maxN or BURST_MAX, W.burstBudget())
	local last = hrp() and hrp().Position
	while n < budget and last do
		if token and token ~= W.travelToken then break end
		local r = hrp()
		if not r or not W.canBlink() then break end
		-- a server rollback throws us ~a whole step back; landing/sliding only moves a few studs
		if (Vector3.new(r.Position.X - last.X, 0, r.Position.Z - last.Z)).Magnitude > 40 then W.stats.blinkRB = (W.stats.blinkRB or 0) + 1 break end
		local flat = Vector3.new(goal.X - r.Position.X, 0, goal.Z - r.Position.Z)
		if flat.Magnitude < 80 then break end
		local to = r.Position + flat.Unit * BLINK_STEP
		local gy = groundY(to.X, to.Z)
		to = Vector3.new(to.X, (gy and gy + 4) or r.Position.Y, to.Z)
		if not W.blinkTo(to) then break end
		last = to
		n += 1
		task.wait(BLINK_GAP)
	end
	return n
end

-- straight CFrame glide with server-rollback detection (speed backs off automatically)
function W.glide(goal, speed, token)
	local r = hrp()
	if not r then return false end
	token = token or W.travelToken
	if os.clock() < (W.slowUntil or 0) then speed = math.min(speed, 45) end
	W.travelling = true
	local cur = r.Position
	local t0 = os.clock()
	local maxT = (goal - cur).Magnitude / 40 + 6
	local lastSet = cur
	local rollbacks = 0
	local done, ok = false, true
	local c
	c = RS.Heartbeat:Connect(function(dt)
		local rr = hrp()
		if not rr or token ~= W.travelToken or os.clock() - t0 > maxT then ok = false done = true c:Disconnect() return end
		local jet = char() and char():GetAttribute("JetPacking")
		if not jet then
			if speed > cfg.travelSpeed then speed = cfg.travelSpeed end
			if W.inTrip and cfg.broomTravel and not cfg.underground and (W.tripBroomTries or 0) < 3 and os.clock() - (W.lastBroomTry or 0) > 3 then
				W.tripBroomTries = (W.tripBroomTries or 0) + 1
				W.lastBroomTry = os.clock()
				task.spawn(W.broomOn)
			end
		elseif cfg.broomTravel and speed < math.min(cfg.broomSpeed, 70) and os.clock() >= (W.slowUntil or 0) then
			speed = math.min(cfg.broomSpeed, 70, speed + 40 * dt) -- short hops near the ground stay <= 70
		end
		if (rr.Position - lastSet).Magnitude > 35 then -- server pulled us back
			rollbacks += 1
			W.stats.rollbacks = (W.stats.rollbacks or 0) + 1
			cur = rr.Position
			speed = math.max(40, speed * 0.75)
			if rollbacks >= 2 then W.slowUntil = os.clock() + 30 end -- server unhappy: stay slow for a while
		end
		local lv = rr:FindFirstChildOfClass("LinearVelocity")
		if lv then lv.MaxForce = 0 end -- stop broom physics from fighting the glide
		local d = goal - cur
		local step = speed * dt
		if d.Magnitude <= step then cur = goal done = true c:Disconnect() else cur += d.Unit * step end
		rr.AssemblyLinearVelocity = Vector3.zero
		local flat = Vector3.new(d.X, 0, d.Z)
		rr.CFrame = flat.Magnitude > 0.1 and CFrame.new(cur, cur + flat) or CFrame.new(cur) * (rr.CFrame - rr.CFrame.Position)
		lastSet = cur
	end)
	repeat task.wait() until done
	W.travelling = false
	return ok, speed
end

-- smooth flight: one continuous controller for the whole leg. Horizontal speed stays constant;
-- height follows the highest ground in a look-ahead window (climb early, no bobbing per waypoint).
function W.fly(goal, speed, token, opts)
	opts = opts or {}
	local r = hrp()
	if not r then return false end
	token = token or W.travelToken
	local look = opts.look or 160
	local vUp, vDown = opts.vUp or 45, opts.vDown or 30
	local clear = opts.clear or cfg.flyHeight
	W.travelling = true
	W.flySpeed = nil
	local cur = r.Position
	local startDist = Vector3.new(goal.X - cur.X, 0, goal.Z - cur.Z).Magnitude
	local maxT = startDist / 35 + 10
	local t0 = os.clock()
	local lastSet = cur
	local rollbacks = 0
	local prof, profT = nil, 0
	local done, ok = false, true
	local c
	local floorY, floorAt
	local upPulls = 0
	W.flyBlocked = false
	-- highest ground between here and `look` studs ahead (sampled every 12 studs, cached 0.25s)
	-- without the broom the server rubber-bands anything hovering, so hug the ground then
	local profJet
	local function cruiseY(pos, dir, remain, jet)
		if os.clock() - profT < (jet and 0.25 or 0.1) and prof and profJet == jet then return prof end
		profT, profJet = os.clock(), jet
		local top = -math.huge
		local clear = jet and clear or 3.5
		for d = 0, math.min(jet and look or 24, remain), jet and 12 or 6 do
			local p = pos + dir * d
			local gy = groundY(p.X, p.Z)
			if gy and gy > top then top = gy end
		end
		prof = top > -math.huge and top + clear or nil
		return prof
	end
	c = RS.Heartbeat:Connect(function(dt)
		local rr = hrp()
		if not rr or token ~= W.travelToken or os.clock() - t0 > maxT then ok = false done = true c:Disconnect() return end
		local jet = char() and char():GetAttribute("JetPacking")
		-- server-side ragdoll (we skip it on the client): movement now gets rolled back -> wait it out
		if char():GetAttribute("Ragdoll") then
			cur, lastSet = rr.Position, rr.Position
			W.flySpeed = cfg.travelSpeed
			return
		end
		local sp = speed
		if not jet then
			sp = math.min(sp, cfg.travelSpeed)
			if W.inTrip and cfg.broomTravel and (W.tripBroomTries or 0) < 3 and os.clock() - (W.lastBroomTry or 0) > 3 then
				W.tripBroomTries = (W.tripBroomTries or 0) + 1
				W.lastBroomTry = os.clock()
				task.spawn(W.broomOn)
			end
		elseif cfg.broomTravel and rollbacks == 0 then
			sp = math.max(sp, cfg.broomSpeed)
		end
		if os.clock() < (W.slowUntil or 0) then sp = math.min(sp, jet and 95 or 45) end
		-- ramp up gently: most rollbacks came 1-7s into a trip right after snapping to full speed
		W.flySpeed = math.min(sp, (W.flySpeed or cfg.travelSpeed) + cfg.flyAccel * dt)
		sp = W.flySpeed
		local back = (rr.Position - lastSet).Magnitude
		if back > 35 then
			W.rbLog = W.rbLog or {}
			local up = rr.Position.Y - lastSet.Y
			table.insert(W.rbLog, 1, string.format("t%.1f sp%d vy%d jet%s back%d up%d y%d rag%.0fs dmg%.0fs", os.clock() - t0, W.flySpeed or 0, W.lastVy or 0, tostring(jet ~= nil), back, up, cur.Y, os.clock() - (W.lastRagdollT or 0), os.clock() - (W.lastDamageT or 0)))
			if #W.rbLog > 30 then table.remove(W.rbLog) end
			-- pulled mostly UP: the server has something solid under us that our ray can't see
			-- (invisible collision) -> don't try to go below it around here
			if up > back * 0.6 then
				floorY, floorAt = rr.Position.Y - 1, Vector3.new(rr.Position.X, 0, rr.Position.Z)
				upPulls += 1
				-- descending onto a spot under a roof: the server won't let us through it (anti-noclip),
				-- every try is pulled back up -> give up instead of fighting it until the timeout
				if upPulls >= 3 then W.flyBlocked = true ok = false done = true c:Disconnect() return end
			end
			cur = rr.Position
			-- a pull of hundreds of studs is a position desync (server snaps us to an old spot),
			-- not a speed complaint: just carry on from where we are
			if back < 300 then
				rollbacks += 1
				W.stats.rollbacks = (W.stats.rollbacks or 0) + 1
				speed = math.max(40, speed * 0.8)
				if rollbacks >= 2 then W.slowUntil = os.clock() + 12 end
			else
				W.stats.snaps = (W.stats.snaps or 0) + 1
			end
		end
		local lv = rr:FindFirstChildOfClass("LinearVelocity")
		if lv then lv.MaxForce = 0 end
		local flat = Vector3.new(goal.X - cur.X, 0, goal.Z - cur.Z)
		local remain = flat.Magnitude
		local dir = remain > 0.01 and flat.Unit or Vector3.zero
		-- horizontal step
		local step = math.min(sp * dt, remain)
		local nx, nz = cur.X + dir.X * step, cur.Z + dir.Z * step
		-- vertical: cruise height ahead, but descend onto the goal over the last stretch
		local want = cruiseY(Vector3.new(nx, 0, nz), dir, remain, jet ~= nil) or cur.Y
		if floorY and (Vector3.new(nx, 0, nz) - floorAt).Magnitude < 100 then want = math.max(want, floorY) end
		local finalApproach = opts.descend ~= false and remain < math.max(60, (cur.Y - goal.Y) * 1.6)
		if finalApproach then want = goal.Y end
		local dy = want - cur.Y
		local vmax = (dy > 0 and vUp or ((finalApproach or not jet) and 60 or vDown)) * dt
		local ny = cur.Y + math.clamp(dy, -vmax, vmax)
		W.lastVy = dt > 0 and (ny - cur.Y) / dt or 0
		cur = Vector3.new(nx, ny, nz)
		rr.AssemblyLinearVelocity = Vector3.zero
		rr.CFrame = remain > 0.5 and CFrame.new(cur, cur + dir) or CFrame.new(cur) * (rr.CFrame - rr.CFrame.Position)
		lastSet = cur
		if remain <= step + 0.01 and math.abs(goal.Y - cur.Y) < 1.5 then done = true c:Disconnect() end
	end)
	repeat task.wait() until done
	W.travelling = false
	return ok, speed
end

-- Royal Apparate (nobles: 12s cd, 22 HP) first, plain Apparate (60s, 50 HP) when it's the one ready
local function apparateSpell()
	local w = wand()
	if not w then return end
	local ra, a = w.Spells:FindFirstChild("Royal Apparate"), w.Spells:FindFirstChild("Apparate")
	local now = workspace:GetServerTimeNow()
	if ra and now >= (ra:GetAttribute("CooldownExpire") or 0) then return ra, w end
	if a and now >= (a:GetAttribute("CooldownExpire") or 0) then return a, w end
	return ra or a, w
end

function W.apparate(goal, escaping)
	local sp, w = apparateSpell()
	local c, h = char(), hum()
	if not (sp and c and h) then return false end
	if workspace:GetServerTimeNow() < (sp:GetAttribute("CooldownExpire") or 0) then return false end
	-- keep enough HP after the cost so we don't trip the low-HP retreat
	local cost = sp:GetAttribute("HealthCost") or 50
	local floor = cost < 35 and math.min(cfg.fleeHp, 30) or cfg.fleeHp -- Royal Apparate is cheap
	if not escaping and (h.Health - cost) / h.MaxHealth * 100 <= math.max(floor, 10) then return false end
	if h.Health <= (sp:GetAttribute("HealthCost") or 50) + 1 then return false end
	if (c:GetAttribute("DashStamina") or 0) < (sp:GetAttribute("StamCost") or 0) then return false end
	W.hoverPos = nil
	-- nothing can be cast on the broom (an aborted trip leaves us mounted)
	if c:GetAttribute("JetPacking") then W.broomOff() task.wait(0.15) end
	equip(w)
	sp:SetAttribute("SubEquipped", true)
	w.ToolListnerEvent:FireServer("Activate", hrp().Position + hrp().CFrame.LookVector * 20, hrp().Position, sp)
	local got = false
	for _ = 1, 15 do task.wait(0.1) if c:GetAttribute("Apparating") then got = true break end end
	sp:SetAttribute("SubEquipped", nil)
	if not got then return false end
	Events.MapApparateEvent:FireServer(Vector3.new(goal.X, 0, goal.Z))
	task.wait(1.2)
	return (hrp().Position - Vector3.new(goal.X, hrp().Position.Y, goal.Z)).Magnitude < 60
end

-- go to a world position; lands `above` studs over the ground there
-- (exact=true: end exactly at goal, e.g. inside buildings)
function W.travel(goal, above, exact)
	W.inTrip = true
	W.tripBroomTries = 0
	local r0 = hrp()
	local t0, d0 = os.clock(), r0 and (Vector3.new(goal.X, 0, goal.Z) - Vector3.new(r0.Position.X, 0, r0.Position.Z)).Magnitude or 0
	W.tripInfo = {}
	local ok, res = pcall(W._travel, goal, above, exact)
	W.inTrip = false
	-- trip log: distance, seconds, what was used (a = apparate, b<n> = blinks, f = fly)
	W.trips = W.trips or {}
	table.insert(W.trips, 1, string.format("%dm %.1fs %s%s", d0, os.clock() - t0, table.concat(W.tripInfo, ""), res and "" or " (aborted)"))
	if #W.trips > 30 then table.remove(W.trips) end
	if not ok then W.log[#W.log + 1] = "travel: " .. tostring(res) return false end
	return res
end
function W._travel(goal, above, exact)
	W.travelToken += 1
	local token = W.travelToken
	local r = hrp()
	if not r then return false end
	W.hoverPos = nil
	above = above or 3
	local gy = groundY(goal.X, goal.Z)
	local target = exact and goal or Vector3.new(goal.X, math.max(goal.Y, (gy or goal.Y)) + above, goal.Z)
	local dist = (Vector3.new(target.X, 0, target.Z) - Vector3.new(r.Position.X, 0, r.Position.Z)).Magnitude
	-- never Apparate into company: it costs half our HP
	-- nobles get Royal Apparate (12s cd, 22 HP): use it for almost every trip
	local asp = apparateSpell()
	local royal = asp and asp.Name == "Royal Apparate"
	local cheap = asp and (asp:GetAttribute("HealthCost") or 50) < 35
	if cfg.useApparate and not (W.noApparate and not cheap) and dist > (royal and cfg.royalApparateMin or cfg.apparateMin) and #W.threats(350, target) == 0 and W.apparate(target) then
		table.insert(W.tripInfo or {}, "a ")
		r = hrp()
		dist = (target - r.Position).Magnitude
	end
	-- a blink burst covers the first ~600 studs in ~3s, the broom does the rest
	if cfg.blinkTravel and dist > 200 and not (char() and char():GetAttribute("JetPacking")) then
		local nb = W.blinkBurst(target, nil, token)
		table.insert(W.tripInfo or {}, "b" .. nb .. " ")
		if token ~= W.travelToken then return false end
		r = hrp()
		dist = (Vector3.new(target.X, 0, target.Z) - Vector3.new(r.Position.X, 0, r.Position.Z)).Magnitude
	end
	local speed = cfg.travelSpeed
	if dist > 150 and not W.noCloak and W.cloakUseful() then W.setCloak(true) end
	if cfg.broomTravel and not cfg.underground and dist > 40 and W.broomOn() then speed = cfg.broomSpeed end
	if cfg.underground then
		local ok = W.glide(W.under(hrp().Position), speed, token)
		ok = ok and W.glide(W.under(target), speed, token)
		if W.undergroundArrive then return ok end
		return ok and W.glide(target, speed, token)
	end
	-- one smooth leg: constant horizontal speed, cruise over the highest ground ahead, land at the end
	local tf = os.clock()
	local done = W.fly(target, speed, token)
	table.insert(W.tripInfo or {}, string.format("f%s%d/%.0fs", speed == cfg.broomSpeed and "B" or "", dist, os.clock() - tf))
	if done and cfg.dismountOnArrive then W.broomOff() end
	return done
end
-- a spot under the terrain at (x,z)
function W.under(p)
	local ty = terrainY(p.X, p.Z) or p.Y
	return Vector3.new(p.X, ty - cfg.undergroundDepth, p.Z)
end
function W.stop() W.travelToken += 1 W.hoverPos = nil end

-- Indoors (Baron/Crown spawn in the castle, some chests sit under roofs): landing straight down
-- hits the roof and the server's anti-noclip keeps us on top. Land on open ground next to the
-- building instead and walk the navmesh path in.
local PFS = game:GetService("PathfindingService")
-- RequestStreamAroundAsync can hang for minutes (its timeout isn't honoured): run it on the side
function W.streamAround(p, t)
	local done = false
	task.spawn(function() pcall(function() lp:RequestStreamAroundAsync(p, t) end) done = true end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < (t or 2) + 0.3 do task.wait(0.05) end
	return done
end
W.roofCache = {}
local function roofed(p, noStream, ignore)
	local key = string.format("%d,%d,%d", p.X / 4, p.Y / 4, p.Z / 4)
	if W.roofCache[key] ~= nil then return W.roofCache[key] end
	-- far targets aren't streamed in: a roof we can't see is still a roof
	-- (never per candidate spot: 132 stream requests x 3s hung the farm for 8 minutes)
	local r = hrp()
	local loaded = r and (r.Position - p).Magnitude < 300
	if not noStream and not loaded then loaded = W.streamAround(p, 3) end
	rayP.FilterDescendantsInstances = { workspace.Characters, workspace.Entities, workspace.Particles, ignore }
	local hit = workspace:Raycast(p + Vector3.new(0, 3, 0), Vector3.new(0, 120, 0), rayP) ~= nil
	-- only trust (and cache) a "no roof" when the area was actually streamed in
	if hit or loaded then W.roofCache[key] = hit end
	return hit
end
-- known indoor spots (castle interior): roofed even when the stream request times out
W.roofCache["366,42,262"], W.roofCache["364,42,264"] = true, true
W.roofed = roofed
-- entry spots that worked (key = target rounded), seeded with the castle's east side
W.entryCache = { ["366,42,262"] = Vector3.new(1506, 175, 1051), ["364,42,264"] = Vector3.new(1506, 175, 1051) }
local function entryKey(t) return string.format("%d,%d,%d", t.X / 4, t.Y / 4, t.Z / 4) end
function W.walkIn(target)
	if target.Magnitude < 5 then return false end -- unstreamed model -> origin, not a real spot
	local key = entryKey(target)
	-- fly close first: the building (and its navmesh) only exists on our side once streamed in
	local cached = W.entryCache[key]
	local r = hrp()
	if cached then
		W.travel(cached, 0, true)
	elseif r and (r.Position - target).Magnitude > 250 then
		local near = target + (r.Position - target).Unit * 200
		W.travel(Vector3.new(near.X, target.Y + 60, near.Z), 0, true)
	end
	W.broomOff()
	-- open ground around the building (nearest first); paths are computed from each spot
	local cands = {}
	if cached then cands[1] = cached end
	for rad = 30, 270, 30 do
		for a = 0, 345, 15 do
			local p = target + Vector3.new(math.cos(math.rad(a)) * rad, 0, math.sin(math.rad(a)) * rad)
			local gy = groundY(p.X, p.Z)
			if gy and math.abs(gy - target.Y) < 60 and not roofed(Vector3.new(p.X, gy, p.Z), true) then cands[#cands + 1] = Vector3.new(p.X, gy + 3, p.Z) end
		end
		if #cands >= 12 then break end
	end
	if #cands == 0 then W.log[#W.log + 1] = "walkIn: no open ground near target" return false end
	local path, from
	for i = 1, math.min(10, #cands) do
		-- the goal itself can sit inside the artifact's collision box (NoPath): also try a spot
		-- 5 studs in front of it, toward the entry
		local flat = Vector3.new(cands[i].X - target.X, 0, cands[i].Z - target.Z)
		local goals = { target }
		if flat.Magnitude > 1 then goals[2] = target + flat.Unit * 5 end
		for _, goal in ipairs(goals) do
			local ok = pcall(function()
				path = PFS:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 8 })
				path:ComputeAsync(cands[i] - Vector3.new(0, 2.5, 0), goal)
			end)
			if ok and path.Status == Enum.PathStatus.Success then from = cands[i] break end
			path = nil
		end
		if path then break end
	end
	if not path then
		W.log[#W.log + 1] = "walkIn: no path from " .. math.min(10, #cands) .. " spots"
		return false
	end
	W.entryCache[key] = from
	W.travel(from, 0, true)
	W.broomOff()
	task.wait(0.3)
	W.travelToken += 1
	local token = W.travelToken
	for _, wp in ipairs(path:GetWaypoints()) do
		if token ~= W.travelToken or not alive() then return false end
		W.glide(wp.Position + Vector3.new(0, 3, 0), 40, token)
	end
	W.stats.walkIns = (W.stats.walkIns or 0) + 1
	return true
end

W.places = {
	["Town / Tree book"] = Vector3.new(287, 73, -234),
	["Gacha book"] = Vector3.new(186, 72, -235),
	["Police (sell)"] = Vector3.new(210, 76, -382),
	["Tavern (sell)"] = Vector3.new(664, 77, 1047),
	["Royal Keep (nobles)"] = Vector3.new(1472, 166, 1095),
	["King's Bank"] = Vector3.new(378, 82, 496),
	["Wizards Bank"] = Vector3.new(1097, 168, -1029),
	["Crystal Cave"] = Vector3.new(926, 85, -752),
	["Rylock's Scrapyard"] = Vector3.new(-172, 150, 1820),
	["Kill merchant"] = Vector3.new(-165, 85, 1747),
	["Spawn"] = Vector3.new(-444, 100, -35),
}
local SELLERS = { Vector3.new(210, 76, -382), Vector3.new(664, 77, 1047), Vector3.new(1472, 166, 1095) }

-------------------------------------------------------------------------------
-- money
-------------------------------------------------------------------------------
-- Drops are client-side pickables claimed via MoneyDropEvent. The VIP_Collector
-- attribute raises the vacuum radius from 40 to 9999 -> every drop on the map.
local function applyVacuum() lp:SetAttribute("VIP_Collector", cfg.vacuum or nil) end
applyVacuum()
conn(lp:GetAttributeChangedSignal("VIP_Collector"), function()
	if cfg.vacuum and not lp:GetAttribute("VIP_Collector") then task.defer(applyVacuum) end
end)

W.stats.startMoney = money()
W.stats.startTime = os.clock()
W.stats.earned = 0
local lastMoney = money()
conn(Concept.Currencies.Money.Changed, function(v)
	if v > lastMoney then W.stats.earned += v - lastMoney end
	lastMoney = v
end)

-- only what trinket sellers take (SellTo/TrinketSell); soulbound items are skipped
-- exactly what the game's GetTrinketValue counts (soulbound ones sell too)
local function sellable(t)
	return t:IsA("Tool") and t:GetAttribute("SellValue") ~= nil
end
local function trinkets()
	local n, v = 0, 0
	local c = char()
	for _, holder in ipairs({ lp.Backpack, c }) do
		for _, t in ipairs((holder and holder:GetChildren()) or {}) do
			if sellable(t) then
				local st = t:GetAttribute("Stacks") or 1
				n += st v += t:GetAttribute("SellValue") * st
			end
		end
	end
	return n, v
end
W.trinkets = trinkets
-- loot shows up several seconds after a chest/wagon opens (spin animation), so log arrivals
W.loot = {}
local function onLoot(t)
	if t:IsA("Tool") and t:GetAttribute("SellValue") then
		local e = string.format("%s $%d (%s, %.0fs after open)", t.Name, t:GetAttribute("SellValue"), tostring(W.lastOpened or "?"), os.clock() - (W.lastOpenT or 0))
		table.insert(W.loot, 1, e)
		if #W.loot > 20 then table.remove(W.loot) end
		W.stats.lootValue = (W.stats.lootValue or 0) + t:GetAttribute("SellValue")
		-- per chest type (red vs brown vs bank): count + value, to see what's worth chasing
		local kind = tostring(W.lastOpened or "?")
		W.lootByKind = W.lootByKind or {}
		local k = W.lootByKind[kind] or { n = 0, v = 0 }
		k.n += 1 k.v += t:GetAttribute("SellValue")
		W.lootByKind[kind] = k
		logf("ww_loot.txt", string.format("%s\t%s\t%d\n", kind, t.Name, t:GetAttribute("SellValue")))
	end
end
conn(lp.Backpack.ChildAdded, onLoot)
conn(lp.ChildAdded, function(b) if b:IsA("Backpack") then conn(b.ChildAdded, onLoot) end end) -- new Backpack each respawn

-- Selling = TrinketSellEvent:FireServer(<DialogConfig>). The game's client fires it once when you
-- step into the zone (and never again until you leave, hence "needs several tries").
-- Measured: the server takes it from anywhere within ~20-25 studs of the seller part
-- (20 ok, 30 rejected), no zone needed. Streaming a seller in from afar does NOT help.
-- So: fly straight at the seller and fire exactly once as soon as we're in range.
local SELL_RANGE = 19
W.sellCfgs = {}
local function noteCfg(v) if v:GetAttribute("DialogType") == "SellTrinkets" then W.sellCfgs[v] = true end end
for _, v in ipairs(CS:GetTagged("DialogConfig")) do noteCfg(v) end
conn(CS:GetInstanceAddedSignal("DialogConfig"), noteCfg)
local function sellCfgInRange()
	local r = hrp()
	if not r then return end
	for v in pairs(W.sellCfgs) do
		if v.Parent and v.Parent:IsA("BasePart") and v:IsDescendantOf(workspace) then
			if (v.Parent.Position - r.Position).Magnitude <= SELL_RANGE then return v end
		else
			W.sellCfgs[v] = nil
		end
	end
end
function W.trySellRemote(v)
	local n0 = trinkets()
	if n0 == 0 then return true end
	local m0 = money()
	Events.TrinketSellEvent:FireServer(v)
	local t0 = os.clock()
	repeat task.wait(0.05) until trinkets() < n0 or os.clock() - t0 > 1.5
	if trinkets() < n0 then
		W.stats.sells = (W.stats.sells or 0) + 1
		W.stats.sellMoney = (W.stats.sellMoney or 0) + (money() - m0)
		W.stats.lastSell = string.format("%d items +$%d at %s", n0, money() - m0, v.Parent.Parent.Name)
		return true
	end
	return false
end

-- nearest seller we may use: Royal Keep only for nobles, Police not while wanted,
-- none with a hostile player (radar) near it
function W.pickSeller()
	local r = hrp()
	if not r then return end
	local best, bd
	for i, p in ipairs(SELLERS) do
		-- wanted: police and the Keep (Daybreak/Imperial guards killed us selling there with a bounty) are off
		local ok = not (i == 3 and (not lp:GetAttribute("Noble") or W.iAmWanted())) and not (i == 1 and W.iAmWanted())
		if ok and #W.threats(150, p) == 0 then
			local d = (p - r.Position).Magnitude
			if not bd or d < bd then best, bd = p, d end
		end
	end
	return best
end

-- a sell trip costs 10-15s: batch small bags unless a seller is on the way anyway
function W.sellWorthIt()
	local n, v = trinkets()
	if n == 0 then return false end
	local p = W.pickSeller()
	if not p then return false end
	local r = hrp()
	return v >= cfg.sellMinValue or (r and (p - r.Position).Magnitude < cfg.sellNear)
end
function W.sellTrinkets()
	local n, val = trinkets()
	if n == 0 then return true end
	local v = sellCfgInRange()
	if v and W.trySellRemote(v) then return true end
	local p = W.pickSeller()
	if not p then status("sell: every seller has company") return false end
	status(string.format("selling %d trinkets ($%d)", n, val))
	W.setCloak(false) -- interactions fail while cloaked; can't toggle it on the broom later
	-- fly at the seller part itself (glides pass through walls); fire the moment we're in range
	local done, sold = false, false
	W.noCloak = true
	task.spawn(function() W.travel(p, 0, true) done = true W.noCloak = false end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 120 do
		v = sellCfgInRange()
		if v then
			W.stop()
			sold = W.trySellRemote(v)
			break
		end
		task.wait(0.05)
	end
	if not sold then
		v = sellCfgInRange()
		sold = v ~= nil and W.trySellRemote(v)
	end
	W.hoverPos = nil
	if sold then W.broomOff() end
	return sold or trinkets() == 0
end

local function prompts(filter)
	local out = {}
	for _, root in ipairs({ workspace.Missions, workspace.Entities }) do
		for _, p in ipairs(root:GetDescendants()) do
			if p:IsA("ProximityPrompt") and p.Enabled and filter(p) then out[#out + 1] = p end
		end
	end
	return out
end
local function openedByMe(p) return (p:GetAttribute("OpenedBy") or ""):find(lp.Name, 1, true) ~= nil end
W.promptTries = {}
local function promptFree(p)
	if p:HasTag("LockedPrompt") or openedByMe(p) then return false end
	local t = W.promptTries[p]
	if t and t.n >= 2 and os.clock() - t.last < 300 then return false end
	local mx, op = p:GetAttribute("MaxCanOpen"), p:GetAttribute("Opened")
	return not (mx and op and op >= mx)
end

-- rescue chests: Imperial (Daybreak) camps leave a bright red chest, poacher camps a brown one.
-- The red ones carry better loot (user report; loot log records the kind to confirm).
local function chestKind(p)
	local holder = p.Parent
	if not holder then return "?" end
	if holder.Name == "Daybreak" then return "red" end
	local main = holder:FindFirstChild("Main")
	if main and main:IsA("BasePart") then
		return (main.Color.R > 0.6 and main.Color.G < 0.35) and "red" or "brown"
	end
	local mission = holder:FindFirstAncestor("CowboyTest")
	return mission and "red" or "brown"
end
W.chestKind = chestKind
local function lootName(p)
	if p.ObjectText == "Animal" then return chestKind(p) .. " chest" end
	return p.ObjectText ~= "" and p.ObjectText or (p.Parent and p.Parent.Name) or "?"
end

function W.openPrompt(p)
	local t = W.promptTries[p] or { n = 0, last = 0 }
	t.n += 1 t.last = os.clock()
	W.promptTries[p] = t
	local holder = p.Parent
	if not holder then return false end
	local cf, size
	if holder:IsA("Model") and not holder:FindFirstChildWhichIsA("BasePart", true) then
		-- parts streamed out: the bounding box would be the world origin (we flew there and died)
		W.streamAround(holder:GetPivot().Position, 2)
	end
	if holder:IsA("Model") then cf, size = holder:GetBoundingBox() else cf, size = holder.CFrame, holder.Size end
	if cf.Position.Magnitude < 5 then return false end
	-- the prompt needs line of sight: stand on the ground beside the loot, try each side
	local sides = { cf.RightVector * (size.X / 2 + 3), -cf.RightVector * (size.X / 2 + 3), cf.LookVector * (size.Z / 2 + 3), -cf.LookVector * (size.Z / 2 + 3) }
	local first = true
	local tStart, tArrive = os.clock(), nil
	local r0 = hrp()
	local dist0 = r0 and (r0.Position - cf.Position).Magnitude or 0
	local function note(res, side)
		W.openLog = W.openLog or {}
		table.insert(W.openLog, 1, string.format("%s %dm travel %.1fs side%d hold%.1f total %.1fs %s", lootName(p), dist0, (tArrive or os.clock()) - tStart, side, p.HoldDuration, os.clock() - tStart, res))
		if #W.openLog > 30 then table.remove(W.openLog) end
	end
	for si, off in ipairs(sides) do
		local spot = cf.Position + off
		local gy = groundY(spot.X, spot.Z)
		if not gy or gy > cf.Position.Y + 6 then gy = cf.Position.Y - size.Y / 2 end -- under a roof: use the loot's floor
		local stand = Vector3.new(spot.X, gy + 3, spot.Z)
		if first then
			-- no streaming here (~2s per chest); a roof we can't see yet is caught by the fly abort
			if roofed(stand, true) then
				if not W.walkIn(stand) then t.n = math.max(t.n, 2) W.hoverPos = nil return false end
			else
				W.travel(stand, 0, true)
			end
			first = false
		else
			W.glide(stand, 30)
		end
		-- the trip got aborted (danger / low hp): never "hover" onto a spot we're not at - that's a
		-- teleport the server snaps back, over and over (we bled out flipping between two places)
		local rr = hrp()
		if not rr or (rr.Position - stand).Magnitude > 25 then W.hoverPos = nil note("not there", si) return false end
		tArrive = tArrive or os.clock()
		if not p.Parent then note("gone", si) return false end
		if W.flyBlocked then -- roof over the loot: skip it for a while
			t.n = math.max(t.n, 2)
			W.hoverPos = nil
			return false
		end
		local r = hrp()
		W.hoverPos = stand
		if r then r.CFrame = CFrame.new(stand, Vector3.new(cf.Position.X, stand.Y, cf.Position.Z)) end
		task.wait(0.3)
		if #W.realThreats() > 0 then W.hoverPos = nil return false end -- don't stand still next to them
		W.setCloak(false) -- prompts don't open while cloaked
		fireproximityprompt(p)
		local t0 = os.clock()
		repeat task.wait(0.2) until openedByMe(p) or not p.Parent or os.clock() - t0 > 1.2 + p.HoldDuration
		if openedByMe(p) or not p.Parent then
			note("ok", si)
			W.hoverPos = nil
			W.lastOpened, W.lastOpenT = lootName(p), os.clock()
			W.stats.opened = (W.stats.opened or 0) + 1
			return true
		end
	end
	note("failed", 4)
	W.hoverPos = nil
	return false
end

-- artifact missions: 2 chests (bounty 200) + an Artifact on a pillar (bounty 1000).
-- Artifact tool must be held 30s, then turns into a trinket (we got a Diamond, 1500).
function W.artifactTargets()
	return prompts(function(p)
		if p.Name ~= "LootGiver" then return false end
		local am = p:FindFirstAncestor("ArtifactMission")
		if am and p.Parent and p.Parent.Name == "Artifact" and not cfg.artifactFarm then return false end
		return am ~= nil and promptFree(p)
	end)
end
function W.wagonTargets()
	return prompts(function(p)
		if (p:GetAttribute("BountyGiver") or 0) > 0 and not cfg.artifactFarm then return false end -- would make us wanted
		return p.Name == "LootGiver" and p:FindFirstAncestor("ArtifactMission") == nil and promptFree(p)
	end)
end

local function waitArtifact()
	local a = lp.Backpack:FindFirstChild("Artifact") or (char() and char():FindFirstChild("Artifact"))
	if not a then return end
	local t0 = os.clock()
	W.holdingArtifact = true
	while a.Parent and os.clock() - t0 < 45 and alive() do
		status("holding artifact " .. tostring(a:GetAttribute("TimeLeft")) .. "s")
		W.setCloak(true)
		-- +1000 bounty: everyone hunts us. React on the radar long before they're in range
		-- (a rogue killed us at 5s left when we only reacted at 190 studs).
		local th = W.threats(450)
		local near = th[1]
		local tr = near and W.track[near.pl]
		if near and (near.d < 280 or (tr and (tr.closing or 0) > 15)) then
			W.hoverPos = nil
			local spot = W.safeSpot(700, 2400)
			status("holding artifact: " .. near.pl.Name .. " " .. math.floor(near.d) .. "m away, moving")
			if not W.apparate(spot, true) then
				W.blinkBurst(W.awayPoint(hrp().Position, near.p, 700), nil)
				W.travel(spot, 3)
			end
		elseif not W.hoverPos then
			local r = hrp()
			local gy = groundY(r.Position.X, r.Position.Z)
			W.hoverPos = Vector3.new(r.Position.X, (gy or r.Position.Y) + 3, r.Position.Z)
		end
		task.wait(0.25)
	end
	W.holdingArtifact = false
	W.hoverPos = nil
end
W.waitArtifact = waitArtifact

-- mining
local function pickaxeTool()
	return lp.Backpack:FindFirstChild("Pickaxe") or (char() and char():FindFirstChild("Pickaxe"))
end
local function castSpell(sp, aimPos)
	local w = sp and sp.Parent and sp.Parent.Parent
	if not (w and w:IsA("Tool")) then return false end
	if workspace:GetServerTimeNow() < (sp:GetAttribute("CooldownExpire") or 0) then return false end
	equip(w)
	sp:SetAttribute("SubEquipped", true)
	local r = hrp()
	w.ToolListnerEvent:FireServer("Activate", aimPos or (r.Position + r.CFrame.LookVector * 30), r.Position, sp)
	task.delay(0.3, function() if sp.Parent then sp:SetAttribute("SubEquipped", nil) end end)
	return true
end
W.castSpell = castSpell

function W.mineOnce()
	local best, bd
	local r = hrp()
	for _, v in ipairs(workspace.Resources:GetChildren()) do
		if (v:GetAttribute("Health") or 0) > 0 then
			local d = (v:GetPivot().Position - r.Position).Magnitude
			if not bd or d < bd then best, bd = v, d end
		end
	end
	if not best then status("no ore vein up") task.wait(3) return end
	local w = wand()
	if not pickaxeTool() then
		local sp = w and w.Spells:FindFirstChild("Vocare Pickaxe")
		if not sp then status("equip Vocare Pickaxe spell first") task.wait(3) return end
		castSpell(sp) task.wait(1.5)
	end
	local vp = best:GetPivot().Position
	W.travel(vp + Vector3.new(0, 0, 4), 1)
	local pick = pickaxeTool()
	if not pick then return end
	equip(pick)
	local t0 = os.clock()
	while cfg.autoMine and best.Parent and (best:GetAttribute("Health") or 0) > 0 and os.clock() - t0 < 30 do
		local rr = hrp()
		W.hoverPos = nil
		rr.CFrame = CFrame.new(rr.Position, Vector3.new(vp.X, rr.Position.Y, vp.Z))
		pick:Activate()
		task.wait(0.35)
	end
	W.stats.mined = (W.stats.mined or 0) + 1
end

-- contracts / skill tree / equip
W.contractTry = {}
function W.claimContracts()
	for _, c in ipairs(Concept.Contracts:GetChildren()) do
		-- a claim the server refuses would otherwise cost 1s on every farm loop
		if not c:GetAttribute("Completed") and (c:GetAttribute("Value") or 0) >= (c:GetAttribute("Goal") or math.huge) and os.clock() - (W.contractTry[c] or -1e9) > 120 then
			W.contractTry[c] = os.clock()
			Events.ContractsEvent:FireServer(c)
			task.wait(1)
		end
	end
end

local Shared_Tree = require(RepS.Modules.Client.SpellBook.Catagories.Tree.Shared_Tree)
function W.nextTreeItem(ch)
	local list = Directory.Tree[ch]
	if not list then return end
	for i, it in ipairs(list) do
		if not Concept.Inventory:FindFirstChild(it.ItemName) then return it, i end
	end
end
function W.buyTree(ch)
	local it = W.nextTreeItem(ch)
	if not it then return false end
	if (it.CurrencyType or "Money") ~= "Money" then return false end
	if money() - it.Cost < cfg.keepMoney then return false end
	local owns = Shared_Tree.GetPlayerOwnsTree(lp, ch)
	if not owns or not Shared_Tree.GetPlayerOwnsTierForTree(lp, ch) then return false end
	Events.Book_TreeEvent:FireServer("Upgrade", ch)
	task.wait(1.6)
	return Concept.Inventory:FindFirstChild(it.ItemName) ~= nil
end
function W.autoBuyStep()
	for _, ch in ipairs(cfg.buyOrder) do
		local it = W.nextTreeItem(ch)
		if it and (it.CurrencyType or "Money") == "Money" and money() - it.Cost >= cfg.keepMoney and Shared_Tree.GetPlayerOwnsTierForTree(lp, ch) then
			if W.buyTree(ch) then W.log[#W.log + 1] = "bought " .. it.ItemName end
			return
		end
	end
end

local function equippedCount(cat)
	local n = 0
	for _, it in ipairs(Concept.Inventory:GetChildren()) do
		local d = Directory.Items[it.Name]
		if d and d.Catagory == cat and it:GetAttribute("Equipped") then n += 1 end
	end
	return n
end
-- best loadout: strongest gear per slot, strongest spells, useful utilities
local function isHealName(n) return n:find("Episki") ~= nil end
local UTIL_PRIO = { Episkios = 2, ["Royal Apparate"] = 100, Apparate = 95, Lasso = 80, ["Open Sesame"] = 75, Stealio = 70, ["Invisio Maxima"] = 65, Invisio = 60, Wingardius = 55, Vocifero = 20, Revelio = 30, Repairo = 5, Lumo = 1 }
-- measured on bandits: Bombarda one-shots 40hp, Ignisio 30 dmg cone (30 studs), Expulso 0 dmg (disarm only)
-- Matrificus: rarity 1 but 18 dmg cone every 3s = ~3x the dps of the 15s-cooldown spells
local SPELL_ADJ = { Matrificus = 30, Bombarda = 8, Ignisio = 6, Ignisium = 8, Expulso = -15, Aquarcia = -5, Haste = -12 }
local function statSum(it)
	local st = it:FindFirstChild("ItemStats")
	local n = 0
	if st then for _, v in pairs(st:GetAttributes()) do if type(v) == "number" then n += v end end end
	return n
end
function W.desiredLoadout()
	local want = {}
	local byCat = {}
	-- only the single best self-heal earns the "always carry a heal" bonus
	local bestHeal, bestHealR
	for _, it in ipairs(Concept.Inventory:GetChildren()) do
		local d = Directory.Items[it.Name]
		if d and d.Catagory == "Spells" and isHealName(it.Name) and (not bestHealR or (d.Rarity or 1) > bestHealR) then bestHeal, bestHealR = it, d.Rarity or 1 end
	end
	for _, it in ipairs(Concept.Inventory:GetChildren()) do
		local d = Directory.Items[it.Name]
		if d then
			local cat = d.Catagory
			local score
			if cat == "Equipment" then
				cat = "Eq:" .. tostring(d.EquipCatagory)
				score = statSum(it) * 10 + (d.Rarity or 0)
			elseif cat == "Utility Spells" then
				score = UTIL_PRIO[it.Name] or 10
				if it.Name == "Vocare Pickaxe" then score = cfg.autoMine and 90 or 3 end
			elseif cat == "Spells" or cat == "Wild Magic" then
				score = (d.Rarity or 1) * 10
				if it == bestHeal then score += 25 elseif isHealName(it.Name) then score -= 15 end
				score += SPELL_ADJ[it.Name] or 0
			end
			if score then
				byCat[cat] = byCat[cat] or {}
				table.insert(byCat[cat], { it = it, score = score })
			end
		end
	end
	for cat, list in pairs(byCat) do
		table.sort(list, function(a, b) return a.score > b.score end)
		local slots = cat:sub(1, 3) == "Eq:" and 1 or (Directory.InventoryEquipSlots[cat] or 0)
		for i, e in ipairs(list) do
			-- gear without stats is cosmetic: keep whatever is worn there
			if cat:sub(1, 3) == "Eq:" and e.score < 10 and i == 1 then break end
			want[e.it] = i <= slots
		end
	end
	return want
end
-- InventoryEvent is a toggle: two concurrent callers flip the same item twice -> lock
function W.autoEquipSpells()
	if W.equipBusy then return false end
	W.equipBusy = true
	local ok, res = pcall(W._autoEquip)
	W.equipBusy = false
	return ok and res
end
function W._autoEquip()
	local want = W.desiredLoadout()
	local changed = false
	for it, on in pairs(want) do -- unequip first to free slots
		if not on and it:GetAttribute("Equipped") then Events.InventoryEvent:FireServer(it) task.wait(0.9) changed = true end
	end
	for it, on in pairs(want) do
		if on and not it:GetAttribute("Equipped") then Events.InventoryEvent:FireServer(it) task.wait(0.9) changed = true end
	end
	return changed
end

-------------------------------------------------------------------------------
-- combat
-------------------------------------------------------------------------------
local cam = workspace.CurrentCamera
W.target = nil

local function isWanted(pl, m)
	return (pl:GetAttribute("Bounty") or 0) > 0 or pl:GetAttribute("Rogue") or m:GetAttribute("Rogued") or (m:GetAttribute("Bounty") or 0) > 0
end
local function validTarget(m)
	if not m or not m.Parent or m == char() then return false end
	local h = m:FindFirstChildOfClass("Humanoid")
	if not h or h.Health <= 0 or m:GetAttribute("KOed") or m:GetAttribute("G_Cloak") then return false end
	local pl = Players:GetPlayerFromCharacter(m)
	if pl then
		if m:GetAttribute("Safezone") then return false end
		-- fight back only when it's legal (shooting a non-rogue makes US rogue), and while farming
		-- leave other players alone: picking fights with rogues just ends in flees
		local legal = isWanted(pl, m)
		if W.attackers and W.attackers[pl] and os.clock() < W.attackers[pl] then return legal end
		if not cfg.aimPlayers or (cfg.bossFarm and W.farming) then return false end
		if cfg.onlyWanted and not isWanted(pl, m) then return false end
		return true
	end
	return cfg.aimAI and m:GetAttribute("IsAI") == true
end
local function aimPart(m) return m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart") end

function W.findTarget(maxRange)
	local r = hrp()
	if not r then return end
	local best, bs
	local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
	for _, h in ipairs(CS:GetTagged("ActiveHumanoid")) do
		local m = h.Parent
		if validTarget(m) then
			local p = aimPart(m)
			if p then
				local d = (p.Position - r.Position).Magnitude
				if d <= (maxRange or cfg.aimRange) then
					local score = d
					if cfg.aimFov > 0 and not W.farming then
						local sp, on = cam:WorldToViewportPoint(p.Position)
						if not on then score = nil else
							local px = (Vector2.new(sp.X, sp.Y) - center).Magnitude
							score = px <= cfg.aimFov and px or nil
						end
					end
					if score and (not bs or score < bs) then best, bs = m, score end
				end
			end
		end
	end
	return best
end

-- silent aim: every aim query the game makes (wand bolts, spell casts, and the
-- server's GetPlayerPositionFunc callback at cast end) returns our target.
local function silentPos()
	if not cfg.silentAim then return end
	local t = W.target
	if t and validTarget(t) then
		local p = aimPart(t)
		if p then return p.Position + (p.AssemblyLinearVelocity * 0.05), t end
	end
end
if not G.__WW_hooks then
	G.__WW_hooks = {}
	for _, ms in ipairs({ RepS.Modules.Shared.GetMouseHit, RepS.Modules.ToolClient.Raw.GetMouseHit }) do
		local f = require(ms)
		local old
		old = hookfunction(f, function(...)
			local sp = G.__WW and G.__WW.silentPos
			if sp then
				local p, t = sp()
				if p then return p, t end
			end
			return old(...)
		end)
	end
	local ev = Events.GetPlayerPositionFunc
	G.__WW_hooks.origInvoke = getcallbackvalue(ev, "OnClientInvoke")
end
W.silentPos = silentPos
do
	local orig = G.__WW_hooks.origInvoke
	Events.GetPlayerPositionFunc.OnClientInvoke = function(a, b)
		local p, t = silentPos()
		if p then return p, char():GetPivot().Position, t end
		return orig(a, b)
	end
end

local UTIL = { Expulso = true, Aquarcia = true, Apparate = true, ["Royal Apparate"] = true, ["Vocare Pickaxe"] = true, Lumo = true, Revelio = true, ["Open Sesame"] = true, Haste = true, Invisio = true, ["Invisio Maxima"] = true, Vocaralea = true, Wingardius = true, Protego = true, Expresso = true, ["Noctous Maxima"] = true, Lasso = true, Lasso2 = true }
local function isHeal(n) return n:find("Episki") ~= nil end
function W.offensiveSpells()
	local w = wand()
	local out = {}
	if not w then return out end
	for _, s in ipairs(w.Spells:GetChildren()) do
		if not UTIL[s.Name] and not isHeal(s.Name) then out[#out + 1] = s end
	end
	return out
end
local function spellReady(s) return workspace:GetServerTimeNow() >= (s:GetAttribute("CooldownExpire") or 0) end

-- Invisio (the Cloak noble's Invisio Maxima) is a toggle (G_Cloak): see-through for others, gone
-- from the map radar (MapEvent stops sending us), no bounty marker, skipped by aim assist. The wand
-- can't fire while cloaked -> stay cloaked all the time except while we're shooting.
local function cloakSpell()
	local w = wand()
	return w and (w.Spells:FindFirstChild("Invisio Maxima") or w.Spells:FindFirstChild("Invisio"))
end
-- the cast costs ~1s (+ uncloaking later): only when someone could come for us
function W.cloakUseful()
	if W.iAmWanted() or W.heistActive or W.holdingArtifact then return true end
	local _, v = trinkets()
	return v >= 1500 or #W.threats(1500) > 0
end
function W.setCloak(on)
	local c = char()
	if not c then return false end
	if (c:GetAttribute("G_Cloak") == true) == on then return true end
	if on and not cfg.useCloak then return false end
	local sp = cloakSpell()
	if not sp or not spellReady(sp) or c:GetAttribute("CastingSpell") or c:GetAttribute("JetPacking") then return false end
	castSpell(sp)
	for _ = 1, 10 do
		task.wait(0.1)
		if (c:GetAttribute("G_Cloak") == true) == on then
			W.stats.cloaks = (W.stats.cloaks or 0) + 1
			return true
		end
	end
	return false
end

-- fire through the game's own tool path (keeps ammo/animations/cooldowns legit)
function W.attackStep()
	local c = char()
	if not c or c:GetAttribute("CastingSpell") then return end
	if not (cfg.autoSpells or cfg.autoFire) then return end
	if c:GetAttribute("G_Cloak") then W.setCloak(false) return end
	W.lastShotT = os.clock()
	local w = wand()
	if not w then return end
	equip(w)
	if cfg.autoSpells then
		for _, s in ipairs(W.offensiveSpells()) do
			if spellReady(s) then
				s:SetAttribute("SubEquipped", true)
				w:Activate()
				task.delay(0.3, function() if s.Parent then s:SetAttribute("SubEquipped", nil) end end)
				return
			end
		end
	end
	if cfg.autoFire then w:Activate() end
end

-- Vocaralea (Wild Magic) is a toggle: +25 max HP (ConjuredArmor) while on; cast only when off
function W.armorStep()
	local c = char()
	if not cfg.keepArmor or not c or c:GetAttribute("ConjuredArmor") or c:GetAttribute("CastingSpell") or c:GetAttribute("JetPacking") or W.travelling then return end
	if os.clock() - (W.lastArmor or 0) < 5 then return end
	local w = wand()
	local sp = w and w.Spells:FindFirstChild("Vocaralea")
	if sp and spellReady(sp) then W.lastArmor = os.clock() castSpell(sp) end
end
function W.healStep()
	local h = hum()
	if not h or h.Health / h.MaxHealth * 100 > cfg.healAt then return end
	local w = wand()
	if not w then return end
	for _, s in ipairs(w.Spells:GetChildren()) do
		if isHeal(s.Name) and spellReady(s) then castSpell(s) return end
	end
end

-- bandit mission farm: hover above the camp, silent-aim everything
function W.missionTarget()
	local r = hrp()
	-- stay with the camp we're on until it's cleared: re-scoring every loop ping-ponged us across
	-- the map after each kill (other players clear camps -> "fewest left" keeps changing): 34% of
	-- the time went into "to mission" trips
	local cur = W.curCamp
	if cur and cur.Parent and not cur:GetAttribute("Completed") and (cur:GetAttribute("EnemiesLeft") or 0) > 0
		and os.clock() > ((W.campSkip or {})[cur] or 0) and #W.threats(300, cur:GetPivot().Position) == 0 then
		return cur
	end
	W.curCamp = W._pickCamp(r)
	return W.curCamp
end
function W._pickCamp(r)
	-- busy server: nothing clear by workClear -> accept camps with nobody within 300 rather than idle
	for _, clear in ipairs({ cfg.workClear, 300 }) do
		local best, bd
		for _, m in ipairs(workspace.Missions:GetChildren()) do
			if m:IsA("Model") and not m:GetAttribute("Completed") and (m:GetAttribute("EnemiesLeft") or 0) > 0 and os.clock() > ((W.campSkip or {})[m] or 0) then
				-- clearing a camp unlocks its 2 rescue wagons: prefer the one that's done soonest
				-- (flight ~120 studs/s, ~4s per bandit), skip camps with hostile players around
				local mp = m:GetPivot().Position
				local d = (mp - r.Position).Magnitude / 120 + m:GetAttribute("EnemiesLeft") * 4
				if m.Name == "CowboyTest" then d -= 12 end -- Imperial camp: its wagons are the red chests
				if #W.threats(clear, mp) == 0 and (not bd or d < bd) then best, bd = m, d end
			end
		end
		if best then return best end
	end
end

-------------------------------------------------------------------------------
-- safety: who can hurt us, fleeing, laying low
-------------------------------------------------------------------------------
function W.iAmWanted()
	return (lp:GetAttribute("Bounty") or 0) > 0 or lp:GetAttribute("Rogue") == true or lp:GetAttribute("HasIllegalArtifact") == true
end
-- RogueEvent (fired by the spellbook's Rogue tab) starts a 40s countdown (RogueTurnOffTick)
-- that wipes bounty + rogue status. Only fire it while rogue, and never twice.
function W.clearBounty()
	if not cfg.autoClearBounty or not lp:GetAttribute("Rogue") then return false end
	if lp:GetAttribute("RogueTurnOffTick") or lp:GetAttribute("HasIllegalArtifact") then return false end
	if os.clock() - (W.lastClear or 0) < 6 then return false end
	W.lastClear = os.clock()
	Events.RogueEvent:FireServer()
	W.stats.bountyClears = (W.stats.bountyClears or 0) + 1
	return true
end

-- heartbeat for the PC-side watchdog (ww_watchdog.sh): time + "disconnected" flag. A kicked /
-- disconnected client (error 277) looks alive to the bridge but nothing replicates any more.
local GuiService = game:GetService("GuiService")
-- Server hop: a hostile server (hunters everywhere) runs at 40-55k/h vs 100-200k/h on a calm one.
-- A rejoin (process restart by the watchdog) lands on another server and also wipes bounty/rogue.
-- HOP when the last 10 min had >= 8 flees or 2 deaths and made < 70k/h; at most every 25 min,
-- never while holding the Baron (Royal Apparate is worth more than a calm server).
W.loadedAt = os.clock()
W.fleeTimes, W.deathTimes, W.moneyHist = {}, {}, {}
cfg.autoHop = cfg.autoHop ~= false
local function countSince(list, sec)
	local n = 0
	for _, t in ipairs(list) do if os.clock() - t < sec then n += 1 end end
	return n
end
function W.hopWanted()
	if not cfg.autoHop or lp:GetAttribute("Noble") == "Baron" then return false end
	if os.clock() - W.loadedAt < 600 then return false end
	local last = 0
	pcall(function() last = tonumber(readfile("ww_hop.txt")) or 0 end)
	if os.time() - last < 1500 then return false end
	local old = W.moneyHist[1]
	if not old or os.clock() - old.t < 590 then return false end
	local perHour = (money() - old.m) / (os.clock() - old.t) * 3600
	local flees, deaths = countSince(W.fleeTimes, 600), countSince(W.deathTimes, 1200)
	if (flees >= 8 or deaths >= 2) and perHour < 70000 then
		W.hopReason = string.format("%d flees, %d deaths, %.0fk/h", flees, deaths, perHour / 1000)
		return true
	end
	return false
end
spawnLoop("heartbeat", function()
	local dc = false
	pcall(function() dc = GuiService:GetErrorMessage() ~= "" end)
	table.insert(W.moneyHist, { t = os.clock(), m = money() })
	while W.moneyHist[1] and os.clock() - W.moneyHist[1].t > 600 do table.remove(W.moneyHist, 1) end
	local flag = dc and "DC" or "OK"
	if W.hopRequested then flag = "HOP" end -- sticky: the watchdog polls every 20s
	if not dc and not W.hopRequested and W.hopWanted() then
		flag = "HOP"
		W.hopRequested = true
		pcall(writefile, "ww_hop.txt", tostring(os.time()))
		logf("ww_deaths.txt", string.format("[%s] server hop requested: %s\n", os.date("%H:%M:%S"), tostring(W.hopReason)))
	end
	pcall(writefile, "ww_hb.txt", string.format("%d %s %d %s", os.time(), flag, money(), tostring(W.status)))
	task.wait(5)
end)

-- what raises the bounty / restarts the 40s clear countdown? log it with what we were doing
W.bountyLog = {}
do
	local lastB, lastTick = lp:GetAttribute("Bounty"), lp:GetAttribute("RogueTurnOffTick")
	local function note(what)
		table.insert(W.bountyLog, 1, string.format("[%s] %s | %s tgt=%s", os.date("%H:%M:%S"), what, tostring(W.status), W.target and W.target.Name or "-"))
		if #W.bountyLog > 40 then table.remove(W.bountyLog) end
	end
	conn(lp:GetAttributeChangedSignal("Bounty"), function()
		local b = lp:GetAttribute("Bounty")
		note(string.format("bounty %s -> %s", tostring(lastB), tostring(b)))
		lastB = b
	end)
	conn(lp:GetAttributeChangedSignal("RogueTurnOffTick"), function()
		local t = lp:GetAttribute("RogueTurnOffTick")
		if t == nil or lastTick == nil or t > lastTick then note(string.format("clear tick %s -> %s", tostring(lastTick), tostring(t))) end
		lastTick = t
	end)
	conn(lp:GetAttributeChangedSignal("Rogue"), function() note("Rogue=" .. tostring(lp:GetAttribute("Rogue"))) end)
end

-- radar: the server broadcasts every player's position at 2 Hz (MapEvent feeds the
-- spellbook map), so players outside the ~420 stud streaming radius are still known
W.radar = {}
conn(Events.MapEvent.OnClientEvent, function(t)
	if type(t) ~= "table" then return end
	local now = os.clock()
	for name, p in pairs(t) do if typeof(p) == "Vector3" then W.radar[name] = { p = p, t = now } end end
end)
local function posOf(pl)
	local m = pl.Character
	if m and m.PrimaryPart then return m.PrimaryPart.Position, os.clock() end
	local e = W.radar[pl.Name]
	if e and os.clock() - e.t < 3 then return e.p, e.t end
end
W.posOf = posOf
-- hunters: players who hit us or came right at us while we were wanted. They stay dangerous for
-- 10 minutes whatever their rogue status (bounty hunters camp the artifact/wanted players).
W.hunters = {}
local function isHunter(pl) return W.hunters[pl.Name] and os.clock() - W.hunters[pl.Name] < 600 end
W.isHunter = isHunter
local function hostilePl(pl, wanted)
	local m = pl.Character
	return wanted or isHunter(pl) or pl:GetAttribute("Rogue") or (m and m:GetAttribute("Rogued")) or (pl:GetAttribute("Bounty") or 0) > 0
end
-- rogues can hit anyone; while we are wanted anyone can hit us. `from` defaults to us.
function W.threats(radius, from)
	local r = hrp()
	local out = {}
	from = from or (r and r.Position)
	if not from then return out end
	local wanted = W.iAmWanted()
	for _, pl in ipairs(Players:GetPlayers()) do
		local p = pl ~= lp and posOf(pl)
		if p then
			local m = pl.Character
			local h = m and m:FindFirstChildOfClass("Humanoid")
			local down = (h and m.PrimaryPart and h.Health <= 0) or (m and m:GetAttribute("KOed"))
			local d = (p - from).Magnitude
			if not down and d <= radius and hostilePl(pl, wanted) then out[#out + 1] = { m = m, pl = pl, d = d, p = p } end
		end
	end
	table.sort(out, function(a, b) return a.d < b.d end)
	return out
end
-- per-player tracking: approaching? attacked us?
W.track = {}
W.attackers = {}
function W.realThreats()
	local out = {}
	for _, t in ipairs(W.threats(cfg.dangerRadius)) do
		local pl = t.pl
		local tr = pl and W.track[pl]
		local approaching = tr and tr.closing and tr.closing > 12
		local attacker = pl and W.attackers[pl] and os.clock() < W.attackers[pl]
		-- within 90 always; further out only when they come at us or already hit us
		-- (160 for everyone meant 16 flees / 10 min on a busy server; a flee costs ~7s)
		if t.d < 90 or approaching or attacker or (isHunter(pl) and t.d < 160) then out[#out + 1] = t end
	end
	return out
end
spawnLoop("track", function()
	task.wait(0.25)
	local r = hrp()
	if not r then return end
	for _, pl in ipairs(Players:GetPlayers()) do
		local p, stamp
		if pl ~= lp then p, stamp = posOf(pl) end
		if p then
			local tr = W.track[pl] or {}
			-- how fast is *their* movement pointed at us (our own travel doesn't count);
			-- radar positions only change at 2 Hz, so use the sample's own timestamp
			if tr.p and stamp > tr.t + 0.05 then
				local v = (p - tr.p) / (stamp - tr.t)
				local toMe = r.Position - p
				local c = toMe.Magnitude > 1 and v:Dot(toMe.Unit) or 0
				tr.closing = (tr.closing or 0) * 0.4 + c * 0.6
			end
			if not tr.t or stamp > tr.t + 0.05 then tr.p, tr.t = p, stamp end
			tr.d = (p - r.Position).Magnitude
			W.track[pl] = tr
		end
	end
	for pl in pairs(W.track) do if not pl.Parent then W.track[pl] = nil end end
end)
function W.attackerTarget()
	local r = hrp()
	local best, bd
	for pl, untilT in pairs(W.attackers) do
		local m = pl.Character
		-- only legal targets: hitting a player who isn't rogue / wanted makes US rogue (+50 bounty,
		-- seen right after our bounty cleared while we still shot at the hunter who'd chased us)
		local legal = pl:GetAttribute("Rogue") or (m and m:GetAttribute("Rogued")) or (pl:GetAttribute("Bounty") or 0) > 0
		if os.clock() < untilT and legal and m and m.PrimaryPart and r then
			local d = (m.PrimaryPart.Position - r.Position).Magnitude
			if d < cfg.aimRange and (not bd or d < bd) then best, bd = m, d end
		end
	end
	return best
end

W.dangerUntil = 0
local lastHp
spawnLoop("safety", function()
	task.wait(0.25)
	local h = hum()
	if not h then lastHp = nil return end
	-- took damage while a hostile player is around -> danger
	if lastHp and h.Health < lastHp - 1 then
		W.lastDamageT = os.clock()
		-- who hit us? nearest hostile player unless a bandit is right next to us
		local near = W.threats(160)
		local aiClose = false
		for _, hh in ipairs(CS:GetTagged("ActiveHumanoid")) do
			local m = hh.Parent
			if m and m:GetAttribute("IsAI") and hh.Health > 0 and hrp() and (m:GetPivot().Position - hrp().Position).Magnitude < 60 then aiClose = true break end
		end
		if #near > 0 and (not aiClose or near[1].d < 50) then
			local pl = Players:GetPlayerFromCharacter(near[1].m)
			if pl then W.attackers[pl] = os.clock() + 25 W.hunters[pl.Name] = os.clock() end
			W.dangerUntil = os.clock() + 20
		end
	end
	lastHp = h.Health
	if W.iAmWanted() then
		for _, t in ipairs(W.threats(40)) do W.hunters[t.pl.Name] = os.clock() end
	end
	-- desync monitor: the radar carries the server's idea of our position (not while cloaked)
	local me = W.radar[lp.Name]
	local rr0 = hrp()
	if me and rr0 and os.clock() - me.t < 0.6 and not (char() and char():GetAttribute("G_Cloak")) then
		local d = Vector3.new(me.p.X - rr0.Position.X, 0, me.p.Z - rr0.Position.Z).Magnitude
		W.desync = d
		-- ~0.5s of radar lag at 120/s is ~60 studs; beyond 200 the server isn't following us
		if d > 200 then
			W.stats.desyncSamples = (W.stats.desyncSamples or 0) + 1
			W.stats.desyncMax = math.max(W.stats.desyncMax or 0, d)
			W.desyncSince = W.desyncSince or os.clock()
		else
			W.desyncSince = nil
		end
	end
	-- last ~8s of hp/position/status for the death log
	local r0 = hrp()
	-- void rescue: remember the last spot with ground under us; falling far below it -> back up
	if r0 then
		local gy = groundY(r0.Position.X, r0.Position.Z)
		if gy and r0.Position.Y - gy < 40 and r0.Position.Y > -50 then W.lastGround = r0.Position end
		if r0.Position.Y < -120 and W.lastGround then
			W.stats.voidRescues = (W.stats.voidRescues or 0) + 1
			W.stop()
			r0.AssemblyLinearVelocity = Vector3.zero
			r0.CFrame = CFrame.new(W.lastGround + Vector3.new(0, 4, 0))
		end
	end
	W.hpHist = W.hpHist or {}
	table.insert(W.hpHist, { t = os.clock(), hp = math.floor(h.Health), p = r0 and r0.Position, s = W.status })
	if #W.hpHist > 32 then table.remove(W.hpHist, 1) end
	-- (heists used a 45-stud radius here: two rogues camping at 29/55 studs killed us mid-heist)
	if cfg.avoidPlayers and #W.realThreats() > 0 then W.dangerUntil = math.max(W.dangerUntil, os.clock() + 8) end
	local lowHp = h.Health / h.MaxHealth * 100 < cfg.fleeHp
	local danger = cfg.avoidPlayers and (os.clock() < W.dangerUntil or lowHp)
	if danger and not W.fleeing and not W.holdingArtifact and (cfg.bossFarm or cfg.artifactFarm or cfg.bankChests or cfg.autoMine) then
		W.stop() -- abort whatever we are doing; farm loop picks up the flee
	end
end)

-- point far away from every other player (candidates: known places + rings around us)
local MAP_MIN, MAP_MAX = Vector2.new(-1850, -1750), Vector2.new(2250, 2380)
local TOWN = Vector3.new(220, 75, -330) -- police/MoL: deadly while wanted
-- point far away from every other player; avoids town while wanted and bandit camps
function W.safeSpot(minFrom, maxFrom)
	local r = hrp()
	local me = r.Position
	local wanted = W.iAmWanted()
	local cands = {}
	for x = MAP_MIN.X, MAP_MAX.X, 300 do
		for z = MAP_MIN.Y, MAP_MAX.Y, 300 do cands[#cands + 1] = Vector3.new(x, me.Y, z) end
	end
	local others = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local p = pl ~= lp and posOf(pl)
		if p then others[#others + 1] = p end
	end
	local camps = {}
	for _, m in ipairs(workspace.Missions:GetChildren()) do if m:IsA("Model") then camps[#camps + 1] = m:GetPivot().Position end end
	local best, bs
	for _, c in ipairs(cands) do
		local d = (Vector3.new(c.X, 0, c.Z) - Vector3.new(me.X, 0, me.Z)).Magnitude
		if d >= (minFrom or 0) and d <= (maxFrom or math.huge) and W.isLand(c.X, c.Z, 80) then
			local nearest = 1500
			for _, o in ipairs(others) do nearest = math.min(nearest, (Vector3.new(o.X, 0, o.Z) - Vector3.new(c.X, 0, c.Z)).Magnitude) end
			local score = nearest - d * 0.1
			if wanted and (Vector3.new(c.X, 0, c.Z) - Vector3.new(TOWN.X, 0, TOWN.Z)).Magnitude < 800 then score -= 2000 end
			for _, cp in ipairs(camps) do if (cp - c).Magnitude < 300 then score -= 400 end end
			if not bs or score > bs then best, bs = c, score end
		end
	end
	if best then
		local gy = groundY(best.X, best.Z)
		best = Vector3.new(best.X, gy or math.max(me.Y, 120), best.Z)
	end
	return best or me
end

-- where can we keep earning far away from `danger`? unlocked chests (red first) > camps > bank chests
function W.productiveSpot(danger, minAway)
	minAway = minAway or 800
	local best, bs
	local function consider(pos, value, land)
		if not pos then return end
		if danger and Vector3.new(pos.X - danger.X, 0, pos.Z - danger.Z).Magnitude < minAway then return end
		if #W.threats(cfg.workClear, pos) > 0 then return end
		if not bs or value > bs then best, bs = land or pos, value end
	end
	if cfg.wagonLoot then
		for _, p in ipairs(W.wagonTargets()) do consider(mdlPos(p.Parent), W.chestKind(p) == "red" and 3000 or 1200) end
	end
	if cfg.bossFarm then
		for _, m in ipairs(workspace.Missions:GetChildren()) do
			if m:IsA("Model") and (m:GetAttribute("EnemiesLeft") or 0) > 0 then
				local mp = m:GetPivot().Position
				-- land beside the camp, not in the middle of it
				consider(mp, (m.Name == "CowboyTest" and 1500 or 1000) - m:GetAttribute("EnemiesLeft") * 60, mp + Vector3.new(80, 0, 0))
			end
		end
	end
	if cfg.bankChests then
		for _, p in ipairs(W.artifactTargets()) do consider(mdlPos(p.Parent), 1300) end
	end
	return best
end

-- Flee = relocate: Apparate to the most productive spot on the other side of the map and keep
-- farming there. Without Apparate: one blink burst straight away from the threat, then carry on
-- with work that's away from it. Only wait around when HP is actually low.
function W.flee(reason)
	W.fleeing = true
	W.hoverPos = nil
	W.stats.flees = (W.stats.flees or 0) + 1
	table.insert(W.fleeTimes, os.clock())
	local r, h = hrp(), hum()
	if not (r and h) then W.fleeing = false return end
	local th = W.realThreats()
	local danger = (th[1] and th[1].p) or r.Position
	local dest = W.productiveSpot(danger, 800)
	status("FLEE: " .. reason .. (dest and " -> relocating" or ""))
	W.broomOff()
	local sp = apparateSpell()
	local moved = false
	-- Apparate is the fastest way out (gone in ~1.5s); the cloak (~0.5s cast) comes after it,
	-- or first when we have to blink/fly away in sight of them
	if cfg.useApparate and sp and h.Health > (sp:GetAttribute("HealthCost") or 50) + 15 and workspace:GetServerTimeNow() >= (sp:GetAttribute("CooldownExpire") or 0) then
		moved = W.apparate(dest or W.safeSpot(900, 3500), true)
		if moved then W.stats.relocations = (W.stats.relocations or 0) + 1 end
	end
	W.setCloak(true)
	if not moved then
		W.blinkBurst(W.awayPoint(r.Position, danger, 700), nil)
		if dest and (dest - hrp().Position).Magnitude < 1500 then
			W.travel(dest, 3)
		elseif #W.realThreats() > 0 then
			W.travel(W.safeSpot(300, 900), 3)
		end
	end
	W.dangerUntil = 0 -- somewhere else now; the safety loop re-arms if they follow
	local t0 = os.clock()
	while alive() and os.clock() - t0 < 60 do
		local hh = hum()
		local pct = hh.Health / hh.MaxHealth * 100
		if pct >= cfg.fleeHp + 15 or #W.realThreats() > 0 then break end
		local w = wand()
		for _, s in ipairs((w and w.Spells:GetChildren()) or {}) do
			if isHeal(s.Name) and spellReady(s) then castSpell(s) break end
		end
		if not W.hoverPos then
			local p = hrp().Position
			local gy = groundY(p.X, p.Z)
			W.hoverPos = Vector3.new(p.X, (gy or p.Y) + 3, p.Z)
		end
		status(string.format("healing up %d%%", pct))
		task.wait(0.5)
	end
	W.hoverPos = nil
	W.fleeing = false
end

-------------------------------------------------------------------------------
-- bank heist (artifact missions spawn at King's Bank / Wizards Bank)
-------------------------------------------------------------------------------
local function isArtifactPrompt(p) return p.Parent and p.Parent.Name == "Artifact" end
local function apparateReady()
	local sp = apparateSpell()
	local h, c = hum(), char()
	if not (sp and h and c) then return false end
	return workspace:GetServerTimeNow() >= (sp:GetAttribute("CooldownExpire") or 0)
		and (h.Health - (sp:GetAttribute("HealthCost") or 50)) / h.MaxHealth * 100 > math.max(cfg.fleeHp, 10)
end
W.apparateReady = apparateReady

-- the artifact's +1000 bounty makes every player a hunter for 30s: only take it with nobody
-- within 700 studs (radar), HP near full and an Apparate ready for the escape. Otherwise leave it
-- for later instead of waiting around (it stays up until someone takes it).
local function artifactOk(site)
	local h = hum()
	if not h or h.Health / h.MaxHealth < 0.8 then return false, "low hp" end
	if #W.threats(700, site) > 0 then return false, "players near" end
	for _, pl in ipairs(Players:GetPlayers()) do
		local p = isHunter(pl) and posOf(pl)
		if p and (p - site).Magnitude < 1800 then return false, pl.Name .. " hunts us" end
	end
	if cfg.heistNeedApparate and not apparateReady() then return false, "apparate on cooldown" end
	return true
end
-- chestsOnly=false: only go when the artifact can be taken too (bank chests alone ~ break even:
-- ~1100 loot vs 40s of rogue status); the farm loop calls it with true as a fallback when idle
function W.heist(chestsOnly)
	if os.clock() < (W.heistCooldown or 0) then return false end
	local targets = {}
	for _, p in ipairs(W.artifactTargets()) do
		if not mdlPos(p.Parent) then -- not streamed in / no position: skip for now
		elseif not isArtifactPrompt(p) then table.insert(targets, 1, p)
		else
			local ok, why = artifactOk(mdlPos(p.Parent))
			if ok then targets[#targets + 1] = p else W.artifactSkip = why end
		end
	end
	if #targets == 0 then return false end
	local withArtifact = isArtifactPrompt(targets[#targets])
	if not withArtifact and not chestsOnly then return false end
	local site = mdlPos(targets[1].Parent)
	if not site then return false end
	-- scout with the radar (map-wide): a rogue camping the loot kills looters on arrival
	local camp = W.threats(cfg.heistClear, site)
	if #camp > 0 then
		status("heist: " .. camp[1].pl.Name .. " camping the bank, waiting")
		return false
	end
	W.heistActive = true
	W.noApparate = true -- arrive with full HP; Apparate costs half of it
	W.stats.heists = (W.stats.heists or 0) + 1
	for _, p in ipairs(targets) do
		if not alive() then break end
		local camp2 = W.threats(cfg.heistClear, site)
		if #camp2 > 0 then
			status("heist: " .. camp2[1].pl.Name .. " showed up, abort")
			-- busy bank: one chest then flee + 40s rogue is a loss; leave the heists alone for a while
			W.heistCooldown = os.clock() + 300
			break
		end
		if isArtifactPrompt(p) then
			-- re-check: the chests just made us wanted, so now every player counts
			local ok, why = artifactOk(site)
			if not ok then status("heist: leaving the artifact (" .. why .. ")") break end
			status("heist: artifact")
			W.openPrompt(p)
			task.wait(0.6)
			-- escape far away right away
			local spot = W.safeSpot(1000, 3200)
			status("heist: escaping")
			if not W.apparate(spot, true) then W.travel(spot, 3) end
		else
			status("heist: chest")
			W.openPrompt(p)
		end
	end
	W.heistActive = false
	W.noApparate = false
	return true
end

-- noble artifacts (Crown/Baron/Phoenix/Cloak) spawn in workspace.NobleStuff.ArtifactSpawners
-- with a "Take Artifact" prompt (NobleGiver, hold 1s). Every spawn is logged to learn the timing.
local function nobleFolder() local n = workspace:FindFirstChild("NobleStuff") return n and n:FindFirstChild("ArtifactSpawners") end
function W.nobleTargets()
	local out, f = {}, nobleFolder()
	if not f then return out end
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Enabled and d.Parent then out[#out + 1] = d end
	end
	return out
end
do
	local f = nobleFolder()
	if f then
		conn(f.DescendantAdded, function(d)
			if d:IsA("ProximityPrompt") then
				task.defer(function()
					local m = d.Parent
					logf("ww_noble.txt", string.format("[%s] spawn %s (%s)\n", os.date("%H:%M:%S"), m and m:GetFullName() or "?", d.ObjectText))
				end)
			end
		end)
	end
end
function W.grabNoble(p)
	local m = p.Parent
	local pos = m and mdlPos(m)
	if not pos then return false end
	local near = W.threats(200, pos)
	if #near > 0 then status("noble artifact: " .. near[1].pl.Name .. " is near it") return false end
	W.nobleTry = W.nobleTry or {}
	if os.clock() - (W.nobleTry[m.Name] or -1e9) < 90 then return false end
	W.nobleTry[m.Name] = os.clock()
	status("noble artifact: " .. m.Name)
	W.noApparate = true
	local arrived
	-- the artifact's own model (case, canopy) is not a roof
	if roofed(pos, false, m.Parent) then arrived = W.walkIn(pos + Vector3.new(0, 1, 0)) else arrived = W.travel(pos + Vector3.new(0, 1, 0), 0, true) end
	W.noApparate = false
	if not p.Parent then return false end
	-- never "hover" onto a spot we didn't reach: that's a straight teleport the server snaps back
	local r = hrp()
	if not arrived or not r or (r.Position - pos).Magnitude > 20 then status("noble artifact: couldn't reach it") return false end
	if #W.realThreats() > 0 then status("noble artifact: company, leaving") return false end
	local before = {}
	for _, t in ipairs(lp.Backpack:GetChildren()) do before[t] = true end
	W.hoverPos = pos + Vector3.new(0, 1.5, 0)
	W.broomOff()
	W.setCloak(false)
	fireproximityprompt(p)
	task.wait(p.HoldDuration + 2)
	W.hoverPos = nil
	local got = {}
	for _, t in ipairs(lp.Backpack:GetChildren()) do if not before[t] then got[#got + 1] = t.Name end end
	local e = string.format("[%s] grabbed %s: got %s | Noble=%s Bounty=%s Illegal=%s", os.date("%H:%M:%S"), m.Name, table.concat(got, ","), tostring(lp:GetAttribute("Noble")), tostring(lp:GetAttribute("Bounty")), tostring(lp:GetAttribute("HasIllegalArtifact")))
	W.log[#W.log + 1] = e
	logf("ww_noble.txt", e .. "\n")
	W.stats.nobles = (W.stats.nobles or 0) + 1
	return true
end

-- death log: the game stamps THF_<faction> (time hit by faction) on characters
W.deaths = {}
local function hookDeath(c)
	local h = c:WaitForChild("Humanoid", 10)
	if not h then return end
	local logged = false
	conn(h.Died, function()
		if logged then return end -- Died fires more than once here
		logged = true
		table.insert(W.deathTimes, os.clock())
		local thf = {}
		for k, v in pairs(c:GetAttributes()) do
			if k:sub(1, 4) == "THF_" then thf[#thf + 1] = k:sub(5) .. "@" .. string.format("%.1f", v) end
		end
		local near = {}
		local r = c.PrimaryPart
		for _, pl in ipairs(Players:GetPlayers()) do
			local m = pl.Character
			if pl ~= lp and r and m and m.PrimaryPart and (m.PrimaryPart.Position - r.Position).Magnitude < 250 then
				near[#near + 1] = string.format("%s(%dm%s)", pl.Name, (m.PrimaryPart.Position - r.Position).Magnitude, (pl:GetAttribute("Rogue") or m:GetAttribute("Rogued")) and ",rogue" or "")
			end
		end
		local e = string.format("[%s] died at %s while '%s' | hit by: %s (gt %.1f) | near: %s | bounty %s",
			os.date("%H:%M:%S"), r and tostring(Vector3.new(math.floor(r.Position.X), math.floor(r.Position.Y), math.floor(r.Position.Z))) or "?",
			tostring(W.status), table.concat(thf, ", "), workspace.DistributedGameTime, table.concat(near, ", "), tostring(lp:GetAttribute("Bounty")))
		local att = {}
		for pl, t in pairs(W.attackers) do if os.clock() < t then att[#att + 1] = pl.Name end end
		e = e .. " | attackers: " .. table.concat(att, ",")
		local hist = {}
		for _, x in ipairs(W.hpHist or {}) do
			if os.clock() - x.t < 8 then
				hist[#hist + 1] = string.format("%.1fs:%d@%s[%s]", x.t - os.clock(), x.hp, x.p and string.format("%d,%d,%d", x.p.X, x.p.Y, x.p.Z) or "?", tostring(x.s))
			end
		end
		e = e .. "\n    hist: " .. table.concat(hist, " ")
		W.hpHist = {}
		W.deaths[#W.deaths + 1] = e
		logf("ww_deaths.txt", e .. "\n")
		W.hoverPos = nil
		W.heistActive = false
		W.noApparate = false
	end)
end
if lp.Character then task.spawn(hookDeath, lp.Character) end
conn(lp.CharacterAdded, hookDeath)

-------------------------------------------------------------------------------
-- main farm loop
-------------------------------------------------------------------------------
W.farmFn = function()
	task.wait(0.3)
	if not alive() then W.hoverPos = nil task.wait(1) return end
	if cfg.autoContracts then W.claimContracts() end
	if cfg.autoBuy then W.autoBuyStep() end
	if cfg.autoEquipSpells and os.clock() - (W.lastEquip or 0) > 15 then W.lastEquip = os.clock() W.autoEquipSpells() end

	local farmingAny = cfg.artifactFarm or cfg.bankChests or cfg.bossFarm or cfg.autoMine or cfg.nobleGrab
	-- holding the artifact: its own escape logic (radar, early hops) beats a generic flee
	if lp.Backpack:FindFirstChild("Artifact") or (char() and char():FindFirstChild("Artifact")) then waitArtifact() return end
	if farmingAny and cfg.avoidPlayers then
		local h = hum()
		if os.clock() < W.dangerUntil then W.flee("hostile player") return end
		if h.Health / h.MaxHealth * 100 < cfg.fleeHp then W.flee("low hp") return end
	end
	-- wanted: sell loot if the seller is clear, otherwise hide until the bounty clears
	W.br = "noble"
	if cfg.nobleGrab then
		-- each artifact gives its own noble spell and replaces the one you hold:
		-- Baron = Royal Apparate (12s map teleport, the farming one), Cloak = Invisio Maxima, ...
		local mine = lp:GetAttribute("Noble")
		for _, p in ipairs(W.nobleTargets()) do
			local kind = p.Parent and p.Parent.Name
			if (not mine or (kind == cfg.noblePrefer and mine ~= kind)) and W.grabNoble(p) then return end
		end
	end
	W.br = "heist"
	if (cfg.bankChests or cfg.artifactFarm) and W.heist() then return end
	W.br = "wanted"
	if W.iAmWanted() then W.clearBounty() end
	-- bounty clearing (40s) and nobody around: keep farming instead of parking
	local clearing = lp:GetAttribute("RogueTurnOffTick") and #W.threats(500) == 0
	if W.iAmWanted() and (farmingAny) and cfg.layLow and not clearing then
		-- sell right away unless the bounty clears soon anyway (then every seller incl. police is fine)
		if cfg.autoSell and trinkets() > 0 and not lp:GetAttribute("RogueTurnOffTick") and W.pickSeller() then W.sellTrinkets() return end
		local spot = W.hoverPos
		if not spot or #W.threats(400) > 0 then
			W.hoverPos = nil
			local s2 = W.safeSpot(300, 2000)
			if (s2 - hrp().Position).Magnitude > 900 and W.apparateReady() then W.apparate(s2) else W.travel(s2, 3) end
			local r = hrp()
			local gy = groundY(r.Position.X, r.Position.Z)
			W.hoverPos = Vector3.new(r.Position.X, (gy or r.Position.Y) + 3, r.Position.Z)
		end
		W.setCloak(true)
		local tick = lp:GetAttribute("RogueTurnOffTick")
		status(string.format("wanted ($%d) - laying low%s", lp:GetAttribute("Bounty") or 0, tick and (", clears in " .. tick .. "s") or ""))
		task.wait(1)
		return
	end
	-- never leave a fight to sell: only when no bandit is in range
	W.br = "sell"
	-- no usable seller (players camping them while we're wanted): keep working instead of retrying
	if cfg.autoSell and trinkets() >= cfg.sellAt and farmingAny and not W.findTarget(260) and W.sellWorthIt() then
		W.sellTrinkets() return
	end
	W.br = "wagons"
	if cfg.wagonLoot and farmingAny then
		local r = hrp()
		local best, bd
		for _, p in ipairs(W.wagonTargets()) do
			local pp = mdlPos(p.Parent)
			if pp and #W.threats(cfg.workClear, pp) == 0 then
				-- red chests are worth a detour: rank by distance / 3
				local d = (pp - r.Position).Magnitude / (chestKind(p) == "red" and 3 or 1)
				if not bd or d < bd then best, bd = p, d end
			end
		end
		if best then status(string.format("%s (%dm)", lootName(best), (mdlPos(best.Parent) - r.Position).Magnitude)) W.openPrompt(best) return end
	end
	W.br = "boss"
	if cfg.bossFarm and not W.iAmWanted() then
		local m = W.missionTarget()
		if m then
			W.farming = true
			local mp = m:GetPivot().Position
			if (hrp().Position - mp).Magnitude > 160 then
				status("to mission")
				W.undergroundArrive = cfg.underground
				W.travel(mp, 40)
				W.undergroundArrive = false
			end
			local t = W.findTarget(260)
			if t then
				status("fighting " .. t.Name)
				-- stand on the ground at range (shots need line of sight)
				local tp = t:GetPivot().Position
				local r = hrp()
				local away = Vector3.new(r.Position.X - tp.X, 0, r.Position.Z - tp.Z)
				away = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
				local spot = tp + away * cfg.fightDistance
				local gy = groundY(spot.X, spot.Z) or tp.Y
				if gy > tp.Y + 25 then gy = tp.Y end -- roof/tree hit, use target height
				local want = Vector3.new(spot.X, gy + 3, spot.Z)
				if not W.hoverPos or (W.hoverPos - want).Magnitude > 12 then
					W.hoverPos = nil
					W.glide(want, cfg.travelSpeed)
					if hrp() and (hrp().Position - want).Magnitude < 15 then W.hoverPos = want end
				end
			else
				-- EnemiesLeft > 0 but nobody in reach (strays / not spawned): don't camp there forever
				W.campWait = W.campWait or {}
				local cw = W.campWait[m] or { since = os.clock() }
				if os.clock() - (cw.last or 0) > 5 then cw.since = os.clock() end
				cw.last = os.clock()
				W.campWait[m] = cw
				if os.clock() - cw.since > 12 then
					W.campSkip = W.campSkip or {}
					W.campSkip[m] = os.clock() + 90
					W.campWait[m] = nil
					W.farming = false
					W.hoverPos = nil
					return
				end
				status("waiting for bandits")
				local wx, wz = mp.X + 70, mp.Z
				local wait = cfg.underground and W.under(mp) or Vector3.new(wx, (groundY(wx, wz) or mp.Y) + 3, wz)
				if not W.hoverPos or (W.hoverPos - wait).Magnitude > 5 then
					W.hoverPos = nil
					W.glide(wait, cfg.travelSpeed)
					if hrp() and (hrp().Position - wait).Magnitude < 15 then W.hoverPos = wait end
				end
			end
			return
		end
		W.farming = false
	end
	-- bounty clearing (we hold fire while wanted): wait next to the next camp, out of its aggro
	-- range, so the fight starts the moment the bounty is gone instead of idling somewhere
	if cfg.bossFarm and W.iAmWanted() and lp:GetAttribute("RogueTurnOffTick") then
		local m = W.missionTarget()
		if m then
			local mp = m:GetPivot().Position
			local r = hrp()
			local away = Vector3.new(r.Position.X - mp.X, 0, r.Position.Z - mp.Z)
			away = away.Magnitude > 1 and away.Unit or Vector3.new(1, 0, 0)
			local stage = mp + away * 200
			if W.isLand(stage.X, stage.Z, 30) and (r.Position - stage).Magnitude > 60 then
				status(string.format("staging near %s (bounty clears in %ss)", m.Name, tostring(lp:GetAttribute("RogueTurnOffTick"))))
				W.travel(stage, 3)
			end
			status(string.format("staging near %s (bounty clears in %ss)", m.Name, tostring(lp:GetAttribute("RogueTurnOffTick"))))
			task.wait(1)
			return
		end
	end
	-- nothing better to do: bank chests even without the artifact
	if (cfg.bankChests or cfg.artifactFarm) and W.heist(true) then return end
	if cfg.autoMine then W.mineOnce() return end
	status("idle")
end
spawnLoop("farm", W.farmFn)
-- farm watchdog: an iteration stuck > 120s (a yielding call that never returns) -> log + restart
spawnLoop("farmwatch", function()
	task.wait(5)
	if W.farmIterStart and os.clock() - W.farmIterStart > 120 then
		local tb = (debug.traceback(W.threads.farm):gsub("\n", " "))
		W.log[#W.log + 1] = "farm hung in " .. tostring(W.br) .. ": " .. tb
		logf("ww_deaths.txt", string.format("[%s] farm hung (%s): %s\n", os.date("%H:%M:%S"), tostring(W.status), tb))
		pcall(task.cancel, W.threads.farm)
		W.farmIterStart = nil
		W.travelToken += 1
		W.hoverPos = nil
		spawnLoop("farm", W.farmFn)
	end
end)

-- combat loop (targeting + auto attack + heal)
spawnLoop("combat", function()
	task.wait(0.12)
	if not alive() then return end
	local need = cfg.silentAim or cfg.autoFire or cfg.autoSpells or cfg.bossFarm
	local attacker = cfg.fightBack and W.attackerTarget()
	W.target = attacker or (need and W.findTarget((cfg.bossFarm and W.farming) and 260 or nil)) or nil
	if attacker then
		local a, b = cfg.autoFire, cfg.autoSpells
		cfg.autoFire, cfg.autoSpells = true, true
		W.attackStep()
		cfg.autoFire, cfg.autoSpells = a, b
		return
	end
	if cfg.autoHeal then W.healStep() end
	-- no offensive casts mid-trip: CastingSpell blocks dash-blinks and casting knocks us off the broom
	if W.inTrip or W.heistActive or W.holdingArtifact then return end -- stay cloaked, no side fights
	W.armorStep()
	-- wanted: every bandit kill adds +25 bounty (measured) -> hold fire until the bounty is cleared
	if W.iAmWanted() then return end
	if W.target and (cfg.autoFire or cfg.autoSpells or cfg.bossFarm) then
		if cfg.bossFarm and W.farming then
			local a, b = cfg.autoFire, cfg.autoSpells
			cfg.autoFire, cfg.autoSpells = true, true
			W.attackStep()
			cfg.autoFire, cfg.autoSpells = a, b
		else
			W.attackStep()
		end
	end
end)

-------------------------------------------------------------------------------
-- player mods
-------------------------------------------------------------------------------
W.noclipped = {}
conn(RS.Stepped, function()
	local c = char()
	if not c then return end
	if cfg.noclip then
		for _, p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false W.noclipped[p] = true end end
	elseif next(W.noclipped) then
		for p in pairs(W.noclipped) do if p.Parent then p.CanCollide = true end end
		W.noclipped = {}
	end
	local h = hum()
	if h and cfg.walkSpeed > 0 and h.WalkSpeed < cfg.walkSpeed then h.WalkSpeed = cfg.walkSpeed end
	if cfg.broomMult ~= 1 and c:GetAttribute("JetPacking") and not W.travelling then
		local lv = c.PrimaryPart and c.PrimaryPart:FindFirstChildOfClass("LinearVelocity")
		if lv then lv.VectorVelocity = lv.VectorVelocity * Vector3.new(cfg.broomMult, 1, cfg.broomMult) end
	end
end)

-- anti-ragdoll: the server only sets the Ragdoll attribute; RagdollClient then puts our humanoid
-- into Physics/PlatformStand. Skip that for our own (living) character.
local RagdollClient = require(RepS.Modules.Client.Char.RagdollClient)
local origRagdolled = RagdollClient.HumanoidRagdolled
RagdollClient.HumanoidRagdolled = function(h, on, died, ...)
	if cfg.antiRagdoll and on and not died and h == hum() then
		W.stats.ragdollsBlocked = (W.stats.ragdollsBlocked or 0) + 1
		W.lastRagdollT = os.clock()
		h.PlatformStand = false
		h:ChangeState(Enum.HumanoidStateType.GettingUp)
		return
	end
	return origRagdolled(h, on, died, ...)
end
conn(UIS.JumpRequest, function()
	local h = hum()
	if cfg.infJump and h and not (char() and char():GetAttribute("JetPacking")) then h:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

local origLight = { Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd, GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient }
local function applyFullbright()
	if cfg.fullbright then
		Lighting.Brightness = 2 Lighting.ClockTime = 14 Lighting.FogEnd = 1e6 Lighting.GlobalShadows = false Lighting.Ambient = Color3.fromRGB(180, 180, 180)
	else
		for k, v in pairs(origLight) do Lighting[k] = v end
	end
end

-------------------------------------------------------------------------------
-- ESP
-------------------------------------------------------------------------------
local espFolder = Instance.new("Folder")
espFolder.Name = "WWVis"
espFolder.Parent = (gethui and gethui()) or game:GetService("CoreGui")
local espCache = {}
local function espFor(obj, color, textFn)
	local e = espCache[obj]
	if not e then
		local hl = Instance.new("Highlight")
		hl.FillTransparency = 0.75 hl.OutlineColor = color hl.FillColor = color
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = obj hl.Parent = espFolder
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 220, 0, 36) bb.AlwaysOnTop = true bb.StudsOffset = Vector3.new(0, 3.5, 0)
		bb.Adornee = obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)) or obj
		bb.Parent = espFolder
		local tl = Instance.new("TextLabel", bb)
		tl.Size = UDim2.new(1, 0, 1, 0) tl.BackgroundTransparency = 1 tl.TextColor3 = color
		tl.TextStrokeTransparency = 0.3 tl.Font = Enum.Font.GothamBold tl.TextSize = 12
		e = { hl = hl, bb = bb, tl = tl, seen = 0 }
		espCache[obj] = e
	end
	e.tl.Text = textFn()
	e.seen = os.clock()
end
spawnLoop("esp", function()
	task.wait(0.4)
	local r = hrp()
	local now = os.clock()
	if r then
		if cfg.espPlayers or cfg.espAI then
			for _, h in ipairs(CS:GetTagged("ActiveHumanoid")) do
				local m = h.Parent
				if m and m ~= char() then
					local pl = Players:GetPlayerFromCharacter(m)
					if (pl and cfg.espPlayers) or (not pl and cfg.espAI and m:GetAttribute("IsAI")) then
						local wanted = pl and isWanted(pl, m)
						local col = pl and (wanted and Color3.fromRGB(255, 70, 70) or (pl:GetAttribute("Noble") and Color3.fromRGB(255, 215, 80) or Color3.fromRGB(120, 200, 255))) or Color3.fromRGB(255, 160, 60)
						espFor(m, col, function()
							local d = (m:GetPivot().Position - r.Position).Magnitude
							local s = string.format("%s  %d/%d  %dm", m.Name, h.Health, h.MaxHealth, d)
							if pl then
								local b = pl:GetAttribute("Bounty")
								if b and b > 0 then s = s .. "  $" .. b end
								if pl:GetAttribute("Noble") then s = s .. "  NOBLE" end
								if m:GetAttribute("Safezone") then s = s .. "  (safe)" end
							end
							return s
						end)
					end
				end
			end
		end
		if cfg.espLoot then
			for _, p in ipairs(prompts(function(p) return p.Name == "LootGiver" end)) do
				local holder = p.Parent
				if holder then
					espFor(holder, Color3.fromRGB(80, 255, 140), function()
						local mine = openedByMe(p) and " (done)" or ""
						return string.format("%s %s/%s%s %dm", holder.Name, tostring(p:GetAttribute("Opened") or 0), tostring(p:GetAttribute("MaxCanOpen") or "?"), mine, (mdlPos(holder) - r.Position).Magnitude)
					end)
				end
			end
			for _, v in ipairs(workspace.Resources:GetChildren()) do
				if (v:GetAttribute("Health") or 0) > 0 then
					espFor(v, Color3.fromRGB(200, 120, 255), function() return string.format("%s %d hp %dm", v.Name, v:GetAttribute("Health"), (v:GetPivot().Position - r.Position).Magnitude) end)
				end
			end
		end
	end
	for o, e in pairs(espCache) do
		if now - e.seen > 1.2 or not o.Parent then e.hl:Destroy() e.bb:Destroy() espCache[o] = nil end
	end
end)

-------------------------------------------------------------------------------
-- GUI
-------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "WWPanel" gui.ResetOnSpawn = false gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = espFolder.Parent
W.gui = gui

local C_BG, C_PANEL, C_ACC, C_TXT, C_DIM = Color3.fromRGB(20, 22, 30), Color3.fromRGB(30, 33, 44), Color3.fromRGB(120, 140, 255), Color3.fromRGB(230, 232, 240), Color3.fromRGB(140, 145, 165)
local main = Instance.new("Frame", gui)
main.Size = UDim2.new(0, 460, 0, 420) main.Position = UDim2.new(0, 60, 0.5, -210)
main.BackgroundColor3 = C_BG main.BorderSizePixel = 0 main.Active = true
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
local top = Instance.new("TextLabel", main)
top.Size = UDim2.new(1, -20, 0, 30) top.Position = UDim2.new(0, 12, 0, 0) top.BackgroundTransparency = 1
top.Font = Enum.Font.GothamBold top.TextSize = 15 top.TextColor3 = C_TXT top.TextXAlignment = Enum.TextXAlignment.Left
top.Text = "Wizard West  ·  RightShift menu  ·  F6 pause farm  ·  F7 stop"
do -- drag
	local dragging, start, sp
	top.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging, start, sp = true, i.Position, main.Position end end)
	conn(UIS.InputChanged, function(i) if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then local d = i.Position - start main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y) end end)
	conn(UIS.InputEnded, function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
end
local statusL = Instance.new("TextLabel", main)
statusL.Size = UDim2.new(1, -24, 0, 34) statusL.Position = UDim2.new(0, 12, 1, -38) statusL.BackgroundTransparency = 1
statusL.Font = Enum.Font.Gotham statusL.TextSize = 12 statusL.TextColor3 = C_DIM statusL.TextXAlignment = Enum.TextXAlignment.Left statusL.TextWrapped = true
W.statusLabel = statusL

local tabBar = Instance.new("Frame", main)
tabBar.Size = UDim2.new(1, -24, 0, 26) tabBar.Position = UDim2.new(0, 12, 0, 32) tabBar.BackgroundTransparency = 1
local tl = Instance.new("UIListLayout", tabBar) tl.FillDirection = Enum.FillDirection.Horizontal tl.Padding = UDim.new(0, 6)
local pages = {}
local function page(name)
	local b = Instance.new("TextButton", tabBar)
	b.Size = UDim2.new(0, 80, 1, 0) b.BackgroundColor3 = C_PANEL b.TextColor3 = C_TXT b.Font = Enum.Font.GothamMedium b.TextSize = 13 b.Text = name b.AutoButtonColor = true
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
	local f = Instance.new("ScrollingFrame", main)
	f.Size = UDim2.new(1, -24, 1, -110) f.Position = UDim2.new(0, 12, 0, 64) f.BackgroundTransparency = 1 f.BorderSizePixel = 0
	f.ScrollBarThickness = 4 f.AutomaticCanvasSize = Enum.AutomaticSize.Y f.CanvasSize = UDim2.new() f.Visible = false
	local l = Instance.new("UIListLayout", f) l.Padding = UDim.new(0, 5) l.SortOrder = Enum.SortOrder.LayoutOrder
	pages[name] = { f = f, b = b, n = 0 }
	b.MouseButton1Click:Connect(function()
		for _, p in pairs(pages) do p.f.Visible = false p.b.BackgroundColor3 = C_PANEL end
		f.Visible = true b.BackgroundColor3 = C_ACC
	end)
	return pages[name]
end
local function row(pg, h)
	pg.n += 1
	local r = Instance.new("Frame", pg.f)
	r.Size = UDim2.new(1, -6, 0, h or 28) r.BackgroundColor3 = C_PANEL r.BorderSizePixel = 0 r.LayoutOrder = pg.n
	Instance.new("UICorner", r).CornerRadius = UDim.new(0, 5)
	return r
end
local function label(parent, text, x, w)
	local t = Instance.new("TextLabel", parent)
	t.Size = UDim2.new(w or 1, -(x or 10) - 4, 1, 0) t.Position = UDim2.new(0, x or 10, 0, 0) t.BackgroundTransparency = 1
	t.Font = Enum.Font.Gotham t.TextSize = 13 t.TextColor3 = C_TXT t.TextXAlignment = Enum.TextXAlignment.Left t.Text = text
	return t
end
local function toggle(pg, text, key, onChange)
	local r = row(pg)
	label(r, text)
	local b = Instance.new("TextButton", r)
	b.Size = UDim2.new(0, 46, 0, 20) b.Position = UDim2.new(1, -54, 0.5, -10) b.Font = Enum.Font.GothamBold b.TextSize = 11
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	local function paint() b.Text = cfg[key] and "ON" or "OFF" b.BackgroundColor3 = cfg[key] and C_ACC or Color3.fromRGB(60, 63, 78) b.TextColor3 = C_TXT end
	paint()
	b.MouseButton1Click:Connect(function() cfg[key] = not cfg[key] paint() if onChange then onChange(cfg[key]) end W.saveCfg() end)
	W.repaint = W.repaint or {}
	table.insert(W.repaint, paint)
end
local function number(pg, text, key, step, lo, hi, onChange)
	local r = row(pg)
	label(r, text)
	local box = Instance.new("TextBox", r)
	box.Size = UDim2.new(0, 70, 0, 20) box.Position = UDim2.new(1, -78, 0.5, -10) box.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
	box.TextColor3 = C_TXT box.Font = Enum.Font.Gotham box.TextSize = 12 box.Text = tostring(cfg[key]) box.ClearTextOnFocus = false
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
	box.FocusLost:Connect(function()
		local v = tonumber(box.Text)
		if v then cfg[key] = math.clamp(v, lo or -math.huge, hi or math.huge) if onChange then onChange(cfg[key]) end W.saveCfg() end
		box.Text = tostring(cfg[key])
	end)
end
local function button(pg, text, fn)
	local r = row(pg)
	local b = Instance.new("TextButton", r)
	b.Size = UDim2.new(1, 0, 1, 0) b.BackgroundTransparency = 1 b.Font = Enum.Font.GothamMedium b.TextSize = 13 b.TextColor3 = C_ACC b.Text = text
	b.MouseButton1Click:Connect(function() task.spawn(function() local ok, e = pcall(fn) if not ok then status("error: " .. tostring(e)) end end) end)
end
local function header(pg, text)
	pg.n += 1
	local t = Instance.new("TextLabel", pg.f)
	t.Size = UDim2.new(1, -6, 0, 20) t.BackgroundTransparency = 1 t.Font = Enum.Font.GothamBold t.TextSize = 12 t.TextColor3 = C_DIM
	t.TextXAlignment = Enum.TextXAlignment.Left t.Text = text:upper() t.LayoutOrder = pg.n
end

-- Farm
local pF = page("Farm")
header(pF, "money")
toggle(pF, "Vacuum all money/scroll drops (map-wide)", "vacuum", applyVacuum)
toggle(pF, "Auto sell trinkets", "autoSell")
number(pF, "Sell when trinkets >=", "sellAt", 1, 1, 50)
toggle(pF, "Grab noble artifacts when they spawn", "nobleGrab")
toggle(pF, "Bank chests (+200 bounty each, auto-cleared)", "bankChests")
toggle(pF, "Also steal the artifact (+1000 bounty)", "artifactFarm")
button(pF, "Run one heist now", function() local a = cfg.avoidPlayers W.heist() end)
toggle(pF, "Open rescue wagons (trinkets ~$1-1.5k)", "wagonLoot")
toggle(pF, "Bandit mission farm (combat)", "bossFarm", function(v) if not v then W.farming = false W.hoverPos = nil end end)
number(pF, "Fight distance from bandit", "fightDistance", 1, 8, 120)
toggle(pF, "Auto mine ore (needs Vocare Pickaxe)", "autoMine")
header(pF, "safety")
toggle(pF, "Flee from dangerous players", "avoidPlayers")
number(pF, "Danger radius", "dangerRadius", 10, 40, 400)
number(pF, "Retreat below HP %", "fleeHp", 5, 10, 90)
toggle(pF, "Lay low while wanted (bounty)", "layLow")
toggle(pF, "Auto clear bounty (40s countdown)", "autoClearBounty")
toggle(pF, "Fight back against attackers", "fightBack")
header(pF, "progress")
toggle(pF, "Auto claim contracts", "autoContracts")
toggle(pF, "Auto buy skill tree (order in cfg.buyOrder)", "autoBuy")
number(pF, "Keep at least $", "keepMoney", 100, 0, 1e9)
toggle(pF, "Auto equip new spells into free slots", "autoEquipSpells")
button(pF, "Sell trinkets now", W.sellTrinkets)
button(pF, "Buy next item in cheapest affordable chapter", function()
	local bestCh, bestCost
	for ch in pairs(Directory.Tree) do
		local it = W.nextTreeItem(ch)
		if it and (it.CurrencyType or "Money") == "Money" and it.Cost <= money() and Shared_Tree.GetPlayerOwnsTree(lp, ch) and Shared_Tree.GetPlayerOwnsTierForTree(lp, ch) then
			if not bestCost or it.Cost < bestCost then bestCh, bestCost = ch, it.Cost end
		end
	end
	if bestCh then status("buying " .. W.nextTreeItem(bestCh).ItemName) W.buyTree(bestCh) else status("nothing affordable") end
end)

-- Travel
local pT = page("Travel")
header(pT, "settings")
number(pT, "Glide speed (no broom, safe <=60)", "travelSpeed", 5, 20, 65)
toggle(pT, "Ride broom while travelling (faster)", "broomTravel")
number(pT, "Broom flight speed (<=140 clean)", "broomSpeed", 5, 40, 140)
toggle(pT, "Travel/wait underground (out of view)", "underground")
number(pT, "Underground depth", "undergroundDepth", 1, 6, 60)
toggle(pT, "Blink burst at trip start (~230 studs/s)", "blinkTravel")
toggle(pT, "Use Apparate for long trips", "useApparate")
number(pT, "Apparate when farther than", "apparateMin", 50, 200, 5000)
number(pT, "Royal Apparate when farther than", "royalApparateMin", 50, 150, 5000)
header(pT, "go to")
local names = {}
for n in pairs(W.places) do names[#names + 1] = n end
table.sort(names)
for _, n in ipairs(names) do button(pT, n, function() status("travel: " .. n) W.travel(W.places[n], 3) status("arrived: " .. n) end) end
button(pT, "Nearest active bandit mission", function() local m = W.missionTarget() if m then W.travel(m:GetPivot().Position, 30) end end)
button(pT, "Nearest artifact loot", function() local t = W.artifactTargets() if t[1] then W.travel(mdlPos(t[1].Parent), 2) end end)
button(pT, "STOP travel / hover", W.stop)

-- Combat
local pC = page("Combat")
header(pC, "aim")
toggle(pC, "Silent aim (wand + spells)", "silentAim")
toggle(pC, "Target players", "aimPlayers")
toggle(pC, "Only wanted players (bounty/rogue)", "onlyWanted")
toggle(pC, "Target bandits / AI", "aimAI")
number(pC, "FOV radius px (0 = nearest)", "aimFov", 10, 0, 2000)
number(pC, "Max range", "aimRange", 10, 20, 400)
header(pC, "auto")
toggle(pC, "Auto fire wand at target", "autoFire")
toggle(pC, "Auto cast offensive spells", "autoSpells")
toggle(pC, "Auto heal (Episkio*)", "autoHeal")
toggle(pC, "Keep Vocaralea armor up (+25 HP)", "keepArmor")
number(pC, "Heal below HP %", "healAt", 5, 5, 95)

-- Player / Visual
local pP = page("Player")
toggle(pP, "Disable client anti-speed freeze", "noAntiSpeed", applyAntiSpeed)
number(pP, "WalkSpeed (0 = default, <=60 tested clean)", "walkSpeed", 1, 0, 60)
toggle(pP, "Noclip", "noclip")
toggle(pP, "Anti ragdoll (stay on your feet)", "antiRagdoll")
toggle(pP, "Infinite jump", "infJump")
number(pP, "Broom speed multiplier (1 = off)", "broomMult", 0.1, 1, 2)
toggle(pP, "Fullbright", "fullbright", applyFullbright)
header(pP, "esp")
toggle(pP, "ESP players (red = wanted, gold = noble)", "espPlayers")
toggle(pP, "ESP bandits / AI", "espAI")
toggle(pP, "ESP loot + ore veins", "espLoot")
header(pP, "server")
button(pP, "Rejoin", function() TS:TeleportToPlaceInstance(game.PlaceId, game.JobId, lp) end)
button(pP, "Server hop", function() TS:Teleport(game.PlaceId, lp) end)
button(pP, "Unload script", function() W.cleanup() end)

pages.Farm.b.BackgroundColor3 = C_ACC
pages.Farm.f.Visible = true

conn(UIS.InputBegan, function(i, gp)
	if gp then return end
	if i.KeyCode == Enum.KeyCode.RightShift then main.Visible = not main.Visible end
	-- F6: pause / resume every farm mode at once
	if i.KeyCode == Enum.KeyCode.F6 then
		local keys = { "bossFarm", "bankChests", "artifactFarm", "autoMine", "wagonLoot", "nobleGrab" }
		if W.paused then
			for k, v in pairs(W.paused) do cfg[k] = v end
			W.paused = nil
			status("farm resumed")
		else
			W.paused = {}
			for _, k in ipairs(keys) do W.paused[k] = cfg[k] cfg[k] = false end
			W.farming = false W.stop()
			status("farm PAUSED (F6)")
		end
		for _, f in ipairs(W.repaint or {}) do f() end
	end
	if i.KeyCode == Enum.KeyCode.F7 then W.stop() status("stopped (F7)") end
end)

-- live stats line
spawnLoop("stats", function()
	task.wait(1)
	local mins = (os.clock() - W.stats.startTime) / 60
	local n, v = trinkets()
	statusL.Text = string.format("%s\n$%d  |  +%d earned (%.0f/h)  |  bag %d ($%d)  |  %s",
		W.status or "idle", money(), W.stats.earned, W.stats.earned / math.max(mins, 0.1) * 60, n, v, W.loot[1] or (W.target and W.target.Name) or "-")
end)

-------------------------------------------------------------------------------
function W.cleanup()
	W.travelToken += 1
	W.hoverPos = nil
	for _, c in ipairs(W.conns) do pcall(function() c:Disconnect() end) end
	for _, t in pairs(W.threads) do pcall(task.cancel, t) end
	AntiSpeed.Update = origAntiSpeed
	RagdollClient.HumanoidRagdolled = origRagdolled
	pcall(function() Events.GetPlayerPositionFunc.OnClientInvoke = G.__WW_hooks.origInvoke end)
	W.silentPos = function() end
	cfg.fullbright = false applyFullbright()
	lp:SetAttribute("VIP_Collector", nil)
	pcall(function() espFolder:Destroy() end)
	pcall(function() gui:Destroy() end)
	if G.__WW == W then G.__WW = { silentPos = function() end } end
end

status("loaded")
return W

--[[ measured notes (2026-09-24)
 - money drops: MoneyDropEvent(amount,type) is capped by the server's pending pool (x3 claim test gave ~1x);
   VIP_Collector attr -> vacuum radius 9999 works (got drops 400+ and 2000+ studs away).
 - trinkets (Tool with SellValue) sell automatically when standing in a DialogConfig part (Police/Tavern/Royal Keep).
 - artifact mission chest gave Mandrake(1000)+Old Ring(350)+Artifact; artifact held 30s -> Diamond(1500). Bounty 150->750, Rogue.
 - Book_TreeEvent("Upgrade", chapter) works from anywhere on the map. Contracts claim is server-checked.
 - anti-TP: 300 stud jump rolled back + ragdoll; ~60/s glide fine, 75+/s rolled back. On broom (JetPacking) 120/s went clean.
 - Apparate: ToolListnerEvent Activate w/ spell -> char attr Apparating -> MapApparateEvent(Vector3 x,0,z) = map-wide TP (50hp, 60s cd).
 - combat: hit detection client side (Raycast.FireRay) + server calls GetPlayerPositionFunc for spell aim -> silent aim.
]]
