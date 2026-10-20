# Проверка проекта

Из корня репозитория:

```sh
Scripts/validate.sh fast
Scripts/validate.sh full --fresh
```

Скрипт также работает по абсолютному пути из любого рабочего каталога. Относительные
пути опций разрешаются относительно каталога вызывающего процесса.

Требуются полный Xcode, `xcodebuild`, `xcrun`, `jq`, `xmllint` и стандартные macOS
utilities. Скрипт проверяет shared scheme и effective settings Debug/Release,
Simulator SDK, точный minimum-supported runtime и доступный simulator в нём.
Baseline берётся из project settings. При отсутствии prerequisites проверка
завершается ошибкой; runtime и simulator автоматически не устанавливаются.

## Режимы

- `fast`: app build и четыре suites: `FeedRSSParserTests`, `FeedAtomParserTests`
  (синтетические RSS/Atom fixtures), `ArticleRetentionContractTests` (правила
  хранения), `AppResourceBudgetContractTests` (лимиты входных данных). Это быстрая
  выборка, не полная регрессия: persistence, sync, image runtime, большие query
  fixtures и UI сюда не входят. Xcode всё равно компилирует test target целиком.
- `full`: `clean build`, затем весь `RSSReaderTests`. Последовательность tests
  задаёт shared scheme; скрипт не включает parallel testing.

Оба режима по умолчанию используют свежий отдельный DerivedData. Для повторной
incremental проверки можно передать `--derived-data PATH`: новый каталог получит
маркер владения, существующий принимается только с маркером этого checkout.
`--fresh` явно закрепляет fresh baseline и несовместим с `--derived-data`.
`full` очищает build products только в выбранном script-owned DerivedData.
Скрипт не делает автоматический clean/retry после ошибки `fast`.

## Окружение и результаты

```sh
Scripts/validate.sh full --developer-dir /Applications/Xcode.app/Contents/Developer \
  --destination 'platform=iOS Simulator,name=<AVAILABLE_NAME>,OS=<VERSION>' \
  --artifacts-dir /tmp/rssreader-validation
```

По умолчанию Xcode выбирается через `DEVELOPER_DIR` / `xcode-select`. Destination
выбирается из доступных устройств точного minimum runtime, стабильно по UUID.
Явный destination разрешает Xcode; нужны конкретный iOS Simulator и совместимый
runtime. Более новый destination не заменяет отдельную minimum-runtime проверку.

Каждый запуск создаёт уникальный `RSSReader-validation-<mode>.*` внутри указанного
родительского каталога или `TMPDIR`. Каталог печатается до проверки Xcode и при
завершении. Артефакты не удаляются автоматически и не предназначены для Git:

- `commands.sh`, `context.json`, toolchain/settings/simulator logs;
- исходные stdout `build.log`, `tests.log`, отдельные phase-specific `.stderr.log`
  и `.exit-status` (diagnostics не смешиваются с JSON/SDK stdout);
- `Tests.xcresult`, если Xcode успел его создать;
- `summary.log`, `test-tree.log` — JSON от `xcresulttool`;
- `report.json` — passed/failed/skipped/expected failures, executed и cases без
  результата; `exit-status.txt` — итоговый статус скрипта.

Верхние счётчики report соответствуют test definitions из Xcode summary.
`runs` отдельно сохраняет счётчики запусков по device/configuration: при
параметризованных тестах их больше. Поиск cases без результата включает
`Test Case`, варианты `Arguments` и `Test Case Run` в дереве отчёта.

Ошибка аргументов или preflight даёт ненулевой статус. Ошибка внешней команды
сохраняет её статус, в частности build/test failure не скрывается обработкой
логов. При test failure скрипт всё равно пытается извлечь `.xcresult`.
Ноль выполненных тестов, cases без результата и неполный/неуспешный отчёт
не считаются успехом (report gate: exit 3). Expected failures отражаются отдельно.
Skipped tests перечислены счётчиком; успешный run не означает, что они проверены.

## UI и границы проверки

`fast` и `full` запускают только unit tests. После добавления UI smoke в #720
включать его явно: `--ui-smoke-target <ACTUAL_TARGET_NAME>`. Target должен быть
включён в shared scheme; до его появления опция завершится понятной ошибкой.
UI smoke и ручная визуальная проверка остаются разными видами evidence.
`build-for-testing` отдельно только собирает тесты и не подтверждает их выполнение.
Скрипт не исправляет scheduler-dependent waits (#849) и image isolation (#848).

Проверка самого CLI без Xcode/Simulator:

```sh
python3 Scripts/test_validate.py
```

Эти проверки используют изолированные fake tools для failure paths и отчётов;
они дополняют реальные `fast`/`full`, а не заменяют их.

## GitHub Actions

`.github/workflows/validation.yml` запускает `full --fresh` для pull requests,
pushes в `main` и `workflow_dispatch`. Ручной запуск становится доступен после
появления workflow в default branch; для первого CI run нужен pull request.

Выбран hosted preview runner `xcode-27` (macOS 27, arm64), Xcode 27.1 build
`27A9275` через `/Applications/Xcode_27.1.app/Contents/Developer` и точный minimum
runtime iOS 27.0. Источник выбора — [runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md),
image `20261012.0260.1`, проверенный 20 октября 2026. Preview status означает
возможные environment/queue failures. Label не фиксирует весь VM image:
workflow проверяет exact Xcode version/build, а `validate.sh` — SDK, minimum
runtime и доступный simulator. При изменении inventory проверка завершается
ошибкой; fallback на latest, другой Xcode/runtime или снижение target отсутствует.

Job timeout — 70 минут, validation step — 45 минут; оставшееся время отведено
в том числе диагностике. Оба завершающих шага используют `always()`:
`rssreader-ci-diagnostics.tar.gz` содержит raw environment/build/test logs,
phase statuses, reports и доступный `Tests.xcresult`, включая частичный bundle.
DerivedData исключён из архива. Артефакт `validation-<run_id>-<run_attempt>`
сохраняется на 7 дней, включая успешные runs. При принудительном завершении VM
или job timeout доставка артефакта не гарантируется.

`pipefail` сохраняет build/test failure через `tee`; упаковка/upload не заменяют
его успешным статусом. Workflow использует только read-only repository token,
не сохраняет checkout credentials, не требует secrets, Apple account или live
CloudKit; release/signing/deployment и UI smoke в него не входят.

Статическая проверка: `actionlint .github/workflows/validation.yml`.
`.github/actionlint.yaml` дополняет inventory линтера preview label `xcode-27`;
название секции `self-hosted-runner` принадлежит формату actionlint и не означает
использование self-hosted infrastructure.
