# RSS Reader

## Цель проекта

Этот проект — приложение для чтения RSS-лент, разрабатываемое как учебный и практический iOS-проект.

Основная цель проекта:
- спроектировать и реализовать современное клиентское приложение на Swift и SwiftUI;
- отработать архитектурный подход с понятным разделением ответственности между слоями приложения;
- реализовать полный базовый сценарий работы с RSS-лентами: загрузка, парсинг, сохранение, отображение и обновление данных;
- выстроить аккуратный инженерный процесс вокруг репозитория, задач, milestones и истории изменений.

Проект в первую очередь ориентирован на создание качественной MVP-версии с понятной архитектурой и возможностью дальнейшего расширения.

## Architecture Overview

Проект строится как SwiftUI-приложение с акцентом на читаемую структуру, изоляцию ответственности и удобство дальнейшего развития.

Текущая структура проекта:
- **Infrastructure** — app composition, dependency wiring, `AppState`, app-level navigation и служебные компоненты;
- **Models** — доменные модели и persistence entities;
- **Services** — network, parsing, repositories, query/read-model слой, sync, background refresh и прикладные сервисы;
- **Views** — экранные модули и переиспользуемые SwiftUI-компоненты;
- **RSSReaderApp / ContentView** — точка входа и корневая интеграция UI с app-level composition.

Ключевые архитектурные принципы:
- **SwiftUI** как основной UI-фреймворк;
- screen-oriented архитектура вместо классического `MVVM`;
- **SwiftData** для локального хранения данных;
- **Repository pattern** для изоляции доступа к данным;
- **Swift Concurrency (async/await)** для асинхронных операций и потоков событий через AsyncSequence/AsyncStream;
- минимизация жёсткой связанности между UI, хранением и сетевым слоем.

Экранный модуль обычно строится из следующих частей:
- `...ScreenController` — принимает пользовательские действия, вызывает зависимости и оркестрирует screen flow;
- `...ScreenState` — хранит изменяемое состояние экрана;
- `...DerivedViewState` и `...PresentationModels` — подготавливают состояние в форме, удобной для SwiftUI-представления;
- `...View` — отображает UI и пробрасывает действия обратно в controller;
- `...PreviewData` — изолирует preview-сценарии от runtime composition.

Базовый поток данных в проекте устроен так:
1. `View` передаёт пользовательское действие в `ScreenController`;
2. `ScreenController` обращается к `AppDependencies`, `Services`, `Repositories` или query layer;
3. данные загружаются, нормализуются, сохраняются и возвращаются в screen flow;
4. `ScreenState` фиксирует актуальное состояние экрана;
5. `DerivedViewState` и presentation-модели преобразуют его в UI-ready representation;
6. `View` отображает результат, не беря на себя orchestration бизнес-логики.

## Roadmap

### Foundation
#### Repository / Project Setup
- [x] инициализация Xcode-проекта;
- [x] настроить `.gitignore`;
- [x] создать milestones для фаз MVP;
- [x] настроить лейблы в проекте;
- [x] настроить GitHub Project;
- [x] добавить `README` в проект.

#### App Foundation
- [x] создать структуру каталогов: `Models` / `Services` / `ViewModels` / `Views` / `Infrastructure`;
- [x] добавить `AppDependencies.swift`;
- [x] настроить контейнер `SwiftData`;
- [x] настроить базовую dependency composition;
- [x] подготовить конфигурацию для `debug` / `logging`;
- [x] добавить app-level state для выбора `feed` / `article`;
- [x] настроить базовый root navigation через `NavigationSplitView`.

#### Domain Models
- [x] создать модели `Feed`, `Article`, `ArticleState`, `AppSettings`, `Folder`;
- [x] определить связи между моделями;
- [x] гарантировать синглтон для `AppSettings`;
- [x] определить уникальность `Folder.name`;
- [x] зафиксировать правила генерации `externalID` на всех устройствах;
- [x] зафиксировать удаление `ArticleState` при удалении `Feed`;
- [x] подумать о производительности;
- [x] добавить `FeedFetchLog`, определить минимальный набор полей для отладки fetch.

### Feed Pipeline
#### Networking / Feed Fetch
- [x] создать `HTTPClient` abstraction для feed-запросов;
- [x] описать `FeedRequest` / `FeedResponse` модели для pipeline;
- [x] реализовать загрузку feed по URL через `URLSession`;
- [x] валидировать HTTP status code и content type ответа;
- [x] добавить conditional headers через `ETag` / `Last-Modified`;
- [x] обрабатывать `304 Not Modified` как отдельный результат fetch;
- [x] добавить retry policy для временных сетевых ошибок;
- [x] логировать результат fetch в `FeedFetchLog`;
- [x] подготовить маппинг transport errors в domain-level fetch errors;
- [x] настроить `URLSessionConfiguration` и request timeout для feed-запросов;
- [x] добавить feed-specific `User-Agent` header.

#### Parsing / Normalization
- [x] создать `FeedParserService` с общим entrypoint для XML feed;
- [x] определять тип фида: `rss` / `atom` / `unknown`;
- [x] ввести parser DTO для feed metadata и entries;
- [x] реализовать parsing RSS 2.0: `channel` / `item`;
- [x] реализовать parsing Atom: `feed` / `entry`;
- [x] извлекать feed metadata: `title` / `subtitle` / `siteURL` / `language`;
- [x] извлекать article payload: `guid` / `url` / `title` / `summary` / `content` / `author` / `dates`;
- [x] создать `FeedNormalizationService` для очистки и приведения полей;
- [x] реализовать нормализацию `title` / source URLs / article content;
- [x] реализовать парсинг дат из RSS/Atom форматов;
- [x] интегрировать генерацию стабильного `externalID`;
- [x] создать `DeduplicationService` для слияния повторяющихся entries;
- [x] отбрасывать пустые и невалидные entries до persistence layer;
- [x] создать единый parser pipeline: `parse -> normalize -> deduplicate -> filter`;
- [x] уточнить merge policy для duplicate entries и выбор более качественного payload;
- [x] добавить diagnostics для причин отбрасывания invalid entries и parser anomalies.

