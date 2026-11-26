# Dziennik diagnozy – lab02 (namespace jacek)

Wiersze z potwierdzoną przyczyną, skopiowane dosłownie z tabel `/diagnoza`.

## 1. Deployment kantyna-web: gotowe 0/2

| hipoteza | dowód z danych | komenda weryfikująca |
|---|---|---|
| **1. W ECR nie ma tagu `kantyna/web:1.0.1`** (pipeline go nie wypchnął albo wypchnął pod inną nazwą) | Błąd dotyczy tylko `web:1.0.1`. Ten sam węzeł pobiera z tego samego konta ECR `payments:1.0.0` i `orders-api:1.0.0`, więc uwierzytelnianie i sieć działają. Pozostałe serwisy są na `1.0.0`. Lab03 opisuje dokładnie ten przypadek. | `aws ecr describe-images --region eu-central-1 --repository-name kantyna/web --query 'imageDetails[].imageTags'` |

## 2. Deployment kantyna-orders-api: gotowe 0/2

| hipoteza | dowód | komenda weryfikująca | wynik |
|---|---|---|---|
| **1. Zła nazwa hosta bazy w `DATABASE_URL`** | Błąd w logach to `Name or service not known`, czyli nazwa się nie rozwiązuje (a nie odmowa połączenia czy złe hasło). Stara wersja deploymentu ma `kantyna-postgres`, nowa ma `kantyna-postgresql`. | `kubectl -n jacek get svc kantyna-postgresql` | **potwierdzona** |

## 3. Deployment kantyna-worker: gotowe 0/1

| hipoteza | dowód z danych | komenda weryfikująca |
|---|---|---|
| **1. Nowa wersja żąda 2Gi pamięci, a quota namespace tego nie mieści (960Mi zajęte + 2Gi > 2560Mi)** | Zdarzenia `FailedCreate` co ok. 16 minut: `exceeded quota: participant-quota, requested: requests.memory=2Gi, used: 960Mi, limited: 2560Mi`. Poprzednia wersja (rev1) miała request 128Mi i limit 256Mi, nowa (rev2) ma 2Gi i 2Gi. To jedyna różnica między wersjami. Helm ma jedną rewizję, więc zmianę zrobiono ręcznie, poza Helmem. | `kubectl -n jacek get events --field-selector involvedObject.name=kantyna-worker-846947dfbd` oraz porównanie `resources` w obu ReplicaSetach |

## 4. Service kantyna-payments: brak podów za Service

| hipoteza | dowód z danych | komenda weryfikująca |
|---|---|---|
| **1. Literówka w selektorze Service (`payment` zamiast `payments`) wprowadzona ręcznym `kubectl patch`** | Selektor to `name=payment`, a pody mają `name=payments`. Ostatnia zmiana Service to `kubectl-patch Update 2026-11-25T13:21:45Z`. Helm ma w manifeście `name: payments`. | `kubectl -n jacek get pods -l app.kubernetes.io/name=payment,app.kubernetes.io/instance=kantyna` (oczekiwane: `No resources found`) |

## 5. Aplikacja: menu przez web – exit code 1

| hipoteza | dowód z danych | komenda weryfikująca |
|---|---|---|
| **1. NetworkPolicy wpuszcza tylko etykietę `frontend`, a web ma `web`, więc pakiety są odrzucane** | W logu nginx: `upstream timed out (110: Operation timed out) while connecting to upstream ... 172.20.25.152:8000`, a dla `/api/menu` kod 499. Pakiety są po cichu odrzucane, a nie odbijane. `orders-api` od startu o 15:17 nie zalogował ani jednego żądania. `get pods -l app.kubernetes.io/name=frontend` nic nie zwraca. | `kubectl -n jacek get networkpolicy kantyna-orders-api-ingress -o yaml` oraz `kubectl -n jacek get pods -l app.kubernetes.io/name=frontend` |
