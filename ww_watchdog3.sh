#!/bin/bash
# Wizard West watchdog v3: restarts Roblox + reloads the farm when the client is disconnected,
# frozen, or the script asks for a server hop (HOP -> join a different, specific server).
# stop it by creating workspace/ww_watchdog.stop
WS=/c/Users/Seifb/AppData/Local/Potassium/workspace
SP=/c/Users/Seifb/AppData/Local/Temp/claude/C--Users-Seifb/97971cfd-a46f-401a-8e18-645b0a73c3f6/scratchpad
LOG=$WS/ww_watchdog.log
now() { date +%s; }
boot() {
  echo "$(date '+%F %T') boot" >> $LOG
  bash $WS/_tools/bridge_send.sh $WS/ww_boot.lua >> $LOG 2>&1
  echo >> $LOG
}
restart() {
  local uri="roblox://experiences/start?placeId=17357719939"
  if [ -n "$2" ]; then uri="$uri&gameInstanceId=$2"; fi
  echo "$(date '+%F %T') restart: $1 -> ${2:-any server}" >> $LOG
  powershell.exe -NoProfile -Command "Get-Process RobloxPlayerBeta -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 3; Start-Process '$uri'" >> $LOG 2>&1
  local t0=$(now)
  for i in $(seq 1 90); do
    sleep 2
    local st=$(stat -c %Y $WS/bridge/status.txt 2>/dev/null || echo 0)
    if [ $(( $(now) - t0 )) -gt 15 ] && [ $(( $(now) - st )) -lt 6 ]; then break; fi
  done
  sleep 8
  boot
}
echo "$(date '+%F %T') watchdog v3 start" >> $LOG
while true; do
  sleep 15
  [ -f $WS/ww_watchdog.stop ] && { echo "$(date '+%F %T') stop file" >> $LOG; exit 0; }
  hb=$(cat $WS/ww_hb.txt 2>/dev/null)
  t=$(echo "$hb" | cut -d' ' -f1); flag=$(echo "$hb" | cut -d' ' -f2); job=$(echo "$hb" | cut -d' ' -f4)
  age=$(( $(now) - ${t:-0} ))
  st=$(stat -c %Y $WS/bridge/status.txt 2>/dev/null || echo 0)
  sage=$(( $(now) - st ))
  if [ "$flag" = "HOP" ]; then
    echo "$job" >> $WS/ww_visited.txt
    target=$(python $SP/pickserver.py "$job" 2>/dev/null)
    restart "HOP: $hb" "$target"
  elif [ "$flag" = "DC" ]; then restart "DC: $hb"
  elif [ $age -gt 120 ] && [ $sage -gt 60 ]; then restart "frozen: hb ${age}s, bridge ${sage}s"
  elif [ $age -gt 240 ] && [ $sage -lt 10 ]; then boot
  fi
done
