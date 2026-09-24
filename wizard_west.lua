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
	nobleGrab = true,       -- take noble artifacts (Crown/Baron/Phoenix/Cloak) when they spawn
	bankChests = true,      -- bank chests at artifact missions (trinkets, +200 bounty each -> auto cleared)
	artifactFarm = false,   -- also steal the artifact (+1000 bounty, Diamond after 30s held)
	heistClear = 150,       -- skip the heist while a rogue is this close to the loot
	heistNeedApparate = true, -- only grab the artifact when Apparate is ready for the escape
	wagonLoot = true,       -- open unlocked wagon loot while farming
	bossFarm = false,       -- bandit mission farm (combat)
	autoMine = false,       -- mine ore veins (needs Vocare Pickaxe)
	autoContracts = true,
	-- safety
	avoidPlayers = true,    -- flee from dangerous players
	dangerRadius = 130,     -- a dangerous player this close -> leave
	fleeHp = 45,            -- HP% at which farming stops and we retreat
	layLow = true,
	autoClearBounty = true, -- RogueEvent: bounty + rogue status wiped after a 40s countdown
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
	undergroundDepth = 14,
	fightDistance = 24,     -- bandit farm: stand on the ground this far from the target
	blinkTravel = true,     -- start trips with a burst of 95-stud dash-blinks (~230 studs/s)
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
			local ok, err = pcall(f)
			if not ok then W.log[#W.log + 1] = name .. ": " .. tostring(err) task.wait(1) end
		end
	end)
	W.threads[name] = t
	return t
end
local function status(s) W.status = s if W.statusLabel then W.statusLabel.Text = s end end
local function mdlPos(m)
	if not m then return nil end
	if m:IsA("BasePart") then return m.Position end
	if m:IsA("Attachment") then return m.WorldPosition end
	local ok, p = pcall(function() return m:GetPivot().Position end)
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
	if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
	task.wait(0.2)
	b.ToolListnerEvent:FireServer("Activate")
	for _ = 1, 15 do task.wait(0.1) if c:GetAttribute("JetPacking") then return true end end
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
		if os.clock() < (W.slowUntil or 0) then sp = math.min(sp, jet and 70 or 45) end
		-- ramp up instead of jumping straight to full speed
		W.flySpeed = math.min(sp, (W.flySpeed or cfg.travelSpeed) + 80 * dt)
		sp = W.flySpeed
		if (rr.Position - lastSet).Magnitude > 35 then -- server pulled us back
			rollbacks += 1
			W.stats.rollbacks = (W.stats.rollbacks or 0) + 1
			cur = rr.Position
			speed = math.max(40, speed * 0.8)
			if rollbacks >= 2 then W.slowUntil = os.clock() + 30 end
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
		local finalApproach = opts.descend ~= false and remain < math.max(60, (cur.Y - goal.Y) * 1.6)
		if finalApproach then want = goal.Y end
		local dy = want - cur.Y
		local vmax = (dy > 0 and vUp or ((finalApproach or not jet) and 60 or vDown)) * dt
		local ny = cur.Y + math.clamp(dy, -vmax, vmax)
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
	equip(w)
	sp:SetAttribute("SubEquipped", true)
	w.ToolListnerEvent:FireServer("Activate", hrp().Position + hrp().CFrame.LookVector * 20, hrp().Position, sp)
	local got = false
	for _ = 1, 30 do task.wait(0.1) if c:GetAttribute("Apparating") then got = true break end end
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
	local ok, res = pcall(W._travel, goal, above, exact)
	W.inTrip = false
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
		r = hrp()
		dist = (target - r.Position).Magnitude
	end
	-- a blink burst covers the first ~600 studs in ~3s, the broom does the rest
	if cfg.blinkTravel and dist > 200 and not (char() and char():GetAttribute("JetPacking")) then
		W.blinkBurst(target, nil, token)
		if token ~= W.travelToken then return false end
		r = hrp()
		dist = (Vector3.new(target.X, 0, target.Z) - Vector3.new(r.Position.X, 0, r.Position.Z)).Magnitude
	end
	local speed = cfg.travelSpeed
	if cfg.broomTravel and not cfg.underground and dist > 40 and W.broomOn() then speed = cfg.broomSpeed end
	if cfg.underground then
		local ok = W.glide(W.under(hrp().Position), speed, token)
		ok = ok and W.glide(W.under(target), speed, token)
		if W.undergroundArrive then return ok end
		return ok and W.glide(target, speed, token)
	end
	-- one smooth leg: constant horizontal speed, cruise over the highest ground ahead, land at the end
	local done = W.fly(target, speed, token)
	if done and cfg.dismountOnArrive then W.broomOff() end
	return done
