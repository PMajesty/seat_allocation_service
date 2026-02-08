<details open>
<summary><h2>🇬🇧 English</h2></summary>

# System Architecture

I used a hybrid approach: Redis for speed and temporary state, PostgreSQL for reliability and permanent records.

## Data Flow

**Reading Availability**
The frontend sees a merged view (`ShowtimeInventoryService`). I take the sold seats from Postgres and overlay the held seats from Redis. Postgres is the source of truth for sales, Redis is the source of truth for holds.

**Buying a Seat**
1.  **Hold**: User selects a seat. Redis runs a Lua script (`atomic_hold.lua`) to lock it. No database writes yet.
2.  **Checkout**: User pays. Rails starts a DB transaction, locks the row with `FOR UPDATE NOWAIT`, charges the card, updates the seat to `sold`, and finally releases the Redis hold. The `NOWAIT` clause ensures that if a lock cannot be acquired immediately, the request fails fast instead of queuing up and starving the database connection pool.

## Redis Strategy
I use Redis to manage ephemeral state.
*   **Holds**: `seat_hold:{id}:{seat}` maps a seat to a user.
*   **User Limits**: `user_holds_z:{id}:{user}` tracks how many seats a user has.
*   **Expiration**: `holds_z:{id}` is a sorted set used to find and expire old holds efficiently.
*   **Locks**: I use Redis keys for broadcast throttling (`broadcast_lock`) and blocking users with too many failed payments (`checkout_lockout`).

## The Checkout Process
1.  **Idempotency Check**: We check the `Idempotency-Key` header against the `payments` table. If a successful payment exists, we return the existing Order ID immediately.
2.  **Refresh Hold**: We ensure the user still holds the seats in Redis.
3.  **DB Transaction**:
    *   Lock rows (`FOR UPDATE NOWAIT`).
    *   Verify availability (double-check against DB status).
    *   Create Order and Payment records.
    *   Update `ShowtimeSeat` status to `sold`.
4.  **Cleanup**: Commit transaction and release Redis holds.

## Load Simulation
The app includes a built-in load testing engine (`LoadSimulationService`).
*   **Modes**: Real Load (organic), High Load (contention), Bot Attack (malicious).
*   **Workers**: `SimulationJob` spawns background workers that create temporary users (`@simulation.local`) and perform holds/releases/purchases to stress-test the locking mechanisms.

</details>

<details>
<summary><h2>🇷🇺 Русский</h2></summary>

# Архитектура

Я использовал гибридный подход: Redis для скорости и временных данных, PostgreSQL для надежности и долгосрочного хранения.

## Поток данных

**Просмотр доступности**
Фронтенд получает объединенную картину (`ShowtimeInventoryService`). Я беру проданные места из Postgres и накладываю на них забронированные места из Redis. Postgres - источник истины для продаж, Redis - для холдов.

**Покупка**
1.  **Холд**: Пользователь выбирает место. Redis блокирует его через Lua-скрипт (`atomic_hold.lua`). База данных в этот момент не трогается.
2.  **Оплата**: Rails открывает транзакцию, блокирует строку через `FOR UPDATE NOWAIT`, проводит оплату, помечает место как проданное и только потом снимает холд в Redis. Использование `NOWAIT` гарантирует, что если блокировка занята, запрос упадет с ошибкой сразу, не создавая очередь и не забивая пул соединений базы данных.

## Структура Redis
Redis управляет всем, что живет недолго.
*   **Холды**: `seat_hold:{id}:{seat}` связывает место с пользователем.
*   **Лимиты**: `user_holds_z:{id}:{user}` следит, чтобы пользователь не набрал лишнего.
*   **Экспирация**: `holds_z:{id}` - сортированное множество для быстрой очистки просроченных броней.
*   **Блокировки**: Я использую ключи для группировки броадкастов (`broadcast_lock`) и временного бана пользователей с частыми ошибками оплаты (`checkout_lockout`).

## Процесс покупки
1.  **Проверка идемпотентности**: Проверяем заголовок `Idempotency-Key` в таблице `payments`. Если платеж уже прошел, сразу возвращаем ID заказа.
2.  **Обновление холда**: Подтверждаем, что места всё еще забронированы за пользователем в Redis.
3.  **Транзакция БД**:
    *   Блокировка строк (`FOR UPDATE NOWAIT`).
    *   Проверка доступности (сверка со статусом в БД).
    *   Создание записей Order и Payment.
    *   Обновление статуса `ShowtimeSeat` на `sold`.
4.  **Очистка**: Коммит транзакции и удаление холдов из Redis.

## Симуляция нагрузки
В приложение встроен движок нагрузочного тестирования (`LoadSimulationService`).
*   **Режимы**: Real Load (органика), High Load (конкуренция), Bot Attack (атака).
*   **Воркеры**: `SimulationJob` запускает фоновые задачи, которые создают временных пользователей (`@simulation.local`) и выполняют бронирование/покупку, проверяя механизмы блокировок на прочность.

</details>
