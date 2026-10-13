# Wspinaczka

Natywna aplikacja iOS do boulderingu: ścianka publikuje problemy (pinezki na zdjęciach sektorów),
a wspinacze podsumowują sesje po wyjściu ze ściany. Pierwsze wdrożenie: **VOLT Boulderownia Łódź**.

Specyfikacja i kolejność prac: [`PLAN.md`](PLAN.md).

## Backend (Supabase)

Projekt Supabase **Wspinaczka 2** (`afmppshzdkljlgzokdam`, region eu-central-1).

| Ścieżka | Zawartość |
|---|---|
| `supabase/migrations/` | schemat, RLS, funkcje RPC, Volt Łódź (wyceny 1–9) |
| `supabase/tests/` | testy pgTAP: uprawnienia, zaproszenia, przykrętki, dziennik, statystyki |
| `supabase/functions/delete-account/` | usuwanie konta + unieważnienie Sign in with Apple |
| `scripts/local-db/test.sh` | migracje + testy na lokalnym Postgresie (bez Dockera) |

Testy:

```bash
# z Dockerem (pełny Supabase)
supabase db start && supabase test db

# bez Dockera (Postgres 16 + pgTAP)
scripts/local-db/test.sh
```

## Aplikacja iOS

| Ścieżka | Zawartość |
|---|---|
| `ios/project.yml` | definicja projektu Xcode (XcodeGen), iOS 26+, bundle ID `wspinaczka.app` |
| `ios/Wspinaczka/` | SwiftUI: logowanie przez Apple, katalog ścianki, profil, zaproszenia |
| `ios/Packages/BoulderKit/` | logika domenowa (dzień wspinaczkowy, filtry, pokrycie, statystyki) + testy |

Pierwsze uruchomienie na Macu:

```bash
brew install xcodegen
cd ios
echo "DEVELOPMENT_TEAM = TWOJ_TEAM_ID" > Config/Local.xcconfig   # Xcode → Settings → Accounts
xcodegen generate
open Wspinaczka.xcodeproj
```

Po każdym `git pull`, który zmienia `project.yml` lub dodaje pliki, uruchom ponownie `xcodegen generate`.

### Przypomnienie po wizycie (wykrywanie wizyty)

`ios/Wspinaczka/Features/Visits/` — opcjonalne (Profil → Przypomnienie po wizycie). `CLMonitor` obserwuje
okręgi (≥ 150 m) wokół najwyżej 15 ścianek; po wyjściu po pobycie > 20 min (z odszumianiem ~5 min) przychodzi
lokalne powiadomienie, które otwiera podsumowanie tej ścianki i tego dnia (`wspinaczka://session?gym=…&day=…`).
Zgoda „Zawsze” jest proszona dwuetapowo, po ekranie wyjaśnienia; bez niej (lub przy przybliżonej lokalizacji)
zostaje ręczne podsumowanie. Brak `UIBackgroundModes: location`.

**Prywatność:** aplikacja nie zapisuje położenia ani trasy — system zgłasza tylko wejście do okręgu i wyjście
z niego. Godziny wizyt są przechowywane wyłącznie lokalnie (`Application Support/gym-visits.json`, maks. 60 dni)
i nie trafiają na serwer ani do ścianki; wyłączenie funkcji je usuwa. Dane, które nie opuszczają telefonu,
nie są „zbierane” w rozumieniu etykiet prywatności App Store.
