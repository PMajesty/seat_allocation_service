<details open>
<summary><h2>🇬🇧 English</h2></summary>

# Failure Modes & Recovery

Here is what happens when things break.

## Elasticsearch Outage
Search functionality is designed to degrade gracefully. If Elasticsearch becomes unreachable, the application catches the connection error. The user is shown a maintenance alert ("Search is currently under maintenance"), and the search results come back empty. The core application (event listing, booking, and payments) remains fully functional.

## Redis Outage
Redis handles temporary holds. If it goes down, users can't select new seats, and checkout will fail when trying to refresh holds. Once Redis is back, the system recovers automatically. Sales data is safe in Postgres and won't be lost.

## Database Outage
If the DB stops, writes stop completely. The API will return 500 errors. Thanks to ACID transactions, I ensure no partial data or corrupted states get committed.

## Payment Gateway Failure & Lockout
The system simulates payment provider latency (5s) and random failures (10% chance).
*   **Retry Logic**: If a payment fails, the user is notified.
*   **Lockout**: To prevent brute-forcing or API abuse, if a user experiences **2 consecutive payment failures**, they are temporarily locked out of purchasing for **1 minute**. This is enforced via Redis key `checkout_lockout:{user_id}`.

## Abandoned Carts
If a user selects seats and leaves, the seats stay held until the TTL expires. Redis keys live for 60 seconds. A background job `CleanupExpiredHoldsJob` runs every minute to clean up any leftover index entries that might have been missed during a crash.

## Thundering Herd
Popular events trigger massive waves of updates. To prevent crashing clients with thousands of WebSocket messages, `BroadcastCoalesceJob` uses a Redis mutex to group changes. I send a single refresh signal every 200ms instead of broadcasting every individual update.

</details>

<details>
<summary><h2>🇷🇺 Русский</h2></summary>

# Сбои и восстановление

Как система ведет себя, когда что-то идет не так.

## Падение Elasticsearch
Функция поиска спроектирована так, чтобы не ломать весь сайт при сбое. Если Elasticsearch недоступен, приложение перехватывает ошибку соединения. Пользователь видит уведомление о технических работах, а результаты поиска возвращаются пустыми. Основной функционал (список событий, бронирование и оплата) продолжает работать штатно.

## Падение Redis
Redis отвечает за временные брони. Если он упадет, пользователи не смогут выбирать места, а покупка не пройдет из-за ошибки обновления холда. После перезапуска Redis система восстановится сама. Данные о продажах лежат в Postgres, поэтому деньги и билеты не пропадут.

## Падение Базы Данных
Без базы запись невозможна. API начнет отдавать 500-е ошибки. ACID-транзакции гарантируют, что частичные данные не запишутся - либо всё, либо ничего.

## Сбои платежного шлюза и блокировка
Система симулирует задержку платежа (5 сек) и случайные сбои (шанс 10%).
*   **Повторы**: Если платеж не прошел, пользователь получает уведомление.
*   **Блокировка**: Чтобы предотвратить перебор или злоупотребление API, если у пользователя случаются **2 ошибки оплаты подряд**, он временно блокируется на **1 минуту**. Это контролируется ключом Redis `checkout_lockout:{user_id}`.

## Брошенные корзины
Если пользователь набрал мест и ушел, они останутся занятыми до истечения TTL. Ключи в Redis живут 60 секунд. Дополнительно каждую минуту запускается `CleanupExpiredHoldsJob`, чтобы подчистить индексы, которые могли "зависнуть" при сбое.

## Thundering Herd
Популярные события вызывают лавину обновлений. Чтобы не положить клиенты тысячами вебсокет-сообщений, `BroadcastCoalesceJob` группирует изменения. Я отправляю один сигнал обновления раз в 200 мс, а не спамлю каждым действием.

</details>
