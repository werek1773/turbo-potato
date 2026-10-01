# Plan: aplikacja do boulderingu (MVP dla Volt Łódź)
_Uzgodnione z właścicielem projektu, 2026-09-30._

**Ustalenia bazowe:** Supabase: projekt **„Wspinaczka 2”** (`afmppshzdkljlgzokdam`, Frankfurt) · bundle ID `wspinaczka.app` · minimalna wersja **iOS 26** (funkcje iOS 27 za `#available`) ·
skala Volta: **liczby 1–9** · UI po polsku (przygotowane pod tłumaczenia).

## Cel

Natywna aplikacja iOS, w której **ścianka publikuje swoje problemy**, a **wspinacze
podsumowują sesje po wyjściu ze ściany** — bez klikania w telefon w trakcie wspinania.
Pierwsza działająca wersja powstaje dla **Volt Łódź** (manager: Kasia), ale model danych
od początku obsługuje wiele ścianek, bo docelowo aplikacja będzie sprzedawana ściankom.
Główną wartością dla ścianki są **anonimowe, zbiorcze statystyki** (wycena społeczności,
popularność, odsetek przejść); dla wspinacza — **katalog z filtrami, szybkie podsumowanie
sesji i statystyki postępów / słabych stron**.

## Kluczowa obserwacja produktowa

Na ściance nikt nie używa telefonu — ludzie są offline i rozmawiają, telefon wyjmują
po wyjściu. Dlatego **głównym ekranem jest „Podsumuj sesję”** (z pamięci, < 60 s),
a nie logowanie w trakcie. Nie ma przycisku „Próba” ani „Start sesji”.

## Stos technologiczny

| Warstwa | Wybór |
|---|---|
| Aplikacja | Swift 6 (strict concurrency), SwiftUI (Liquid Glass); deployment target **iOS 26**, funkcje iOS 27 za `#available`; bundle ID `wspinaczka.app`; lokalnie: **outbox** oczekujących zapisów (Codable) + cache — idempotentne upserty |
| Backend | **Supabase (region UE)**: Postgres + Row Level Security, Auth (Sign in with Apple), Storage (zdjęcia sektorów), **Edge Functions** (wymiana/revoke tokenu Apple, usuwanie konta) |
| Projekt Xcode | generowany z `project.yml` przez **XcodeGen** (brak ręcznie edytowanego `.pbxproj`) |
| Logika domenowa | lokalny Swift Package `BoulderKit` bez zależności od UI — testowalny również poza Xcode |
| CI | GitHub Actions: `macos` (xcodegen + xcodebuild build/test), `ubuntu` (Supabase CLI + testy pgTAP dla RLS) |

Kod piszę w środowisku bez Xcode — kompilacja na MacBooku właściciela i w CI na macOS.

## Role i uprawnienia

| Rola | Zakres | Kto (Volt) | Uprawnienia |
|---|---|---|---|
| Admin platformy | globalna (tabela `platform_admins`) | właściciel projektu | tworzy ścianki, wyznacza managerów |
| Manager | per ścianka | Kasia | sektory, skala wycen, geofence, zaprasza/odbiera routesetterów, widzi statystyki ścianki |
| Routesetter | per ścianka | zaproszeni przez managera | dodaje/edytuje/zdejmuje problemy, przekręca sektory, widzi statystyki ścianki |
| Wspinacz | każdy zalogowany | klienci | przegląda publiczne ścianki, prywatny dziennik i sesje |

- Role per ścianka w tabeli `gym_memberships (gym_id, user_id, role)`.
- **Uprawnienia egzekwowane w bazie (RLS)**, nie tylko w aplikacji.
- **Admin w osobnej tabeli `platform_admins` bez żadnych polityk dla klienta** — nie da się go nadać
  przez API (nie może być kolumną w `profiles`, którą użytkownik edytuje).