#### Persistence / Repositories
- [x] создать `FeedRepository` для CRUD и fetch metadata feed;
- [x] создать `ArticleRepository` для upsert и выборок статей;
- [x] создать `ArticleStateRepository` для чтения user state в article queries;
- [x] создать `AppSettingsRepository` для singleton `AppSettings`;
- [x] создать `FeedFetchLogRepository` для истории fetch attempts;
- [x] реализовать сохранение `FeedFetchLog` в persistence layer;
- [x] реализовать сохранение нового feed и обновление его metadata;
- [x] реализовать upsert статей по ключу `feed + externalID`;
- [x] реализовать загрузку списка feeds для sidebar;
- [x] реализовать загрузку статей выбранного feed с сортировкой;
- [x] реализовать загрузку глобального inbox;
- [x] реализовать расчёт unread counts по feed;
- [x] реализовать удаление feed с каскадной очисткой связанных данных;
- [x] расширить `ArticleStateRepository` write-side API: `fetchOrCreate` / `upsert` / bulk updates для `read` / `starred` / `hidden`;
- [x] добавить выборку статьи по `articleID` для reader flow и будущих user actions;
- [x] добавить read-model/query DTO для article list и reader, чтобы UI получал объединённые данные `Article + ArticleState + Feed`;
- [x] расширить query API репозиториев под следующие экраны: фильтры `unread` / `starred` / `hidden` для inbox и feed article lists.

#### Refresh Orchestration
- [x] создать `FeedRefreshService` как единый coordinator refresh pipeline;
- [x] определить и зафиксировать публичный API сервиса: `refresh(feedID:)`, `refreshAllActiveFeeds()`, `refreshFeeds(_:)`, entrypoint для первого refresh после добавления feed;
- [x] определить и зафиксировать batch refresh result contract с агрегированными итогами по feeds и списком per-feed результатов;
- [x] определить и зафиксировать `FeedRefreshResult` для одного feed с полями статуса `fetched` / `notModified` / `failed`, `startedAt`, `finishedAt`, `duration`, количеством обработанных/upsert/rejected entries и diagnostics summary;
- [x] определить transactional boundary refresh одного feed и явно зафиксировать, какие изменения должны сохраняться атомарно: атомарно сохраняются `article upserts`, `article reconciliation`, `feed content metadata`, `feed fetch state`; `FeedFetchLog` сохраняется вне атомарной транзакционной границы;
- [x] определить и реализовать policy для `304 Not Modified`, включая обновление feed metadata и итоговый result/status: возвращать `FeedRefreshResult.notModified`, обновлять `lastFetchedAt`, принимать новые `ETag` / `Last-Modified` из ответа при наличии, очищать `lastSyncError`, не обновлять `lastSuccessfulFetchAt`, не выполнять parse/upsert/reconcile pipeline;
- [x] определить и реализовать policy для parser anomalies и rejected entries: в `diagnostics summary` входят количество `parser anomalies` и `rejected entries`; оба типа проблем пишутся в application log; наличие `parser anomalies` и `rejected entries` считается `soft failure` и не переводит refresh в `failed`, если fetch/parse pipeline в целом завершился успешно;
- [x] определить и реализовать reconciliation policy для статей, которые отсутствуют в свежем feed payload: не удалять их физически, а помечать `isDeletedAtSource = true`; статьи, которые снова появились в payload, возвращать в активное состояние через обычный `upsert/reconcile` flow;
- [x] определить и реализовать batch refresh policy с продолжением обработки остальных feeds при ошибке одного feed: использовать `continueOnError`, сохранять per-feed `failed` result в batch result и продолжать обработку оставшихся feeds;
- [x] реализовать refresh одного feed от network до persistence через этапы `fetch -> parse -> normalize -> deduplicate -> filter -> reconcile -> upsert`;
- [x] реализовать загрузку feed metadata из persistence и сборку `FeedRequest` с conditional headers перед каждым refresh;
- [x] реализовать обновление metadata feed из parsed payload при успешном refresh;
- [x] реализовать обновление `lastFetchedAt` для каждой попытки refresh независимо от исхода;
- [x] реализовать обновление `lastSuccessfulFetchAt` только для успешного refresh с новым payload;
- [x] реализовать обновление `lastSyncError` по результату refresh и очистку ошибки после успешного завершения;
- [x] реализовать обновление `lastETag` и `lastModifiedHeader` по результату HTTP fetch;
- [x] реализовать сохранение `FeedFetchLog` для каждого завершённого refresh с нормализованным статусом, HTTP code, сообщением ошибки и diagnostics summary;
- [x] реализовать защиту от одновременного refresh одного и того же feed;
- [x] реализовать in-flight deduplication повторного запроса на refresh одного и того же feed по выбранной policy;
- [x] реализовать refresh всех active feeds через `FeedRepository.fetchActiveFeeds()`;
- [x] ограничить параллелизм при batch refresh конфигурируемым лимитом;
- [x] реализовать агрегирование batch refresh результатов: количество `fetched`, `notModified`, `failed`, список ошибок и общее время выполнения;
- [x] реализовать cancellation semantics для refresh одного feed без повреждения persistence state;
- [x] реализовать cancellation semantics для batch refresh с корректным завершением уже запущенных или отменённых подзадач;
- [x] подготовить orchestration API для ручного refresh из UI без привязки UI к низкоуровневым fetch/parse сервисам;
- [x] подготовить orchestration API и контракты результата для будущего background refresh без реализации background scheduling в этом эпике;
- [x] ввести отдельный статус `cancelled` для refresh result и batch aggregation, чтобы отмена не маскировалась под `failed` в UI, telemetry и логах;
- [x] добавить integration tests для single feed refresh: `fetched`, `notModified`, `failed`, `cancelled`;
- [x] добавить integration tests для batch refresh: частичный успех, ошибки отдельных feeds, ограничение параллелизма и отмена;
- [x] добавить integration tests на защиту от concurrent refresh одного и того же feed;
- [x] добавить integration tests на обновление feed metadata и reconciliation статей после refresh.