end
-- a spot under the terrain at (x,z)
function W.under(p)
	local ty = terrainY(p.X, p.Z) or p.Y
	return Vector3.new(p.X, ty - cfg.undergroundDepth, p.Z)
end
function W.stop() W.travelToken += 1 W.hoverPos = nil end

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
		pcall(appendfile, "ww_loot.txt", string.format("%s\t%s\t%d\n", kind, t.Name, t:GetAttribute("SellValue")))
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
		local ok = not (i == 3 and not lp:GetAttribute("Noble")) and not (i == 1 and W.iAmWanted())
		if ok and #W.threats(150, p) == 0 then
			local d = (p - r.Position).Magnitude
			if not bd or d < bd then best, bd = p, d end
		end
	end
	return best
end

function W.sellTrinkets()
	local n, val = trinkets()
	if n == 0 then return true end
	local v = sellCfgInRange()
	if v and W.trySellRemote(v) then return true end
	local p = W.pickSeller()
	if not p then status("sell: every seller has company") return false end
	status(string.format("selling %d trinkets ($%d)", n, val))
	-- fly at the seller part itself (glides pass through walls); fire the moment we're in range
	local done, sold = false, false
	task.spawn(function() W.travel(p, 0, true) done = true end)
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
	if holder:IsA("Model") then cf, size = holder:GetBoundingBox() else cf, size = holder.CFrame, holder.Size end
	-- the prompt needs line of sight: stand on the ground beside the loot, try each side
	local sides = { cf.RightVector * (size.X / 2 + 3), -cf.RightVector * (size.X / 2 + 3), cf.LookVector * (size.Z / 2 + 3), -cf.LookVector * (size.Z / 2 + 3) }
	local first = true
	for _, off in ipairs(sides) do
		local spot = cf.Position + off
		local gy = groundY(spot.X, spot.Z)
		if not gy or gy > cf.Position.Y + 6 then gy = cf.Position.Y - size.Y / 2 end -- under a roof: use the loot's floor
		local stand = Vector3.new(spot.X, gy + 3, spot.Z)
		if first then W.travel(stand, 0, true) first = false else W.glide(stand, 30) end
		if not p.Parent then return false end
		local r = hrp()
		W.hoverPos = stand
		if r then r.CFrame = CFrame.new(stand, Vector3.new(cf.Position.X, stand.Y, cf.Position.Z)) end
		task.wait(0.3)
		fireproximityprompt(p)
		local t0 = os.clock()
		repeat task.wait(0.2) until openedByMe(p) or not p.Parent or os.clock() - t0 > 1.2 + p.HoldDuration
		if openedByMe(p) or not p.Parent then
			W.hoverPos = nil
			W.lastOpened, W.lastOpenT = lootName(p), os.clock()
			W.stats.opened = (W.stats.opened or 0) + 1
			return true
		end
	end
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
	while a.Parent and os.clock() - t0 < 45 and alive() do
		status("holding artifact " .. tostring(a:GetAttribute("TimeLeft")) .. "s")
		if #W.threats(cfg.dangerRadius + 60) > 0 then
			W.hoverPos = nil
			local spot = W.safeSpot(400, 1600)
			if not W.apparate(spot) then W.travel(spot, 3) end
		elseif not W.hoverPos then
			local r = hrp()
			local gy = groundY(r.Position.X, r.Position.Z)
			W.hoverPos = Vector3.new(r.Position.X, (gy or r.Position.Y) + 3, r.Position.Z)
		end
		task.wait(0.5)
	end
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
function W.claimContracts()
	for _, c in ipairs(Concept.Contracts:GetChildren()) do
		if not c:GetAttribute("Completed") and (c:GetAttribute("Value") or 0) >= (c:GetAttribute("Goal") or math.huge) then
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
local UTIL_PRIO = { ["Royal Apparate"] = 100, Apparate = 95, Lasso = 80, ["Open Sesame"] = 75, Stealio = 70, ["Invisio Maxima"] = 65, Invisio = 60, Wingardius = 55, Vocifero = 20, Revelio = 30, Repairo = 5, Lumo = 1 }
-- measured on bandits: Bombarda one-shots 40hp, Ignisio 30 dmg cone (30 studs), Expulso 0 dmg (disarm only)
local SPELL_ADJ = { Bombarda = 8, Ignisio = 6, Ignisium = 8, Expulso = -15, Aquarcia = -5, Haste = -12 }
local function statSum(it)
	local st = it:FindFirstChild("ItemStats")
	local n = 0
	if st then for _, v in pairs(st:GetAttributes()) do if type(v) == "number" then n += v end end end
	return n
end
function W.desiredLoadout()
	local want = {}
	local byCat = {}
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
				if isHealName and isHealName(it.Name) then score += 25 end -- always carry a heal
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
function W.autoEquipSpells()
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
		if W.attackers and W.attackers[pl] and os.clock() < W.attackers[pl] then return true end -- always fight back
		if not cfg.aimPlayers then return false end
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

