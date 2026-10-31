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
Локальный baseline #858 — Xcode 27.2 stable `27B52`, SDK/minimum iOS 27.2,
Swift language mode 5.0; hosted adoption ещё не подтверждён реальным run (см. GitHub Actions ниже).
Shared TestAction задаёт язык `ru` и регион `RU`: часть unit assertions проверяет
русские строки. Скрипт проверяет этот baseline, чтобы результат не зависел от
языка Mac/Simulator. Это не заменяет отдельную locale regression matrix.

Project configuration хранится в `RSSReader.xcodeproj/project.xcproj`, созданном
штатной конвертацией Xcode. Формат допускает trailing commas (JSON5): `jq empty`
и `plutil -lint` к нему неприменимы. Syntax check — Foundation `JSONSerialization`
с `.json5Allowed`; semantic validation — `xcodebuild -list`, effective settings и
реальный build/tests. `validate.sh` использует контейнер `.xcodeproj` через Xcode
и не разбирает project configuration как прежнюю PBX objects map.

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
выбирается из доступных устройств всех images точного minimum runtime, стабильно
по runtime identifier и UUID. У iOS 27.2 обычный image
`com.apple.CoreSimulator.SimRuntime.iOS-27-2` (`24B8117`) и Duo-only
`com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4` (`24B91016s`) имеют одну
версию, но разные hardware profiles; устройство связано со своим image.
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
логов. Названия фаз и исходный stdout build/tests выводятся в консоль отдельным
ограниченным временем команды monitor: Xcode пишет в файл, а `tail` явно
останавливается после команды, не ожидая закрытия stdout её потомками. stderr
сохраняется отдельно и печатается при ошибке. При test failure скрипт всё равно
пытается извлечь `.xcresult`.
Ноль выполненных тестов, cases без результата и неполный/неуспешный отчёт
не считаются успехом (report gate: exit 3). Expected failures отражаются отдельно.
Skipped tests перечислены счётчиком; успешный run не означает, что они проверены.

## UI и границы проверки

`fast` и `full` запускают только unit tests. UI smoke включается явно:

```sh
Scripts/validate.sh fast --ui-smoke-target RSSReaderUITests \
  --destination 'platform=iOS Simulator,name=<IPHONE_OR_IPAD_NAME>,OS=27.2'
```

Эта команда выполняет build, быстрые unit suites и UI smoke. Для полного unit
runner вместе с UI используйте `full`. В shared scheme `RSSReader` оба test targets
включены, поэтому Xcode Run All Tests запускает также UI suite; unit-only CLI
должен сохранять `-only-testing:RSSReaderTests`.

Отдельный UI-only запуск из repository root:

```sh
xcodebuild -project RSSReader.xcodeproj -scheme RSSReader -configuration Debug \
  -destination 'platform=iOS Simulator,name=<IPHONE_OR_IPAD_NAME>,OS=27.2' \
  -derivedDataPath <ISOLATED_DERIVED_DATA_PATH> \
  -resultBundlePath <NEW_RESULT_BUNDLE_PATH> \
  -only-testing:RSSReaderUITests test
```

Выполните suite отдельно на iPhone и iPad, затем повторите с новым result path.
Для iPad suite использует landscape и проверяет доступность списка рядом с Reader.
Нужны уже установленный iOS 27.2 runtime и созданные destinations; отсутствующая
проверка не считается successful run. Фактическое выполнение и результаты
проверяйте в `.xcresult`, включая failures/skips и нулевой test count.

`NavigationSmokeTests` запускает приложение с `--ui-smoke` и
`RSSREADER_UI_SMOKE_SOURCE_URL`, передавая адрес собственного HTTP fixture server
на `127.0.0.1` с динамическим портом. Test-only bootstrap доступен только в Debug
Simulator, срабатывает до production bootstrap/stores и отклоняет отсутствующий
или нелокальный URL. Каждый launch создаёт новые in-memory SwiftData stores,
settings, folder preferences и feed-icon cache; image runtime изолирован и offline.
CloudKit sources и background scheduler подменены локальными зависимостями.
UI runner отклоняет Release/device запуск до app launch. Аргументы не сохраняются в shared LaunchAction; обычный запуск использует live
composition. Реальный `SFSafariViewController` получает локальную HTML-страницу.

Suite проверяет Reader/Safari/return routes, Settings dismissal и повторный launch,
а также add/initial refresh/rename/unsubscribe cancel+confirm и
create/rename folder/move/delete folder с сохранением подписки. Для add-feed
точный URL `https://ui-smoke.invalid/added-feed` возвращает локальный RSS fixture
из Debug Simulator bootstrap; остальные app HTTP requests остаются offline.
Long press контекстных меню направляется в содержащую native List cell,
найденную по semantic identity дочернего элемента. Проверка move дополнительно
сворачивает/раскрывает папку и сверяет видимость перенесённой ленты.
Выбор destination folder направляется во вложенный `Text`: центр широкой
plain Button на iPad попадает в пустой `Spacer` вне её текущей hit area.
Assertions используют semantic identifiers и bounded waits. На iOS 27 рамка URL в accessibility Safari перекрывает Close: автоматический XCTest hit point на iPhone попадает в угол вне круглой кнопки. Только для этого native control нажатие направляется в центр его актуального semantic element frame; фиксированные экранные координаты не используются. Business logic
остаётся в unit tests; pixel layout, жесты, RTL/Dynamic Type и ручная визуальная
корректность этим suite не подтверждаются. Hosted CI пока запускает только unit
baseline: UI не добавлен без отдельной проверки runner/destination.
`build-for-testing` только собирает тесты и не подтверждает их выполнение.

