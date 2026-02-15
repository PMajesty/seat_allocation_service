<details open>
<summary><h2>🇬🇧 English</h2></summary>

# Seat Allocation Service

I built this high-contention seat allocation system using Rails 8, Redis, PostgreSQL, Elasticsearch, and RabbitMQ.

The goal was to handle heavy traffic and prevent overselling using a "Redis holds - Database sale" pattern. Redis manages temporary inventory locks with atomic Lua scripts, while Postgres handles the final transaction using row-level locking (`FOR UPDATE NOWAIT`).

For background jobs I intentionally did **not** use Sidekiq. I wanted to keep Redis focused on cache/ephemeral coordination (holds, limits, mutexes) instead of also being the job transport, and low key I also wanted an excuse to learn RabbitMQ-so I wired jobs through **RabbitMQ + Sneakers**.

## Documentation
Check out how I designed the [Architecture & Data Flow](docs/ARCHITECTURE.md), guaranteed [System Invariants](docs/INVARIANTS.md), and managed [Failure Modes](docs/FAILURE_MODES.md).

## Key Features

**Concurrency & Integrity**
I use optimistic locking in Redis for seat selection and pessimistic locking in Postgres for payments. Lua scripts ensure that checking and setting a hold happens atomically, so race conditions are impossible at the selection stage.

**Traffic Control & VIP Rope**
To stop abuse, I limit how long a user can hold a seat (60s TTL) and how many seats they can hold at once (max 3).
*   **VIP Rope**: New accounts (< 10 hours old) are automatically restricted from holding the last 20% of inventory. This protects loyal users during bot attacks.
*   **Throttling**: `Rack::Attack` limits request rates for sensitive endpoints.

**Background Jobs (RabbitMQ + Sneakers)**
Background work is executed by Sneakers workers consuming RabbitMQ queues.
*   **Why RabbitMQ**: I wanted a clean separation where Redis is used for short-lived coordination (holds/locks), and RabbitMQ is used for durable job delivery.
*   **Publish/Consume**: The app publishes messages via `MessagePublisher.publish(queue, args)` (JSON payloads), and workers consume from dedicated queues (`payment_simulation`, `search_indexer`, cleanup queues).
*   **Local Dev**: `Procfile.dev` runs a `sneakers work ...` process alongside the web server.

**Full-Text Search**
Events are indexed in Elasticsearch using n-gram tokenizers, allowing for fuzzy matching and efficient searching even with partial queries.

**Asynchronous & Resilient Checkout**
*   **Async Processing**: Payments are processed in the background (`PaymentSimulationWorker`) to keep the API responsive. The frontend receives real-time updates via ActionCable (`UserPaymentChannel`).
*   **Intermediate State**: Seats transition to a persisted `processing` state in Postgres during payment, preventing double-booking even if Redis holds expire.
*   **Idempotency**: The API supports `Idempotency-Key` headers to safely handle network retries without double-charging.
*   **Simulated Latency**: The checkout process includes artificial latency and random failure injection to demonstrate how the system handles payment provider timeouts and errors.

**Authentication**
The app serves both HTML and JSON. Browsers use `HttpOnly` cookies with CSRF protection, while API clients send a JWT in the `Authorization` header.

## Quick Start

Get the app running in minutes using Docker for dependencies (Postgres, Redis, Elasticsearch, RabbitMQ).

```bash
# 1. Configure environment
cp .env.example .env

# 2. Start database, redis, elasticsearch, and rabbitmq
docker compose up -d

# 3. Setup database and seed data (waits for ES + RabbitMQ to be ready)
bin/setup --skip-server

# 4. Configure scheduled jobs
bundle exec whenever --update-crontab

# 5. Start the application (web + sneakers worker)
bin/dev
```

Visit `http://localhost:3000` to see the app.

RabbitMQ Management UI is available at `http://localhost:15672` (default guest/guest) if you want to inspect queues during load tests.

## Simulation
I built a load generator right into the app. Log in as `admin@showtime.com` (password: `12345678`) and check the Dashboard. You can simulate organic traffic, heavy contention, or a bot attack to see how the system holds up.

</details>

<details>
<summary><h2>🇷🇺 Русский</h2></summary>

# Seat Allocation Service

Я построил эту систему бронирования мест с высокой конкуренцией на Rails 8, Redis, PostgreSQL, Elasticsearch и RabbitMQ.