-- fire through the game's own tool path (keeps ammo/animations/cooldowns legit)
function W.attackStep()
	local c = char()
	if not c or c:GetAttribute("CastingSpell") then return end
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
	local best, bd
	for _, m in ipairs(workspace.Missions:GetChildren()) do
		if m:IsA("Model") and not m:GetAttribute("Completed") and (m:GetAttribute("EnemiesLeft") or 0) > 0 then
			-- clearing a camp unlocks its 2 rescue wagons: prefer the one that's done soonest
			-- (flight ~120 studs/s, ~4s per bandit), skip camps with hostile players around
			local mp = m:GetPivot().Position
			local d = (mp - r.Position).Magnitude / 120 + m:GetAttribute("EnemiesLeft") * 4
			if m.Name == "CowboyTest" then d -= 12 end -- Imperial camp: its wagons are the red chests
			if #W.threats(200, mp) == 0 and (not bd or d < bd) then best, bd = m, d end
		end
	end
	return best
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
local function hostilePl(pl, wanted)
	local m = pl.Character
	return wanted or pl:GetAttribute("Rogue") or (m and m:GetAttribute("Rogued")) or (pl:GetAttribute("Bounty") or 0) > 0
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
		if t.d < 60 or approaching or attacker then out[#out + 1] = t end
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
		if os.clock() < untilT and m and m.PrimaryPart and r then
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
		-- who hit us? nearest hostile player unless a bandit is right next to us
		local near = W.threats(160)
		local aiClose = false
		for _, hh in ipairs(CS:GetTagged("ActiveHumanoid")) do
			local m = hh.Parent
			if m and m:GetAttribute("IsAI") and hh.Health > 0 and hrp() and (m:GetPivot().Position - hrp().Position).Magnitude < 60 then aiClose = true break end
		end
		if #near > 0 and (not aiClose or near[1].d < 50) then
			local pl = Players:GetPlayerFromCharacter(near[1].m)
			if pl then W.attackers[pl] = os.clock() + 25 end
			W.dangerUntil = os.clock() + 20
		end
	end
	lastHp = h.Health
	if cfg.avoidPlayers and #(W.heistActive and W.threats(45) or W.realThreats()) > 0 then W.dangerUntil = math.max(W.dangerUntil, os.clock() + 8) end
	local lowHp = h.Health / h.MaxHealth * 100 < cfg.fleeHp
	local danger = cfg.avoidPlayers and (os.clock() < W.dangerUntil or lowHp)
	if danger and not W.fleeing and (cfg.bossFarm or cfg.artifactFarm or cfg.bankChests or cfg.autoMine) then
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
		if d >= (minFrom or 0) and d <= (maxFrom or math.huge) then
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
		if #W.threats(400, pos) > 0 then return end
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
	local r, h = hrp(), hum()
	if not (r and h) then W.fleeing = false return end
	local th = W.realThreats()
	local danger = (th[1] and th[1].p) or r.Position
	local dest = W.productiveSpot(danger, 800)
	status("FLEE: " .. reason .. (dest and " -> relocating" or ""))
	local sp = apparateSpell()
	local moved = false
	if cfg.useApparate and sp and h.Health > (sp:GetAttribute("HealthCost") or 50) + 15 and workspace:GetServerTimeNow() >= (sp:GetAttribute("CooldownExpire") or 0) then
		moved = W.apparate(dest or W.safeSpot(900, 3500), true)
		if moved then W.stats.relocations = (W.stats.relocations or 0) + 1 end
	end
	if not moved then
		local away = Vector3.new(r.Position.X - danger.X, 0, r.Position.Z - danger.Z)
		if away.Magnitude < 1 then away = Vector3.new(1, 0, 0) end
		W.blinkBurst(r.Position + away.Unit * 700, nil)
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
		if pct >= cfg.fleeHp + 20 or #W.realThreats() > 0 then break end
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

function W.heist()
	local targets = W.artifactTargets()
	if #targets == 0 then return false end
	table.sort(targets, function(a, b) return (isArtifactPrompt(a) and 1 or 0) < (isArtifactPrompt(b) and 1 or 0) end)
	local site = mdlPos(targets[1].Parent)
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
		if #camp2 > 0 then status("heist: " .. camp2[1].pl.Name .. " showed up, abort") break end
		if isArtifactPrompt(p) then
			if not apparateReady() and cfg.heistNeedApparate then
				status("heist: waiting for Apparate before the artifact")
				local sp = apparateSpell()
				local t0 = os.clock()
				while not apparateReady() and os.clock() - t0 < 70 and alive() do task.wait(0.5) end
			end
			status("heist: artifact")
			W.openPrompt(p)
			task.wait(0.6)
			-- escape far away right away
			local spot = W.safeSpot(1000, 3200)
			status("heist: escaping")
			if not W.apparate(spot) then W.travel(spot, 3) end
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
					pcall(appendfile, "ww_noble.txt", string.format("[%s] spawn %s (%s)\n", os.date("%H:%M:%S"), m and m:GetFullName() or "?", d.ObjectText))
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
	status("noble artifact: " .. m.Name)
	W.noApparate = true
	W.travel(pos + Vector3.new(0, 1, 0), 0, true)
	W.noApparate = false
	if not p.Parent then return false end
	local before = {}
	for _, t in ipairs(lp.Backpack:GetChildren()) do before[t] = true end
	W.hoverPos = pos + Vector3.new(0, 1.5, 0)
	fireproximityprompt(p)
	task.wait(p.HoldDuration + 2)
	W.hoverPos = nil
	local got = {}
	for _, t in ipairs(lp.Backpack:GetChildren()) do if not before[t] then got[#got + 1] = t.Name end end
	local e = string.format("[%s] grabbed %s: got %s | Noble=%s Bounty=%s Illegal=%s", os.date("%H:%M:%S"), m.Name, table.concat(got, ","), tostring(lp:GetAttribute("Noble")), tostring(lp:GetAttribute("Bounty")), tostring(lp:GetAttribute("HasIllegalArtifact")))
	W.log[#W.log + 1] = e
	pcall(appendfile, "ww_noble.txt", e .. "\n")
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
		W.deaths[#W.deaths + 1] = e
		pcall(appendfile, "ww_deaths.txt", e .. "\n")
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
spawnLoop("farm", function()
	task.wait(0.3)
	if not alive() then W.hoverPos = nil task.wait(1) return end
	if cfg.autoContracts then W.claimContracts() end
	if cfg.autoBuy then W.autoBuyStep() end
	if cfg.autoEquipSpells and os.clock() - (W.lastEquip or 0) > 15 then W.lastEquip = os.clock() W.autoEquipSpells() end

	local farmingAny = cfg.artifactFarm or cfg.bankChests or cfg.bossFarm or cfg.autoMine or cfg.nobleGrab
	if farmingAny and cfg.avoidPlayers then
		local h = hum()
		if os.clock() < W.dangerUntil then W.flee("hostile player") return end
		if h.Health / h.MaxHealth * 100 < cfg.fleeHp then W.flee("low hp") return end
	end
	if lp.Backpack:FindFirstChild("Artifact") or (char() and char():FindFirstChild("Artifact")) then waitArtifact() return end
	-- wanted: sell loot if the seller is clear, otherwise hide until the bounty clears
	if cfg.nobleGrab then
		for _, p in ipairs(W.nobleTargets()) do if W.grabNoble(p) then return end end
	end
	if (cfg.bankChests or cfg.artifactFarm) and W.heist() then return end
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
		local tick = lp:GetAttribute("RogueTurnOffTick")
		status(string.format("wanted ($%d) - laying low%s", lp:GetAttribute("Bounty") or 0, tick and (", clears in " .. tick .. "s") or ""))
		task.wait(1)
		return
	end
	-- never leave a fight to sell: only when no bandit is in range
	if cfg.autoSell and trinkets() >= cfg.sellAt and farmingAny and not W.findTarget(260) then
		W.sellTrinkets() return
	end
	if cfg.wagonLoot and farmingAny then
		local r = hrp()
		local best, bd
		for _, p in ipairs(W.wagonTargets()) do
			local pp = mdlPos(p.Parent)
			if pp and #W.threats(150, pp) == 0 then
				-- red chests are worth a detour: rank by distance / 3
				local d = (pp - r.Position).Magnitude / (chestKind(p) == "red" and 3 or 1)
				if not bd or d < bd then best, bd = p, d end
			end
		end
		if best then status(string.format("%s (%dm)", lootName(best), (mdlPos(best.Parent) - r.Position).Magnitude)) W.openPrompt(best) return end
	end
	if cfg.bossFarm then
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
					W.hoverPos = want
				end
			else
				status("waiting for bandits")
				local wx, wz = mp.X + 70, mp.Z
				local wait = cfg.underground and W.under(mp) or Vector3.new(wx, (groundY(wx, wz) or mp.Y) + 3, wz)
				if not W.hoverPos or (W.hoverPos - wait).Magnitude > 5 then
					W.hoverPos = nil
					W.glide(wait, cfg.travelSpeed)
					W.hoverPos = wait
				end
			end
			return
		end
		W.farming = false
	end
	if cfg.autoMine then W.mineOnce() return end
	status("idle")
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
	W.armorStep()
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
