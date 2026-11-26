# Post-mortem (szkic, bez szukania winnych): awaria Kantyny w namespace `jacek`, 2026-11-25

Konwencja: **[F]** to fakt potwierdzony danymi z klastra lub logów, **[H]** to hipoteza. Czasy są w UTC. Znak „~” oznacza czas wyliczony z wieku obiektów, a nie odczytany wprost.

## Podsumowanie
[F] Około 13:21 w ciągu jednej minuty w namespace `jacek` pojawiło się pięć zmian, wszystkie poza Helmem. Helm ma tylko rewizję 1 z 24.11. Każda zmiana zepsuła inny element Kantyny:

| # | Zmiana | Skutek |
|---|---|---|
| 1 | obraz `web:1.0.1`, którego nie ma w ECR | `ImagePullBackOff` |
| 2 | `DATABASE_URL` z hostem `kantyna-postgresql` | orders-api w `CrashLoopBackOff` |
| 3 | worker z requestem pamięci 2Gi | quota odrzuca utworzenie poda |
| 4 | selektor Service `payments` zmieniony na `payment` | Service bez endpointów |
| 5 | NetworkPolicy wpuszczająca do orders-api tylko etykietę `frontend` | web nie łączy się z API |

[F] Usługę przywrócono ok. 15:24. Przy zmianach 1–4 wróciliśmy do wartości z release Helm, przy zmianie 5 poprawiliśmy selektor w NetworkPolicy. `setup/check.sh jacek` zwraca `SUKCES: 11/11`.

## Wpływ
- [F] **web:** 0 gotowych podów i Service bez endpointów od ~13:21 do ~15:15. UI w tym czasie było niedostępne.
- [F] **orders-api:** 0/2 gotowych od ~13:21 do 15:17:22 (`Application startup complete`).
- [F] **payments:** Service bez endpointów od 13:21:45 do ~15:22. Pody działały, ale ruch do nich nie trafiał.
- [F] **worker:** 0 podów od ~13:21 do 15:21:06. W tym środowisku `QUEUE_URL` jest pusty, więc worker i tak nie przetwarza kolejki.
- [F] **Połączenie web → orders-api:** zablokowane do ~15:24. Odpowiedzi 499 na `/api/menu` i 504 na `/api/orders`.
- [H] Przez ok. 2 godziny nie dało się złożyć żadnego zamówienia. Nie mam metryk biznesowych (liczba zamówień, wskaźnik błędów), które by to potwierdziły.

## Oś czasu

| czas (UTC) | zdarzenie | źródło |
|---|---|---|
| 24.11 17:42:31 | instalacja release Helm `kantyna`, rewizja 1 | `helm history`, managedFields |
| 25.11 13:21:38 | nowy ReplicaSet web z obrazem `1.0.1` | `creationTimestamp` RS |
| ~13:21 | nowe ReplicaSety orders-api (host `kantyna-postgresql`) i worker (2Gi) | wiek RS |
| 13:21:45 | `kubectl-patch` selektora Service `kantyna-payments` | managedFields |
| 13:21:46 | `kubectl apply` NetworkPolicy `kantyna-orders-api-ingress` (etykieta `aiops/lab: lab02`) | metadata |
| 13:21–15:13 | web: ponad 460 nieudanych pobrań obrazu; orders-api: 34–36 restartów; worker: cykliczne `FailedCreate exceeded quota` | events, `get pods` |
| ~15:06 | start diagnozy (`/diagnoza`, tylko komendy odczytu) | sesja |
| 15:13:18–48 | log orders-api: `Name or service not known`, potem `PoolTimeout`, potem `Application startup failed` | `logs --previous` |
| ~15:15 | web przywrócony do `1.0.0`, 2/2 gotowe | `rollout status` |
| 15:17:22 | orders-api wstaje po przywróceniu `kantyna-postgres` | log |
| 15:21:06 | worker wstaje po przywróceniu zasobów z rewizji 1 | log |
| ~15:22 | Service payments z endpointami `10.40.13.50` i `10.40.13.54` | EndpointSlice |
| 15:23:21 / 15:23:27 | nginx: `/api/menu` 499, `/api/orders` 504 `upstream timed out ... while connecting` | log web |
| ~15:24 | poprawka NetworkPolicy (`frontend` na `web`), `check.sh` zwraca 11/11 | `check.sh` |

