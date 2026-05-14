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
- [x] вынести `SourceManagement` service/app-flow/state/controller tests из `RSSReaderTests.swift` в отдельные suite files, чтобы source onboarding и source editing flow были разложены по service-layer, app-level launch context, screen state и screen controller orchestration;
- [x] вынести оставшиеся `Sidebar` selection/filtering tests, shell action/app-flow tests и `FeedNormalization`/`SourceIconCache` tests из `RSSReaderTests.swift` в отдельные suite files, чтобы монолитный test file сузился до небольшого persistence/infra хвоста;
- [x] вынести оставшиеся `AppDependencies` и repository persistence tests из `RSSReaderTests.swift` в отдельные suite files и удалить сам `RSSReaderTests.swift`, чтобы test target полностью перешёл на feature-/layer-oriented структуру без общего монолитного suite file;
- [x] зафиксировать целевой sync scope: в CloudKit должны синхронизироваться `Feed`, `Folder`, `ArticleState` и `AppSettings`, а `Article` и `FeedFetchLog` должны оставаться только локальным storage слоем;
- [x] провести audit CloudKit compatibility для `AppSettings`, `Feed` и `Folder`: проверить `@Attribute(.unique)`, relationship semantics и текущие invariants, которые могут блокировать SwiftData sync;
- [x] провести audit CloudKit compatibility для `ArticleState`, `Article` и `FeedFetchLog`: проверить `#Unique`, nonoptional relationships, delete rules и закрепить границу между sync-backed сущностями и локальным article cache;
- [x] адаптировать schema и repository layer для `AppSettings`, `Feed` и `Folder`: убрать зависимость от schema-level uniqueness там, где она несовместима с CloudKit, и перенести инварианты в repository/service layer;
- [x] адаптировать schema и repository layer для `ArticleState`: привести модель к CloudKit-compatible виду и сохранить корректность conflict/update paths на уровне repository/service logic;
- [x] закрепить `Article` и `FeedFetchLog` как local-only storage и отделить их от sync-backed persistence configuration;
- [x] переразложить `ModelConfiguration` в `AppDependencies.makeWithSwiftData`, чтобы sync-backed и local-only store были описаны явно, а CloudKit container policy не зависел от неявного automatic discovery;
- [x] настроить Xcode capabilities для CloudKit sync: включить `iCloud` и `Background Modes` с `Remote notifications` и зафиксировать используемый CloudKit container;
- [x] встроить DEBUG-only bootstrap orchestration для CloudKit development schema: добавить app-level entry point, explicit preflight и skip/logging path, чтобы инициализация development schema имела единую точку запуска и не требовала ручного отдельного сценария;
- [x] завершить CloudKit-compatible persistence boundary для source/article слоя: убрать ownership collections `Feed.articles` и `Folder.feeds`, заменить direct `Article.feed` relationship на scalar local-cache linkage и довести `DEBUG-only` development schema bootstrap до реального `initializeCloudKitSchema()` path с зафиксированным success / skip behavior в тестах;
- [x] перевести `SyncBackedStore` с `.none` на explicit private CloudKit database policy и проверить, что `ModelContainer` поднимается с активным CloudKit-backed configuration только для sync-backed моделей;

