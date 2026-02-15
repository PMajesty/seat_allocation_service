<details open>
<summary><h2>🇬🇧 English</h2></summary>

# System Architecture

I used a hybrid approach:

*   Redis for speed + ephemeral coordination (holds, limits, mutexes)
*   PostgreSQL for reliability + permanent records (orders, payments, final seat state)
*   Elasticsearch for complex search queries
*   RabbitMQ for background job delivery (consumed by Sneakers workers)

A deliberate design choice here is keeping Redis focused on “inventory coordination” instead of also being the background job transport (so: no Sidekiq). RabbitMQ gives durable delivery semantics for background tasks, and I also wanted to learn it.

## Data Flow

**Reading Availability**
The frontend sees a merged view (`ShowtimeInventoryService`). I take the sold and processing seats from Postgres and overlay the held seats from Redis. Postgres is the source of truth for sales and processing states, Redis is the source of truth for temporary holds.

**Searching Events**
Search queries are offloaded to Elasticsearch to avoid expensive `LIKE` queries on the primary database.

*   **Indexing**: When an Event is created or updated, the app publishes a message to RabbitMQ (`search_indexer` queue). A Sneakers worker (`SearchIndexerWorker`) consumes that message and updates Elasticsearch asynchronously.
*   **Querying**: We use n-gram tokenizers to support fuzzy matching on event titles.

**Buying a Seat (Asynchronous Flow via RabbitMQ)**
1.  **Hold**: User selects a seat. Redis runs a Lua script (`atomic_hold.lua`) to lock it. No database writes yet.
2.  **Initiation**: User clicks buy. `CheckoutStarter` validates the request, opens a DB transaction, locks the rows (`FOR UPDATE NOWAIT`), updates the seat status to `processing`, persists payment context, and publishes a message to RabbitMQ (`payment_simulation` queue). The API returns `202 Accepted` to the client.
3.  **Processing**: `PaymentSimulationWorker` consumes the message, simulates payment latency/failure, and calls `CheckoutCallbackHandler`.
4.  **Finalization**: `CheckoutCallbackHandler` opens a new DB transaction, verifies the seats are still `processing`, creates the Order/Payment records, updates seats to `sold` (or reverts to `available` on failure), releases Redis holds, and broadcasts the result to the user via ActionCable.

## Redis Strategy

Redis manages ephemeral state:

*   **Holds**: `seat_hold:{id}:{seat}` maps a seat to a user.
*   **User Limits**: `user_holds_z:{id}:{user}` tracks how many seats a user has.
*   **Expiration Index**: `holds_z:{id}` is a sorted set used to find and expire old holds efficiently.
*   **Payment Context**: `payment_ctx:{ref}` stores metadata (seat IDs, idempotency keys) needed to finalize the order.
*   **Locks**: keys used for broadcast throttling (`broadcast_lock`) and blocking users with too many failed payments (`checkout_lockout`).

## RabbitMQ Strategy (Sneakers)

RabbitMQ is the background job delivery layer. The Rails app publishes JSON messages and workers consume them.

**Publishing**
`MessagePublisher.publish(queue_name, args)` publishes `args.to_json` to the configured exchange with `to_queue: queue_name`.

**Workers / Queues**
Core queues in this system:

*   `payment_simulation` → `PaymentSimulationWorker`
*   `search_indexer` → `SearchIndexerWorker`
*   `cleanup_expired_holds` → `CleanupExpiredHoldsWorker`
*   `cleanup_processing_seats` → `CleanupProcessingSeatsWorker`
*   `cleanup_simulation` → `CleanupSimulationWorker`

**Scheduled Work**
Cron (`whenever`) triggers periodic cleanup by publishing messages (instead of directly running ActiveJob):

*   every 1 minute → publish `cleanup_expired_holds`
*   every 10 minutes → publish `cleanup_processing_seats`

## The Checkout Process
1.  **Idempotency Check**: We check the `Idempotency-Key` header against the `payments` table and Redis. If a payment is already processing or completed, we return the status immediately.
2.  **Transition to Processing**:
    *   Lock rows (`FOR UPDATE NOWAIT`) in Postgres.
    *   Update `ShowtimeSeat` status to `processing`. This persists the reservation beyond the Redis TTL.
    *   Store context in Redis (`payment_ctx`).
    *   Publish the payment simulation message to RabbitMQ.
3.  **Background Execution**:
    *   `PaymentSimulationWorker` sleeps (simulating latency) and determines success/failure.
4.  **Callback & Broadcast**:
    *   **Success**: Create Order, set seats to `sold`, release Redis holds, broadcast `success` event.
    *   **Failure**: Revert seats to `available`, release Redis holds, increment failure counter, broadcast `error` event.

## Load Simulation
The app includes a built-in load testing engine (`LoadSimulationService`).

*   **Modes**: Real Load (organic), High Load (contention), Bot Attack (malicious).
*   **Workers**: simulation activity triggers cleanup by publishing to RabbitMQ (`cleanup_simulation` queue). The simulation itself stresses holds/releases/purchases to validate locking and recovery behavior.

</details>

<details>
<summary><h2>🇷🇺 Русский</h2></summary>

# Архитектура

Я использовал гибридный подход:

*   Redis для скорости и эфемерной координации (холды, лимиты, мьютексы)
*   PostgreSQL для надежности и долгосрочных данных (заказы, платежи, финальное состояние мест)
*   Elasticsearch для сложного поиска
*   RabbitMQ для доставки фоновых задач (обрабатываются Sneakers-воркерами)

