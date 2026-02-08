<details open>
<summary><h2>🇬🇧 English</h2></summary>

# System Invariants

These are the hard guarantees I built into the design.

## 1. No Overselling
It is impossible for two users to buy the same seat. The `CheckoutService` opens a transaction and locks the seat rows with `SELECT ... FOR UPDATE NOWAIT`. Inside that lock, I check if the status is still available. If not, the transaction rolls back. The `NOWAIT` modifier prevents connection starvation by failing immediately if the row is already locked by another transaction. The database is the final gatekeeper.

## 2. Single Holder Exclusivity
Only one user can hold a specific seat at a time. I enforce this with a Redis Lua script `atomic_hold.lua`. Since Lua executes atomically, two requests cannot race to check the key existence. First one wins, second one fails.

## 3. Hold Limits
A user cannot exceed the maximum hold count, which defaults to 3. The Lua script checks the size of the user's hold set before allowing a new one.

## 4. Status Consistency
A seat cannot be marked `sold` without an `order_id`. I enforce this at the database level with a Check Constraint. You either have both a sold status and an order ID, or neither.

## 5. VIP Inventory Protection
New or untrusted users cannot deplete the entire inventory.
*   **The Rule**: If a user account is less than 10 hours old, they are treated as "untrusted".
*   **The Limit**: Untrusted users are dynamically blocked from holding seats once 80% of the venue capacity is sold/held. This ensures the last 20% of tickets are available only to established users, mitigating bot scalping attacks.

</details>

<details>
<summary><h2>🇷🇺 Русский</h2></summary>

# Инварианты Системы

Жесткие гарантии, которые я заложил в архитектуру.

## 1. Никакого овербукинга
Два пользователя не могут купить одно место. `CheckoutService` открывает транзакцию и блокирует строки через `SELECT ... FOR UPDATE NOWAIT`. Внутри блокировки я проверяю статус. Если место занято - откат. `NOWAIT` предотвращает исчерпание пула соединений: если строка заблокирована другой транзакцией, ошибка возвращается мгновенно. База данных - последняя инстанция.

## 2. Эксклюзивность холда
Место может держать только один человек. Это контролирует Lua-скрипт `atomic_hold.lua` в Redis. Скрипт выполняется атомарно, поэтому состояние гонки исключено: кто первый встал, того и место.

## 3. Лимиты на руки
Пользователь не может набрать больше мест, чем разрешено конфигом (по умолчанию 3). Скрипт проверяет текущее количество холдов пользователя перед добавлением нового.

## 4. Согласованность данных
Место не может получить статус `sold` без привязки к заказу. Это гарантирует Check Constraint в базе данных. Либо у места есть и статус "продано", и ID заказа, либо нет ни того, ни другого.

## 5. Защита VIP-инвентаря
Новые или недоверенные пользователи не могут выкупить зал подчистую.
*   **Правило**: Если аккаунту менее 10 часов, он считается "недоверенным".
*   **Лимит**: Недоверенные пользователи блокируются, если 80% зала уже занято или продано. Это гарантирует, что последние 20% билетов достанутся только проверенным пользователям, что защищает от перекупщиков-ботов.

</details>