### Reading Experience
#### Reading State Domain
- [x] создать `ArticleStateService` как единый orchestration-слой поверх `ArticleStateRepository`;
- [x] реализовать `markAsRead`;
- [x] реализовать `markAsUnread`;
- [x] реализовать `toggleStarred`;
- [x] реализовать bulk action `markAllVisibleAsRead`;
- [x] обновлять `updatedAt` и `lastInteractionAt` при каждом пользовательском изменении;
- [x] подготовить policy `last-write-wins` для будущих sync-конфликтов по `ArticleState.updatedAt`;
- [x] добавить unit tests для article state transitions.

#### Reading Shell / Navigation
- [x] определить финальную модель selection/navigation для `Sources -> Articles -> Article -> WebView`;
- [x] стабилизировать selection при refresh и смене фильтра;
- [x] добавить refresh/selection behavior для смены source без рассинхронизации списка и reader;
- [x] подготовить entry points для menu / source actions, которые нужны shell-уровню.
- [x] добавить unit tests на source switch: сброс article/detail selection и reload trigger;
- [x] добавить unit tests на filter switch: обновление active filter без потери shell consistency;
- [x] добавить unit tests на web view route: open/close article web view через `AppState`;
- [x] добавить unit tests на shell action entry points в `AppDependencies`.

#### Sources Screen
- [x] привести текущий sidebar к дизайну экрана Sources;
- [x] добавить отдельную стратегию кэширования иконок источников;
- [x] добавить нормализацию иконок под favicon / маленький square asset;
- [x] добавить fallback на site favicon, если feed не отдал `iconURL`;
- [x] показать loading/error state, а не только empty state;
- [x] добавить ручной refresh и статус синхронизации для Sources sidebar.

#### Sources Filtering
- [x] определить отдельный shell-level state для фильтра `Sources`, чтобы логика отбора источников не жила в `Articles Screen`;
- [x] переделать toolbar `Sources` под три кнопки: одна слева и две справа, показать subtitle и вынести туда дату последнего обновления источников и `Syncing...` во время refresh;
- [x] показывать в `Smart Views` только активный фильтр и скрывать остальные smart rows;
- [x] скрыть заголовок `Smart Views`, если в секции остаётся единственная активная ячейка;
- [x] при активном фильтре `Starred` показывать только те папки и источники, в которых есть starred статьи;
- [x] при активном фильтре `Unread` показывать только те папки и источники, в которых есть непрочитанные статьи;
- [x] при активном фильтре `All Items` показывать все папки и все источники, сохраняя unread counters;
- [x] скрывать секцию `Folders`, если после применения фильтра в ней не осталось папок или источников;
- [x] скрывать секцию `Ungrouped`, если после применения фильтра в ней не осталось источников;
- [x] определить selection behavior при смене фильтра: текущий selection сохраняется, если остаётся видимым, иначе происходит fallback на активную smart row;
- [x] подготовить query/read-model для расчёта наличия unread/starred статей на уровне папок и источников;
- [x] добавить folder-level navigation: ввести folder-level selection в `AppState` и связать tap по папке с открытием списка статей для этой папки;
- [x] при folder-level navigation наследовать активный `SourcesFilter`: `Unread` показывает только непрочитанные статьи папки, `Starred` показывает только starred статьи папки, `All Items` показывает все статьи папки;
- [x] при single feed selection наследовать активный `SourcesFilter`: `Unread` показывает только непрочитанные статьи источника, `Starred` показывает только starred статьи источника, `All Items` показывает все статьи источника;
- [x] определить persistence policy для `SourcesFilter` и восстанавливать последний выбранный фильтр при запуске приложения;
- [x] вынести subtitle-логику из `SidebarView` в отдельный helper (`SidebarToolbarState` / `SidebarSubtitleFormatter`), чтобы производное состояние toolbar не жило внутри `View`;
- [x] сделать counters в sidebar filter-aware: `All Items` показывает unread counters для `Smart Views`, папок и источников, `Unread` показывает unread counters, `Starred` показывает starred counters;
- [x] добавить недостающие unit tests на `SidebarToolbarState` и `SidebarSubtitleFormatter`.

#### Articles Screen
- [x] определить screen-level state/model для `Articles Screen`, чтобы отделить загрузку, refresh, empty/error состояния, toolbar actions и swipe actions от `View`;
- [x] определить navigation flow экрана: показать toolbar c back button, поддержать swipe слева-направо для возврата на экран `Sources`;
- [x] формировать title `Articles Screen` из текущего `SidebarSelection` (`Unread`, имя папки, имя источника и т.д.);
- [x] формировать subtitle `Articles Screen` из активного `SourcesFilter`: для `All Items` и `Unread` показывать количество непрочитанных статей, для `Starred` показывать количество starred статей;
- [x] демонтировать legacy `selectedArticleListFilter` из app-level flow;
- [x] привести текущий список к дизайну экрана Articles;
- [x] сгруппировать статьи по дням и показать section headers `Today / Yesterday / date`;
- [x] оформить ячейку списка: metadata row `source / time`, затем текст краткого содержимого статьи;
- [x] визуально показать `read/unread` и `starred` state в ячейке, сохранив чистый список без separators;
- [x] добавить нижние actions экрана статей для `search` и `Mark all as read`, показать destructive confirmation dialog и связать bulk action с `ArticleStateService.markAllVisibleAsRead`;
- [x] подготовить swipe actions для ячеек: swipe слева-направо помечает статью прочитанной, swipe справа-налево помечает статью starred;
- [x] добавить `pull to refresh` для текущего selection через `FeedRefreshService`;
- [x] добавить полноценный loading/error UX для первичной загрузки и refresh;
- [x] декомпозировать Article​List​View на несколько файлов: Article​List​View, Article​List​Content​View, Article​List​Refresh​Banner, Article​List​Row​View, Article​List​Section​Header​View, Article​List​Preview​Data;
- [x] вынести load/refresh orchestration из View в отдельный screen-level coordinator или Articles​Screen​Actions/Articles​Screen​Controller, чтобы View не решал, какой query вызывать и как интерпретировать результаты;
- [x] вынести post-action mutation rules из View в Articles​Screen​State или отдельный reducer/helper. Сейчас правила mark read, toggle star, mark all as read размазаны по View, хотя это screen behavior;
- [x] вынести производный UI state экрана из View. Минимум: toolbar​Actions, search empty placeholder, refresh banner model, loading copy;
- [x] добавить недостающие тесты именно на refresh UX. Сейчас покрыт state-level failure path, но полезно отдельно зафиксировать сценарии successful refresh clears previous refresh error и selection change resets stale refresh feedback.