Это сознательное решение: Redis используется для “координации инвентаря”, а не как транспорт фоновых задач (поэтому: без Sidekiq). RabbitMQ дает устойчивую доставку сообщений, плюс мне хотелось разобраться с ним.

## Поток данных

**Просмотр доступности**
Фронтенд получает объединенную картину (`ShowtimeInventoryService`). Я беру проданные и обрабатываемые (`processing`) места из Postgres и накладываю на них забронированные места из Redis. Postgres - источник истины для продаж и обработки, Redis - для временных холдов.

**Поиск событий**
Поисковые запросы направляются в Elasticsearch, чтобы избежать тяжелых `LIKE` запросов к основной базе данных.

*   **Индексация**: При создании/обновлении события приложение публикует сообщение в RabbitMQ (очередь `search_indexer`). Sneakers-воркер (`SearchIndexerWorker`) асинхронно обновляет индекс Elasticsearch.
*   **Запросы**: Используется n-gram токенизация для поддержки нечеткого поиска по названиям.

**Покупка (Асинхронный поток через RabbitMQ)**
1.  **Холд**: Пользователь выбирает место. Redis блокирует его через Lua-скрипт (`atomic_hold.lua`). База данных в этот момент не трогается.
2.  **Инициация**: Пользователь нажимает "Купить". `CheckoutStarter` валидирует запрос, открывает транзакцию, блокирует строки (`FOR UPDATE NOWAIT`), переводит места в `processing`, сохраняет контекст платежа и публикует сообщение в RabbitMQ (очередь `payment_simulation`). API возвращает клиенту `202 Accepted`.
3.  **Обработка**: `PaymentSimulationWorker` читает сообщение, симулирует задержку/ошибки оплаты и вызывает `CheckoutCallbackHandler`.
4.  **Финализация**: `CheckoutCallbackHandler` открывает новую транзакцию, проверяет, что места всё еще `processing`, создает Order/Payment, переводит места в `sold` (или возвращает в `available` при ошибке), снимает Redis-холды и отправляет результат пользователю через ActionCable.

## Структура Redis

Redis управляет всем, что живет недолго:

*   **Холды**: `seat_hold:{id}:{seat}` связывает место с пользователем.
*   **Лимиты**: `user_holds_z:{id}:{user}` следит, чтобы пользователь не набрал лишнего.
*   **Экспирация**: `holds_z:{id}` - сортированное множество для быстрой очистки просроченных броней.
*   **Контекст оплаты**: `payment_ctx:{ref}` хранит метаданные (ID мест, ключи идемпотентности), необходимые для финализации заказа.
*   **Блокировки**: ключи для группировки броадкастов (`broadcast_lock`) и временного бана пользователей с частыми ошибками оплаты (`checkout_lockout`).

## Стратегия RabbitMQ (Sneakers)

RabbitMQ - слой доставки фоновых задач. Rails публикует JSON-сообщения, воркеры читают их из очередей.

**Публикация**
`MessagePublisher.publish(queue_name, args)` публикует `args.to_json` в настроенный exchange с `to_queue: queue_name`.

**Очереди / воркеры**
Основные очереди:

*   `payment_simulation` → `PaymentSimulationWorker`
*   `search_indexer` → `SearchIndexerWorker`
*   `cleanup_expired_holds` → `CleanupExpiredHoldsWorker`
*   `cleanup_processing_seats` → `CleanupProcessingSeatsWorker`
*   `cleanup_simulation` → `CleanupSimulationWorker`

**Планировщик**
Cron (`whenever`) запускает периодическую очистку через публикацию сообщений (а не через ActiveJob):

*   раз в минуту → publish `cleanup_expired_holds`
*   раз в 10 минут → publish `cleanup_processing_seats`

## Процесс покупки
1.  **Проверка идемпотентности**: Проверяем `Idempotency-Key` в таблице `payments` и в Redis. Если платеж уже обрабатывается или завершен, сразу возвращаем статус.
2.  **Переход в Processing**:
    *   Блокировка строк (`FOR UPDATE NOWAIT`) в Postgres.
    *   Обновление статуса `ShowtimeSeat` на `processing`. Это сохраняет бронь даже если Redis TTL истечет.
    *   Сохранение контекста в Redis (`payment_ctx`).
    *   Публикация сообщения в RabbitMQ для запуска фоновой обработки.
3.  **Фоновое выполнение**:
    *   `PaymentSimulationWorker` “спит” (симулируя задержку) и определяет успех/неудачу.
4.  **Коллбэк и Броадкаст**:
    *   **Успех**: Создание Order, перевод мест в `sold`, снятие холдов Redis, отправка события `success`.
    *   **Ошибка**: Возврат мест в `available`, снятие холдов, инкремент счетчика ошибок, отправка события `error`.

## Симуляция нагрузки
В приложение встроен движок нагрузочного тестирования (`LoadSimulationService`).

*   **Режимы**: Real Load (органика), High Load (конкуренция), Bot Attack (атака).
*   **Воркеры**: режимы симуляции запускают очистку через публикацию в RabbitMQ (`cleanup_simulation`). Сама симуляция нагружает холды/освобождения/покупки, проверяя механизмы блокировок и восстановления.

</details>