- **Brak bezpośrednich zapisów do `gym_memberships`** — wyłącznie RPC z hierarchią ról:
  managera nadaje tylko admin platformy; manager nadaje/odbiera routesetterów; nie da się usunąć
  ostatniego managera; akceptacja zaproszenia nigdy nie obniża istniejącej roli.
- Zaproszenia: manager generuje zaproszenie (rola routesetter) → **kod (10+ znaków, jednorazowy
  domyślnie, ważny 7 dni) + link** `schemat://invite?code=…`; akceptacja przez `accept_invite(code)`
  z atomowym `UPDATE … WHERE used_count < max_uses AND revoked_at IS NULL AND expires_at > now() RETURNING`
  i limitem prób na użytkownika. Universal Links dopiero gdy będzie domena.
- Zasady dla funkcji security definer: helpery (`has_gym_role`) w prywatnym schemacie,
  `SET search_path = ''`, `REVOKE EXECUTE FROM public, anon`, sprawdzenie `auth.uid()` i roli w każdej RPC.

## Model danych (Supabase)

Wszystkie klucze główne to UUID; tabele zapisywane offline mają **UUID generowane w aplikacji** (idempotencja).
Odwołania w obrębie ścianki / użytkownika przez **złożone klucze obce** (np. `(sector_id, gym_id) → sectors(id, gym_id)`,
`(session_id, user_id) → sessions(id, user_id)`), żeby nie dało się wskazać cudzych wierszy mimo RLS.

- `profiles` — id (= auth.users), display_name, created_at (prywatne; innym widoczny tylko widok `public_profiles(id, display_name)`
  ograniczony do osób ze wspólnej ścianki)
- `user_consents` — stats_opt_out, health_data_consent (+ daty)
- `platform_admins` — user_id (bez polityk dla klienta)
- `gyms` — name, slug, city, **timezone**, lat, lng, geofence_radius_m (min. 150 m), active_grade_scale_id
- `grade_scales`, `grades` — **własna skala ścianki** (Volt: liczby **1–9**, na wzór V-scale):
  label, sort_order, `v_equivalent` (opcjonalne — potrzebne dopiero do porównań między ściankami), opcjonalny kolor;
  **wyceny są niezmienne** (tylko dezaktywacja); statystyki w obrębie ścianki po `sort_order`
- `gym_memberships` — gym_id, user_id, role (`manager` | `routesetter`), granted_by
- `invites` — gym_id, role, code_hash, created_by, expires_at, max_uses, used_count, revoked_at
- `sectors` — gym_id, name, sort_order, current_photo_id, last_reset_at, archived_at
- `sector_photos` — sector_id, storage_path, width, height, taken_at, created_by
- `sector_resets` — sector_id, photo_id, reset_at, created_by, note (oś czasu przykrętek)
- `problems` — gym_id, sector_id (bieżący), grade_id, hold_color, style_tags[] (przewieszenie/pion/płyta,
  krawądki/oblaki/szczypy, dynamiczny/statyczny…), set_by, set_at, reset_id, removed_at, removed_reset_id
- `problem_placements` — problem_id, photo_id, **pin_x, pin_y** (0…1) — pinezka per zdjęcie,
  więc archiwum każdej przykrętki zachowuje swoje pinezki także dla problemów, które przetrwały
- `problem_grade_history` — zmiany wyceny problemu (przejście zapamiętuje wycenę z chwili przejścia)
- `problem_holds` — **tabela na etap 2** (builder chwytów); tworzona później, bez zmian w `problems`
- `sessions` (prywatne) — user_id, gym_id, **local_date** (dzień wg strefy ścianki, granica doby 04:00),
  started_at, ended_at, source (`geofence` | `manual`), unikalne `(user_id, gym_id, local_date)`
- `session_wellbeing` (prywatne, **tylko przy osobnej zgodzie na dane zdrowotne**) — session_id,
  energy (1–5), rpe (1–10), skin, pain_areas[], note
