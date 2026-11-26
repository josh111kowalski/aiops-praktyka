## Różnice
### Element: Namespace
- zly.yaml (z ogólnego promptu): brak
- dobry.yaml (z kontekstu): jacek

## Element: Połączenie z bazą
- zly.yaml (z ogólnego promptu): osobne zmienne DB_HOST=postgres, DB_PORT…
- dobry.yaml (z kontekstu): DATABASE_URL → kantyna-postgres:5432/kantyna

## Element: Flagi (mountPath)
- zly.yaml (z ogólnego promptu): brak montowania
- dobry.yaml (z kontekstu): /etc/kantyna/flags