#### Sync Runtime
- [x] зафиксировать source of truth для sync enablement и `useiCloudSync`: persisted setting `AppSettings.useiCloudSync` остаётся пользовательской app-level boot preference; первый запуск идёт в disabled state по дефолтному `false`; при выключенном sync sync-backed store продолжает жить локально, но поднимается без `CloudKit`; изменение настройки требует нового app launch / `ModelContainer` rebuild, а не мгновенного runtime-переключения policy;
- [x] довести `Settings Screen` contract для sync enablement до явного UX-решения: `useiCloudSync` остаётся редактируемой app-level boot preference; sync-секция должна показывать отдельный toggle с copy про применение на следующем запуске и отдельный status row для текущего runtime session state, чтобы persisted intent не маскировался под уже переключённый sync runtime;
- [x] подключить `AppComposition` / `AppDependencies.makeWithSwiftData` к policy sync enablement: перед созданием основного `ModelContainer` приложение должно делать bootstrap-read persisted `AppSettings.useiCloudSync` через временный local-only configuration, после чего поднимать финальный `sync-backed` store либо с private `CloudKit`, либо с `.none`, чтобы app bootstrap соответствовал сохранённому user intent уже на следующем запуске;
- [x] реализовать runtime account availability adapter через `CKContainer.accountStatus()` и `CKAccountChanged`: выделен отдельный service-layer adapter, который маппит `CKAccountStatus` в runtime-состояния `available`, `noAccount`, `restricted`, `temporarilyUnavailable` и `couldNotDetermine`, а также переопрашивает account availability при `CKAccountChanged` без смешивания этого слоя с `SyncCoordinator` и store event orchestration;
- [x] выделить `CloudKit` runtime event source на базе `NSPersistentCloudKitContainer.eventChangedNotification`: добавлен отдельный adapter, который нормализует `NSPersistentCloudKitContainer.Event` в runtime-события `setup` / `import` / `export`, различает активную фазу по `endDate == nil`, завершённые успешные события и runtime failures по завершившимся unsucceeded/error events, и тем самым подготавливает отдельный event feed для будущего `SyncCoordinator` без смешивания его с placeholder `ICloudSyncStatusService`;
- [x] создать базовый `SyncCoordinator` как app-level orchestration layer для CloudKit/SwiftData sync lifecycle и единственную точку владения runtime sync state: выделен отдельный coordinator с собственным `SyncRuntimeState`, который хранит enablement, account context, активность `setup` / `import` / `export`, runtime failures и проекцию в текущий `ICloudSyncStatus`, но пока ещё не подключён к реальным account/event sources и app lifetime wiring следующими пунктами roadmap;
- [x] подключить account availability и `CloudKit` events к `SyncCoordinator`, чтобы coordinator различал disabled state, account problems, setup/import/export activity и runtime failures: `SyncCoordinator` теперь умеет подписываться на `ICloudAccountAvailabilityService` и `CloudKitRuntimeEventSource`, применять initial/current account availability, реагировать на последующие `CKAccountChanged`-derived updates и `CloudKit` runtime events, а также удерживать единый runtime state для disabled, account problem, active `setup` / `import` / `export` и failure cases без app-level wiring следующего шага;
- [x] подключить `SyncCoordinator` к `AppDependencies` и `AppComposition`, чтобы coordinator имел app-level lifetime и стал единым runtime source для status service, shell state и последующих reload consumers: `AppComposition` теперь создаёт app-level `SyncCoordinator` и стартует его один раз на app launch, а `AppDependencies` удерживает coordinator вместе с runtime sources и explicit startup hook, чтобы последующие пункты roadmap могли читать единый sync runtime из dependency graph, не создавая новые coordinator instances по месту использования;
- [x] заменить текущий placeholder `ICloudSyncStatusService` на реализацию, которая читает фактический runtime state из `SyncCoordinator` и account/store context: status service больше не смотрит напрямую на persisted `useiCloudSync`, а выступает thin projection поверх app-level `SyncCoordinator`, чтобы `Settings Screen`, app bootstrap и последующие shell consumers читали единый runtime sync status, уже собранный из enablement policy, account availability и `CloudKit` store events;
- [x] подключить runtime sync status из `SyncCoordinator` к `AppState` и shell-level state, чтобы UI обновлялся из реального sync lifecycle, а не только из persisted intent: `AppComposition` теперь зеркалит текущий `SyncCoordinator.iCloudSyncStatus` в `AppState`, а shell-level presentation (`Sidebar` toolbar и другие потребители `AppState`) начинает читать runtime status уже из app-level state вместо одноразовой интерпретации persisted intent, что подготавливает следующие шаги про richer sync UX и remote reload wiring;
- [x] расширить account/status UX для sync: `Settings Screen` теперь использует richer sync status presentation поверх `SyncCoordinator.runtimeState`, различает `noAccount`, `restricted`, `temporarilyUnavailable`, `couldNotDetermine`, общую runtime checking state, activity-specific `setup` / `import` / `export` copy и явным текстом объясняет, что для sync используется `Apple ID`, уже вошедший на устройстве, без отдельной учётной записи приложения;
- [x] реализовать app-level reload triggers именно для `CloudKit import` / remote sync path на базе `NSPersistentStoreRemoteChange` и завершения import-событий: добавлен отдельный runtime source для remote store change notifications, `AppDependencies` теперь держит app-level lifetime orchestration, которая выпускает reload только при pair `remote change + finished import`, а `AppState` получил отдельный remote sync reload path для `Sidebar`, `Articles` и `Article Screen`, не смешанный с reload behavior следующего эпика `Background Refresh`;
- [x] добавить unit/integration tests для `SyncCoordinator`, account status mapping, `CloudKit` event mapping и remote reload wiring: покрыты unit-сценарии для `SyncCoordinator` и `CKAccountStatus` mapping, `CloudKit` runtime event mapping проверяется отдельно от notification bridge, а app-level remote reload wiring дополнительно зафиксирован integration-тестами на pair semantics, порядок прихода `remote change` и `finished import`, а также guard against stale reload после failed import, чтобы следующий блок `Sync Validation` опирался уже на стабилизированный runtime contract.