- `ascents` (prywatne wiersze) — id z aplikacji, user_id, problem_id, session_id, grade_id_snapshot,
  result (`flash` | `top` | `project`), attempts_bucket (`1` | `2-3` | `4-10` | `10+` | null),
  perceived_grade (`soft` | `ok` | `hard` | null), limiters[] (**zamknięty, niemedyczny** zbiór tagów), note;
  **unikalne `(session_id, problem_id)`** — tap na pinezce to zmiana stanu (upsert), „brak” = usunięcie;
  flash dozwolony tylko, gdy nie ma wcześniejszego przejścia tego problemu;
  przejście na zdjętym problemie przyjmowane, jeśli data sesji ≤ data zdjęcia problemu

Storage: bucket `sector-photos` — odczyt publiczny bez listowania, **tylko INSERT** (bez UPDATE/DELETE)
dla managera/routesettera ścianki z `gym_id` w ścieżce `gym_id/sector_id/uuid.jpg`; RPC sprawdza, że sektor
należy do tej ścianki; limit typu (JPEG/HEIC) i rozmiaru; **EXIF (GPS) usuwany w aplikacji** przed wysłaniem;
okresowe sprzątanie osieroconych plików.

### Przekręcenie sektora (jedna akcja)
1. Routesetter robi nowe zdjęcie → `sector_photos` + `sector_resets`.
2. Wybiera problemy do zdjęcia (domyślnie wszystkie aktywne) → `removed_at`, `removed_reset_id`.
3. Problemy, które zostają, dostają **nowy wiersz `problem_placements`** na nowym zdjęciu (te same współrzędne,
   do poprawienia przeciągnięciem) — stare pinezki zostają w archiwum.
4. Dodaje nowe pinezki. Archiwalne zdjęcie + problemy danej przykrętki pozostają przeglądalne.
Całość w jednej RPC `reset_sector(sector_id, expected_current_photo_id, …)` z `SELECT … FOR UPDATE`
na sektorze — równoległa przykrętka lub dodanie pinezki do starego zdjęcia zostaje odrzucone.

### Prywatność i dane dla ścianki
- `sessions`, `session_wellbeing`, `ascents`: RLS — **wiersz widzi tylko właściciel**.
- Statystyki ścianki to **gotowe migawki liczone raz na dobę z kilkudniowym opóźnieniem**
  (tabela `problem_stats_snapshot`), bez parametrów zapytania (daty/sektor) — nie da się
  „odejmować” wyników przed i po czyjejś wizycie.
- **k ≥ 5 dla każdej wyświetlanej komórki** (np. każdy kubełek perceived_grade / limitera osobno),
  z tłumieniem uzupełniającym; liczby zaokrąglane (np. do 5).
- Podstawa prawna: dane o problemach (nie zdrowotne) — **prawnie uzasadniony interes z możliwością
  wypisania się** (`stats_opt_out`); przy opt-in w jednej ściance k ≥ 5 byłoby rzadko osiągane.
- **Samopoczucie, ból, skóra, notatki — nigdy nie trafiają do ścianki**; zapisywane tylko po
  **osobnej, wyraźnej zgodzie** na dane o zdrowiu (art. 9 RODO).
- **Usunięcie konta w aplikacji** (wymóg App Store 5.1.1(v)): Edge Function — revoke tokenu Apple
  (`appleid.apple.com/auth/revoke`; przy logowaniu `authorizationCode` wymieniany w Edge Function
  na refresh token, przechowywany po stronie serwera) + `auth.admin.deleteUser`.
  Klucze obce: `ON DELETE CASCADE` dla danych użytkownika (sesje, przejścia, członkostwa),
  `ON DELETE SET NULL` dla autorstwa (set_by, created_by, granted_by) — katalog ścianki zostaje.
- **Eksport danych** (art. 15/20) — RPC zwracająca JSON z danymi użytkownika.
- Etykiety prywatności App Store: lokalizacja, zdrowie i fitness, identyfikatory.

