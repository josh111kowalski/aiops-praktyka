# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Czym jest to repo

Repo ćwiczeniowe szkolenia „AIOps w praktyce” (Sages). Uczestnik pracuje na forku; nowe laby pobiera przez `git pull upstream main`. Treść jest po polsku.

- `app/` — aplikacja **Kantyna** (zamawianie obiadów), mikroserwisy na AWS EKS (eu-central-1). Szczegóły: `app/README.md`.
- `labs/labNN-*/README.md` — laboratoria (cel, kroki, warunek „SUKCES”). Część labów ma własne zasady, np. lab01: „tylko pytasz, nic nie zmieniasz w kodzie” (wyjątek: `CLAUDE.md`, `.claude/settings.json`).
- `docs/NN-*/` — materiały do tematów (`*.md` + `architektura.html`), `docs/prompts/` — szablony promptów.
- `setup/` — przygotowanie stanowiska; `setup/check.sh [namespace]` sprawdza wdrożenie Kantyny w klastrze (oczekiwane `SUKCES: 11/11`).

## Wersje narzędzi
- kubectl - 1.37.2
- Helm - 3.22.1

## Komendy (uruchamiane z `app/`)

```bash
docker compose up -d --build          # lokalnie: UI :8088, orders-api :8000, payments :8080
docker compose down -v                # stop + usunięcie danych bazy
docker compose --profile loadgen up -d loadgen   # ruch syntetyczny (PEAK_RPS=...)

make test                             # wszystkie testy
make test-orders-api                  # cd orders-api && uv run pytest -q
make test-payments                    # go test w kontenerze golang:1.23
make helm-lint                        # helm lint deploy/helm/kantyna
make helm-template REGISTRY=<r> VERSION=<v>
helm lint app                         # komenda do sprawdzania zmian
```

Pojedynczy test:

```bash
cd app/orders-api && uv run pytest tests/test_flags.py::<nazwa_testu>
docker run --rm -v "$PWD/app/payments:/src" -w /src golang:1.23 go test -run <TestName> ./...
```

Testy `orders-api` nie potrzebują bazy: `tests/conftest.py` ustawia `SKIP_DB_INIT=1` i używa `TestClient`. Testów dla `worker`, `loadgen` i `web` nie ma.

## Architektura Kantyny

Przepływ zamówienia: `web` (nginx, proxy `/api/*`) → `orders-api` (FastAPI) → `payments` (Go, `POST /pay`; odmowa = brak zapisu) → zapis w PostgreSQL w jednej transakcji → zdarzenie do SQS (tylko gdy ustawiono `QUEUE_URL`) → `worker` zapisuje paragon do S3 (po 5 nieudanych próbach DLQ). Lokalnie nie ma SQS/S3, więc worker tylko czeka. `loadgen` generuje ruch o profilu dobowym (Europe/Warsaw).

**Flagi runtime = celowe wstrzykiwanie awarii.** Każdy serwis (`orders-api/app/flags.py`, `worker/app/flags.py`, `payments/flags.go`) co kilkanaście sekund czyta `FLAGS_FILE` (domyślnie `/etc/kantyna/flags/flags.json`), bez restartu. Wartość z pliku ma pierwszeństwo przed zmienną środowiskową. Źródła pliku:
- lokalnie: `app/deploy/local/flags.json`,
- na klastrze: sekcja `flags:` w `values.yaml` → ConfigMap `<fullname>-flags`.

Flagi (`error_rate`, `memory_leak_mb_per_min`, `cpu_burn`, `db_pool_leak`, `slow_menu_query`, `log_noise`, `latency_ms`, `fail_rate`…) są obsługiwane w `orders-api/app/runtime.py` i odpowiadają alertom z `PrometheusRule`. To mechanizm do labów diagnostycznych, a nie bugi do „naprawiania” w kodzie.

**Warianty builda (`APP_VARIANT`)**: `stable`, `receipt-v2` (ok. 7% błędów renderowania paragonu, zamówienie przechodzi), `menu-v2` (zapytanie menu N+1, jak `slow_menu_query`). Wariant i wersja trafiają do `/version` i metryki `kantyna_build_info`.

**Observability**: każdy serwis wystawia `/metrics`; logi to JSON na stdout (`ts`, `level`, `msg`, `route`, `status`, `duration_ms`, `trace_id`…); orders-api wysyła trace'y OTLP do Tempo. Alerty `Kantyna*` w `deploy/helm/kantyna/templates/prometheusrule.yaml` mają runbooki w `app/runbooks/<NazwaAlertu>.md`. Nowy alert = nowy runbook o tej samej nazwie.

## Pułapki i zasady

- `app/.env` zawiera **fałszywe** sekrety do ćwiczeń, a `.claude/settings.json` blokuje m.in. `*secret*`, `kubectl delete`, `kubectl exec`. Nie czytaj sekretów i nie obchodź tych reguł.
- `orders-api/Dockerfile.legacy` + `requirements-legacy.txt` (Python 3.9, stare zależności, `make legacy-build`) to osobny, starszy wariant builda. Nie aktualizuj go przy okazji zmian w głównym `Dockerfile`.
- Klaster jest wspólny: działaj tylko w namespace uczestnika. Zmiany na klastrze (`kubectl apply/patch/rollout/set`) wymagają potwierdzenia.
- `labs/lab06-agent-runbook/zepsuj.sh` celowo psuje wdrożenie (scenariusz labu).
- nie uruchamiaj `kubectl delete`