#### Article Screen
- [x] определить screen-level state/model для `Article Screen`, чтобы отделить загрузку статьи, toolbar actions, menu state, `share`, error/empty состояния и rendering policy от `ReaderView`;
- [x] определить compact navigation flow экрана: toolbar с back button слева, без отдельного title в navigation bar, возврат на `Articles Screen` по кнопке и системному back behavior;
- [x] оформить header контента в порядке `publishedAt` / `title` / `author` / `feedTitle`, включая правила скрытия пустых полей и единый formatter для даты и времени публикации;
- [x] улучшить content rendering pipeline: выбрать лучший доступный источник между `contentHTML`, `contentText`, `summary`, поддержать многоабзацный текст, inline images и аккуратный fallback для статей без полного тела;
- [x] добавить `share` в правую часть top bar и нижние actions `mark unread`, `star`, `open in app-browser` как три раздельные bottom bar кнопки;
- [x] связать нажатие на read toggle кнопку с `ArticleStateService`, обновлять screen state без повторной загрузки экрана и переключать `read` status статьи в обе стороны с иконкой `circle` / `circle.fill`;
- [x] связать нажатие на кнопку `star` с `ArticleStateService`, обновлять screen state без повторной загрузки экрана и переключать иконку `star` / `star.fill` по текущему `starred` status статьи;
- [x] связать нажатие на кнопку `open in app-browser` с app-level navigation entry point, чтобы `Article Screen` открывал `WebView Screen` через app-level routing без прямого знания о shell-роутинге;
- [x] связать нажатие на кнопку `share` с системным share sheet, использовать canonical article URL с корректным fallback на `articleURL`;
- [x] реализовать `markAsReadOnOpen` на основе `AppSettings` с явной policy: статья помечается read при открытии detail screen, но это не должно ломать ручное действие `mark unread`;
- [x] определить и реализовать loading / not found / rendering failure UX для `Article Screen`, а не только happy path с уже загруженной статьёй;
- [x] подготовить extension point под future full text flow: зафиксировать, где будет жить логика `full text` extraction, как она влияет на `ReaderArticleDTO`/presentation model и чем базовый embedded reader отличается от отдельного reader mode;
- [x] добавить unit tests на screen-level state и action reducer для `Article Screen`, включая `markAsReadOnOpen`, bottom actions и переход в `WebView Screen`.

#### WebView Screen
- [x] определить app-level navigation flow для `WebView Screen`: `RootView` должен уметь переключать detail между `Article Screen` и `WebView Screen` по `ReadingDetailRoute.webView`, а закрытие web view должно возвращать пользователя к текущей статье;
- [x] создать отдельный `WebView Screen` на базе `WKWebView` для `articleURL`, чтобы экран получал уже подготовленный `ArticleWebViewRoute` и не знал о shell-роутинге напрямую;
- [x] определить screen-level state/model для `WebView Screen`, чтобы отделить `initialURL`, loading progress, navigation title, share action availability и error state от SwiftUI `View`;
- [x] реализовать загрузку `articleURL` в `WKWebView` с базовым loading state для первого открытия страницы;
- [x] реализовать error / fallback UX, если `articleURL` невалиден или страница не открывается, с явным сценарием возврата назад к статье;
- [x] добавить toolbar-кнопку `share` в правой части top bar и связать её с canonical `articleURL` / текущим `ArticleWebViewRoute.url`;
- [x] поддержать `defaultReaderMode` из `AppSettings` как policy initial presentation для `WebView Screen`;
- [x] добавить нижний action `open in external browser` в `bottomBar`;
- [x] реализовать единственный кастомный gesture `left-edge swipe to close`: edge swipe от левого края закрывает `WebView Screen` и возвращает пользователя в `Article Screen`, а встроенный history navigation внутри `WKWebView` отключён, чтобы жест не конфликтовал с поведением страницы;
- [x] добавить нижний action `refresh` в левой части `bottomBar` и связать его с перезагрузкой текущей страницы в `WKWebView` без возврата к общему `command bridge`;
- [x] синхронизировать `current page URL` с `WebView Screen` state, чтобы `share` и `open in external browser` использовали фактический адрес текущей открытой страницы, а не только исходный `ArticleWebViewRoute.url`;
- [x] привести loading presentation `WebView Screen` к тому же UI pattern, что и у `Article Screen`, чтобы первичная загрузка выглядела консистентно на уровне приложения;
- [x] скрывать browser actions (`share`, `refresh`, `open in external browser`) в loading/error состояниях `WebView Screen`, чтобы toolbar и `bottomBar` не предлагали действия над ещё не открытой или недоступной страницей;
- [x] провести `cleanup` `WebViewScreenView`: выделить секции/подвью, добавить `MARK` и упростить чтение `WKWebView` bridge-слоя без изменения поведения экрана.

