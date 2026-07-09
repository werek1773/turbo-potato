# turbo-potato

GitHubowy system współpracy trzech profili modeli:

| Profil | Rola |
| --- | --- |
| Fable 5 | planowanie, specyfikacje i końcowy advisor |
| GPT 5.6 SOL | główne kodowanie złożonych lub ryzykownych zmian |
| GLM 5.2 w VS Code | tanie, powtarzalne i łatwo weryfikowalne zadania masowe |

Codex może wykonywać Deep Research z aktualnych źródeł, a wyniki przekazuje
Fable do planowania. Nazwy modeli są profilami użytkownika; repozytorium nie
narzuca ani nie zgaduje identyfikatorów API.

## Przepływ

1. `fable-wayfinder` tworzy mapę decyzji w GitHub Issues.
2. `codex-research` zbiera źródła dla pytań badawczych.
3. `fable-to-spec` tworzy specyfikację.
4. `fable-to-tickets` dzieli ją na małe zadania.
5. `model-router` kieruje trudne zadania do GPT, a bezpieczne masowe zadania do GLM.
6. `gpt-code` albo `glm-batch` wykonuje zadanie.
7. `fable-advisor` ocenia plan, Pull Request, przebieg batcha i wynik końcowy.

Duże batche GLM są idempotentne, checkpointowane i wznawialne. Mają canary,
limity kosztu i współbieżności, maksymalnie dwie automatyczne próby, dead-letter
queue oraz automatyczny awans trudnych przypadków do GPT.

## Zawartość

- [`AGENTS.md`](AGENTS.md) — obowiązująca hierarchia i twarde reguły;
- [skills](grill-me-codex-main/skills) — role i procedury dla modeli;
- [Issue templates](.github/ISSUE_TEMPLATE) — mapa, decyzje i routed execution;
- [Pull Request template](.github/pull_request_template.md) — dowody wykonania i ocena Fable;
- [oryginalny pakiet grill-me-codex](grill-me-codex-main/README.md) — wcześniejsze skills zachowane bez zmian.

## VS Code i GLM

GLM 5.2 działa jako tani wykonawca w VS Code. Przed pracą powinien otrzymać
`AGENTS.md`, konkretny GitHub Issue oraz instrukcję `glm-batch/SKILL.md`.
Nie dostaje zadań wymagających decyzji architektonicznych, dostępu do sekretów,
migracji, płatności, uprawnień ani operacji destrukcyjnych.

## Inspiracja i modyfikacje

Mechanika Wayfindera, specyfikacji i małych tickets została zaadaptowana z
[skills Matta Pococka](https://github.com/mattpocock/skills) oraz omówionego
[filmu o wersji 1.1](https://www.youtube.com/watch?v=A8mokin_YOs). Ten wariant
zmienia hierarchię modeli i dodaje routing kosztowy, canary, checkpointy,
dead-letter queue oraz awans GLM → GPT. Są to świadome modyfikacje dla Twojego
układu, a nie bezkrytyczna kopia zaleceń z filmu.