#### Sync Validation
- [x] устранить bootstrap blocker для `CloudKit`-backed `SwiftData` store перед simulator validation: выровнен `validation contract` с фактическим `runtime contract`, расширена диагностика `ModelContainer` / `NSPersistentCloudKitContainer`, а `syncBacked` schema приведена к требованиям `CloudKit` через property-level defaults для non-optional attributes и явную двустороннюю `Feed` / `Folder` relationship boundary, после чего `Settings Screen` снова открывается при включённом `useiCloudSync` и runtime может дойти до account-status checking state;
- [x] очистить app-level `CloudKit` bootstrap/runtime path и simulator diagnostics на одном endpoint: `schema bootstrap`, `ModelContainer` bootstrap и diagnostic/probe paths больше не повторно поднимают конфликтующие `NSPersistentCloudKitContainer`-инстанции, не мутируют immutable `NSManagedObjectModel`, не зацикливают launch на `another instance of this persistent store actively syncing with CloudKit in this process` и не засоряют лог ложными `Core Data` / `CloudKit` ошибками при неготовом account/runtime path, оставляя в runtime только реальные account-status сигналы (`Skipped CloudKit development schema bootstrap...`, `Skipped CloudKit-backed model container bootstrap...`);
- [x] завершить app-level bootstrap flow для `useiCloudSync`: persisted sync preference больше не зависит только от локального `AppSettings.useiCloudSync`, app-level bootstrap теперь хранит явный `desired sync intent` отдельно от effective `ModelContainer` policy текущего launch, `SyncCoordinator` не стартует как `CloudKit`-enabled при local-only fallback bootstrap, а `Settings Screen` последовательно объясняет пользователю переход между сохранённым sync intent и временно недоступным `CloudKit` account/runtime path;
- [x] сузить и покрыть тестами account/bootstrap gating вокруг `CKAccountStatus`: для `available`, `temporarilyUnavailable`, `noAccount`, `restricted` и `couldNotDetermine` нужно отдельно зафиксировать, когда приложение поднимает `CloudKit`-backed store, когда остаётся в local-only bootstrap path и как при этом маппится runtime status в `SyncCoordinator` и `Settings Screen`;
- [x] завершить cleanup/refactor sync bootstrap/runtime кода: выровнять границы между `RSSReaderApp`, `AppComposition`, `AppDependencies`, `CloudKitDevelopmentSchemaBootstrap`, `SyncCoordinator` и diagnostic/probe helpers, удалить временные workaround/debug hooks, а также оставить один понятный путь для account-aware bootstrap и runtime sync diagnostics;
- [x] усилить app-level логирование и диагностику sync-ошибок: account/status resolution, bootstrap policy selection, `NSUbiquitousKeyValueStore` preference propagation, `CloudKit` runtime failures и app-level reload correlation должны логироваться так, чтобы следующий цикл simulator/device validation можно было проводить без повторного добавления ad-hoc debug кода.
- [x] добить единый composition/bootstrap path для sync validation: убрать или выровнять запасной `AppComposition.makeRoot(modelPartition:)` path, который сейчас может обходить `makeAppDependencies()`, чтобы любой app/previews/test harness bootstrap проходил через один и тот же account-aware sync setup, общий `logger` и `SyncCoordinator` wiring;
- [x] покрыть тестами `AppSyncBootstrapPreferenceStore` и `NSUbiquitousKeyValueStore` propagation: отдельно зафиксировать приоритет между `NSUbiquitousKeyValueStore` и `UserDefaults`, поведение `synchronize()`, запись bootstrap preference в оба storage и соответствующие diagnostic logs, чтобы sync enablement bootstrap больше не зависел от неявного внешнего состояния;
- [x] решить судьбу DEBUG-only schema bootstrap guard: либо вынести `CloudKitDevelopmentSchemaBootstrap.didAttemptBootstrapThisLaunch` в явный и тестируемый app-level guard, либо удалить его в пользу более прозрачного orchestration path, чтобы DEBUG bootstrap не зависел от скрытого process-global состояния.

