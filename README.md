# RSSReader

RSSReader — современное iOS-приложение для чтения RSS- и Atom-лент. Оно объединяет локальное хранение статей, удобную организацию подписок, поиск и app-owned Reader с возможностью открыть оригинальную публикацию в системном браузере.

Проект развивается как практическое Swift-приложение с акцентом на нативные Apple frameworks, предсказуемое поведение интерфейса и чёткое разделение ответственности между слоями.

## Возможности

- добавление и редактирование RSS- и Atom-лент;
- организация лент по папкам;
- импорт и экспорт подписок через OPML;
- списки всех, непрочитанных и избранных статей;
- фильтрация, сортировка и поиск по материалам;
- локальный Reader для содержимого из feed и открытие оригинальной страницы через `SFSafariViewController`;
- ручное и фоновое обновление лент;
- локальное хранение статей, пользовательского состояния и диагностических данных с ограниченной retention policy;
- синхронизация пользовательских данных через CloudKit;
- локализованный интерфейс с поддержкой Dynamic Type, RTL-языков и системных appearance settings.

## Технологии

- **Swift**
- **SwiftUI**
- **Swift Concurrency** (`async`/`await`, `AsyncSequence`, `AsyncStream`)
- **SwiftData**
- **CloudKit**
- **BackgroundTasks**
- **SafariServices** (`SFSafariViewController`)
- **Foundation XML parsing**
- **Swift Testing**

Проект использует системные Apple frameworks и не зависит от сторонних Swift packages.

## Архитектура

RSSReader использует screen-oriented архитектуру. App-level composition и state связывают экранные модули с прикладными сервисами, а repositories и query layer изолируют persistence и формирование read models. Networking, parsing, persistence и UI остаются отдельными границами, а асинхронные операции построены на Swift Concurrency.

SwiftUI views преимущественно отображают готовое presentation state и передают пользовательские действия в controllers. Бизнес-логика, навигационная orchestration и работа с данными не принадлежат представлениям.

## Разработка

Unit- и integration-тесты написаны с использованием Swift Testing. Разработка, приоритеты и текущее состояние задач отслеживаются в [RSSReader Roadmap](https://github.com/users/brozozowska/projects/2) и [GitHub Issues](https://github.com/brozozowska/RSSReader/issues).