#### Screen Shell Cleanup
- [x] вынести shell-level navigation policy из `RootView` в отдельные screen-shell сущности: compact column routing, detail destination resolution и back-navigation rules не должны жить вперемешку с самой `View`-разметкой;
- [x] унифицировать compact back navigation / edge-swipe policy для `Articles Screen`, `Article Screen` и `WebView Screen`, чтобы пороги жестов, правила показа back button и contract возврата назад описывались единообразно, а не дублировались в нескольких `*NavigationState`;
- [x] определить единый screen composition pattern для основных экранов приложения: как соотносятся `ScreenState`, `DerivedViewState`, `Controller`, primary loading, placeholder/error presentation и toolbar visibility policy, чтобы `Articles`, `Article` и `WebView` были собраны по одной архитектурной схеме;
- [x] выровнять preview infrastructure основных экранов: единые `PreviewContainer` / `PreviewData` conventions, явное разделение preview-only state и runtime wiring, без расхождения между `Articles`, `Article` и `WebView` screen previews;
- [x] перевести `Articles`, `Article` и `WebView` на системный compact back button вместо собственных toolbar-leading кнопок, чтобы navigation chrome соответствовал нативному поведению `NavigationSplitView` на iPhone и не дублировался в toolbar;
- [x] добавить shell-level previews / demo flows для сквозного просмотра основных экранов и navigation transitions, чтобы можно было проверять связность `Sidebar` → `Articles` → `Article` → `WebView` без ручного прогона приложения;
- [x] перевести leading swipe action строки статьи на двусторонний `read/unread` toggle в `Articles Screen`, чтобы после пометки статьи прочитанной пользователь мог сразу вернуть её в unread без перехода на другой экран;
- [x] провести короткий consistency pass по основным экранам после shell cleanup: выровнять loading copy, empty/error/no-selection presentation и названия user actions между `Sidebar` → `Articles` → `Article` → `WebView`, не меняя screen architecture и не трогая toolbar composition или navigation title/subtitle rules;
- [x] привести `SidebarView` к тому же screen composition pattern, что и основные экраны: выделить `SidebarScreenState` / `SidebarScreenDerivedViewState` / `SidebarScreenController`, вынести loading/error/empty policy из `View` и убрать смешение runtime state c query orchestration;
- [x] вынести preview infrastructure `SidebarView` в отдельный `SidebarPreviewData`-файл: `PreviewHost`, scenario factory, seed data и preview-only helpers не должны жить в runtime `SidebarView.swift`;
- [x] после декомпозиции `SidebarView` выровнять его границы с остальными экранами: `View` должна в основном рендерить готовый presentation contract, а не одновременно хранить local screen state, selection behavior, preview wiring и toolbar policy.

#### Settings Integration
- [x] привести модель `AppSettings` к целевому виду для `Settings Integration`: зафиксировать `selectedSourcesFilterRawValue` как единственный persisted источник для source filter state и оставить `showUnreadOnly` только как legacy-поле на время миграции;
- [x] удалить `showUnreadOnly` из `AppSettings` и связанных persistence paths после завершения миграции на один `selectedSourcesFilterRawValue`;
- [x] добавить в `AppState` или соседний app-level navigation state отдельное состояние показа `Settings Screen`, чтобы открытие/закрытие настроек на iPhone/iPad не жило локально внутри `SidebarView`;
- [x] определить app-level presentation для `Settings Screen` на iPhone/iPad: экран должен открываться по действию `Settings` из toolbar/menu как отдельный modal flow (`sheet`) поверх текущего `NavigationSplitView` и не входить в его detail-routing;
- [x] организовать единый settings flow загрузки/редактирования/сохранения `AppSettings`, чтобы экран не читал и не записывал `SwiftData` напрямую, а работал через явный repository/service boundary;
- [x] выделить presentation model для секций настроек и их item types (`toggle`, `picker`, `navigation link`, `status row`), чтобы `Settings Screen` рендерил готовый UI contract, а не собирал форму ad hoc;
- [x] собрать `Settings Screen` в той же screen-архитектуре, что и остальные экраны: выделить `SettingsScreenState`, `SettingsScreenController`, presentation models, preview data и contract user actions вместо прямой работы `View` с `AppSettingsRepository`;
- [x] организовать настройку `defaultReaderMode`: значение должно редактироваться через `Settings Screen`, сохраняться в `AppSettings` и определять initial presentation policy при открытии статьи;
- [x] организовать настройку `markAsReadOnOpen`: значение уже применяется в `ArticleScreenController`, но должно стать редактируемым через `Settings Screen` и сохраняться в `AppSettings`;
- [x] организовать настройку сортировки unread/article list order через `sortMode`, сведя пользовательский выбор к понятным вариантам `Oldest first` / `Newest first` и не exposing технические raw values enum напрямую;
- [x] организовать настройку `askBeforeMarkingAllAsRead`: сейчас `ArticlesScreenState` уже умеет хранить `pendingConfirmation`, но policy подтверждения не вынесена в `AppSettings` и не управляется пользователем;
- [x] подготовить presentation model тела статьи к наличию tappable links: текущие `summary` / `contentHTML` / `contentText` сводятся в `ArticleScreenBodyBlock.paragraph(String)`, поэтому сначала нужно ввести link-aware representation для текста и не терять metadata о ссылках при рендеринге body content;
- [x] определить screen-level contract для tap handling по ссылкам внутри тела статьи: `ReaderView` не должен открывать URL ad hoc, поэтому нужен явный user action flow `body link tapped` через `ArticleScreenController` и app-level/opening boundary;
- [x] организовать отдельную настройку policy открытия ссылок именно из тела статьи (`in-app browser` или внешний браузер): значение должно редактироваться через `Settings Screen`, сохраняться в `AppSettings` и применяться в `Article Screen` при тапе по inline-links, а не к toolbar-действию открытия самой статьи;
- [x] организовать отдельную настройку policy открытия source article из `ArticleScreen` (`in-app browser` или внешний браузер): значение должно редактироваться через `Settings Screen`, сохраняться в `AppSettings` и применяться к нижнему toolbar-действию открытия исходной статьи, а не к inline-ссылкам внутри body;
- [x] организовать настройку интерфейсного режима (`automatic light/dark`, `automatic light/black`, `light`, `dark`, `black`): для этого потребуется добавить новое persisted setting и определить app-level theme application policy, которой пока нет в `RootView` / `AppState`;
- [x] организовать настройку background refresh policy через `refreshIntervalPreference`, связав `Settings Screen` с будущим `BackgroundRefreshService`, чтобы выбор между manual/background refresh не остался изолированным enum без runtime orchestration;
- [x] определить UX и статус-строку для `iCloud sync indicator`: в `AppSettings` уже есть `useiCloudSync`, но в проекте пока нет ни `CloudKit` wiring, ни app-level sync status source, поэтому индикатор нужно проектировать как consumer будущего sync state, а не как локальный UI toggle;
- [x] сократить дублирование persistence flow в `SettingsScreenController`: сейчас почти каждая editable setting проходит через одинаковый шаблон `validate -> build AppSettingsPatch -> save -> applyLoadedSnapshot`, поэтому перед следующим эпиком стоит вынести общий helper и выровнять update-path для всех настроек;
- [x] отделить screen-specific input `Settings Screen` от общего `AppSettingsSnapshot`: сейчас presentation pipeline экрана напрямую потребляет весь service snapshot, включая поля, которые не являются собственным UI input экрана, поэтому полезно ввести отдельную screen-level data model / normalized input для `Settings Screen`;
- [x] провести cleanup `Settings Screen` contract и interaction paths: убрать неиспользуемые `navigationLink`-ветки и служебные `not implemented yet`-paths в `SettingsScreenController`, если они не нужны текущему UI и только размывают фактический contract экрана.

