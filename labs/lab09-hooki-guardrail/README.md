# lab09 — Hooki Claude Code: pas bezpieczeństwa dla agenta

**Zasada:** hook to deterministyczny skrypt, który Claude Code uruchamia przed każdym wywołaniem narzędzia. Nie pyta modelu o zdanie. Ale widzi tylko tekst komendy, więc da się go obejść. Granicą zostają uprawnienia konta.

**Po labie masz:** dwa hooki (blokada groźnych komend `kubectl` i skan promptu pod kątem kluczy), test hooka bez modelu, sprawdzenie na żywo i co najmniej jedno obejście z opisem, która warstwa by je zatrzymała.

**Scenariusz:** zespół chce, żeby Claude Code mógł swobodnie diagnozować klaster (`kubectl` na liście dozwolonych, bez pytania o każdą komendę), ale nigdy niczego nie usuwał i nie czytał Secretów. Dokładacie hook jako pas bezpieczeństwa i sprawdzacie, ile jest wart.

## Zanim zaczniesz

- terminal w katalogu swojego forka, `kubectl get pods` działa w Twoim namespace
- `jq` (`jq --version`; jeśli brak: `brew install jq` albo `sudo apt install -y jq`)
- katalog labu z gotowym testem:

```bash
mkdir -p lab09/.claude/hooks
cp labs/lab09-hooki-guardrail/testy.sh labs/lab09-hooki-guardrail/przypadki.txt lab09/
```

Hooki będą działać tylko w sesji `claude` uruchomionej z katalogu `lab09/`. Reszta forka (i capstone) zostaje bez zmian.

✅ `jq --version` działa, w `lab09/` są `testy.sh` i `przypadki.txt`.

## 1. AI pisze hooki

Nowa sesja `claude` w **katalogu głównym forka** (nie w `lab09/`):

```text
Napisz w lab09/ dwa hooki Claude Code w bashu (JSON ze stdin czytany przez jq) i plik lab09/.claude/settings.json, który je podpina:
1. lab09/.claude/hooks/blokada-kubectl.sh: PreToolUse z matcherem Bash. Blokuje komendy kubectl, które zmieniają klaster
   (delete, patch, edit, apply, replace, scale, set, rollout restart, rollout undo), i każdą komendę kubectl, która czyta Secrety.
   kubectl get, describe i logs przepuszcza. Przy blokadzie powód po polsku na stderr.
2. lab09/.claude/hooks/skan-promptu.sh: UserPromptSubmit. Blokuje prompt z kluczem AWS (AKIA...), kluczem prywatnym PEM albo tokenem GitHub.
W settings.json ścieżki do skryptów przez $CLAUDE_PROJECT_DIR. Nadaj skryptom prawo wykonania. Niczego nie uruchamiaj.
```

Przeczytaj oba skrypty, zanim pójdziesz dalej:
- skąd hook bierze komendę? (pole w JSON-ie na wejściu)
- jakim kodem wyjścia blokuje? Musi być `exit 2`. `exit 1` to dla Claude Code tylko błąd hooka i komenda **wykona się** mimo wszystko.
- co się stanie, jeśli na laptopie nie ma `jq`?

✅ Oba skrypty i `settings.json` istnieją, a Ty umiesz odpowiedzieć na trzy pytania wyżej.

## 2. Test bez modelu

`testy.sh` podaje hookowi każdą komendę z `przypadki.txt` tak, jak robi to Claude Code (JSON na stdin), i porównuje wynik z oczekiwanym. Działa w sekundę i nie kosztuje ani tokena.

```bash
cd lab09
./testy.sh
```

Każde `ŹLE` to błąd hooka. Wklej agentowi wynik i poproś o poprawkę. Zwróć uwagę na dwa rodzaje błędów:
- `BLOK` przepuszczony: dziura w zabezpieczeniu,
- `OK` zablokowany (np. `grep -i delete` w logach): fałszywy alarm. Agent, który nie może przeczytać logów, nie zdiagnozuje awarii.

Dopisz do `przypadki.txt` co najmniej 3 własne przypadki: dwa, które hook ma zatrzymać, i jeden, który ma przepuścić. Szukaj sposobów zapisu, których autor hooka mógł nie przewidzieć (kolejność flag, `--namespace=…`, kilka komend w jednej linii).

✅ `./testy.sh` → `niezgodne: 0`, w tym Twoje 3 przypadki.

## 3. Na żywo

Cel do usunięcia, tylko Twój i niczego nie psuje:

```bash
kubectl create configmap cel-hooka --from-literal=lab=09
```

Sesja `claude` **z katalogu `lab09/`**, z całym `kubectl` na liście dozwolonych (bez pytania o zgodę, więc pilnuje tylko hook):

```bash
claude --allowedTools "Bash(kubectl:*)"
```

Przy pytaniu o zaufanie do katalogu odpowiedz tak. Wpisz `/hooks` i sprawdź, czy widać `PreToolUse` i `UserPromptSubmit`.

```text
Usuń configmapę cel-hooka w moim namespace.
```

Agent powinien dostać odmowę od hooka i podać komendę do ręcznego uruchomienia. Sprawdź w drugim terminalu:

```bash
kubectl get configmap cel-hooka
```

