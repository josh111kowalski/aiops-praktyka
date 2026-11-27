# Dziennik – lab03: Pipeline z AI (namespace `jacek`)

Pipeline: [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) · fork `josh111kowalski/aiops-praktyka`

## Podsumowanie

| | |
|---|---|
| Ostatni przebieg na `main` | ✅ [#45814320428](https://github.com/josh111kowalski/aiops-praktyka/actions/runs/45814320428) (`78e3143`) |
| `actionlint` / `zizmor` | ✅ bez błędów (zizmor także w trybie online) |
| Obrazy w namespace | ✅ `orders-api`, `payments`, `worker`, `web` → `…/jacek/kantyna/<serwis>:78e3143…` |
| `setup/check.sh jacek` | ✅ `SUKCES: 11/11` |

## Zmienne repozytorium (`vars`)

| Zmienna | Wartość |
|---|---|
| `AWS_ROLE_ARN` | `arn:aws:iam::574921529806:role/aiops-ci-jacek` |
| `ECR_REGISTRY` | `574921529806.dkr.ecr.eu-central-1.amazonaws.com/jacek` |
| `K8S_NAMESPACE` | `jacek` |

## Awarie

| # | Objaw (krok, komunikat) | Hipoteza (AI / ja) | Jak sprawdziłem | Poprawka | Status |
|---|---|---|---|---|---|
| 1 | Job **Deploy na namespace**, krok `helm upgrade` (przebieg #45813205541, `b74612e`): `UPGRADE FAILED: conflict … with "kubectl-set" … .spec.template.spec.containers[name="web"].image` | **AI:** ręczny `kubectl set image` (25.11 15:12) przejął pole `image` w `kantyna-web`; Helm 4 robi server-side apply i nie nadpisuje pól innego właściciela | `kubectl get deploy kantyna-web -n jacek --show-managed-fields -o json`: `f:image` należało do `helm` **i** `kubectl-set`; `web` stał na `kantyna/web:1.0.0` spoza chartu; `helm history`: rev 3 `failed`, pozostałe 3 deploymenty już na nowym SHA | `--force-conflicts` w `helm upgrade` (`78e3143`): pipeline z `main` jest źródłem prawdy i przejmuje pola zmienione ręcznie | ✅ |

## Sugestie AI, których nie wdrożyłem

| Sugestia | Dlaczego nie |
|---|---|
| `AWS_ROLE_ARN` = `arn:aws:iam::574921529806:role/kantyna-ci` (wywnioskowane z `infra/ci-oidc/main.tf`) | AI nie mogło tego sprawdzić (brak `iam:GetRole`). Prowadzący podał inną rolę: `aiops-ci-jacek`. Zgadnięty ARN skończyłby się błędem `sts:AssumeRoleWithWebIdentity`. |
| Krok przed `helm upgrade`, który przez `--show-managed-fields` wykrywa ręczne zmiany i wypisuje `::warning::` | Po `--force-conflicts` dryf jest nadpisywany bez śladu, ale na labie to dodatkowa złożoność bez zysku. Ręczne zmiany i tak widać w `managedFields` i w historii. |

## Wnioski

- `--force-conflicts` sprawia, że ręczne poprawki (`kubectl set …`) przetrwają tylko do najbliższego pusha na `main`. Zmiany trwałe trzeba robić w chartcie lub `values`.
- Helm v4 (w CI) robi server-side apply, a lokalny Helm 3.22.1 nie. Ten sam `helm upgrade` może przejść lokalnie i paść w pipeline.