#### Source Management
- [x] добавить в `AppState` или соседний app-level navigation state отдельное состояние показа `Source Management Screen`, чтобы открытие/закрытие add-source flow не жило локально внутри `SidebarView`;
- [x] определить app-level presentation для `Source Management Screen` на iPhone/iPad: экран должен открываться по действию `Add Source` из `SidebarView` как отдельный modal flow (`sheet`) поверх текущего `NavigationSplitView` и не входить в его detail-routing;
- [x] определить entry UX `Source Management Screen`: экран должен явно разделять сценарии `add feed`, `create folder` и последующие folder assignment / move actions, а не смешивать их в одном неструктурированном `Form`;
- [x] собрать `Source Management Screen` в той же screen-архитектуре, что и остальные экраны: выделить `SourceManagementScreenState`, `SourceManagementScreenController`, presentation models, preview data и contract user actions;
- [x] добавить отдельный `FolderRepository` и подключить его в `AppDependencies`, чтобы создание папок и выбор списка папок не зависели от побочных эффектов в `FeedRepository` и не оставались без явной persistence boundary;
- [x] выделить service layer для source management operations: отдельный orchestration-service должен отвечать за preview feed по URL, создание feed, создание folder и перемещение feed между folder / ungrouped state, чтобы screen-level controller не координировал repository/network logic напрямую;
- [x] расширить persistence/service contract для folder assignment: нужен явный update-path для назначения `Feed.folder`, переноса feed между папками и удаления feed из папки без ручной правки `SwiftData`-моделей из UI-слоя;
- [x] реализовать сценарий `create folder`: экран должен поддерживать создание новой папки с валидацией имени, проверкой уникальности и определением `sortOrder`, совместимым с текущим sidebar grouping;
- [x] организовать сценарий `add feed`: screen-level input model для URL, нормализация ввода, локальная валидация и понятное состояние primary action до запуска network preview;
- [x] реализовать preview feed по URL через существующие `FeedFetcher` и `FeedParserService`, чтобы до сохранения пользователь видел распознанные metadata (`title`, `subtitle`, `siteURL`, `iconURL`, `kind`) и мог подтвердить добавление источника;
- [x] организовать duplicate/invalid/unsupported handling для `add feed` flow: отдельные UX-сценарии нужны для невалидного URL, network failure, неподдерживаемого feed и уже существующего feed с тем же URL через `FeedRepository.fetchFeed(url:)`;
- [x] реализовать выбор папки при создании feed и отдельный move flow для существующих feed: пользователь должен иметь возможность поместить источник в новую или существующую папку, перенести его между папками и вернуть в `ungrouped` state;
- [x] реализовать сохранение нового feed после подтверждения preview: источник должен создаваться в persistence с нормализованным URL, стартовыми metadata из preview и выбранной целевой папкой либо `ungrouped` placement;
- [x] организовать первый refresh после добавления feed, чтобы после сохранения источник проходил через существующий refresh pipeline, загружал статьи и обновлял `Sidebar` / `Articles` без ручного перезапуска приложения;
- [x] определить source-level actions в `Sidebar`: нужен явный UX для запуска edit / move flow над существующим feed, чтобы редактирование или перемещение между папками происходило из списка источников, а не требовало повторного add-source сценария;
- [x] провести consistency pass для `Source Management` UX: выровнять loading / success / error / empty states, copy для create/edit/move flows и app-level reload behavior после создания папки, добавления feed или перемещения источника;
- [x] довести app-level completion behavior для `Source Management`: после `create folder`, `move source`, `edit feed`, `edit folder`, `unsubscribe` и `delete folder` должны быть явно определены reload `Sidebar` / `Articles`, retarget текущего selection и правила закрытия modal flow;
- [x] добавить shell-level regression tests для `Source Management`: нужны отдельные проверки на reload / selection / dismiss behavior после create / move / edit / delete операций, чтобы app-level orchestration не расходился с screen-level success state;
- [x] расширить preview / dev fixtures для `Source Management`: обновить `RootViewPreviewData` и `SourceManagementScreenPreviewData`, чтобы можно было вручную проверять create / edit / move flows, видимость новых папок и post-action состояние без живого сценария в приложении;
- [x] убрать `SourceManagementScenarioPlaceholderPresentation` и placeholder-routing из `SourceManagementScreenPresentationModels` / `SourceManagementScreenView`, а также выровнять `Source Management` tests с актуальным screen/state contract после cleanup временных веток;
- [x] вынести preview-only builders из `SourceManagementScreenState` в `SourceManagementScreenPreviewData` и test fixtures, чтобы production state не смешивался с dev fixtures;
- [x] декомпозировать `SourceManagementScreenController`: разделить context loading, add/edit/create/move orchestration и mapping ошибок/status presentation, чтобы controller перестал быть монолитной точкой входа;
- [x] сократить дублирование source / folder context loading и completion glue между `SourceManagementScreenController` и `AppDependencies`, чтобы app-level routing и screen-level orchestration читались как единый flow без повторяющихся helper-веток;
- [x] почистить `SourceManagementScreenView`: убрать routing-specific `Binding` / `ActionHandlers` glue из корневого view и вынести общие status / feedback card helpers.

