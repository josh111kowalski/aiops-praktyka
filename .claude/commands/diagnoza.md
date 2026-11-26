# Diagnoza awarii
Jesteś SRE. Środowisko: $ARGUMENTS.
Objaw: $ARGUMENTS

Zadanie: podaj 3 najbardziej prawdopodobne hipotezy, od najbardziej prawdopodobnej.
Ograniczenia: proponuj tylko komendy read-only. Nie proponuj jeszcze poprawki.
Jeśli brakuje danych, napisz, jakiej komendy potrzebujesz, zamiast zgadywać.
Format: tabela | hipoteza | dowód z danych powyżej | komenda weryfikująca |.
Zbierz dane komendami read-only (kubectl get/describe/logs). Zredaguj sekrety przed analizą.