#### Sync Hardening
- [x] сузить app-level remote reload correlation до конкретного `sync-backed` store: текущий reload wiring уже требует pair `NSPersistentStoreRemoteChange + finished import`, но пока не сопоставляет store identity между `remote change` и `CloudKit` event context; нужно выпускать reload только для совпавшего sync-backed store и не реагировать на несвязанные или future local-only/store-adjacent notifications;
- [x] покрыть store-scoped remote reload correlation дополнительными integration-тестами: отдельно зафиксировать сценарии mismatched `storeIdentifier` / `storeUUID`, local-only store notifications, повторные import events без нового remote change и stale pending state после failure/cancellation, чтобы reload contract не оставался вероятностным;
- [x] довести app-level логирование и диагностику sync bootstrap/runtime до полного operational contract: отдельно логировать container setup failures, schema/bootstrap failures, bootstrap fallback reasons, account/status resolution, merge/import/export failures и итоговые reload decisions так, чтобы будущая device validation шла по заранее известным log markers без ad-hoc instrumentation;
- [x] определить и зафиксировать окончательную projection boundary для runtime sync state: решить, остаётся ли `ICloudSyncStatusService` самостоятельным read-model adapter поверх `SyncCoordinator` или удаляется в пользу прямого app-level runtime source, после чего выровнять чтение sync status между `SyncCoordinator`, `AppState`, `Settings Screen` и shell-level consumers без дублирующих status projections;
- [x] провести cleanup / refactor app-level sync orchestration после стабилизации runtime contract: сузить обязанности `AppDependencies` вокруг remote reload/bootstrap wiring, убрать одноразовые diagnostic helpers и оставшиеся временные glue-ветки, а также оставить одну понятную композицию между `AppComposition`, `AppDependencies`, `SyncCoordinator` и runtime sources;
- [x] добавить явный teardown / cancellation path для `AppSyncRuntimeOrchestrator`: убрать текущую lifecycle-зависимость от app-lifetime-only поведения, гарантированно отменять observation tasks для `CloudKitRuntimeEventSource` и `PersistentStoreRemoteChangeSource`, а также исключить retain cycle между orchestrator и `Task`, чтобы previews, test harness и пересборка dependency graph не оставляли висящие sync subscriptions;
- [x] зафиксировать отдельную app-level boundary между `remote sync reload` и будущим `background refresh reload`: не смешивать `CloudKit import`-driven reload path с foreground/background refresh orchestration, чтобы следующий эпик `Background Refresh` переиспользовал только нужные reload hooks в `AppState`, не размывая текущий sync runtime contract.

### Background Refresh
#### Background Refresh Foundation
- [x] ввести app-level `Background Refresh` identifier contract: выбран постоянный identifier, он добавлен в `Info.plist` через `BGTaskSchedulerPermittedIdentifiers` и зафиксирован как infrastructure-level константа, чтобы `RSSReaderApp`, scheduler и validation использовали один и тот же source of truth;
- [x] зарегистрировать app-level entry point в `RSSReaderApp` через SwiftUI `backgroundTask(.appRefresh(...))`, чтобы background launch шёл через явный корневой handler, а не требовал screen-level участия;
- [x] выделить отдельный scheduler layer для `BGAppRefreshTaskRequest`: scheduler умеет `schedule`, `cancel` и `replace` pending request, а логика `earliestBeginDate` не живёт внутри `RSSReaderApp`, `RootView` или controller-кода;
- [x] связать scheduler policy с текущим `BackgroundRefreshService` contract: `RefreshPreference` уже маппится в `minimumBackgroundRefreshInterval`, и это значение стало единственным входом для app-level scheduling policy без дублирования интерпретации interval в UI или app shell;
- [x] подключить scheduler к app bootstrap: на launch приложение читает текущую `BackgroundRefreshConfiguration` и либо ставит следующий request, либо явно очищает pending background work для `manual`;
- [x] связать scheduler с изменением `refreshIntervalPreference`: после обновления настройки через `Settings Screen` приложение перепланирует или отменяет pending request без расхождения между persisted `AppSettings`, `BackgroundRefreshService` и `BGTaskScheduler`;
- [x] добить system prerequisites для `BGAppRefreshTask`: проверены и явно включены `Background Modes` с `fetch`, а также подтверждено, что после перехода на явный `Info.plist` app target не потерял обязательные plist/capability-настройки для background refresh.

