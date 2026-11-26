#!/usr/bin/env bash
# lab03c: wrzuca na main rolę CI (infra/ci-oidc/main.tf) i otwiera PR, który ją zmienia.
# Uruchom z katalogu głównego forka, z GH_REPO ustawionym na fork.
set -euo pipefail

LAB="$(cd "$(dirname "$0")" && pwd)"
BRANCH="ci-release-refs"

[ -n "${GH_REPO:-}" ] || { echo "Ustaw GH_REPO=<Twój GitHub>/aiops-praktyka"; exit 1; }
[ "$(gh repo view --json nameWithOwner -q .nameWithOwner)" = "$GH_REPO" ] || { echo "gh nie wskazuje na $GH_REPO"; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "Masz niezacommitowane zmiany. Zrób commit albo git stash."; exit 1; }

git switch main
git pull --ff-only

mkdir -p infra/ci-oidc
cp "$LAB/pliki/main/main.tf" infra/ci-oidc/main.tf
git add infra/ci-oidc/main.tf
git commit -m "infra: rola CI przez OIDC (tylko main)" || echo "(rola już jest na main)"
git push origin main

git switch -C "$BRANCH"
cp "$LAB/pliki/zmiana/main.tf" infra/ci-oidc/main.tf
git commit -am "ci: deploy także z gałęzi release/*"
git push -u --force origin "$BRANCH"

BODY="$(mktemp)"
cat > "$BODY" <<'EOF'
## Co
- dopuszczam wdrożenia z gałęzi `release/*` (lista gałęzi w `local.deploy_refs`)
- upraszczam dopasowanie nowego formatu `sub` z ID repo: wcześniej każdą gałąź trzeba było wpisywać dwa razy
- `max_session_duration` 2 h: build release'u z testami e2e nie mieści się w godzinie
- tagi na roli

## Dlaczego
Release 2.0 budujemy z `release/2.0`, a pipeline dostaje teraz `AccessDenied` przy `AssumeRoleWithWebIdentity`.

## Ryzyko
Uprawnienia roli bez zmian (ECR i `eks:DescribeCluster`). Zmienia się tylko lista gałęzi w trust policy.
EOF
gh pr create --base main --head "$BRANCH" \
  --title "ci: deploy także z gałęzi release/*" --body-file "$BODY"
rm -f "$BODY"

git switch main
gh pr list
