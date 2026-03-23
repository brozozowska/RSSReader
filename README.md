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

Предполагаемая структура проекта:
- **App** — точка входа в приложение, конфигурация контейнера SwiftData, регистрация background tasks, корневой роутинг;
- **Models** — доменные модели и структуры данных;
- **Services** — работа с сетью, XML, нормализацией, хранилищем, синхронизацией, фоновой загрузкой;
- **ViewModels** — состояние экранов и пользовательские действия;
- **Views** — экранные и переиспользуемые SwiftUI-компоненты;
- **Infrastructure** — конфигурация приложения, зависимости, логирование, служебные компоненты.

Ключевые архитектурные принципы:
- **SwiftUI** как основной UI-фреймворк;
- **MVVM-подход** для разделения представления и логики представления;
- **SwiftData** для локального хранения данных;
- **Repository pattern** для изоляции доступа к данным;
- **Swift Concurrency (async/await)** для асинхронных операций и потоков событий через AsyncSequence/AsyncStream;
- минимизация жёсткой связанности между UI, хранением и сетевым слоем.

Базовый поток данных предполагается таким:
1. приложение запрашивает RSS-источник;
2. сетевой слой загружает данные;
3. слой парсинга преобразует RSS во внутренние модели;
4. репозитории сохраняют и отдают данные приложению;
5. ViewModels подготавливают состояние для интерфейса;
6. Views отображают список лент, статьи и состояние приложения.

## Roadmap

### Foundation
#### Repository / Project Setup
- инициализация Xcode-проекта;
- настроить `.gitignore`;
- создать milestones для фаз MVP;
- настроить лейблы в проекте;
- настроить GitHub Project;
- добавить `README` в проект.

#### App Foundation
- создать структуру каталогов: `Models` / `Services` / `ViewModels` / `Views` / `Infrastructure`;
- добавить `AppDependencies.swift`;
- настроить контейнер `SwiftData`;
- настроить базовую dependency composition;
- подготовить конфигурацию для `debug/logging`;
- добавить app-level state для выбора `feed/article`;
- настроить базовый root navigation через `NavigationSplitView`.

#### Domain Models
- создать модели `Feed`, `Article`, `ArticleState`, `AppSettings`, `Folder`;
- определить связи между моделями;
- гарантировать синглтон для `AppSettings`;
- определить уникальность `Folder.name`;
- зафиксировать правила генерации `externalID` на всех устройствах;
- зафиксировать удаление `ArticleState` при удалении `Feed`;
- подумать о производительности;
- добавить `FeedFetchLog`, определить минимальный набор полей для отладки fetch.

### Feed Pipeline
#### Networking / Feed Fetch
- создать HTTP client abstraction;
- реализовать GET-запрос feed URL;
- обработать HTTP errors;
- добавить поддержку ETag;
- добавить поддержку Last-Modified;
- реализовать conditional requests;
- логировать результат fetch;
- использовать async/await для сетевых запросов;
- добавить retry policy на сетевые ошибки.

#### Parsing / Normalization
- создать FeedParserService;
- поддержать RSS parsing;
- поддержать Atom parsing;
- определять тип фида rss/atom/unknown;
- извлекать метаданные feed;
- извлекать список entries/items;
- создать промежуточные DTO для parser layer;
- создать NormalizationService;
- нормализовать title/source URLs;
- нормализовать article content/summary;
- реализовать парсинг дат из нескольких форматов;
- реализовать построение стабильного externalID;
- создать DeduplicationService;
- добавить стратегию дедупликации по externalID/guid/url;
- отбрасывать пустые/сломанные entries.

#### Persistence / Repositories
- создать FeedRepository;
- создать ArticleRepository;
- создать ArticleStateRepository;
- создать SettingsRepository;
- сохранение нового feed;
- загрузка списка feeds;
- сохранение новых статей;
- обновление существующих статей;
- получение статей для выбранного feed;
- получение глобального inbox;
- удаление feed с каскадной очисткой article cache;
- обновление unread counts.