Главная задача - держать высокую нагрузку и предотвращать овербукинг. Я использовал схему "Redis holds - Database sale". Redis берет на себя быстрые временные блокировки через атомарные Lua-скрипты, а Postgres гарантирует надежность финальной транзакции через блокировку строк (`FOR UPDATE NOWAIT`).

Для фоновых задач я сознательно **не** использовал Sidekiq. Хотел отделить Redis (холды/лимиты/мьютексы/эфемерные данные) от транспорта задач, и, если честно, я “low key” хотел разобраться с RabbitMQ - поэтому фоновые задачи сделаны через **RabbitMQ + Sneakers**.

## Документация
Подробнее про [Архитектуру](docs/ARCHITECTURE.md), [Инварианты системы](docs/INVARIANTS.md) и [Сценарии сбоев](docs/FAILURE_MODES.md).

## Ключевые особенности

**Конкурентность и целостность**
Для выбора мест я использую оптимистичную блокировку в Redis, а для оплаты - пессимистичную в Postgres. Lua-скрипты гарантируют, что проверка и установка холда происходят атомарно, исключая гонки.

**Контроль трафика и VIP-зона**
Чтобы избежать злоупотреблений, я ограничиваю время холда (60 сек) и количество мест в одних руках (макс. 3).
*   **VIP Rope**: Новые аккаунты (созданные менее 10 часов назад) не могут забронировать последние 20% мест. Это защищает реальных пользователей во время атак ботов.
*   **Троттлинг**: `Rack::Attack` ограничивает частоту запросов к API.

**Фоновые задачи (RabbitMQ + Sneakers)**
Фоновая работа выполняется Sneakers-воркерами, которые читают очереди RabbitMQ.
*   **Почему RabbitMQ**: Я хотел четкое разделение: Redis для короткоживущей координации (холды/локи), RabbitMQ для доставки задач.
*   **Publish/Consume**: Приложение публикует сообщения через `MessagePublisher.publish(queue, args)` (JSON), а воркеры читают из отдельных очередей (`payment_simulation`, `search_indexer`, cleanup-очереди).
*   **Локальная разработка**: `Procfile.dev` поднимает отдельный процесс `sneakers work ...` рядом с веб-сервером.

**Полнотекстовый поиск**
События индексируются в Elasticsearch с использованием n-gram токенизации, что обеспечивает быстрый нечеткий поиск даже по частичным запросам.

**Асинхронный и надежный чекаут**
*   **Асинхронная обработка**: Платежи обрабатываются в фоне (`PaymentSimulationWorker`), чтобы API оставался отзывчивым. Фронтенд получает обновления в реальном времени через ActionCable (`UserPaymentChannel`).
*   **Промежуточное состояние**: Во время оплаты места переводятся в статус `processing` в Postgres. Это предотвращает двойную продажу, даже если TTL в Redis истечет.
*   **Идемпотентность**: API поддерживает заголовок `Idempotency-Key`, что позволяет безопасно повторять запросы при сбоях сети без риска двойного списания.
*   **Симуляция задержек**: В процесс оплаты встроена искусственная задержка и генератор случайных ошибок, чтобы продемонстрировать устойчивость системы к проблемам платежных шлюзов.

**Аутентификация**
Приложение отдает и HTML, и JSON. Браузеры работают через `HttpOnly` cookie с CSRF-защитой, а API-клиенты передают JWT в заголовке `Authorization`.

## Быстрый старт

Запуск приложения за пару минут с использованием Docker (Postgres, Redis, Elasticsearch, RabbitMQ).

```bash
# 1. Настройка окружения
cp .env.example .env

# 2. Запуск базы данных, redis, elasticsearch и rabbitmq
docker compose up -d

# 3. Настройка базы и сидов (скрипт дождется готовности ES + RabbitMQ)
bin/setup --skip-server

# 4. Настройка планировщика (Cron)
bundle exec whenever --update-crontab

# 5. Запуск приложения (web + sneakers worker)
bin/dev
```

Откройте `http://localhost:3000`.

UI RabbitMQ Management доступен на `http://localhost:15672` (по умолчанию guest/guest), удобно смотреть очереди во время нагрузочных тестов.

## Симуляция
В приложение встроен генератор нагрузки. Зайдите под `admin@showtime.com` (пароль `12345678`) в Dashboard. Там можно запустить эмуляцию обычного трафика, высокой конкуренции или атаки ботов, чтобы проверить защиту в деле.

</details>
