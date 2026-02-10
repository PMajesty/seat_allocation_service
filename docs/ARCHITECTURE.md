<details open>
<summary><h2>🇬🇧 English</h2></summary>

# System Architecture

I used a hybrid approach: Redis for speed and temporary state, PostgreSQL for reliability and permanent records, and Elasticsearch for complex queries.

## Data Flow

**Reading Availability**
The frontend sees a merged view (`ShowtimeInventoryService`). I take the sold and processing seats from Postgres and overlay the held seats from Redis. Postgres is the source of truth for sales and processing states, Redis is the source of truth for temporary holds.

**Searching Events**
Search queries are offloaded to Elasticsearch to avoid expensive `LIKE` queries on the primary database.
*   **Indexing**: When an Event is created or updated, `SearchIndexerJob` pushes the data to Elasticsearch asynchronously. This ensures the write path remains fast and is not blocked by search indexing latency.
*   **Querying**: We use n-gram tokenizers to support fuzzy matching on event titles.

**Buying a Seat (Asynchronous Flow)**
1.  **Hold**: User selects a seat. Redis runs a Lua script (`atomic_hold.lua`) to lock it. No database writes yet.
2.  **Initiation**: User clicks buy. `CheckoutStarter` validates the request, opens a DB transaction, locks the rows (`FOR UPDATE NOWAIT`), and updates the seat status to `processing`. It then enqueues a background job (`PaymentSimulationJob`) and returns `202 Accepted` to the client.
3.  **Processing**: The background job simulates gateway latency.
4.  **Finalization**: `CheckoutCallbackHandler` receives the payment result. It opens a new transaction, verifies the seats are still `processing`, creates the Order/Payment records, and updates seats to `sold`. Finally, it broadcasts the result to the user via ActionCable.

## Redis Strategy
I use Redis to manage ephemeral state.
*   **Holds**: `seat_hold:{id}:{seat}` maps a seat to a user.
*   **User Limits**: `user_holds_z:{id}:{user}` tracks how many seats a user has.
*   **Expiration**: `holds_z:{id}` is a sorted set used to find and expire old holds efficiently.
*   **Payment Context**: `payment_ctx:{ref}` stores metadata (seat IDs, idempotency keys) needed by the background worker to finalize the order.
*   **Locks**: I use keys for broadcast throttling (`broadcast_lock`) and blocking users with too many failed payments (`checkout_lockout`).

## The Checkout Process
1.  **Idempotency Check**: We check the `Idempotency-Key` header against the `payments` table and Redis. If a payment is already processing or completed, we return the status immediately.
2.  **Transition to Processing**:
    *   Lock rows (`FOR UPDATE NOWAIT`) in Postgres.
    *   Update `ShowtimeSeat` status to `processing`. This persists the reservation beyond the Redis TTL.
    *   Store context in Redis (`payment_ctx`) and enqueue the job.
3.  **Background Execution**:
    *   `PaymentSimulationJob` sleeps (simulating latency) and determines success/failure.
4.  **Callback & Broadcast**:
    *   **Success**: Create Order, set seats to `sold`, release Redis holds, broadcast `success` event.
    *   **Failure**: Revert seats to `available`, release Redis holds, increment failure counter, broadcast `error` event.

## Load Simulation
The app includes a built-in load testing engine (`LoadSimulationService`).
*   **Modes**: Real Load (organic), High Load (contention), Bot Attack (malicious).
*   **Workers**: `SimulationJob` spawns background workers that create temporary users (`@simulation.local`) and perform holds/releases/purchases to stress-test the locking mechanisms.

</details>

<details>
<summary><h2>🇷🇺 Русский</h2></summary>

# Архитектура

Я использовал гибридный подход: Redis для скорости и временных данных, PostgreSQL для надежности и долгосрочного хранения, и Elasticsearch для сложных запросов.

## Поток данных

**Просмотр доступности**
Фронтенд получает объединенную картину (`ShowtimeInventoryService`). Я беру проданные и обрабатываемые (`processing`) места из Postgres и накладываю на них забронированные места из Redis. Postgres - источник истины для продаж и обработки, Redis - для временных холдов.

**Поиск событий**
Поисковые запросы направляются в Elasticsearch, чтобы избежать тяжелых `LIKE` запросов к основной базе данных.
*   **Индексация**: При создании или обновлении события `SearchIndexerJob` асинхронно обновляет индекс. Это гарантирует, что запись в БД остается быстрой и не блокируется задержками Elasticsearch.
*   **Запросы**: Используется n-gram токенизация для поддержки нечеткого поиска по названиям.

**Покупка (Асинхронный поток)**
1.  **Холд**: Пользователь выбирает место. Redis блокирует его через Lua-скрипт (`atomic_hold.lua`). База данных в этот момент не трогается.
2.  **Инициация**: Пользователь нажимает "Купить". `CheckoutStarter` валидирует запрос, открывает транзакцию, блокирует строки (`FOR UPDATE NOWAIT`) и переводит статус мест в `processing`. Затем он ставит задачу в очередь (`PaymentSimulationJob`) и возвращает клиенту `202 Accepted`.
3.  **Обработка**: Фоновая задача симулирует задержку шлюза.
4.  **Финализация**: `CheckoutCallbackHandler` получает результат оплаты. Он открывает новую транзакцию, проверяет, что места всё еще `processing`, создает записи Order/Payment и обновляет статус мест на `sold`. Результат отправляется пользователю через ActionCable.

## Структура Redis
Redis управляет всем, что живет недолго.
*   **Холды**: `seat_hold:{id}:{seat}` связывает место с пользователем.
*   **Лимиты**: `user_holds_z:{id}:{user}` следит, чтобы пользователь не набрал лишнего.
*   **Экспирация**: `holds_z:{id}` - сортированное множество для быстрой очистки просроченных броней.
*   **Контекст оплаты**: `payment_ctx:{ref}` хранит метаданные (ID мест, ключи идемпотентности), необходимые воркеру для завершения заказа.
*   **Блокировки**: Я использую ключи для группировки броадкастов (`broadcast_lock`) и временного бана пользователей с частыми ошибками оплаты (`checkout_lockout`).

## Процесс покупки
1.  **Проверка идемпотентности**: Проверяем заголовок `Idempotency-Key` в таблице `payments` и в Redis. Если платеж уже обрабатывается или завершен, сразу возвращаем статус.
2.  **Переход в Processing**:
    *   Блокировка строк (`FOR UPDATE NOWAIT`) в Postgres.
    *   Обновление статуса `ShowtimeSeat` на `processing`. Это сохраняет бронь даже если Redis TTL истечет.
    *   Сохранение контекста в Redis (`payment_ctx`) и постановка задачи в очередь.
3.  **Фоновое выполнение**:
    *   `PaymentSimulationJob` "спит" (симулируя задержку) и определяет успех/неудачу.
4.  **Коллбэк и Броадкаст**:
    *   **Успех**: Создание Order, перевод мест в `sold`, снятие холдов Redis, отправка события `success`.
    *   **Ошибка**: Возврат мест в `available`, снятие холдов, инкремент счетчика ошибок, отправка события `error`.

## Симуляция нагрузки
В приложение встроен движок нагрузочного тестирования (`LoadSimulationService`).
*   **Режимы**: Real Load (органика), High Load (конкуренция), Bot Attack (атака).
*   **Воркеры**: `SimulationJob` запускает фоновые задачи, которые создают временных пользователей (`@simulation.local`) и выполняют бронирование/покупку, проверяя механизмы блокировок на прочность.

</details>
