# lab08 — Alert z AI i `promtool`: test na zielono to jeszcze nie działający alert

**Zasada:** reguła alertu od AI to kod. Najpierw testy jednostkowe pokazują, że logika jest dobra. Potem historia prawdziwych danych pokazuje, czy alert odpaliłby wtedy, kiedy coś się naprawdę działo.

**Po labie masz:** plik z dwoma regułami alertów dla Kantyny, testy `promtool` na zielono, dowód, że testy coś pilnują, i sprawdzenie reguły na historii namespace'u `demo`.

**Scenariusz:** zespół chce dwóch nowych alertów: „za dużo błędów przy składaniu zamówień” i „zamówienia przestały powstawać”. Ma być mało fałszywych alarmów, szczególnie w nocy, kiedy ruch jest mały.

## Zanim zaczniesz

- terminal w katalogu swojego forka, Claude Code uruchamiane z tego samego katalogu
- Grafana z lab05 (Explore, źródło danych Prometheus)
- `promtool` (jest w pakiecie Prometheusa):

| System | Instalacja |
|---|---|
| macOS | `brew install prometheus` |
| Linux / WSL (x86_64) | `curl -fsSL https://github.com/prometheus/prometheus/releases/download/v3.16.0/prometheus-3.16.0.linux-amd64.tar.gz \| tar xz --strip-components=1 prometheus-3.16.0.linux-amd64/promtool && sudo install promtool /usr/local/bin/ && rm promtool` |
| z Dockerem | `alias promtool='docker run --rm -v "$PWD":/w -w /w --entrypoint promtool prom/prometheus:v3.16.0'` |

```bash
promtool --version
mkdir -p lab08
```

✅ `promtool --version` pokazuje 3.x.

## 1. AI pisze reguły

Nowa sesja `claude`:

```text
Napisz plik reguł Prometheusa (zwykły plik rule_files, nie PrometheusRule z Kubernetesa) do lab08/reguly.yaml,
grupa kantyna-lab08, dwa alerty dla namespace demo:
1. KantynaZamowieniaBledy: ponad 5% odpowiedzi 5xx przy składaniu zamówień (POST /api/orders w orders-api)
   przez 5 minut. Nie ma odpalać przy bardzo małym ruchu, np. w nocy.
2. KantynaBrakZamowien: przez 15 minut nie powstało żadne zamówienie (licznik orders_created_total).
   Ma odpalić także wtedy, gdy metryka w ogóle zniknie.
Etykiety: severity warning dla 1, critical dla 2. Annotacja summary po polsku.
Niczego nie wdrażaj.
```

```bash
promtool check rules lab08/reguly.yaml
```

Zanim pójdziesz dalej, sprawdź w Grafanie (Explore → Metrics browser, metryka `http_requests_total`, namespace `demo`), czy etykiety z reguły istnieją: nazwa etykiety ze ścieżką (`route`? `path`? `handler`?), `method`, `status`. Model często zgaduje te nazwy.

Odpowiedz sobie też na dwa pytania:
- jak reguła 1 rozpoznaje „mały ruch” i od ilu zapytań na sekundę uznaje ruch za wystarczający?
- czym w regule 2 jest `absent(...)` (albo coś podobnego) i po co tam jest?

✅ `promtool check rules` → `SUCCESS: 2 rules found`, a etykiety z reguły istnieją w Grafanie.

## 2. Testy jednostkowe i dowód, że coś pilnują

`promtool test rules` podaje regule sztuczne serie danych i sprawdza, czy alert odpala w danym momencie. Działa offline, nadaje się do CI.

```text
Napisz lab08/testy.yaml dla promtool test rules (rule_files: [reguly.yaml]). Przypadki:
a) 10% błędów 5xx przy normalnym ruchu (ok. 1 zapytanie na sekundę): po 4 minutach jeszcze cisza, po 12 minutach KantynaZamowieniaBledy odpala,
b) 1% błędów: cisza,
c) noc: mały ruch (ok. 1 zapytanie na minutę), połowa to 5xx: cisza,
d) licznik orders_created_total stoi w miejscu: KantynaBrakZamowien odpala,
e) seria orders_created_total znika: KantynaBrakZamowien odpala.
Etykiety serii takie same jak w regułach. Oczekiwane etykiety i annotacje alertu wpisz w exp_labels i exp_annotations.
```

```bash
promtool test rules lab08/testy.yaml
```

Zielone testy jeszcze niczego nie dowodzą. Zepsuj regułę i sprawdź, czy któryś test się wywróci. Każdą zmianę zrób w `reguly.yaml`, uruchom testy, potem przywróć oryginał (`git diff`, `git checkout lab08/reguly.yaml`, jeśli już był commit):

| Zmiana w regule | Który test powinien się wywrócić? |
|---|---|
| próg `0.05` → `0.5` | a) |
| usuń warunek o małym ruchu | c) |
| usuń `absent(...)` z reguły 2 | e) |

