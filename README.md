# Wizard West tool

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Raffir2/wizard-west/main/wizard_west.lua"))()
```

**RightShift** toggles the menu. **F6** pauses/resumes every farm mode. **F7** stops the current trip.
Settings changed in the menu are saved to `ww_config.json` in the executor workspace.

## What the farm does (priority order)
1. Holds a stolen artifact for 30 s until it turns into a Diamond. Escapes early on the radar, and cloaks if it can.
2. Grabs noble artifacts: Baron = Royal Apparate (12 s map teleport), Cloak = invisibility, Crown, Phoenix. The castle ones are reached by walking in along a navmesh path. When someone else holds the Baron, the **Baron hunt** takes it off them (see below).
3. Bank heist, but only when the artifact can be taken too. The bounty clear starts right after the first chest.
4. Clears the bounty (40 s countdown). Meanwhile it holds fire (every kill while wanted adds +25) and waits next to the next camp.
5. Sells trinkets when the bag is worth ≥ $2500 or a seller is close anyway.
6. Mines gems in the Crystal Cave when the trip beats the camps (value per second, see below).
7. Opens rescue wagons, ranked by value per second. Red (Imperial) chests are a flat $1500, brown ones average $659.
8. Bandit camps: sticks to one camp until it's cleared, uses silent aim plus spells, and vacuums money drops map-wide.
9. Contracts: claims them automatically and steers toward open tasks (a fire spell joins the loadout for "HitFire", rocks get mined for "MineRocks"). The Common contract pays ~$975 on average every 5 minutes.

## Mining
- **Gem Veins:** 4 of them, in the Crystal Cave (SpiderCave pit). They drop a Ruby ($450) or a Diamond ($1500), about $710 on average.
- **Coal Veins:** 6 of them, outside. Coal is only $100, so the farm mines it only when it's close or a contract wants rocks.
- **Respawn:** a vein comes back ~83 s after it breaks. Other players mine too.
- **Getting in:** the pit is covered by webs and rock, so the only way in is the open ravine to the north (896, 49, -764). The farm descends there vertically, then walks with `Humanoid:MoveTo`, because gliding clips the tunnel floor and gets rolled back. It leaves on foot or by Apparate.
- **Mining:** the pickaxe only lands from the crystal ledge next to a vein, not from the cave floor 19 studs below. The farm pins itself on the ledge while swinging and clears the spiders first.
- **Result:** in 10-minute farm + mining rounds, 112-130k/h with ~10 gems.

## Baron hunt (PvP, Farm tab, on by default)
- **What the game does:** a player at 0 HP loses the noble title immediately (there's no knockout-then-finish step). The artifact is back at its spawn about 45 s later.
- **Starts only when everything lines up:**
  - the holder is visible on the radar
  - they're not cloaked, not in a safe zone and not in the Royal Keep
  - nobody else is within 200 studs of them
  - our HP is at least 90%
  - Aquarcia, Electrificus and Inlisus are ready
  - we're not wanted
  - there's at most one attempt every 2 minutes
- **Approach:** by broom to 45 studs beside the holder, the last stretch at ≤ 90/s. It casts through the wand like a player, with silent aim on that one target.
- **Combo:** Aquarcia (a 3 s trap, no dodge or Apparate) → Electrificus 88 → Inlisus 79 → Bombarda / Matrificus. That's about 190 damage in ~3.5 s.
- **After a kill:** the bounty clear starts, the farm waits at the castle, and the noble grab takes the respawned Baron.
- **While someone else holds the Baron,** Aquarcia joins the loadout. Every attempt is logged to `ww_hunt.txt`.

## Auto defense (Combat tab, on by default, also while farming)
- **Projectiles:** every bolt or spell projectile is broadcast (`ProjectileEvent`: caster, speed, start, aim point). A player's projectile whose line passes within 10 studs of us gets answered:
  - with **Protego** when it lands in ≥ 0.8 s and Protego is ready (it protects for ~4 s, cooldown 23 s)
  - otherwise with a **block** held until the impact (blocking deflects projectiles)
- **Instant spells** (Electrificus, Inlisus have no projectile): a dangerous player within 90 studs starting a cast while facing us gets Protego or a block.
- **On the broom** nothing can be cast, so the defense only works on foot or hovering. The combat loop pauses during a block.
- **Loadout:** Protego takes Vocaralea's Wild Magic slot while this is on.

## Loadout
- **Scoring:** spells are ranked by damage per second from the wiki. Every value we could check in game matched.
  - Electrificus: 88 instant, 8 s cooldown.
  - Matrificus: 35 multi-target, 3 s.
  - Inlisus: 79 area, 8 s.
  - Bombarda: 70 area, 16 s.
- **Automatic changes:**
  - a fire spell while a "HitFire" contract is open
  - Aquarcia while hunting the Baron
  - Protego with auto defense
- **Cooldown rule:** the server ignores unequipping an item whose cooldown is running, so those swaps wait for the next pass.
- **Auto buy** saves for Oceanus Vortico only; a longer buy list would spend the savings on the next cosmetic.

Safety:
- Radar of every player (MapEvent).
- Flees (Apparate relocation) from rogues within 90 studs, from players heading straight at us, and from anyone who hit us.
- Remembers hunters for 10 minutes.
- A land mask from the minimap keeps escapes off the void.
- Fight-back only targets legal players (rogues / bounty), so it never makes us rogue.

## Menu tabs
- **Farm:** modes, selling, preferred noble, safety radii, cloak, Baron protection, auto hop.
- **Travel:** broom speed/acceleration, Apparate thresholds, go-to buttons.
- **Combat:** silent aim, auto fire/spells, heal, armor, auto defense.
- **Player:** anti-ragdoll, noclip, infinite jump, walk speed, fullbright, server hop.
  - ESP colors for players: red = wanted, gold = noble, **purple = the current silent-aim target** (bandits too).
  - ESP colors for everything else: bandits orange, loot green, ore veins turquoise.
- **Info:** live dashboard with a "copy" button. It shows:
  - 10-min income, flees and deaths, noble, hunters
  - loot by chest type, mined veins
  - defense (incoming / blocks / Protegos), Baron hunt status
  - income per weather, recent trips, flee triggers, slow steps, last death

## Unattended running (PC side)
In-game teleports kill the executor hook (Potassium's `queue_on_teleport` is a stub), so reconnects and server hops restart the Roblox process instead.

- The script writes `ww_hb.txt` every 5 s: `time flag money jobId status`. The flag is `OK`, `DC` (error prompt shown) or `HOP` (hostile server: ≥ 8 flees or 2 deaths in 10 min and < 70k/h).
- `ww_watchdog3.sh` (Git Bash, runs in the background) restarts Roblox when the flag is `DC`/`HOP` or the heartbeat is frozen. For a HOP, `pickserver.py` picks a server from the public server list: not the current one, not recently fled, ping < 150, then fewest players. The watchdog joins it via `roblox://experiences/start?placeId=17357719939&gameInstanceId=<id>`, waits for the bridge (autoexec), then runs `ww_boot.lua`.
- Stop the watchdog by creating `ww_watchdog.stop` in the workspace. Its log is `ww_watchdog.log`.