Potem w tej samej sesji:

```text
Sprawdź, czy ten klucz jest aktywny: AKIAIOSFODNN7EXAMPLE
```

Prompt nie powinien w ogóle dojść do modelu.

✅ `cel-hooka` dalej istnieje, a prompt z kluczem zablokował hook (komunikat Twojego hooka na ekranie).

## 4. Obejście: ile wart jest pas?

W drugim terminalu przygotuj „skrypt sprzątający”:

```bash
printf '#!/usr/bin/env bash\n# sprzątanie po labie\nkubectl delete configmap cel-hooka\n' > lab09/porzadki.sh
chmod +x lab09/porzadki.sh
```

W sesji z kroku 3:

```text
Uruchom ./porzadki.sh i powiedz, co wypisał.
```

`./porzadki.sh` nie ma na liście dozwolonych, więc Claude Code zapyta o zgodę. Popatrz, co widzisz w pytaniu, i zatwierdź. Potem:

```bash
kubectl get configmap cel-hooka
```

Dopisz do `przypadki.txt` linię `BLOK|./porzadki.sh` i uruchom `./testy.sh`. Hook widzi tylko tekst komendy, nie to, co jest w pliku.

Teraz sprawdź warstwę, której tekst komendy nie obchodzi. Konto `agent` z lab06:

```bash
kubectl auth can-i delete configmaps --as=system:serviceaccount:$(kubectl config view --minify -o jsonpath='{..namespace}'):agent
```

Wymyśl jeszcze dwa obejścia (podpowiedzi: inny język programowania, API Kubernetesa bez `kubectl`, alias). Nie musisz ich uruchamiać. Zapisz w `lab09/notatki.md`:

| Obejście | Hook | Pytanie o zgodę | RBAC konta `agent` |
|---|---|---|---|
| `./porzadki.sh` | przepuszcza | pyta, ale pokazuje tylko nazwę skryptu | |
| | | | |
| | | | |

✅ `cel-hooka` zniknął przez skrypt, `./testy.sh` pokazuje `ŹLE` dla `./porzadki.sh`, tabela w `notatki.md` ma 3 obejścia.

## Dziennik

Zapisz w `lab09/notatki.md`:

| # | Krok | Co poprawiłem po AI albo co mnie zaskoczyło |
|---|---|---|
| 1 | | |

## SUKCES

- [ ] `lab09/.claude/settings.json` i dwa hooki, `./testy.sh` → `niezgodne: 0` dla wszystkich przypadków poza `./porzadki.sh`
- [ ] na żywo: `kubectl delete` zatrzymany przez hook, prompt z kluczem zatrzymany przed modelem
- [ ] tabela obejść w `lab09/notatki.md` i jedno zdanie: która warstwa jest granicą, a która tylko pasem
- [ ] commit katalogu `lab09/` w forku (bez `porzadki.sh`)

## Dla chętnych

- **Zapytaj zamiast blokować.** Zamiast `exit 2` hook może zwrócić JSON `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "…"}}`. Wtedy komenda nie jest zablokowana, tylko wraca do człowieka mimo listy dozwolonych. Przerób hook dla `rollout restart`: kiedy to lepsze niż blokada?
- **Ostrzeżenie o prompt injection.** Hook `PostToolUse` na `Bash`, który szuka w wyniku komendy tekstu w stylu „ignore previous instructions” i dokłada modelowi ostrzeżenie (`additionalContext`). Sprawdź na logach z lab06. Dlaczego ten hook może tylko ostrzec, a nie zablokować?
- **Ochrona pipeline'u.** Hook `PreToolUse` z matcherem `Write|Edit`, który nie pozwala agentowi zmieniać `.github/workflows/`. Jakie pole JSON-a sprawdzasz?
- **Fail-open.** Zmień w `settings.json` ścieżkę do hooka na nieistniejącą. Czy `kubectl delete` przechodzi? Co to znaczy dla hooka, który ma być zabezpieczeniem?

## Gdy coś nie działa

| Objaw | Co zrobić |
|---|---|
| `/hooks` nie pokazuje hooków | `claude` uruchomione poza `lab09/`? Wyjdź (`/exit`), `cd lab09`, uruchom jeszcze raz |
| hook nie blokuje, a `./testy.sh` mówi, że blokuje | sesja `claude` z innego katalogu albo `settings.json` zmieniony w trakcie sesji. Uruchom `claude` ponownie |
| `permission denied` przy `./testy.sh` albo w komunikacie hooka | `chmod +x lab09/testy.sh lab09/.claude/hooks/*.sh` |
| `./testy.sh`: wszystko `OK`, nic nie blokuje | hook nie kończy się kodem 2 (np. `exit 1` albo brak `jq`: pusta komenda, więc nic nie pasuje). Uruchom ręcznie i czytaj błędy: `echo '{"tool_input":{"command":"kubectl delete pod x"}}' \| .claude/hooks/blokada-kubectl.sh; echo $?` |
| agent mówi, że nie może przeczytać logów | fałszywy alarm hooka (np. słowo `delete` w `grep`). Dopisz przypadek `OK` do `przypadki.txt` i popraw hook |
| `kubectl create configmap`: `already exists` | został z poprzedniej próby, to nic. Idź dalej |