## Przyczyna źródłowa
- [F] **Bezpośrednia przyczyna:** pięć zmian w konfiguracji wprowadzonych do klastra imperatywnie (`kubectl patch`, `kubectl apply`, zmiany szablonów deploymentów), z pominięciem Helma, który jest źródłem prawdy.
- **Luki w systemie i procesie, które na to pozwoliły:**
  1. [F] Nic nie sprawdza zmian przed wdrożeniem. Klaster przyjął obraz, którego nie ma w ECR, nazwę hosta bez odpowiadającego Service i selektor, który nie pasuje do żadnego poda.
  2. [F] Nic nie wykrywa rozjazdu między klastrem a Helmem. Release nadal wygląda na `deployed`, rewizja 1, choć stan klastra jest inny.
  3. [F] Rolling update nie ochronił usługi, bo stare ReplicaSety miały już 0 replik. [H] Stare pody usunięto inną drogą niż rollout.
  4. [F] Do sprawdzenia `check.sh` minęło ok. 1 h 45 min. Nie mam danych, czy w tym czasie odpaliły jakieś alerty.
  5. [F] NetworkPolicy nie ma w chart Helm, więc po ponownym zastosowaniu jej pliku źródłowego błąd wróci.

## Co zadziałało
- [F] `setup/check.sh` wskazał każdy objaw osobno, co pozwoliło diagnozować je po kolei.
- [F] Porównanie szablonów starego i nowego ReplicaSetu oraz manifestu Helm pokazało dokładną różnicę (obraz, env, resources, selektor).
- [F] `managedFields` i `creationTimestamp` pokazały, że zmiany zrobiono imperatywnie i mniej więcej kiedy.
- [F] Diagnoza szła wyłącznie komendami odczytu. Każdą zmianę na klastrze wykonano dopiero po potwierdzeniu i sprawdzono po wdrożeniu.
- [F] Zdarzenie quoty podało dokładne liczby (`requested`, `used`, `limited`).

## Co nie zadziałało
- [F] Zbiorcze zdarzenia `BackOff` przykryły pierwotny komunikat `ErrImagePull`, więc o braku tagu przesądził dopiero odczyt z ECR.
- [F] Użytkownik IAM nie ma `ecr:BatchGetImage`, więc nie dało się sprawdzić manifestu obrazu.
- [F] Uszkodzona NetworkPolicy była niewidoczna, dopóki działały inne awarie, i wyszła na jaw dopiero na końcu.
- [F] Skrypt `check.sh` sprawdza tylko ruch z web. Nie pokaże, czy NetworkPolicy blokuje Prometheusa albo `loadgen`.
- [F] Szum diagnostyczny: do poda nginx wstrzykiwany jest init container OpenTelemetry dla Javy.

## Akcje
Właściciele i terminy zostawiłem do uzupełnienia, bo nie wynikają z danych.

| # | akcja | właściciel | termin |
|---|---|---|---|
| 1 | Polityka admission (np. Kyverno/Gatekeeper): obraz musi istnieć w rejestrze, a selektor Service musi pasować do etykiet z chartu | _do ustalenia_ | _do ustalenia_ |
| 2 | Wykrywanie rozjazdu z Helmem (`helm diff` cyklicznie albo GitOps z auto-sync) | _do ustalenia_ | _do ustalenia_ |
| 3 | Przenieść NetworkPolicy do chartu Helm z selektorami z helperów etykiet i dopuścić ruch z Prometheusa | _do ustalenia_ | _do ustalenia_ |
| 4 | Alerty na `kube_deployment_status_replicas_available == 0` i na Service bez endpointów, z runbookami w `app/runbooks/` | _do ustalenia_ | _do ustalenia_ |
| 5 | Ograniczyć zmiany imperatywne (`patch`, `set`, `apply`) w namespace aplikacji przez RBAC na rzecz pipeline'u | _do ustalenia_ | _do ustalenia_ |
| 6 | Nadać uprawnienie odczytu manifestów ECR (`ecr:BatchGetImage`) roli diagnostycznej | _do ustalenia_ | _do ustalenia_ |
| 7 | Wyłączyć wstrzykiwanie OpenTelemetry dla języków, których serwis nie używa | _do ustalenia_ | _do ustalenia_ |

## Pytania otwarte
1. Jakim mechanizmem wprowadzono zmiany o 13:21 (skrypt, pipeline, ręcznie)? Etykieta `aiops/lab: lab02` sugeruje scenariusz labu, ale to [H].
2. Jak stare ReplicaSety trafiły do 0 replik, skoro strategia RollingUpdate nie powinna tego zrobić?
3. Czy w trakcie awarii odpaliły alerty `Kantyna*` i czy ktoś je dostał? Alertmanagera nie sprawdzałem.
4. Czy obecna NetworkPolicy blokuje zbieranie metryk orders-api przez Prometheusa i ruch z `loadgen`?
5. Jaki był faktyczny wpływ na użytkowników (nieudane zamówienia, błędy 5xx)? Potrzebne metryki z Prometheusa za 13:21–15:24.