#### Background Refresh Execution
- [x] подключить системный `background task` к существующему `BackgroundRefreshService`, чтобы фактическое выполнение фонового refresh шло через уже реализованный service layer и `FeedRefreshService.refreshAllActiveFeedsForBackground()`, а не через отдельную app-level refresh ветку;
- [x] ввести app-level execution coordinator для SwiftUI `backgroundTask(.appRefresh(...))`: coordinator владеет запуском refresh `Task`, наблюдением за системной cancellation через `withTaskCancellationHandler` и преобразованием service-level результата в единый execution outcome contract, не протаскивая execution-логику обратно в `RSSReaderApp`;
- [x] зафиксировать execution outcome contract для background refresh: явно определено, как трактуются success, partial failure, total failure, skipped `manual` policy и cancellation в SwiftUI completion path, чтобы post-run scheduling, logging и foreground reload опирались на один и тот же app-level результат;
- [x] после любого завершившегося background execution планировать следующий request через тот же scheduler, чтобы runtime не расходился между initial bootstrap path и post-run path;
- [x] зафиксировать persistence contract для materialized `Article`: background refresh обновляет тот же local-only article cache, который уже используют foreground refresh flows и query services, без отдельной модели или special-case persistence path;
- [x] определить foreground handoff policy после background refresh: явно закреплено, когда достаточно только сохранить локальные данные до следующего открытия экрана, а когда при возврате приложения в foreground `AppState` должен выпускать отдельный `backgroundRefresh` reload trigger без смешения с текущим `remoteSyncImport` path;
- [x] реализовать app-level foreground reload orchestration для `backgroundRefresh`: после успешного background execution `AppComposition` и `AppState` должны один раз доставить нужный reload trigger в активный runtime и не плодить лишние reload во время неактивного состояния приложения;
- [x] добавить execution-level logging и diagnostics markers для start, completion, cancellation, skipped-manual policy и reschedule outcome, чтобы `Background Refresh Validation` мог опираться на наблюдаемый runtime contract, а не только на косвенные side effects;
- [x] обработать сценарии отсутствия сети, системной cancellation по тайм-бюджету, disabled `Background App Refresh` и других execution failures так, чтобы background refresh не ломал локальное состояние, не маскировал проблему под success и оставлял понятный scheduling follow-up;
- [x] покрыть tests execution orchestration: success, partial failure, total failure, cancellation, skipped-manual policy, post-run reschedule и foreground reload handoff должны быть проверены отдельно от scheduler tests;
- [x] довести typed scheduling failure diagnostics до всех app-level scheduling paths: launch bootstrap и settings-driven reschedule логируют те же классифицированные причины (`backgroundRefreshUnavailable`, `notPermitted`, `tooManyPendingTaskRequests`), что и post-run execution path, чтобы validation не зависел от generic error messages вне execution coordinator;
- [x] стабилизировать cancellation/runtime markers для validation: marker о получении системной cancellation должен публиковаться в детерминированном app-level порядке относительно terminal execution outcome, чтобы device validation не опирался на потенциально гоняющийся fire-and-forget logging path;
- [x] отделить heuristic network-failure diagnostics от validation contract: явно зафиксировано в execution contract, что `likelyNoConnectivity` остаётся best-effort marker и не должен использоваться как единственный источник истины в validation сценариях.

#### Background Refresh Validation
- [x] добавить явный app-level registration marker для `Background Refresh`: `RSSReaderApp` публикует bootstrap marker для `.backgroundTask(.appRefresh(...))` path и identifier contract, а launch scheduling перенесён из `makeAppDependencies()` в guarded app-root startup path, чтобы `BGTaskScheduler.submit` не происходил раньше registration handler;
- [x] добавить typed app-level snapshot для `Background Refresh` runtime prerequisites: введён отдельный infrastructure-level source, который собирает `backgroundRefreshStatus`, `Low Power Mode`, `refreshIntervalPreference` и app-level `schedulingMode`, а `AppDependencies` публикует этот snapshot как единый runtime entry point для future validation и diagnostics;
- [x] ввести единый `Background Refresh` validation diagnostics contract: добавлен отдельный app-level diagnostics reporter с typed snapshot по stage-ам (`registration`, `scheduling`, `executionStart`, `executionCancellation`, `executionCompletion`, `postRunReschedule`), а `RSSReaderApp`, `AppComposition` и `BackgroundRefreshExecutionCoordinator` публикуют единые markers с префиксом `Background refresh validation stage=...` вместо разрозненных app-level литералов;
- [x] покрыть tests-ами validation observability layer: добавлен отдельный infrastructure-level suite для registration marker, runtime prerequisites snapshot и diagnostics reporter contract, чтобы observability-поведение проверялось напрямую, а не только как побочный эффект существующих scheduler / execution orchestration tests.

#### Background Refresh Hardening
- [x] провести cleanup / refactor background refresh-related кода после введения validation observability: app lifecycle wiring больше не собирает registration / launch scheduling / execution вручную через top-level helpers и legacy app-level markers; `RSSReaderApp` и `AppComposition` делегируют эти app-level входы в `AppDependencies`, где сходятся `BackgroundRefreshService`, execution coordinator, scheduler и validation diagnostics reporter, а временные debug hooks в launch scheduling path удалены;
- [x] сузить `Background Refresh` diagnostics surface до устойчивого app-level contract: `BackgroundRefreshValidationDiagnosticsReporter` оставлен единственным каноническим набором validation markers, а scheduler / `BackgroundRefreshService` / app-level wrappers вокруг них переведены на `debug`-only internal traces с явными `... trace ...` префиксами, чтобы validation не опирался на второй конкурирующий набор логов;
- [x] после cleanup diagnostics проверить, что app-level reload boundary между `remote sync reload` и `background refresh reload` не деградировала и не замаскирована новыми hardening-правками: добавлен сквозной test, который поднимает оба app-level пути на одном `AppState` и подтверждает, что foreground handoff path продолжает выставлять `backgroundRefresh`, а CloudKit / persistent store correlation path продолжает выставлять `remoteSyncImport`, не схлопывая оба reload-сигнала в один flow.

