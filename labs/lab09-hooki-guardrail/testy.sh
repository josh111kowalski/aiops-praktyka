#!/usr/bin/env bash
# Sprawdza hook bez modelu: każdą komendę z przypadki.txt podaje hookowi tak, jak robi to Claude Code.
# Użycie: ./testy.sh [ścieżka do hooka]   (domyślnie .claude/hooks/blokada-kubectl.sh)
hook=${1:-.claude/hooks/blokada-kubectl.sh}
ok=0; zle=0
while IFS='|' read -r oczekiwane cmd; do
  [[ -z $oczekiwane || $oczekiwane == \#* ]] && continue
  jq -n --arg c "$cmd" '{hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}' | "$hook" >/dev/null 2>&1
  [[ $? -eq 2 ]] && wynik=BLOK || wynik=OK
  if [[ $wynik == "$oczekiwane" ]]; then ok=$((ok+1)); echo "  ok    $wynik  $cmd"
  else zle=$((zle+1)); echo "  ŹLE   $wynik (miało być $oczekiwane)  $cmd"; fi
done < "${PRZYPADKI:-przypadki.txt}"
echo "zgodne: $ok, niezgodne: $zle"
[[ $zle -eq 0 ]]