## Log files (executor workspace)
- `ww_deaths.txt`: deaths with killers, the last 8 s of HP/position/status, farm hangs and hop requests.
- `ww_loot.txt`: chest kind, item and value.
- `ww_noble.txt`: noble artifact spawns and grabs.
- `ww_hunt.txt`: Baron hunt attempts and results.
- `ww_weather.txt`: each weather change, with money and the mission list.
  - Weather: `Lighting.CurrentWeather` is Daybreak, Nightfall or Rainfall, every ~16 min for 5 min.
  - Measured: Daybreak ~84-119k/h, Nightfall ~61k/h, none ~70-80k/h.
- `ww_chests.txt`: each chest type's loot table, once per type. Every chest opening broadcasts its full table (`TrinketChestOpenEvent`).

## Dead ends (verified, so nobody retries them)
- `MoneyDropEvent` claims are checked against the server's per-player ledger (`Claimable<Type>` attributes on the player). A wrong type grants nothing, an item amount > 1 burns the entitlement and grants nothing, and money is capped at the pending amount.
- Other flight abilities are no faster: the client caps every flight model at 72.
- Bought outfits and hats have no stats. The stats (Health/Damage +5) are random rolls on dropped items.
- Gacha gives wands only. A wand sells for 2 Essence of its rarity; a cursed one (~0.5%) sells for $10k.
- Kill-milestone outfits and the Founder chapter: the outfits are cosmetic, and the Founder chapter is locked.
- Trading needs a second player and moves only items.
- Chest loot is rolled by the server on open.

## Measured limits
- Broom: 120/s is clean; 135 gets rollbacks; 160 knocks you off.
- Without the broom: ~55/s.
- Blink bursts before a broom leg cause rollbacks.
- Selling works only within ~20 studs of the seller part.
- The noble title is lost on death, or when someone else takes that artifact.
- The bounty clear countdown pauses while you're cloaked.
- `RequestStreamAroundAsync` can hang for minutes; the script always runs it with a hard timeout.
- Spells: casting `InplaceCast` spells freezes the character, so the combat loop pauses while the farm walks a path.
- Apparate at very low HP fails and leaves you at 10 HP (wiki); the script keeps the cost margin.
