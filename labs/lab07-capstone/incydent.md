# Dziennik incydentu

- **Data:** 2026-11-27
- **Namespace:** jacek
- **Objaw / alert:** `setup/check.sh` → 8/11; orders-api 0/2 gotowych podów, menu i zamówienia przez web nie działają

| Godzina | Hipoteza (AI / ja) | Komenda / zapytanie | Wynik | Status |
|---|---|---|---|---|
| 15:30 | (ja) Kantyna w namespace `jacek` działa poprawnie | `setup/check.sh` | **8/11.** ❌ `kantyna-orders-api`: gotowe 0/2 (2 pody w nowej wersji); ❌ menu przez web i ❌ zamówienie przez web: `command terminated with exit code 1`. OK: web 2/2, payments 2/2, worker 1/1, postgres, endpointy wszystkich 4 serwisów | odrzucona |
| 15:31 | (AI) orders-api nie przechodzi readiness | `kubectl -n jacek get pods`, `describe pod`, `get events` | Oba pody `Running`, 0/1 Ready, **0 restartów**. Event: `Readiness probe failed: /readyz … context deadline exceeded` | potwierdzona |
| 15:32 | (AI) H1: flaga `db_pool_leak` wyczerpuje pulę połączeń do bazy | `kubectl logs <pod orders-api>`, `kubectl get configmap kantyna-flags` | Logi: `PoolTimeout: couldn't get a connection after 30.00 sec` od 14:25:19 UTC; ostatnie udane zamówienie o 14:24:41 UTC. Flagi: `db_pool_leak: true`, `slow_menu_query: true` | otwarta |
| 15:32 | (AI) H2: `slow_menu_query` (N+1) dłużej trzyma połączenia, czynnik dodatkowy | traceback w logach | `PoolTimeout` w `get_menu` → `fetch_menu(slow=menu_uses_n_plus_one())` | otwarta |
| 15:32 | (AI) H3: ruch z loadgena ujawnił wyciek | `kubectl get pods` | loadgen działa od ok. 14:20 UTC (w values Helm `loadgen.enabled: false`) | otwarta |
| 15:32 | (AI) Awaria Postgresa | `kubectl logs kantyna-postgres-0` | STS Ready, w logach tylko zwykłe checkpointy | odrzucona |
| 15:35 | (AI) Runbook `KantynaDBPoolExhausted`, krok 1: pula wycieka | PromQL `max by (pod)(db_pool_connections_in_use{namespace="jacek"}) / max by (pod)(db_pool_size{namespace="jacek"})` | Do ok. 14:24 UTC 0, od 14:26 **1.0 (10/10)** na obu podach i nie spada, czyli wyciek | H1 potwierdzona |
| 15:35 | (AI) Runbook, krok 4: ostatnie zmiany | `helm -n jacek history kantyna`, managedFields ConfigMap `kantyna-flags` | Ostatni release Helm (rev 5) z 26.11, bez override'ów flag. ConfigMap zmieniona przez **`kubectl-patch` o 14:23:01 UTC (15:23)**. Domyślnie w chartcie obie flagi = `false` | potwierdzona (przyczyna) |
| 15:35 | Runbook, krok 2: sesje w bazie | `pg_stat_activity` przez `kubectl exec` | Pominięte, `kubectl exec` zablokowany w `.claude/settings.json` | pominięta |
| 15:37 | (ja, zgoda) Naprawa wg runbooka: cofnięcie zmiany ustawień | `kubectl -n jacek patch configmap kantyna-flags` (`db_pool_leak=false`, `slow_menu_query=false`) | `configmap/kantyna-flags patched` (15:37:18) | wykonane |
| 15:37 | (ja, zgoda) Naprawa wg runbooka: zwolnienie połączeń | `kubectl -n jacek rollout restart deploy/kantyna-orders-api` | `successfully rolled out` (15:37:36) | wykonane |
| 15:37 | Weryfikacja | `setup/check.sh`, PromQL `db_pool_connections_in_use` | **SUKCES: 11/11**. Nowy pod: 0 połączeń w użyciu (stare serie 10/10 to jeszcze nieodświeżone metryki usuniętych podów) | rozwiązane |
| 15:45 | (AI) Zapobieganie: alert nie odpalił, bo `prometheusRule.enabled: false`; rozmiar puli nie jest ustawiany z chartu | commit [`5c6d213`](https://github.com/josh111kowalski/aiops-praktyka/commit/5c6d21387130bcb3d48bea8e6f004b174bc46ab3) (`5c6d21387130bcb3d48bea8e6f004b174bc46ab3`) na gałęzi `incydent/db-pool-leak-2026-11-27`, [PR #5](https://github.com/josh111kowalski/aiops-praktyka/pull/5) | `prometheusRule.enabled: true`, poprawiony `runbookBaseUrl`, `ordersApi.dbPool.min/max` → `DB_POOL_MIN/MAX`. `helm lint` OK. CI Kantyna: [przebieg 46018844411](https://github.com/josh111kowalski/aiops-praktyka/actions/runs/46018844411): **success** (testy orders-api i payments pass; build i deploy pominięte) | w review |

**Przyczyna:** ręczny `kubectl patch` ConfigMap `kantyna-flags` o 15:23 włączył `db_pool_leak` (oraz `slow_menu_query`). Pula orders-api (max 10) zapełniła się w ok. 3 min, `/readyz` nie dostawał połączenia, więc oba pody wypadły z Service.
**Do wyjaśnienia:** kto i po co zrobił patch o 15:23; czy loadgen (włączony poza Helmem) ma zostać.

<!-- Status: otwarta / potwierdzona / odrzucona -->