### Polish
#### Interface Polish
- [x] `Launch Navigation`: запускать приложение с экраном `Sources`, а не с заранее выбранным `Inbox` / экраном статей; закрепить это в `ReadingNavigationState` и compact-column policy, чтобы первый экран был экраном выбора источников;
- [x] `Add Feed Input Polish`: сделать placeholder в поле `Feed URL` визуально вторичным и не похожим на активную ссылку;
- [x] `Feed Discovery From Site URL`: разрешить ввод короткого адреса сайта вроде `example.com` в `SourceManagement` flow; нормализовать ввод, проверить типовые `http` / `https` варианты, RSS / Atom candidates и HTML autodiscovery, затем показать пользователю найденный feed или понятную ошибку, если источник добавить нельзя;
- [x] `Sources Toolbar Actions`: разъединить в `SidebarView` действия добавления источника и фильтрации так, чтобы `Add Source` и `Filter Sources` воспринимались как отдельные toolbar controls;
- [x] `Reader Adjacent Article Navigation`: добавить переход к следующей и предыдущей статье из `ReaderView` без возврата к списку; свайп вверх должен открывать следующую статью, свайп вниз — предыдущую, если такая статья есть в текущем article-list context;
- [x] `Safari Route Model`: переименовать web-view navigation contract в app-level `ArticleSafariRoute` / `ReadingDetailRoute.safari`, чтобы route явно описывал системный in-app browser, а не кастомный `WKWebView`;
- [x] `Safari Presentation Bridge`: заменить `WebViewScreenView` на SwiftUI bridge к `SFSafariViewController` через `UIViewControllerRepresentable`, настроить `dismissButtonStyle`, `barCollapsingEnabled` и delegate-driven dismiss обратно в `AppState`;
- [x] `Safari App Wiring`: переименовать article-browser entry points в `AppDependencies.openArticleInSafari` / `closePresentedArticleSafari` и убедиться, что source article / body link opening проходят через новый app-level Safari flow без web-view терминологии;
- [x] `Safari Unsupported URL Handling`: сохранить app-level проверку `http` / `https` URL до показа `SFSafariViewController`, чтобы unsupported article links не приводили к пустому browser presentation;
- [x] `Safari Browser Tests`: закрепить shell / article-screen tests вокруг `SFSafariViewController` presentation, dismiss flow, source article opening и body link opening после замены кастомного `WKWebView`;
- [x] `Remove WKWebView Browser Surface`: удалить устаревшие `WebViewScreenState`, `WebViewScreenController`, кастомный `WKWebView` bridge, preview/loading/reload/open-external toolbar state и связанные tests, если они больше не используются после перехода на `SFSafariViewController`;
- [x] `Swipe Actions Dark Theme`: исправить цвета swipe actions для `Unread` / `Read` и `Starred` в `ArticleListContentView`, чтобы в тёмной теме фон и символы оставались контрастными;
- [x] `Settings Picker Menus`: заменить `confirmationDialog` для picker-настроек на inline `Menu` внутри строки настройки, чтобы короткие списки опций открывались рядом с выбранной настройкой без отдельного modal / drill-down flow;
- [x] `Settings Information Architecture`: перегруппировать `SettingsScreen` в четыре группы `Appearance`, `Reading`, `Article List` и `Updates & Sync`, поднять app-level оформление выше, оставить reading/list настройки рядом с основным flow и объединить background refresh с iCloud sync вместо отдельного `Advanced`;
- [x] `Settings Value Control Layout`: привести picker-ячейки `SettingsScreen` к iOS Settings-like layout: убрать inline-описания из picker-строк в section footers, показывать короткие selected values справа, длинные selected values второй строкой под названием настройки, открывать `Menu` только из value-control с `chevron.up.chevron.down`;
- [x] Синхронизировать `SettingsScreen` / `SourceManagementScreen` modal presentation с текущим `AppThemeApplicationPolicy`, чтобы системные `List`-ячейки и кастомный фон не расходились после смены темы.
- [x] `Source Management Copy Polish`: переписать тексты `SourceManagementScreen` для добавления / редактирования источников и папок так, чтобы они описывали пользовательский сценарий без технических деталей про validation, preview metadata, parser diagnostics и sidebar internals;
- [x] `Add Feed Single Save Flow`: убрать промежуточный `Confirm Feed` / `Confirm Changes` state из add/edit feed flow и разгрузить navigation bar: оставить системный inline `navigationTitle`, заменить правый action на compact confirmation button с галочкой, неактивной до успешного preview, перенести `Preview Feed` вниз формы, а после preview дать один финальный action `Add Feed` или `Save Changes`, который сохраняет источник, делает initial refresh и открывает экран статей источника;
- [x] `Edit Feed URL-Only Flow`: убрать перемещение между папками из edit feed screen, чтобы экран редактирования источника отвечал только за изменение URL и связанную с ним повторную проверку `Preview Feed`; если пользователь не меняет URL, экран не должен требовать сетевой preview ради изменения размещения, потому что folder placement будет вынесен в отдельный organize-flow;
- [x] `Source Organize Context Action`: добавить для источника действие `Organize...` из long-press / context menu, которое открывает отдельный flow перемещения выбранного источника между папками по модели существующего `Move Sources`, но сразу с предвыбранным feed и без сетевой проверки `Preview Feed`;
- [x] `Source Management Compact Confirmation Controls`: привести оставшиеся create/edit окна `SourceManagementScreen` к единому compact confirmation pattern: заменить длинные navigation-bar кнопки с текстом на compact action с галочкой, убрать лишнюю нагрузку с navigation bar, а на экране `Add Source` заменить `Done` на системный close-control с крестиком;
- [x] `Source Management Direct Launch Close Control`: при открытии `SourceManagementScreen` сразу в edit feed, edit folder или organize feed flow из sidebar context menu заменить системную кнопку back на close-control с крестиком, чтобы пользователь мог закрыть модальное окно без возврата на entry-экран `Add Source`;
- [ ] `Folder Reorder Controls`: заменить текстовую секцию `Sidebar Placement` в create/edit folder flow на явные move up / move down controls в `Existing Folders`, добавить service/repository contract для изменения `Folder.sortOrder` и обновлять sidebar порядок без ручного ввода позиции;
- [ ] `Add Feed Completion Stays On Sources`: изменить app-level completion после создания источника: после успешного `Add Feed` закрывать `SourceManagementScreen`, обновлять список `Sources`, но оставаться на экране источников без автоматического перехода на экран статей добавленного feed;
- [ ] `Add Feed Nested Folder State Restoration`: сохранить состояние `add feed` flow при переходе в `Create New Folder` из уже полученного `Preview Feed`: при возврате назад пользователь должен видеть тот же URL, preview metadata, выбранную папку и доступный финальный `Add Feed`, а не сброшенную форму;
- [ ] `Empty Folders Sidebar Visibility`: показывать на экране `Sources` все сохранённые папки, включая пустые, и сохранять для них context menu / long-press действия `Edit...` и `Delete`, чтобы папку можно было переименовать или удалить даже до добавления источников;
- [ ] `Folder Name Case-Insensitive Uniqueness`: усилить invariant имени папки на уровне validation и service/repository boundary: запретить создание и переименование папок, которые отличаются только регистром или пробелами вокруг имени, например `Tech` и `TeCh`;
- [ ] `Custom Activity Indicator`: заменить оставшиеся системные `ProgressView` в приложении на единый кастомный SwiftUI-индикатор активности, чтобы loading UI не зависел от lifecycle edge cases `ProgressView` внутри `List`, `NavigationStack` и условных секций;
- [ ] `Feed Display Name Override`: добавить пользовательское имя источника поверх title из feed XML, чтобы source title можно было задать вручную при добавлении и редактировании источника; refresh должен обновлять техническую metadata из XML, но не перетирать выбранное пользователем display name и связанные article/sidebar projections;
- [ ] `Feed Import Preview And Limits`: сделать initial subscription понятнее: показывать, сколько entries найдено в preview / initial refresh, и ввести явный app-level policy для ограничения количества импортируемых статей при подписке на источник, чтобы разные feed payload sizes не приводили к непредсказуемым 20 / 100+ новым статьям;
- [ ] `Article Retention Policy`: отделить feed reconciliation от видимости архива статей: статьи, уже попавшие на устройство, должны оставаться доступными до выбранного retention window (`all time`, `6 months`, `1 month`, `1 week`), а настройка retention должна управлять cleanup / list visibility без неожиданного исчезновения прочитанных старых статей;
- [ ] `Reader HTML Body Normalization`: улучшить обработку HTML / escaped HTML из RSS / Atom payloads перед рендерингом статьи, чтобы `ArticleScreenContentRenderer` показывал читаемый текст и ссылки, а не literal `<p>` / `<a href=...>` fragments из XML;
- [ ] `Adjacent Article Navigation Stabilization`: стабилизировать swipe navigation в `ReaderView`, чтобы свайп вверх / вниз использовал актуальный article navigation context и не мог повторно выбирать текущую статью при наличии следующей / предыдущей статьи в текущем списке;
- [ ] `Reader Mode Semantics`: пересмотреть настройки `Open Articles` для `Embedded Reader` и `Reader Mode`: либо реализовать реально различающееся поведение reader-mode / full-text extraction, либо объединить / переименовать режимы так, чтобы настройка не обещала несуществующий сценарий.

