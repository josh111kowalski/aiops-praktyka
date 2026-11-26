# lab04b — Kyverno z AI: polityka „obrazy tylko z naszego ECR”

**Zasada:** polityka od AI to kod. Zanim trafi do klastra, pokazujesz, że odrzuca zły manifest, przepuszcza dobry i wiesz, co zablokowałaby w tym, co już działa. Wszystko offline albo tylko z odczytem klastra. Niczego nie wdrażasz.

**Po labie masz:** politykę Kyverno, która wpuszcza tylko obrazy z firmowego ECR z konkretnym tagiem, dwa pliki testowe (dobry i zły), `kyverno test` na zielono i decyzję, co zrobić z tym, czego polityka nie przepuszcza w Twoim namespace.

**Scenariusz:** zespół bezpieczeństwa ogłasza regułę: „Od przyszłego tygodnia w klastrze uruchamiamy tylko obrazy z naszego ECR `574921529806.dkr.ecr.eu-central-1.amazonaws.com`, zawsze z konkretnym tagiem, nigdy `:latest`”. Zanim ją włączą, chcą wiedzieć, co się zepsuje.

## Zanim zaczniesz

- zdrowa Kantyna w Twoim namespace (`setup/check.sh` → `SUKCES: 11/11`)
- terminal w katalogu swojego forka, Claude Code uruchamiane z tego samego katalogu
- Kyverno CLI w wersji 1.19 lub nowszej:

| System | Instalacja |
|---|---|
| macOS | `brew install kyverno` |
| Linux / WSL (x86_64) | `curl -fsSL https://github.com/kyverno/kyverno/releases/download/v1.19.1/kyverno-cli_v1.19.1_linux_x86_64.tar.gz \| tar xz kyverno && sudo install kyverno /usr/local/bin/ && rm kyverno` |

```bash
kyverno version
mkdir -p lab04b
```

✅ `kyverno version` pokazuje 1.19 lub nowszą.

## 1. AI pisze politykę

Nowa sesja `claude`:

```text
Napisz politykę Kyverno w formacie ValidatingPolicy (apiVersion policies.kyverno.io/v1, Kyverno 1.19, wyrażenia CEL).
Reguła: Deploymenty i StatefulSety mogą używać tylko obrazów z rejestru
574921529806.dkr.ecr.eu-central-1.amazonaws.com i obraz musi mieć konkretny tag (nie :latest, nie bez tagu).
Tryb: odrzucaj (Deny). Każda reguła z czytelnym komunikatem po polsku.
Zapisz do lab04b/polityka.yaml. Nie stosuj niczego w klastrze.
```

Przeczytaj plik, zanim pójdziesz dalej:
- `apiVersion` i `kind`: czy to `ValidatingPolicy`, a nie stare `kyverno.io/v1 ClusterPolicy`?
- tryb: `Deny` czy tylko `Audit`?
- czy prefiks rejestru kończy się na `/`? (Bez `/` przejdzie też `574921529806.dkr.ecr.eu-central-1.amazonaws.com.zly-rejestr.io/…`.)

✅ `lab04b/polityka.yaml` istnieje, a Ty umiesz odpowiedzieć na trzy pytania wyżej.

## 2. Dowód: odrzuca zły, przepuszcza dobry

Napisz sam (albo poproś agenta i przeczytaj) dwa minimalne Deploymenty:
- `lab04b/test/dobry.yaml`: obraz `574921529806.dkr.ecr.eu-central-1.amazonaws.com/kantyna/web:1.0.0`,
- `lab04b/test/zly.yaml`: ten sam obraz, ale z tagiem `:latest`.

```bash
kyverno apply lab04b/polityka.yaml --resource lab04b/test/dobry.yaml
kyverno apply lab04b/polityka.yaml --resource lab04b/test/zly.yaml
```

Dobry ma dać `fail: 0`, zły `fail: 1`. Jeśli zły przechodzi, wklej agentowi wynik i poproś o poprawkę.

Potem sprawdź drugą regułę: zmień w kopii złego pliku obraz na `nginx:1.27` (konkretny tag, ale obcy rejestr). Też ma być `fail`.

`ValidatingPolicy` zgłasza tylko pierwszą niespełnioną regułę, więc przy obrazie łamiącym obie zobaczysz `fail: 1`, nie `fail: 2`.

✅ Dobry plik przechodzi, `:latest` i obcy rejestr są odrzucane.

## 3. Audyt: co zablokowałaby w Twoim namespace?

Kyverno może sprawdzić to, co już działa w klastrze. Tylko czyta, niczego nie zmienia:

```bash
kyverno apply lab04b/polityka.yaml --cluster --namespace <login>
```

Coś się nie zgadza. Ustal sam, który zasób i dlaczego:

```bash
kubectl get deploy,statefulset -o custom-columns=NAZWA:.metadata.name,OBRAZ:.spec.template.spec.containers[*].image
```

To jest prawdziwa decyzja, którą podejmuje zespół przed włączeniem polityki. Wybierz jedną drogę i zapisz uzasadnienie w `lab04b/notatki.md`:

| Droga | Co to znaczy |
|---|---|
| A. Lustro w ECR | obraz kopiujemy do naszego ECR i zmieniamy chart. Polityka bez wyjątków. (Tylko opisz kroki, nie masz uprawnień do ECR.) |
| B. Wąski wyjątek | polityka przepuszcza **dokładnie ten jeden** obraz z tym tagiem |
| C. Włączamy w `Audit` | polityka tylko raportuje, a naprawy robimy później |

Jeśli wybierasz B: poproś agenta o wyjątek i sprawdź, czy nie jest za szeroki. Złe wyjątki to np. cały rejestr `docker.io`, wszystkie StatefulSety albo dowolny tag postgresa. Dopisz do testów `lab04b/test/zly-postgres.yaml` z tym samym obrazem, ale tagiem `:latest`. Ma być odrzucany.

```bash
kyverno apply lab04b/polityka.yaml --cluster --namespace <login>
kyverno apply lab04b/polityka.yaml --resource lab04b/test/zly-postgres.yaml
```

✅ Wiesz, który zasób łamie politykę i dlaczego. Decyzja z uzasadnieniem jest w `lab04b/notatki.md`. Przy drodze B audyt daje `fail: 0`, a `zly-postgres.yaml` jest odrzucany.

## 4. Test, który pójdzie do pipeline'u

`kyverno apply` sprawdzasz oczami. `kyverno test` sprawdza sam i kończy się kodem 1, gdy wynik nie zgadza się z oczekiwanym. To nadaje się do CI.

Poproś agenta:

```text
Napisz lab04b/kyverno-test.yaml (apiVersion cli.kyverno.io/v1alpha1, kind Test) dla polityki z lab04b/polityka.yaml.
Zasoby: wszystkie pliki z lab04b/test/. Oczekiwane wyniki: dobry.yaml → pass, każdy zly*.yaml → fail.
Ścieżki w pliku względem katalogu lab04b/.
```

```bash
kyverno test lab04b/
```

Teraz sprawdź, czy test naprawdę coś pilnuje: zmień w `kyverno-test.yaml` oczekiwany wynik dla `zly` na `pass` i uruchom jeszcze raz. Test ma się wywrócić (`1 tests failed`, kod wyjścia 1: `echo $?`). Przywróć `fail`.

✅ `kyverno test lab04b/` → wszystkie testy przechodzą, a celowo zepsute oczekiwanie wywraca test.

## Dziennik

Zapisz w `lab04b/notatki.md`:

| # | Krok | Co poprawiłem po AI albo co mnie zaskoczyło |
|---|---|---|
| 1 | | |

## SUKCES

- [ ] `lab04b/polityka.yaml`: `ValidatingPolicy`, `Deny`, prefiks rejestru z `/` na końcu
- [ ] `kyverno test lab04b/` → wszystkie testy na zielono, w tym co najmniej jeden zły przypadek
- [ ] w `lab04b/notatki.md` decyzja A, B albo C z uzasadnieniem
- [ ] commit katalogu `lab04b/` w forku

## Dla chętnych

- **Dziura w `initContainers`.** Czy Twoja polityka sprawdza `initContainers`? Dopisz test `zly-init.yaml`: dobry kontener główny, a initContainer z `busybox:latest`. Jeśli przechodzi, popraw politykę z agentem.
- **Krok w pipeline.** Dodaj do `.github/workflows/ci.yml` krok `kyverno test lab04b/` przed wdrożeniem (instalacja z tarballa jak na Linuksie wyżej). Przepuść workflow przez `actionlint` i `zizmor` jak w lab03.
- **Stary format.** Poproś AI o tę samą politykę bez podawania formatu i wersji. Jaki `kind` dostałeś? Czy `kyverno test` nadal przechodzi?
- **Obraz z digestem zamiast tagu.** `…/kantyna/web@sha256:…` to najbezpieczniejsza forma. Dopisz test: czy Twoja polityka go przepuszcza? Jeśli tak, to z dobrego powodu czy przypadkiem?

## Gdy coś nie działa

| Objaw | Co zrobić |
|---|---|
| `kyverno: command not found` | instalacja z tabeli w „Zanim zaczniesz” |
| `kyverno apply` z `--cluster`: błąd uprawnień albo timeout | `kubectl get pods` działa? Jeśli nie, zgłoś prowadzącemu swój adres IP |
| `kyverno apply` na pliku z `kubectl get … -o yaml` kończy się stack trace'em | CLI nie czyta obiektu `List`. Użyj `--cluster` albo zapisz zasoby jako osobne dokumenty YAML |
| `kyverno test`: `no policies found` albo `resource not found` | ścieżki w `kyverno-test.yaml` są względem katalogu `lab04b/`, nie korzenia repo |
| `kyverno apply` pokazuje `error: 1` zamiast `fail: 1` | wyrażenie CEL wywróciło się na tym obrazie (np. `image(...)` albo `messageExpression`). To nie jest odrzucenie z komunikatem. Wklej wynik agentowi i poproś o poprawkę |
| AI dało `kind: ClusterPolicy` | działa w 1.19, ale jest przestarzałe. Poproś o `ValidatingPolicy` i podaj wersję |
