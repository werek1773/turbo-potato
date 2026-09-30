# Plan Review Log: aplikacja do boulderingu (MVP Volt Łódź)

Act 1 (grill) zakończony — plan uzgodniony z właścicielem projektu (10 pytań).
Act 2: Codex CLI niedostępny w tym środowisku — recenzję krytyczną wykonał osobny agent Claude
(ten sam dostawca modelu, więc to słabsza forma niezależnej weryfikacji niż w oryginalnym skillu).

## Runda 1 — VERDICT: REVISE

Najważniejsze zarzuty i reakcja:

| # | Zarzut | Zmiana w planie |
|---|---|---|
| 1 | `is_platform_admin` w `profiles` → każdy może się nadać admina przez API | osobna tabela `platform_admins` bez polityk klienta |
| 2 | Brak usuwania konta + revoke tokenu Apple (odrzucenie w App Store) | Edge Function delete-account + wymiana `authorizationCode` |
| 3 | Klucze obce blokują usunięcie konta / kasują katalog | CASCADE dla danych użytkownika, SET NULL dla autorstwa, eksport danych |
| 4 | Dane zdrowotne (art. 9 RODO), limitery mogą je przemycać | osobna zgoda, `session_wellbeing`, zamknięty niemedyczny zbiór limiterów, region UE |
| 5 | k ≥ 5 do obejścia (różnicowanie, małe komórki, parametry) | dobowe migawki z opóźnieniem, k per komórka, zaokrąglanie, brak parametrów |
| 6 | Pułapki security definer | prywatny schemat, `search_path=''`, REVOKE z public/anon, kontrola roli w RPC |
| 7 | Nadużycia zaproszeń (brute force, wyścig, eskalacja) | dłuższe jednorazowe kody, atomowy UPDATE, limit prób, managera nadaje tylko admin |
| 8 | Bezpośrednie zapisy do `gym_memberships` | tylko RPC z hierarchią ról, ochrona ostatniego managera |
| 9 | Odwołania do cudzych wierszy mimo RLS | złożone klucze obce |
| 10 | Dziury w Storage | tylko INSERT, walidacja ścieżki, limity, usuwanie EXIF |
| 11 | Przesuwanie pinezek niszczy archiwum | `problem_placements` per zdjęcie |
| 12 | Równoległe przykrętki | `reset_sector` z `expected_current_photo_id` + `FOR UPDATE` |
| 13 | Duplikaty z kolejki offline, cykl tapów | UUID z aplikacji, unikalne `(session_id, problem_id)`, upsert/usunięcie |
| 14 | Grupowanie sesji (strefa czasu, północ, logowanie po fakcie) | `gyms.timezone`, `local_date` z granicą 04:00, sesja jako kontener ekranu podsumowania |
| 15 | Zmiany skali wycen | wyceny niezmienne, `v_equivalent`, snapshot wyceny w przejściu, historia wycen |
| 16–17 | Założenia o CLMonitor, App Review lokalizacji | promień ≥ 150 m, odszumianie, bez background mode, max ~15 ścianek, opt-out powiadomień |
| 18 | Widoczność profili | widok `public_profiles` |
| 19 | Target iOS 27 vs CI i klienci | rekomendacja iOS 26 + `#available` — **decyzja właściciela** |
| 20 | SwiftData + Swift 6 do synchronizacji | outbox + idempotentne upserty; opt-out zamiast opt-in dla statystyk niezdrowotnych |

Status: poprawki wprowadzone; czeka na decyzję właściciela (pkt 19) i brakujące dane (nazwa, skala Volta, sektory).