#### Testing
- [ ] unit tests для normalizer;
- [ ] unit tests для date parsing;
- [ ] unit tests для external ID generation;
- [ ] unit tests для deduplication;
- [ ] unit tests для article state transitions;
- [ ] integration tests для refresh pipeline;
- [ ] UI tests для add feed flow;
- [ ] UI tests для read/unread flow.

### Deferred Validation
#### Sync Real-Device Validation Kit
- [ ] собрать явный `validation checklist` для sync-сценариев на паре `simulator + real device`: first launch с `useiCloudSync = off`, first launch с `useiCloudSync = on`, bootstrap fallback при `noAccount` / `temporarilyUnavailable`, включение и выключение sync из `Settings Screen`, remote import после изменений на втором рантайме и повторный launch после уже включённого sync;
- [ ] для каждого сценария зафиксировать ожидаемый operational contract: `bootstrap path`, `SyncCoordinator.runtimeState`, `AppState.iCloudSyncStatus`, состояние `Settings Screen` и ожидаемые `log markers`, чтобы validation опирался на уже существующую app-level диагностику, а не на ручные догадки;
- [ ] подготовить минимальный `smoke-test matrix` только для `simulator + real device`: fresh install, existing local-only store и existing sync-backed store на одном iCloud account, чтобы после появления платного `Apple Developer Program` membership было понятно, какой минимальный набор прогонов обязателен;
- [ ] описать prerequisites и reset procedure для deferred sync validation: какой build/configuration использовать, как очищать local store и install state, как подготавливать iCloud account и какие логи собирать при mismatch;
- [ ] подготовить шаблон фиксации результатов validation pass с полями `scenario`, `environment`, `result`, `observed status transitions`, `observed log markers` и `notes`, чтобы финальная проверка синхронизации документировалась консистентно.

