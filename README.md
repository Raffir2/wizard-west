# Wizard West tool

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Raffir2/wizard-west/main/wizard_west.lua"))()
```

**RightShift** toggles the menu. **F6** pauses/resumes every farm mode. **F7** stops the current trip.
Settings changed in the menu are saved to `ww_config.json` in the executor workspace.

## What the farm does (priority order)
1. Holds a stolen artifact for 30 s until it turns into a Diamond. Escapes early on the radar, and cloaks if it can.
2. Grabs noble artifacts: Baron = Royal Apparate (12 s map teleport), Cloak = invisibility, Crown, Phoenix. The castle ones are reached by walking in along a navmesh path.
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

Safety:
- Radar of every player (MapEvent).
- Flees (Apparate relocation) from rogues within 90 studs, from players heading straight at us, and from anyone who hit us.
- Remembers hunters for 10 minutes.
- A land mask from the minimap keeps escapes off the void.
- Fight-back only targets legal players (rogues / bounty), so it never makes us rogue.

## Menu tabs
- **Farm:** modes, selling, preferred noble, safety radii, cloak, Baron protection, auto hop.
- **Travel:** broom speed/acceleration, Apparate thresholds, go-to buttons.
- **Combat:** silent aim, auto fire/spells, heal, armor.
- **Player:** anti-ragdoll, walk speed, ESP, server hop.
- **Info:** live dashboard: 10-min income, flees/deaths, noble, hunters, loot by chest type, recent trips, flee triggers, slow steps, last death. There's a "copy" button.

## Unattended running (PC side)
In-game teleports kill the executor hook (Potassium's `queue_on_teleport` is a stub), so reconnects and server hops restart the Roblox process instead.

- The script writes `ww_hb.txt` every 5 s: `time flag money jobId status`. The flag is `OK`, `DC` (error prompt shown) or `HOP` (hostile server: ≥ 8 flees or 2 deaths in 10 min and < 70k/h).
- `ww_watchdog3.sh` (Git Bash, runs in the background) restarts Roblox when the flag is `DC`/`HOP` or the heartbeat is frozen. For a HOP, `pickserver.py` picks a server from the public server list: not the current one, not recently fled, ping < 150, then fewest players. The watchdog joins it via `roblox://experiences/start?placeId=17357719939&gameInstanceId=<id>`, waits for the bridge (autoexec), then runs `ww_boot.lua`.
- Stop the watchdog by creating `ww_watchdog.stop` in the workspace. Its log is `ww_watchdog.log`.

## Log files (executor workspace)
- `ww_deaths.txt`: deaths with killers, the last 8 s of HP/position/status, farm hangs and hop requests.
- `ww_loot.txt`: chest kind, item and value.
- `ww_noble.txt`: noble artifact spawns and grabs.

## Dead ends (verified, so nobody retries them)
- `MoneyDropEvent` claims are checked against the server's per-player ledger (`Claimable<Type>` attributes on the player). A wrong type grants nothing, an item amount > 1 burns the entitlement and grants nothing, and money is capped at the pending amount.
- Other flight abilities are no faster: the client caps every flight model at 72.
- Bought outfits and hats have no stats. The stats (Health/Damage +5) are random rolls on dropped items.
- Gacha gives wands only. A wand sells for 2 Essence of its rarity; a cursed one (~0.5%) sells for $10k.

## Measured limits
- Broom: 120/s is clean; 135 gets rollbacks; 160 knocks you off.
- Without the broom: ~55/s.
- Blink bursts before a broom leg cause rollbacks.
- Selling works only within ~20 studs of the seller part.
- The noble title is lost on death, or when someone else takes that artifact.
- The bounty clear countdown pauses while you're cloaked.
- `RequestStreamAroundAsync` can hang for minutes; the script always runs it with a hard timeout.
