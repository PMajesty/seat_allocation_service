<details open>
<summary><h2>🇬🇧 English</h2></summary>

# Failure Modes & Recovery

Here is what happens when things break.

## Elasticsearch Outage
Search functionality is designed to degrade gracefully. If Elasticsearch becomes unreachable, the application catches the connection error. The user is shown a maintenance alert ("Search is currently under maintenance"), and the search results come back empty. The core application (event listing, booking, and payments) remains fully functional.

Search indexing is asynchronous, so an Elasticsearch outage does not block core writes. Indexing messages may be consumed and fail inside the indexer worker until Elasticsearch is healthy again.

## Redis Outage
Redis handles temporary holds and several coordination locks. If it goes down, users can't select new seats, and checkout initiation will fail when trying to refresh holds. Once Redis is back, the system recovers automatically. Sales data is safe in Postgres and won't be lost.

## RabbitMQ Outage (Background Jobs)
RabbitMQ is used for background job delivery (payments, search indexing, cleanup). If RabbitMQ is unreachable:

*   **Checkout initiation impact**: publishing the payment message can fail. The API treats this as a checkout initiation failure and performs compensation immediately:
    *   seats are reverted from `processing` back to `available`
    *   Redis payment context (`payment_ctx:*`) is removed
    *   idempotency `processing` marker (if set) is cleared
    *   Redis holds are released
*   **Recovery path**: under normal conditions, no manual recovery is needed because seats are reverted immediately. `CleanupProcessingSeatsWorker` (scheduled every 10 minutes) still serves as a safety net for any seats that end up stuck in `processing` due to unexpected crashes between steps.
*   **Search indexing impact**: event writes still succeed, but indexing messages won’t be delivered, so search results can become stale until RabbitMQ recovers.

This is an intentional trade: Redis remains dedicated to ephemeral inventory coordination, while RabbitMQ is responsible for durable task delivery.

## Database Outage
If the DB stops, writes stop completely. The API will return 500 errors. Thanks to ACID transactions, I ensure no partial data or corrupted states get committed.

## Payment Gateway Failure & Lockout
The system simulates payment provider latency (3-6s) and random failures (10% chance).

*   **Async Feedback**: Since payments are backgrounded (RabbitMQ → Sneakers worker), failures are pushed to the client via ActionCable.
*   **Retry Logic**: If a payment fails, the user is notified and the seats are released.
*   **Lockout**: To prevent brute-forcing or API abuse, if a user experiences **2 consecutive payment failures**, they are temporarily locked out of purchasing for **1 minute**. This is enforced via Redis key `checkout_lockout:{user_id}`.

## Worker Crash (Stuck Processing Seats)
If a background worker crashes while a payment is processing, the seats could remain in the `processing` state indefinitely.

*   **Recovery**: `CleanupProcessingSeatsWorker` runs every 10 minutes. It finds seats that have been `processing` for longer than the timeout (10 mins) and releases them back to `available`.

## Abandoned Carts
If a user selects seats and leaves, the seats stay held until the TTL expires. Redis keys live for 60 seconds. A cleanup worker `CleanupExpiredHoldsWorker` is triggered every minute to clean up any leftover index entries that might have been missed during a crash.

## Thundering Herd
Popular events trigger massive waves of updates. To prevent crashing clients with thousands of WebSocket messages, `BroadcastCoalesceJob` uses a Redis mutex to group changes. I send a single refresh signal every 200ms instead of broadcasting every individual update.

</details>

<details>
<summary><h2>🇷🇺 Русский</h2></summary>

# Сбои и восстановление

Как система ведет себя, когда что-то идет не так.

## Падение Elasticsearch
Функция поиска спроектирована так, чтобы не ломать весь сайт при сбое. Если Elasticsearch недоступен, приложение перехватывает ошибку соединения. Пользователь видит уведомление о технических работах, а результаты поиска возвращаются пустыми. Основной функционал (список событий, бронирование и оплата) продолжает работать штатно.

Индексация асинхронная, поэтому сбой Elasticsearch не блокирует основные записи. Сообщения индексации могут падать внутри воркера до восстановления Elasticsearch.

## Падение Redis
Redis отвечает за временные брони и координационные локи. Если он упадет, пользователи не смогут выбирать места, а покупка не начнется из-за ошибки обновления холда. После перезапуска Redis система восстановится сама. Данные о продажах лежат в Postgres, поэтому деньги и билеты не пропадут.

## Падение RabbitMQ (фоновые задачи)
RabbitMQ используется для доставки фоновых задач (платежи, индексация поиска, очистки). Если RabbitMQ недоступен:

*   **Влияние на старт покупки**: публикация сообщения на обработку платежа может не выполниться. В этом случае API считает старт покупки неуспешным и сразу делает компенсацию:
    *   места переводятся из `processing` обратно в `available`
    *   удаляется контекст платежа в Redis (`payment_ctx:*`)
    *   очищается idempotency-маркер `processing` (если был выставлен)
    *   снимаются Redis-холды
*   **Путь восстановления**: обычно ручное восстановление не требуется, потому что места откатываются сразу. `CleanupProcessingSeatsWorker` (раз в 10 минут) остается “страховкой” на случай, если из-за неожиданного крэша между шагами места все же зависнут в `processing`.
*   **Влияние на поиск**: создание/обновление событий не ломается, но сообщения индексации не доставляются, поэтому поиск может стать “устаревшим” до восстановления RabbitMQ.

Это осознанный компромисс: Redis остается выделенным под координацию инвентаря, а RabbitMQ отвечает за доставку задач.

## Падение Базы Данных
Без базы запись невозможна. API начнет отдавать 500-е ошибки. ACID-транзакции гарантируют, что частичные данные не запишутся — либо всё, либо ничего.

## Сбои платежного шлюза и блокировка
Система симулирует задержку платежа (3-6 сек) и случайные сбои (шанс 10%).

*   **Асинхронная обратная связь**: Платежи идут в фоне (RabbitMQ → Sneakers воркер), а информация об ошибках приходит клиенту через ActionCable.
*   **Повторы**: Если платеж не прошел, пользователь получает уведомление, а места освобождаются.
*   **Блокировка**: Чтобы предотвратить перебор или злоупотребление API, если у пользователя случаются **2 ошибки оплаты подряд**, он временно блокируется на **1 минуту**. Это контролируется ключом Redis `checkout_lockout:{user_id}`.

## Падение воркера (Зависшие места)
Если фоновый процесс упадет во время обработки платежа, места могут теоретически "зависнуть" в статусе `processing`.

*   **Восстановление**: `CleanupProcessingSeatsWorker` запускается каждые 10 минут. Он находит места, которые висят в обработке дольше таймаута (10 мин), и возвращает их в статус `available`.

## Брошенные корзины
Если пользователь набрал мест и ушел, они останутся занятыми до истечения TTL. Ключи в Redis живут 60 секунд. Дополнительно раз в минуту запускается `CleanupExpiredHoldsWorker`, чтобы подчистить индексы, которые могли "зависнуть" при сбое.

## Thundering Herd
Популярные события вызывают лавину обновлений. Чтобы не положить клиенты тысячами вебсокет-сообщений, `BroadcastCoalesceJob` группирует изменения через Redis mutex. Я отправляю один сигнал обновления раз в 200 мс, а не спамлю каждым действием.

</details>
