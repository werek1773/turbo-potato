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