## Kluczowe przepływy w aplikacji

1. **Logowanie** — Sign in with Apple → profil → wybór ścianki (Volt).
2. **Katalog** — lista sektorów ze zdjęciami i pinezkami; filtry łączone: wycena/zakres,
   sektor, kolor, „niezrobione przeze mnie”, „nowe od mojej ostatniej wizyty”;
   licznik pokrycia („4: 7 z 12 aktywnych”).
3. **Podsumuj sesję** (główny ekran) — zdjęcia sektorów, tap na pinezkę cyklicznie:
   brak → top → flash → projekt; na górze nowe problemy i typowy zakres wycen;
   dla projektów tagi „co zatrzymało”; na końcu energia, RPE, skóra, ból. Cel < 60 s.
   Można uzupełnić sesję z poprzednich dni.
4. **Automatyczne sesje** — sesja = (ścianka, dzień lokalny wg strefy ścianki, granica doby 04:00).
   Ekran podsumowania zawsze pracuje „na sesji” (domyślnie dziś / wykryta wizyta; można wybrać
   wcześniejszy dzień), a przejścia dziedziczą jej datę — czas kliknięcia w tramwaju nie ma znaczenia.
   Serwer scala duplikaty (geofence + ręczna, dwa urządzenia) dzięki unikalności `(user, gym, local_date)`.
5. **Wykrywanie wizyty** — `CLMonitor` z okręgiem ≥ 150 m (zgoda „Zawsze”, dwuetapowa; osobna zgoda
   na powiadomienia; `CLServiceSession`); monitor odtwarzany i zdarzenia konsumowane od razu przy
   starcie aplikacji; czasy wejścia/wyjścia zapisywane lokalnie, wyjście z opóźnieniem ~5 min
   (odszumianie), powiadomienie po pobycie > 20 min. Monitorowane max ~15 ulubionych ścianek,
   nakładające się obszary rozstrzyga najbliższy środek. **Bez `UIBackgroundModes: location`**.
   Wyłączenie powiadomień per ścianka (routesetterzy w pracy). Przy przybliżonej lokalizacji
   lub braku zgody — ręczne „Podsumuj dzisiejszą sesję”. Żadnej trasy nie zapisujemy.
6. **Narzędzia routesettera** — dodaj problem (tap na zdjęciu → kolor → wycena → opcjonalne tagi),
   edytuj, zdejmij, przekręć sektor, archiwum przykrętek.
7. **Manager** — sektory, skala wycen, geofence, zaproszenia, lista osób z rolami.
8. **Statystyki wspinacza** — piramida wycen (flash/top), pokrycie ścianki, kalendarz sesji
   i seria tygodni, prosty profil słabych stron (udział limiterów w ostatnich 6 tyg.).
9. **Statystyki ścianki** — wycena społeczności, popularność, odsetek przejść, problemy
   z najczęstszymi limiterami (migawka dobowa, k ≥ 5).
10. **Konto** — zgody (statystyki, dane zdrowotne), eksport danych, usunięcie konta.

## Struktura repozytorium

```
ios/
  project.yml              # XcodeGen
  App/                     # SwiftUI: widoki, nawigacja, integracje (Auth, CLMonitor, powiadomienia)
  Packages/BoulderKit/     # domena: grupowanie sesji, statystyki, skale wycen, filtry + testy
supabase/
  config.toml
  migrations/              # schemat, RLS, funkcje RPC
  tests/                   # pgTAP — testy uprawnień
  seed.sql                 # dane testowe (Volt, przykładowe sektory)
.github/workflows/         # ios.yml, supabase.yml
PLAN.md
```

## Kolejność realizacji (etap 1 = MVP)

1. **Backend**: migracje (schemat, RLS, RPC: role, accept_invite, reset_sector, statystyki-migawki, eksport),
   Edge Functions (Apple token, delete-account), testy pgTAP **w tym testy ataków** (eskalacja roli,
   cudze wiersze, podrobione zaproszenia), seed.