Jeśli po zmianie testy dalej są zielone, test niczego nie pilnuje. Wklej agentowi regułę, test i wynik i zapytaj, dlaczego test tego nie łapie. Podpowiedź do c): przy jakim `interval` w teście `rate(...[5m])` ma z czego liczyć?

✅ `promtool test rules` → `SUCCESS`, a każda z trzech zmian wywraca właściwy test.

## 3. Prawdziwe dane: czy alert odpaliłby?

Testy sprawdziły logikę na danych, które sam wymyśliłeś. Teraz sprawdź regułę na historii namespace'u `demo`.

W Grafanie: Explore → Prometheus → zakres **ostatnie 4 dni** → wklej wyrażenie `expr` z reguły 1 (bez `for`). Każdy punkt na wykresie to moment, w którym warunek był spełniony.

Porównaj wynik z tabelą „Co naprawdę się stało” z tematu 3.2 i z godzinami z lab05 (`momenty.md`). Czy reguła 1 pokazuje coś w czasie incydentu z błędami API?

Jeśli wykres jest pusty, ustal dlaczego. To zapytanie pokazuje, z jakimi etykietami zapisują się prawdziwe błędy:

```promql
sum by (method, route, status) (increase(http_requests_total{namespace="demo", status=~"5.."}[4d]))
```

Popraw regułę z agentem. Dopisz do `testy.yaml` przypadek z etykietami takimi, jakie widzisz w prawdziwych danych. Tak powstaje test regresji: ten błąd już nie wróci. Sprawdź poprawioną regułę jeszcze raz na historii.

Na koniec reguła 2 na tym samym zakresie: czy odpaliłaby w nocy albo w innym momencie, w którym nic złego się nie działo?

✅ Reguła 1 pokazuje okresy pokrywające się z incydentami z 3.2, `promtool test rules` → `SUCCESS` z nowym przypadkiem. Wnioski w `lab08/notatki.md`.

## Dziennik

Zapisz w `lab08/notatki.md`:

| # | Krok | Co poprawiłem po AI albo co mnie zaskoczyło |
|---|---|---|
| 1 | | |

## SUKCES

- [ ] `promtool check rules lab08/reguly.yaml` → `SUCCESS`
- [ ] `promtool test rules lab08/testy.yaml` → `SUCCESS`, a próg, warunek małego ruchu i `absent` są pilnowane przez testy
- [ ] reguła 1 sprawdzona na historii `demo`, w `testy.yaml` jest przypadek z etykietami z prawdziwych danych
- [ ] commit katalogu `lab08/` w forku

## Dla chętnych

- **Krok w pipeline.** Dodaj do `.github/workflows/ci.yml` krok `promtool test rules lab08/testy.yaml` (obraz `prom/prometheus:v3.16.0` albo tarball). Przepuść workflow przez `actionlint` i `zizmor` jak w lab03.
- **Do charta.** Przenieś regułę 1 do `app/deploy/helm/kantyna/templates/prometheusrule.yaml` (namespace przez `{{ $ns }}` jak w pozostałych regułach) i sprawdź `helm template` + `promtool check rules` na wyciętym fragmencie `spec`.
- **Szum w nocy.** Jaki jest najmniejszy ruch `POST` w `demo` w ciągu ostatnich 4 dni (`min_over_time`)? Czy próg „małego ruchu” z reguły 1 ma zapas?
- **`for` a okno.** Zmień `for: 5m` na `for: 0m`. Który test się zmienia i dlaczego to więcej fałszywych alarmów?

## Gdy coś nie działa

| Objaw | Co zrobić |
|---|---|
| `promtool: command not found` | instalacja z tabeli w „Zanim zaczniesz” |
| `could not parse expression` | wyrażenie PromQL jest niepoprawne. Wklej błąd agentowi |
| `field kind not found in type rulefmt.RuleGroups` | AI dało PrometheusRule z Kubernetesa. `promtool` czyta tylko zawartość `spec` (od `groups:`) |
| `WARNING: no file match pattern lab08/lab08/reguly.yaml` | ścieżka w `rule_files` jest względem katalogu pliku testów: `reguly.yaml`, nie `lab08/reguly.yaml`. Uwaga: to tylko ostrzeżenie. Testy z oczekiwaną ciszą przechodzą wtedy bez żadnej reguły |
| test pada z `got:[]` | alert nie odpalił. Sprawdź `eval_time` (musi minąć okno i `for`) i czy etykiety serii pasują do selektora w regule |
| test pada z różnicą w etykietach | w `exp_labels` brakuje etykiety, którą dokłada reguła (np. `namespace` z `sum by`) |
| z aliasem Dockera: `permission denied` albo brak pliku | uruchamiaj z katalogu forka. Alias widzi tylko bieżący katalog |