### Sync
#### Sync / CloudKit Foundation
- [x] зафиксировать целевой cross-device reading scenario для sync: между устройствами должны синхронизироваться структура источников и `ArticleState`, а актуальный список `Article` должен появляться на втором устройстве после manual refresh или background refresh без промежуточной app-авторизации;
- [x] вынести общий test-support и sync/cross-device tests из `RSSReaderTests.swift` в отдельные файлы, чтобы дальнейшая декомпозиция test target шла по feature-oriented структуре;
- [x] перейти от `extension RSSReaderTests` к standalone suite types и начать разнос service-level тестов по feature-oriented файлам (`Sync`, `Feeds`, `Articles`), чтобы navigator и test target отражали логические границы ответственности;
- [x] вынести `Sidebar` query/presentation/state tests из `RSSReaderTests.swift` в отдельные suite files, чтобы feature-oriented структура test target отражала отдельные read-model, presentation и screen-state обязанности;
- [x] вынести `ArticleScreen` state/rendering/controller/navigation tests из `RSSReaderTests.swift` в отдельные suite files, чтобы тесты reader detail flow были разложены по screen state, content rendering, controller orchestration и navigation policy;
- [x] вынести `Shell` и `WebViewScreen` navigation/state tests из `RSSReaderTests.swift` в отдельные suite files, чтобы shell-level routing и embedded browser flow были отделены от `ArticlesScreen` и app settings/persistence блоков;
- [x] вынести `ArticlesScreen` state/controller/mutation/presentation tests из `RSSReaderTests.swift` в отдельные suite files, чтобы list flow был разложен по screen state, controller orchestration, mutation reducer и presentation helpers;
- [x] вынести `Settings`/`AppSettings` persistence/service/presentation/state/controller/theme tests из `RSSReaderTests.swift` в отдельные suite files, чтобы app settings flow был разложен по repository/service, screen presentation/state, controller orchestration и theme policy;
- [ ] зафиксировать целевой sync scope: в CloudKit должны синхронизироваться `Feed`, `Folder`, `ArticleState` и `AppSettings`, а `Article` и `FeedFetchLog` должны оставаться только локальным storage слоем;
- [ ] провести audit CloudKit compatibility для `AppSettings`, `Feed` и `Folder`: проверить `@Attribute(.unique)`, relationship semantics и текущие invariants, которые могут блокировать SwiftData sync;
- [ ] провести audit CloudKit compatibility для `ArticleState`, `Article` и `FeedFetchLog`: проверить `#Unique`, nonoptional relationships, delete rules и закрепить границу между sync-backed сущностями и локальным article cache;
- [ ] адаптировать schema и repository layer для `AppSettings`, `Feed` и `Folder`: убрать зависимость от schema-level uniqueness там, где она несовместима с CloudKit, и перенести инварианты в repository/service layer;
- [ ] адаптировать schema и repository layer для `ArticleState`: привести модель к CloudKit-compatible виду и сохранить корректность conflict/update paths на уровне repository/service logic;
- [ ] закрепить `Article` и `FeedFetchLog` как local-only storage и отделить их от sync-backed persistence configuration;
- [ ] переразложить `ModelConfiguration` в `AppDependencies.makeWithSwiftData`, чтобы sync-backed и local-only store были описаны явно, а CloudKit container policy не зависел от неявного automatic discovery;
- [ ] настроить Xcode capabilities для CloudKit sync: включить `iCloud` и `Background Modes` с `Remote notifications` и зафиксировать используемый CloudKit container;
- [ ] реализовать DEBUG-only bootstrap development schema для CloudKit, чтобы development container инициализировался до запуска runtime sync и не требовал ручных разрозненных действий.

#### Sync Runtime
- [ ] определить app-level policy для sync enablement и `useiCloudSync`: зафиксировать, как persisted user intent влияет на создание sync-backed store и как приложение ведёт себя при выключенном sync;
- [ ] реализовать проверку iCloud account availability через runtime account status APIs и выделить отдельные состояния `available`, `noAccount`, `restricted`, `temporarilyUnavailable` и `couldNotDetermine`;
- [ ] создать базовый `SyncCoordinator` как app-level orchestration layer для CloudKit/SwiftData sync lifecycle и единственную точку владения runtime sync state;
- [ ] подключить runtime account status и store status к `SyncCoordinator`, чтобы coordinator умел различать disabled state, account problems, активную синхронизацию и runtime failures;
- [ ] заменить текущий placeholder `ICloudSyncStatusService` на реализацию, которая читает фактический runtime state из `SyncCoordinator` и account/store context;
- [ ] расширить account/status UX для sync: `Settings Screen` должен показывать понятные статусы отсутствия iCloud account, необходимости входа в `Apple ID`, restricted/temporarily unavailable cases и не требовать отдельную учётную запись приложения;
- [ ] подключить `SyncCoordinator` и runtime sync status к `AppState` и `AppComposition`, чтобы shell-level state обновлялся из реального sync lifecycle, а не только из persisted intent;
- [ ] реализовать app-level reload triggers после remote sync, чтобы изменения из CloudKit обновляли `Sidebar`, `Articles`, `Article Screen` и другие screen-level controller flows.