2. **Szkielet iOS**: XcodeGen, BoulderKit, klient Supabase, Sign in with Apple, CI.
3. **Katalog**: sektory, zdjęcia z pinezkami, filtry, pokrycie.
4. **Routesetter + manager**: dodawanie problemów, przekręcanie, archiwum, zaproszenia, skala.
5. **Podsumuj sesję**: ascents, automatyczne sesje, samopoczucie, kolejka offline.
6. **Geofence + powiadomienia**.
7. **Statystyki**: wspinacza i ścianki.
8. **TestFlight** dla Kasi i routesetterów → wprowadzenie danych Volta → klienci.

## Etap 2 i dalej (poza MVP)

- Timer treningowy (tabata, hangboard, 4x4, własne interwały) + Live Activity,
  **powiązany z profilem słabych stron** (rekomendacje protokołów).
- Builder chwytów (`problem_holds`), wygodny na iPadzie z Apple Pencil.
- Komentarze i oceny problemów (społeczność).
- HealthKit (zapis treningu „wspinaczka”), Apple Watch (tętno, docelowo auto-liczenie podejść).
- Widżety, podsumowania sesji przez on-device Foundation Models.
- Kolejne ścianki, panel webowy dla managerów, Android.

## Kluczowe decyzje i kompromisy

- **Supabase zamiast CloudKit** — role per ścianka, panel web i Android w przyszłości.
- **Pinezka na zdjęciu sektora zamiast zaznaczania chwytów** — koszt dla routesetterów przy przykrętkach.
- **Logowanie po sesji zamiast w trakcie** — zgodne z tym, jak ludzie naprawdę się wspinają;
  liczba prób tylko orientacyjna (koszyki).
- **Timer poza MVP** — wyróżnikiem jest katalog + podsumowanie + statystyki dla ścianki.
- **Anonimowość k ≥ 5** dla statystyk ścianki; dane zdrowotne zawsze prywatne.
- **Kody zaproszeń + custom URL scheme** zamiast Universal Links (brak domeny na start).
- **Statystyki ścianki jako dobowe migawki**, nie zapytania na żywo — prywatność kosztem świeżości.
- **Outbox + idempotentne upserty zamiast synchronizacji SwiftData** — prostsze pod Swift 6.

## Ryzyka / otwarte kwestie

- **Brak Xcode w środowisku Claude** — błędy kompilacji wychodzą dopiero w CI/na Macu.
- **Nowości iOS 27** mogą być słabo znane Claude — bazą są stabilne API z iOS 26.
- **Geofence w budynku jest nieprecyzyjny** (opóźnione/zaszumione wyjścia) — stąd odszumianie
  i ręczna ścieżka jako pełnoprawna.
- **Zgoda „Zawsze” na lokalizację** — część osób odmówi; ręczne podsumowanie musi być równie wygodne.
- **Adopcja przez klientów** — bez wprowadzonych problemów aplikacja jest pusta; routesetterzy muszą to robić
  przy każdej przykrętce (dlatego dodanie problemu < 15 s).
- **RODO** — administratorem danych jest właściciel projektu; potrzebna polityka prywatności,
  prawdopodobnie ocena skutków (DPIA) dla danych zdrowotnych, umowa powierzenia z Supabase,
  zgoda Volta na publikację zdjęć ściany; zdjęcia bez klientów na ścianie.
- **Plan Supabase** — darmowy plan wystarcza do testów; przed klientami rozważyć płatny (backupy, brak pauzowania).
- Do ustalenia: wyświetlana nazwa aplikacji, sektory Volta (zdjęcia od właściciela).

## Poza zakresem MVP

Timer, builder chwytów, komentarze, HealthKit/Watch, widżety, AI, wiele ścianek w praktyce
(model danych je obsługuje), panel web, Android, płatności.
