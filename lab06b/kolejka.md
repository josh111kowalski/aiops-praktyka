# Kolejka napraw: pierwsze 3 podatności

Źródło: `lab06b/wynik.json` (Trivy). Kontekst: orders-api jest wystawione do internetu przez ALB i nie ma uwierzytelnienia; payments to serwis wewnętrzny.

| # | ID | Pakiet | Zainstalowana | Z poprawką | Dlaczego ta |
|---|----|--------|---------------|------------|-------------|
| 1 | GHSA-6q48-6c7w-9gw2 (CRITICAL) | certifi (orders-api/uv.lock) | 2026.7.22 | 2026.10.18 | To jedyna podatność CRITICAL w wyniku: ktoś, kto ma skompromitowany klucz CA i jest na ścieżce ruchu, może podsłuchać lub zmienić ruch TLS wychodzący z orders-api. |
| 2 | CVE-2026-54283 (HIGH) | starlette (orders-api/uv.lock) | 0.41.3 | 1.3.1 | Atakujący bez logowania może wyczerpać zasoby API wystawionego do internetu, bo limity `request.form()` nie działają dla `application/x-www-form-urlencoded`; 1.3.1 to też najwyższa wersja z poprawką dla starlette w pliku. |
| 3 | CVE-2025-62727 (HIGH) | starlette (orders-api/uv.lock) | 0.41.3 | 0.49.1 | Druga podatność HIGH typu DoS bez uwierzytelnienia (CVSS 7.5): spreparowany nagłówek `Range` zużywa CPU w odpowiedziach z plikami (`FileResponse`/`StaticFiles`). |

## Uwagi

- **certifi:** w polu `FixedVersion` jest 2026.10.18, ale opis zaleca **2026.10.19 lub nowszą**, bo 2026.10.18 usunęła wszystkie korzenie emSign, a 2026.10.19 przywróciła te, których problem nie dotyczy. Po aktualizacji trzeba przebudować obraz.
- **starlette:** podniesienie do 1.3.1 zamyka wszystkie 7 podatności starlette z pliku, czyli także CVE-2026-48818, CVE-2025-54121, CVE-2026-48710, CVE-2026-48817 i CVE-2026-54282. W praktyce pozycje 2 i 3 to jedna zmiana.
- **Później:** CVE-2026-63209 (github.com/klauspost/compress v1.17.9 → 1.18.7, HIGH) dotyczy payments, który nie jest dostępny z internetu. CVE-2026-39824 (golang.org/x/sys v0.22.0 → 0.44.0) dotyczy kodu `golang.org/x/sys/windows`, a serwis działa na Linuksie. Dwie podatności opentelemetry-api (1.29.0 → 1.45.1 / 1.45.2) mają poziom MEDIUM.
