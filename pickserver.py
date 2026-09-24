# pick a server to hop to: not the current one, not recently fled, prefer ping < 150 then fewest players
import json, sys, urllib.request, os
cur = sys.argv[1] if len(sys.argv) > 1 else ""
visited_file = r"C:\Users\Seifb\AppData\Local\Potassium\workspace\ww_visited.txt"
visited = set()
if os.path.exists(visited_file):
    visited = set(l.strip() for l in open(visited_file) if l.strip())
url = "https://games.roblox.com/v1/games/17357719939/servers/Public?sortOrder=Asc&limit=100"
try:
    data = json.load(urllib.request.urlopen(url, timeout=10)).get("data", [])
except Exception:
    data = []
cands = [s for s in data if s["id"] != cur and s["id"] not in visited and s["playing"] < s["maxPlayers"] - 1]
if not cands:
    cands = [s for s in data if s["id"] != cur and s["playing"] < s["maxPlayers"] - 1]
cands.sort(key=lambda s: ((s.get("ping") or 999) > 150, s["playing"]))
if cands:
    print(cands[0]["id"])