#### Refresh Orchestration
- создать FeedRefreshService;
- реализовать refresh одного feed;
- реализовать refresh всех active feeds;
- ограничить параллелизм запросов;
- использовать TaskGroup/Structured Concurrency для параллелизма;
- исключить параллельный двойной refresh одного feed;
- обновлять lastFetchedAt;
- обновлять lastSuccessfulFetchAt;
- сохранять lastSyncError;
- обрабатывать 304 Not Modified.

### Reading Experience
#### User State / Reading Actions
- создать ArticleStateService;
- реализовать markAsRead;
- реализовать markAsUnread;
- реализовать toggleStarred;
- добавить markAsReadOnOpen;
- добавить bulk action markAllVisibleAsRead;
- обновлять updatedAt при каждом пользовательском изменении;
- подготовить логику last-write-wins для конфликтов состояния.

#### Sidebar UI
- создать SidebarViewModel;
- экран sidebar со списком feeds;
- показ unread counts;
- добавить smart sections: All;
- добавить smart sections: Unread;
- добавить smart sections: Starred;
- добавить выбор активного feed;
- добавить empty state для отсутствия подписок.

#### Article List UI
- создать ArticleListViewModel;
- список статей выбранного feed;
- глобальный список всех статей;
- сортировка по publishedAt desc;
- фильтр unread only;
- отображение состояния read/unread;
- отображение starred state;
- pull to refresh (c async/await обработкой обновления);
- empty state для пустого списка;
- error state для ошибки загрузки.

#### Reader UI
- создать ReaderViewModel;
- экран чтения статьи;
- показ title/source/date;
- показ summary/content;
- действие open in browser;
- действие share;
- действие mark unread;
- действие star/unstar;
- автоматическая отметка read on appear.

#### Add Feed Flow
- создать AddFeedViewModel;
- экран добавления feed по URL;
- валидация URL;
- превью найденного feed;
- сохранение feed;
- первый refresh после добавления;
- обработка ошибки при невалидном или неподдерживаемом feed;
- empty/error UX для add feed flow.

#### Settings
- создать SettingsViewModel;
- экран настроек;
- markAsReadOnOpen;
- show unread only default;
- sort mode;
- iCloud sync indicator;
- ручной refresh.

### Sync
#### Sync / CloudKit
- настроить SwiftData + CloudKit;
- проверить синк Feed;
- проверить синк ArticleState;
- проверить синк AppSettings;
- добавить Folder в sync scope;
- реализовать SyncCoordinator;
- обработка конфликтов ArticleState по updatedAt;
- проверить сценарий запуска на втором устройстве;
- добавить UI-индикатор состояния синка;
- логирование sync-ошибок.

### Background Refresh
#### Background Refresh
- создать BackgroundRefreshService;
- зарегистрировать background task;
- планировать следующий refresh;
- запускать FeedRefreshService в фоне;
- корректно завершать background task;
- обновлять данные после background refresh;
- проверить поведение при отсутствии сети.

### Polish
#### Testing
- unit tests для normalizer;
- unit tests для date parsing;
- unit tests для external ID generation;
- unit tests для deduplication;
- unit tests для article state transitions;
- integration tests для refresh pipeline;
- UI tests для add feed flow;
- UI tests для read/unread flow.

#### Polish / Release Prep
- улучшить launch/empty/loading states;
- улучшить сообщения об ошибках;
- проверить accessibility labels;
- проверить performance на длинных списках;
- подготовить app icons;
- подготовить screenshots;
- подготовить privacy notes;
- подготовить TestFlight checklist;
- подготовить release checklist.

### Post-MVP
#### Post-MVP backlog
- feed discovery по URL сайта;
- OPML import;
- OPML export;
- full text extraction/reader mode;
- image prefetch;
- advanced smart folders;
- скрытие статьи;
- поиск по статьям;
- macOS/iPad polish;
- advanced conflict UI.

## Tech Stack

- **Swift**
- **SwiftUI**
- **Swift Concurrency (async/await)**
- **SwiftData**
- **CloudKit**
- **XCTest**
- **Git/GitHub**

## Статус проекта

Проект находится на ранней стадии разработки. В текущем состоянии основной фокус направлен на формирование архитектурного фундамента и подготовку MVP.