#### Background Refresh Real-Device Validation Kit
- [ ] проверить ограничения бесплатного `Apple Developer` / `Personal Team` для полного `Background Refresh` validation path: какие части single-device и combined validation доступны без платного membership, а какие блокируются capability / signing / cloud-инфраструктурой;
- [ ] если после проверки ограничений подтверждается блокировка на `Personal Team`, считать приоритетной инфраструктурной задачей раннее подключение платного аккаунта разработчика, чтобы снять долг сразу по двум направлениям: `Sync Real-Device Validation Kit` и `Background Refresh` real-device validation;
- [ ] зафиксировать шаблон `validation pass` для `Background Refresh` с полями `scenario`, `environment`, `preconditions`, `observed log markers`, `observed runtime state`, `result` и `notes`, чтобы device-проверки документировались консистентно;
- [ ] подготовить минимальный `single-device validation matrix` для `Background Refresh`: simulator-only smoke check, real-device scheduling check и отдельные real-device execution scenarios, чтобы validation можно было закрывать инкрементально, а не одним большим прогоном;
- [ ] проверить baseline single-device сценарий `automatic refresh`: request планируется на launch, background task стартует через system/dev trigger, execution публикует ожидаемые markers и после run перепланирует следующий request;
- [ ] проверить failure-oriented single-device сценарии: отсутствие сети, системное cancellation / expiration, disabled `Background App Refresh`, Low Power Mode и `manual` policy не ломают локальное состояние и оставляют ожидаемый scheduling / logging outcome;
- [ ] подготовить combined `sync + background refresh` validation matrix для двух девайсов: сценарии с background materialization на втором устройстве должны идти отдельным deferred шагом после закрытия single-device validation;
- [ ] проверить сценарий “обновили источники на iPhone, прочитали часть статей, открыли iPad после background refresh”: второй девайс должен локально материализовать свежие `Article`, применить synced `ArticleState` и показать только непрочитанные статьи в `Unread`;
- [ ] проверить fallback-сценарий без background refresh: после тех же действий на первом устройстве второй девайс должен достигать консистентного состояния через manual refresh без расхождения с background materialization contract.

### Release Prep
#### App Store Preparation
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