#### Sync Validation
- [ ] проверить sync для `Feed`: добавление, изменение и удаление источников на одном устройстве должны переноситься на второе устройство;
- [ ] проверить sync для `Folder`: создание папок, изменение структуры и folder assignment для feed должны переноситься между устройствами;
- [ ] проверить sync для `AppSettings`: настройки чтения, сортировки, link policies, темы и других persisted preferences должны консистентно приходить на второе устройство;
- [ ] проверить sync для `ArticleState`: read/starred/hidden state должен синхронизироваться между устройствами без потери локальных действий и без рассинхронизации с article list/query layer;
- [ ] проверить и при необходимости скорректировать conflict resolution `ArticleState` по `updatedAt` для реального multi-device сценария и CloudKit merge behavior;
- [ ] проверить сценарий cross-device manual refresh: после refresh и чтения на первом устройстве второе устройство должно после ручного refresh получить тот же набор `Article`, а synced `ArticleState` должен сразу скрыть уже прочитанные материалы из `Unread`;
- [ ] проверить, что `Article` и `FeedFetchLog` не попадают в CloudKit sync и остаются только локальным cache/diagnostic storage;
- [ ] проверить end-to-end сценарий запуска на втором устройстве: чистый запуск, вход в тот же `Apple ID`, получение уже существующих `Feed` / `Folder` / `AppSettings` / `ArticleState`, дальнейшее чтение на двух устройствах и восстановление после временного отсутствия сети.

#### Sync Hardening
- [ ] добавить app-level логирование и диагностику sync-ошибок для container setup, schema/bootstrap failures, account/status resolution, merge issues и runtime sync failures;
- [ ] провести cleanup / refactor sync-related кода: убрать placeholder-only ветки, выровнять границы между `SyncCoordinator`, status service и shell state, а также удалить временные debug hooks и одноразовые migration helpers, если они больше не нужны.

### Background Refresh
#### Background Refresh Foundation
- [ ] зарегистрировать `background task` identifier и app-level entry point в `RSSReaderApp`, чтобы система могла запускать feed refresh в фоне через SwiftUI `backgroundTask`;
- [ ] выделить отдельный scheduler layer для background refresh requests, чтобы планирование следующего запуска не жило внутри `RSSReaderApp`, `RootView` или screen/controller кода;
- [ ] связать scheduler с app lifecycle: при запуске приложения и после успешного выполнения background task должен планироваться следующий refresh request консистентно с выбранной policy;
- [ ] связать scheduler с `refreshIntervalPreference`: при изменении настройки приложение должно перепланировать или отключать фоновые задачи без расхождения между `Settings Screen`, `BackgroundRefreshService` и runtime scheduling.

#### Background Refresh Execution
- [ ] подключить системный `background task` к существующему `BackgroundRefreshService`, чтобы фактическое выполнение фонового refresh шло через уже реализованный service layer, а не через отдельную app-level orchestration ветку;
- [ ] корректно завершать `background task` с учётом успешного refresh, partial failure и cancellation, чтобы система получала валидный execution result;
- [ ] сохранять результат background refresh так, чтобы при следующем foreground/open экраны видели уже обновлённый локальный список `Article` без обязательного ручного refresh;
- [ ] реализовать app-level reload behavior после успешного background refresh, чтобы `AppState`, shell и screen-level controller flows обновлялись консистентно при возврате приложения на экран;
- [ ] обработать сценарии отсутствия сети, системных runtime ограничений и других execution failures так, чтобы background refresh не порождал ложный success и не ломал локальное состояние.

#### Background Refresh Validation
- [ ] проверить сценарий “обновили источники на iPhone, прочитали часть статей, открыли iPad после background refresh”: iPad должен получить свежие `Article` локально и применить synced `ArticleState`, показав только непрочитанные статьи в `Unread`;
- [ ] проверить fallback-сценарий без background refresh: после тех же действий на первом устройстве второй девайс должен достигать консистентного состояния через manual refresh;
- [ ] проверить поведение background refresh при отсутствии сети, временной недоступности системы и отключённой automatic refresh policy.

#### Background Refresh Hardening
- [ ] добавить логирование и диагностику background refresh execution, scheduling decisions и системных отказов запуска;
- [ ] провести cleanup / refactor background refresh-related кода: выровнять границы между scheduler, `BackgroundRefreshService`, app lifecycle wiring и screen reload helpers, а также убрать временные debug hooks, если они больше не нужны.

### Polish
#### Testing
- [ ] unit tests для normalizer;
- [ ] unit tests для date parsing;
- [ ] unit tests для external ID generation;
- [ ] unit tests для deduplication;
- [ ] unit tests для article state transitions;
- [ ] integration tests для refresh pipeline;
- [ ] UI tests для add feed flow;
- [ ] UI tests для read/unread flow.

#### Polish / Release Prep
- [ ] улучшить launch/empty/loading states;
- [ ] улучшить сообщения об ошибках;
- [ ] проверить accessibility labels;
- [ ] проверить performance на длинных списках;
- [ ] подготовить app icons;
- [ ] подготовить screenshots;
- [ ] подготовить privacy notes;
- [ ] подготовить TestFlight checklist;
- [ ] подготовить release checklist.

### Post-MVP
#### Post-MVP backlog
- [ ] feed discovery по URL сайта;
- [ ] OPML import;
- [ ] OPML export;
- [ ] full text extraction/reader mode;
- [ ] image prefetch;
- [ ] advanced smart folders;
- [ ] скрытие статьи;
- [ ] поиск по статьям;
- [ ] macOS/iPad polish;
- [ ] advanced conflict UI.

## Tech Stack

- **Swift**
- **SwiftUI**
- **Swift Concurrency (async/await)**
- **SwiftData**
- **CloudKit**
- **Swift Testing**
- **Git/GitHub**
