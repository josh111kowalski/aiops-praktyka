# PR #3: orders-api: szybciej
Commit: aba16203c9a20159a33c01cca3d63496c6396a89 · Data przeglądu: 2026-11-26

**Werdykt: NIE MERGUJ**

## Najważniejsze powody
1. Workflow CI dostaje `permissions: write-all` (`.github/workflows/ci.yml:14`), a w tym samym pliku akcja `actions/setup-go` traci przypięcie do SHA na rzecz `@v4` (`.github/workflows/ci.yml:66`). Razem otwiera to drogę do ataku na łańcuch dostaw: przestawiony tag akcji wykona się z tokenem z pełnym zapisem do repo.
2. Obraz `orders-api` dostaje tag `latest` (`app/deploy/helm/kantyna/values.yaml:78`). Wdrożenie przestaje być powtarzalne, a przy `pullPolicy: IfNotPresent` węzły mogą uruchamiać różne wersje.
3. Z `orders-api` usunięto `resources.limits` (po `app/deploy/helm/kantyna/values.yaml:92`), a opis PR-a („drobne poprawki”) nie mówi, co i dlaczego się zmienia. Tytuł „szybciej” nie odpowiada zmianom, które dotyczą uprawnień CI i konfiguracji wdrożenia.

## Blokery
- `.github/workflows/ci.yml:14` · permissions: write-all w workflow · każdy job (także z akcjami firm trzecich) dostaje token z zapisem do kodu, wydań, pakietów itd. Przywróć `permissions: contents: read`.
- `.github/workflows/ci.yml:66` · akcja GitHub nieprzypięta do pełnego SHA · `actions/setup-go@v4` to ruchomy tag, a w dodatku cofnięcie z v7.1.0 do v4. Przywróć `@d8cbb8045d7f43706b9177cceb36c1f91a6644d5 # v7.1.0`.
- `app/deploy/helm/kantyna/values.yaml:78` · obraz z tagiem latest · niepowtarzalne wdrożenia, brak jednoznacznego rollbacku, rozjazd wersji między podami. Przywróć konkretny tag (wcześniej `0.0.0-dev`).

## Uwagi
- `app/deploy/helm/kantyna/values.yaml:92` · usunięte resources.limits · bez limitów wyciek pamięci (np. flaga `memory_leak_mb_per_min`) albo `cpu_burn` może zagłodzić inne pody na wspólnym węźle. Przywróć `limits: cpu: 500m, memory: 384Mi`.
- PR (opis) · opis PR-a nie mówi, co i dlaczego się zmienia · „drobne poprawki” nie opisuje zmian. Opisz każdą zmianę i jej powód, a zmiany CI wydziel do osobnego PR-a.

## Checki CI
- Testy orders-api: pass (11s)
- Testy payments: pass (34s)
- Build ${{ matrix.service }}: skipping
- Deploy na namespace: skipping