Проверка самого CLI без Xcode/Simulator:

```sh
python3 Scripts/test_validate.py
python3 Scripts/test_ci_simulator.py
```

test_ci_simulator.py выполняет фактический preparation block workflow с fake Xcode tools:
reuse, download/create, Duo-only inventory, wrong build/profile, missing runtime
и сохранение download failure status. Fixture Scripts/Fixtures/ci-ios-27.2-duo-runtime.json
содержит relevant metadata реального hosted Duo-only runtime (run 41186673111);
fake download различает запрос release 27.2 и exact build 24B8117.

Эти проверки используют изолированные fake tools для failure paths и отчётов;
они дополняют реальные `fast`/`full`, а не заменяют их.

## GitHub Actions

По решению пользователя от 31 октября 2026 CI временно использует Xcode 27.2
**RC 27B48**, пока локальная разработка остаётся на stable 27B52. Это явное
исключение для CI, не смена общего stable baseline. Выбран точный путь
/Applications/Xcode_27.2_Release_Candidate.app/Contents/Developer, без mutable latest
или автоматического принятия другого build. [Runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md),
image 20261026.0314.1, подтверждает наличие RC. После появления stable требуется
отдельная правка пути/build pin и hosted validation; silently принимать RC/stable нельзя.

Первый hosted run 41186673111 подтвердил Xcode RC/SDK, но остановился до build/tests:
version-only download выбрал Duo-only runtime. Исправленный запрос exact build
ещё требует нового hosted run. Наличие iOS 27.2 runtime в inventory
не подтверждено, поэтому workflow явно подготавливает его на disposable runner:
при отсутствии обычного image запускает xcodebuild -downloadPlatform iOS
-buildVersion 24B8117 -architectureVariant arm64. Выбор только по release 27.2
неоднозначен: первый hosted run скачал Duo-only 24B91014. После установки обязательны точные
identifier com.apple.CoreSimulator.SimRuntime.iOS-27-2, version 27.2, build 24B8117
и поддержка выбранного device type. Duo-only image не заменяет обычный. Другой build,
недоступный download или несовместимость runtime с RC дают failure; fallback на
старую iOS или ослабление checks отсутствует. При отсутствии устройства создаётся
один RSSReader CI iPhone через simctl. Локальные runtimes script не меняет.

Для #858 пользователь подтвердил работу на iPhone 18 Pro / iOS 27.2 и принял
ограниченный Duo gate: native launch без compatibility/emulation layout с тёмным
полем сбоку. Полная Duo matrix (poses, resize/rotation, navigation и continuity)
перенесена в отдельный будущий эпик и не блокирует этот переход.
После принятия локального результата и успешного hosted RC run
можно завершить cleanup старых локальных runtimes; ждать stable в CI ради cleanup
при этом временном разрешении не требуется. Смена CI на stable остаётся follow-up.

`.github/workflows/validation.yml` запускает `full --fresh` для pull requests
и `workflow_dispatch`. Повторного автоматического запуска после merge/push в
`main` нет: обязательная проверка выполняется на PR перед merge.
Ручной запуск становится доступен после
появления workflow в default branch; для первого CI run нужен pull request.

Hosted preview runner — xcode-27 (macOS 27, arm64). Label не фиксирует весь VM image:
workflow проверяет exact Xcode version/build, а validate.sh — SDK, minimum runtime
и доступный simulator. Required check Clean build and full unit suite сохраняется.
Preview runner допускает queue/environment failures; CI RC пока не считается проверенным.

Подготовка runtime/device ограничена 25 минутами, boot — внутри того же шага через
simctl bootstatus -b. Исходный, подготовленный и итоговый simulator inventories,
runtime-install.log и simulator-boot.log входят в diagnostics. UUID передаётся в
validate.sh --destination. Сам validate.sh по-прежнему не устанавливает runtime
и не создаёт simulator: явная CI preparation вынесена в workflow.

Job timeout — 100 минут, validation step — 45 минут; оставшееся время отведено
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

Для `main` включены обязательный PR и successful check `Clean build and full unit suite`
именно от GitHub Actions, с требованием актуальности ветки относительно `main`.
Правила действуют и для администратора; обязательных сторонних approvals нет.
Force push и удаление `main` запрещены. Имя required check — часть внешнего
repository contract: при переименовании job нужно согласованно обновить правило.
