#!/usr/bin/env bash
# Hook PreToolUse (Bash): agent może zmergować PR tylko wtedy, gdy ten skrypt się zgodzi.
# Warunki: świeży przegląd z werdyktem MERGE, czysty diff (reguły bez modelu), zielone CI.
# Kod 2 = komenda się nie wykona, a stderr wraca do Claude jako powód.

cmd=$(jq -r '.tool_input.command // empty' | tr -d '\r')   # tr: jq.exe na Windowsie kończy linie CRLF

# Merge przez API omija warunki, więc nie przechodzi wcale
if grep -qE 'gh api' <<<"$cmd" && grep -qE '/merge([^a-z]|$)' <<<"$cmd"; then
  echo "Bramka merge: merge tylko przez gh pr merge <nr>, nie przez gh api." >&2
  exit 2
fi
grep -qE '(^|[;&|[:space:]])gh pr merge' <<<"$cmd" || exit 0

# Numer PR-a: pierwszy argument po "gh pr merge", który jest liczbą albo linkiem do PR-a
nr=$(sed -E 's/.*gh pr merge//' <<<"$cmd" | tr ' ' '\n' | sed -E 's#.*/pull/##' | grep -m1 -E '^[0-9]+$')
if [ -z "$nr" ]; then
  echo "Bramka merge: podaj numer PR-a wprost (gh pr merge <nr> --squash)." >&2
  exit 2
fi

powody=""
nie() { powody+="- $1"$'\n'; }

# 1. Przegląd z werdyktem MERGE, nowszy niż ostatni commit PR-a
plik="${CLAUDE_PROJECT_DIR:-.}/przeglady/pr-$nr.md"
if [ ! -f "$plik" ]; then
  nie "brak przeglądu przeglady/pr-$nr.md (uruchom /przeglad-pr $nr)"
else
  # werdykt w tej samej linii co słowo „Werdykt” albo w linii niżej (nagłówek + wartość)
  werdykt=$(grep -iA2 -m1 'werdykt' "$plik" | tr '\n' ' ')
  grep -iqE 'werdykt[^a-z]*merge([^a-z]|$)' <<<"$werdykt" || nie "werdykt w przeglady/pr-$nr.md to nie MERGE"
  ostatni=$(gh pr view "$nr" --json commits -q '.commits[-1].committedDate' 2>/dev/null)
  przeglad=$(date -u -r "$plik" +%Y-%m-%dT%H:%M:%SZ)
  if [ -z "$ostatni" ]; then
    nie "nie udało się odczytać PR #$nr"
  elif [[ ! "$przeglad" > "$ostatni" ]]; then
    nie "przegląd ($przeglad) jest starszy niż ostatni commit PR-a ($ostatni)"
  fi
fi

# 2. Diff sprawdzony regułami, bez modelu: werdykt mógł być wynikiem manipulacji
dodane=$(gh pr diff "$nr" 2>/dev/null | grep -E '^\+[^+]')
# odwołania do sekretów (secretKeyRef, ${{ secrets.X }}) są w porządku
jawne=$(grep -viE 'secretkeyref|valuefrom|secrets\.' <<<"$dodane")
grep -iqE '(password|passwd|secret|token|api_?key)[a-z_]*"?[[:space:]]*[:=][[:space:]]*"?[^"[:space:]$]{3,}' <<<"$jawne" \
  && nie "sekret albo hasło w diffie"
awk '{l=tolower($0)} l~/name:.*(password|passwd|secret|token|api_?key)/{k=1; next}
     k && l~/value:[[:space:]]*"?[^"[:space:]$]{3,}/{f=1} {k=0} END{exit !f}' <<<"$jawne" \
  && nie "sekret w zmiennej env (name/value)"
grep -qE 'write-all' <<<"$dodane" && nie "permissions: write-all"
grep -iqE '(tag:[[:space:]]*"?latest|:latest([^a-z]|$))' <<<"$dodane" && nie "obraz z tagiem latest"
grep -E 'uses:[[:space:]]*[^[:space:]]+@' <<<"$dodane" | grep -qvE '@[0-9a-f]{40}' && nie "akcja nieprzypięta do pełnego SHA"

# 3. CI zielone (gh pr checks: 0 = wszystko przeszło; czerwone, w toku albo brak checków = nie)
gh pr checks "$nr" >/dev/null 2>&1 || nie "checki CI nie są zielone albo ich brak (gh pr checks $nr)"

[ -z "$powody" ] && exit 0
printf 'Bramka merge: PR #%s nie zostanie zmergowany.\n%sNie obchodź bramki. Pokaż człowiekowi powody.\n' "$nr" "$powody" >&2
exit 2
