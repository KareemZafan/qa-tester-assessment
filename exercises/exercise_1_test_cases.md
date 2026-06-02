# Exercise 1: Test Case Design — Concurrency-Sensitive Payment API

| Detail     | Value          |
|------------|----------------|
| **Time**   | ~30 minutes    |
| **Points** | 20             |
| **Type**   | Written test case design |

---

## Why This Exercise Exists

Writing test cases is the single most-used QA skill on this team. Our backend has an endpoint that **moves real money between user wallets** under high concurrency. A missed edge case here doesn't fail a build — it duplicates a user's coins, drops a paid gift, or worse.

We want to see how you think about coverage **before** any automation exists. Generic test cases like "verify the API returns 200" score zero. **Be specific. Think like an attacker, not just a user.**

---

## The Feature

Users in a live-stream room can send a virtual **Gift** (paid for with in-app coins) to the room. When sending, the user also picks `winners_count` — the backend then picks a **random subset of viewers** currently in that room and credits each of them a small bonus payout in coins (a common live-app feature pattern: TikTok Live gifts, Bigo Live raffles, Twitch bits with viewer rewards).

**Why testing this is interesting:** the endpoint moves coins between wallets under concurrency, broadcasts a real-time event to everyone in the room, integrates with payment-funded balances, and must be idempotent against retries from flaky mobile networks.

## API Spec — `POST /api/gifts/send`

The endpoint is **authenticated via Laravel Sanctum bearer token** and rate-limited at **30 requests/minute per user**.

### Request

```http
POST /api/gifts/send HTTP/1.1
Host: api.example.com
Authorization: Bearer {sanctum_token}
Content-Type: application/json

{
  "room_id": 12345,
  "gift_id": 7,
  "quantity": 10,
  "winners_count": 5,
  "idempotency_key": "uuid-v4-here"
}
```

### Validation rules

- `room_id` — required, integer, must reference an existing room the user is currently joined to
- `gift_id` — required, integer, must reference a gift the sender owns or can purchase
- `quantity` — required, integer, between 1 and 100
- `winners_count` — required, integer, between 1 and 50, must be ≤ current room audience size
- `idempotency_key` — required, UUID v4, must be unique per user for 24h
- Sender's wallet must have `quantity × gift.coin_price` coins or more

### Success response (200)

```json
{
  "transaction_id": 98765,
  "coins_charged": 5000,
  "winners": [
    { "user_id": 222, "coins_awarded": 250 },
    { "user_id": 333, "coins_awarded": 250 }
  ],
  "remaining_balance": 12000
}
```

### Known constraints

- The endpoint internally uses a database transaction with row-level locking on `wallets.user_id`
- A WebSocket event `gift.sent` is broadcast to the room channel on success
- Multiple payment providers can top-up the wallet (e.g., Stripe, PayPal) — top-ups land asynchronously via webhook

---

## Your Task

Write your test cases in `answers/exercise_1_test_cases.md` (or fill in this file directly). Group them under the headings below. Aim for **20-30 test cases total** — quality over count.

For each test case use this format:

```
### TC-XX: [Short title]
- **Category:** Happy path / Validation / Auth / Concurrency / Security / Business logic / Performance
- **Priority:** P0 / P1 / P2 / P3
- **Preconditions:** [What state must exist before this runs]
- **Steps:** [Numbered, specific]
- **Expected Result:** [What we assert — status code, response body fields, DB state, side effects like broadcast events]
- **Why it matters:** [One sentence — what bug would this catch in production?]
```

### Required sections (write at least the indicated count)

1. **Happy path** (2-3 cases)
2. **Field validation** (4-6 cases) — boundary values, types, missing fields
3. **Authentication & authorization** (3-4 cases) — invalid token, expired, wrong user, room not joined
4. **Concurrency / race conditions** (3-4 cases) — this is where the bugs hide
5. **Idempotency** (2 cases) — same `idempotency_key` replayed
6. **Business logic & money** (3-4 cases) — insufficient balance, room empty, winner == sender
7. **Side effects** (2 cases) — WebSocket / broadcast event delivery, DB transaction rollback
8. **Negative / security** (2 cases) — SQL/JSON injection in IDs, very large `quantity`

---

## Evaluation Criteria

| Criterion | Points | What We Look For |
|-----------|--------|------------------|
| Coverage breadth | 5 | All 8 categories addressed; not just happy path |
| Concurrency thinking | 5 | Real race-condition cases (parallel sends, wallet lock contention, audience changing mid-call) |
| Specificity | 4 | Exact status codes, exact DB assertions, named fields — not "verify response" |
| Priority discipline | 3 | P0/P1 reserved for money-loss & auth bypass; not everything is P0 |
| Bug-catching framing | 3 | Each test ties back to "what bug would this catch" |

---

## Important

- **AI will hand you a generic CRUD test list.** We can tell. Add the cases that come from having actually shipped a payment/wallet feature.
- A test case that says "verify response status is 200 OK" with no other detail is worth nothing.
- If you spot a gap or ambiguity in the spec above, **call it out** — that's a strong signal. Senior testers don't accept specs at face value.
- Concurrency cases should describe exactly **what runs in parallel** and **what shared state could be corrupted**.


## The solution 
# Exercise 1: Test Case Design — `POST /api/gifts/send`

> **Spec gaps I'm calling out before writing cases:**
> 1. The spec doesn't define what happens when `winners_count` equals the current audience size but one viewer leaves between request receipt and winner selection — the audience count check and the draw are not atomic.
> 2. It's unclear whether the sender can be among the randomly selected winners. This is a real money question, not just UX.
> 3. "gift the sender owns or can purchase" is ambiguous — can the backend auto-purchase mid-request, and if the purchase webhook lands during the gift send, is that a TOCTOU bug?
> 4. The 24h idempotency window: does it reset per calendar day (UTC midnight) or a rolling 24h from first use?
> 5. The rate-limit of 30 req/min — is it per user, per IP, or both? Token-sharing abuse is possible.

---

## 1. Happy Path

### TC-01: Successful gift send with multiple winners
- **Category:** Happy path
- **Priority:** P0
- **Preconditions:** Authenticated user with 10,000 coins; gift_id 7 costs 500 coins each; room 12345 exists with 10+ active viewers; fresh idempotency_key
- **Steps:**
    1. `POST /api/gifts/send` with `{ room_id: 12345, gift_id: 7, quantity: 10, winners_count: 5, idempotency_key: "<new-uuid>" }`
- **Expected Result:**
    - HTTP 200
    - `coins_charged` = 5000 (quantity × gift.coin_price)
    - `winners` array has exactly 5 entries, each with `user_id` and `coins_awarded`
    - `remaining_balance` = sender's prior balance − 5000
    - Sender's `wallets.balance` in DB decremented by 5000 (atomic check — no other amount)
    - Each winner's `wallets.balance` in DB incremented by their `coins_awarded`
    - `gift.sent` WebSocket event broadcast to room channel 12345
    - One row inserted in `transactions` table with correct amount and `room_id`
- **Why it matters:** Validates the entire happy-path flow; a regression here means zero gifts work in production.

---

### TC-02: Successful send with minimum parameters (quantity=1, winners_count=1)
- **Category:** Happy path
- **Priority:** P0
- **Preconditions:** Sender has exactly the cost of 1 gift; room has at least 1 other viewer
- **Steps:**
    1. `POST /api/gifts/send` with `{ room_id: 12345, gift_id: 7, quantity: 1, winners_count: 1, idempotency_key: "<uuid>" }`
- **Expected Result:**
    - HTTP 200
    - `coins_charged` = gift.coin_price (exact)
    - `winners` array has exactly 1 entry
    - `remaining_balance` = 0 (sender spent last coins)
    - Sender wallet in DB = 0, not negative
- **Why it matters:** Catches off-by-one in balance math and verifies a zero-balance edge case doesn't overdraft.

---

### TC-03: Successful send with maximum parameters (quantity=100, winners_count=50)
- **Category:** Happy path
- **Priority:** P1
- **Preconditions:** Sender has ≥ 100 × gift.coin_price coins; room has ≥ 50 active viewers
- **Steps:**
    1. `POST /api/gifts/send` with `quantity: 100, winners_count: 50`
- **Expected Result:**
    - HTTP 200
    - `winners` has exactly 50 entries
    - Total coins distributed to winners ≤ coins_charged (platform keeps a cut or it equals — whichever matches business rules; flag if spec is silent)
    - All 50 winner wallet rows updated in DB
- **Why it matters:** Validates boundary max values work and that locking 50+ wallet rows simultaneously doesn't deadlock.

---

## 2. Field Validation

### TC-04: Missing required field — `idempotency_key` absent
- **Category:** Validation
- **Priority:** P1
- **Preconditions:** Valid auth token, valid room and gift
- **Steps:**
    1. Send request body without `idempotency_key`
- **Expected Result:**
    - HTTP 422
    - Error response references `idempotency_key` field
    - No DB writes occur, no WebSocket event broadcast
- **Why it matters:** Ensures the server enforces idempotency_key presence; without it, retries could double-charge.

---

### TC-05: `quantity` = 0 (below minimum)
- **Category:** Validation
- **Priority:** P1
- **Preconditions:** Valid auth, room, and gift
- **Steps:**
    1. Send `quantity: 0`
- **Expected Result:**
    - HTTP 422 with validation error on `quantity`
    - No coins deducted
- **Why it matters:** Prevents a zero-cost gift transaction that corrupts accounting.

---

### TC-06: `quantity` = 101 (above maximum)
- **Category:** Validation
- **Priority:** P1
- **Preconditions:** Valid auth, room, and gift
- **Steps:**
    1. Send `quantity: 101`
- **Expected Result:**
    - HTTP 422 with validation error on `quantity`
- **Why it matters:** Enforces upper bound; without it a bulk coin drain is possible in one call.

---

### TC-07: `winners_count` > current room audience size
- **Category:** Validation / Business logic
- **Priority:** P0
- **Preconditions:** Room has exactly 3 active viewers
- **Steps:**
    1. Send `winners_count: 4`
- **Expected Result:**
    - HTTP 422 with message indicating winners_count exceeds audience
    - No coins charged
- **Why it matters:** Prevents the backend from trying to pick 4 winners from 3 people, which would either crash or award the same person twice.

---

### TC-08: `idempotency_key` is not a valid UUID v4 format
- **Category:** Validation
- **Priority:** P1
- **Preconditions:** Valid auth and room
- **Steps:**
    1. Send `idempotency_key: "not-a-uuid"`
- **Expected Result:**
    - HTTP 422 with error on `idempotency_key`
    - No transaction created
- **Why it matters:** Weak idempotency key format allows collisions and key-guessing attacks.

---

### TC-09: `room_id` references a room the user is not currently joined to
- **Category:** Validation / Auth
- **Priority:** P0
- **Preconditions:** Valid auth; user is NOT in room 99999
- **Steps:**
    1. Send `room_id: 99999`
- **Expected Result:**
    - HTTP 403 or 422 (spec should clarify — I'd expect 403 since it's an authorization failure, not a format error)
    - No coins charged
- **Why it matters:** Without this check, a user could send gifts to rooms they're not in, which breaks the live-stream social contract and could be exploited for manipulation.

---

## 3. Authentication & Authorization

### TC-10: No Authorization header
- **Category:** Auth
- **Priority:** P0
- **Preconditions:** None
- **Steps:**
    1. Send request with no `Authorization` header
- **Expected Result:**
    - HTTP 401
    - No DB writes
- **Why it matters:** Unauthenticated access to a money-movement endpoint is a critical security failure.

---

### TC-11: Expired Sanctum token
- **Category:** Auth
- **Priority:** P0
- **Preconditions:** A previously valid token that has since expired
- **Steps:**
    1. Send request with `Authorization: Bearer <expired_token>`
- **Expected Result:**
    - HTTP 401
    - Response body indicates token expired or invalid
- **Why it matters:** Expired tokens must not process financial transactions.

---

### TC-12: Valid token belonging to a different user (token swapped)
- **Category:** Auth
- **Priority:** P0
- **Preconditions:** User A's token; attempt to initiate a gift that should deduct from User A's wallet
- **Steps:**
    1. User A authenticates, gets token
    2. Attacker uses User A's token with their own room and gift preferences
- **Expected Result:**
    - HTTP 200 but deduction is from User A's wallet (the token owner), not some injected user_id
    - Confirm: there is no `sender_user_id` field in the request body that could override the authenticated user — if such a field exists and is honored, that's a **critical auth bypass bug**
- **Why it matters:** Confirms the backend derives the sender from the token, not from user-supplied input.

---

### TC-13: Valid token but user's account is suspended/banned
- **Category:** Auth / Business logic
- **Priority:** P0
- **Preconditions:** User has a valid token but their account status = suspended
- **Steps:**
    1. Send valid request with suspended user's token
- **Expected Result:**
    - HTTP 403 with clear error
    - No coins deducted, no WebSocket event
- **Why it matters:** Banned users should not be able to move money in the system.

---

## 4. Concurrency / Race Conditions

### TC-14: Simultaneous duplicate requests from same user (race on idempotency_key)
- **Category:** Concurrency
- **Priority:** P0
- **Preconditions:** Sender has sufficient balance; fresh idempotency_key K1
- **Steps:**
    1. Fire 2 identical requests with the **same** idempotency_key K1 at exactly the same millisecond (use threads or `ab`/`k6`)
- **Expected Result:**
    - Exactly **one** transaction is committed; the other returns 200 with the cached response OR returns 409/422 — but **never** two deductions
    - Sender wallet decremented exactly once
    - DB: one transaction row, not two
- **Why it matters:** Mobile apps retry on network timeout. Without a database-level unique constraint on `(user_id, idempotency_key)`, both requests can pass the "key used?" check before either commits, resulting in a double charge.

---

### TC-15: Concurrent sends exhausting wallet balance
- **Category:** Concurrency
- **Priority:** P0
- **Preconditions:** Sender has exactly 5000 coins; gift costs 5000 coins per send
- **Steps:**
    1. Fire 3 concurrent requests simultaneously, each requesting a 5000-coin gift, with **different** idempotency_keys
- **Expected Result:**
    - Exactly **one** succeeds (HTTP 200); the other two return 402/422 (insufficient balance)
    - Sender wallet never goes below 0
    - DB: exactly one transaction row, balance = 0
- **Why it matters:** Without row-level locking or optimistic concurrency, all three reads see balance=5000, all three pass the balance check, and all three deduct — resulting in a −10,000 balance (real money loss to the platform).

---

### TC-16: Viewer leaves room between `winners_count` validation and winner selection
- **Category:** Concurrency
- **Priority:** P1
- **Preconditions:** Room has exactly 5 viewers; sender requests `winners_count: 5`
- **Steps:**
    1. Begin gift send request
    2. Simultaneously, one viewer leaves the room (WebSocket disconnect or `DELETE /room/leave`)
    3. Request completes winner selection
- **Expected Result:**
    - Either: the request succeeds and selects from the 4 remaining viewers (with `winners_count` adjusted or an error returned)
    - OR: HTTP 422 because the audience shrank below `winners_count`
    - **Never:** a null/missing winner entry in the response, or an awarded payout to a user_id who left
- **Why it matters:** This is a TOCTOU (Time-Of-Check-Time-Of-Use) bug. The audience size check and winner draw must be atomic or the winner pool can shrink mid-draw.

---

### TC-17: Wallet top-up webhook lands during a concurrent gift send
- **Category:** Concurrency
- **Priority:** P1
- **Preconditions:** User has 0 coins; a Stripe webhook crediting 5000 coins is in-flight; gift costs 5000 coins
- **Steps:**
    1. Trigger gift send at the same instant the top-up webhook hits the server
- **Expected Result:**
    - If top-up commits first: gift send succeeds with correct balance math
    - If gift send commits first: gift send returns 402 insufficient balance; top-up applies correctly afterward leaving balance = 5000
    - **Never:** a partial state where coins are deducted but the gift is not recorded, or coins are both credited and a race-corrupted balance results
- **Why it matters:** Async payment webhooks run outside the gift transaction. Without proper wallet locking, a concurrent credit and debit can corrupt the balance (e.g., both read balance=0, credit writes 5000, debit reads stale 0 and fails, but the credit already committed — or worse, the debit wins the lock race and charges against a negative balance).

---

## 5. Idempotency

### TC-18: Same `idempotency_key` replayed after successful transaction
- **Category:** Idempotency
- **Priority:** P0
- **Preconditions:** A gift send was completed successfully using key K1
- **Steps:**
    1. Replay the identical request with the same key K1 within 24h
- **Expected Result:**
    - HTTP 200 (or 200 with a cached response header)
    - Response body is **identical** to the original response (same `transaction_id`, `coins_charged`, `winners`)
    - Sender wallet is **not** deducted again
    - No new `transactions` row in DB
    - No second `gift.sent` WebSocket event broadcast
- **Why it matters:** Mobile retries on a flaky connection must not double-charge the user.

---

### TC-19: Same `idempotency_key` replayed after the 24h window expires
- **Category:** Idempotency
- **Priority:** P1
- **Preconditions:** Key K1 was used 25 hours ago
- **Steps:**
    1. Send request with the same key K1
- **Expected Result:**
    - HTTP 200 — treated as a **new** transaction; deduction applies fresh
    - New `transaction_id` in response
    - New DB transaction row
- **Why it matters:** Idempotency keys that never expire become a permanent denial-of-service on specific key values, which is a bug if a user legitimately wants to reuse a key after 24h (per spec).

---

## 6. Business Logic & Money

### TC-20: Insufficient wallet balance
- **Category:** Business logic / Money
- **Priority:** P0
- **Preconditions:** Sender has 4999 coins; gift costs 500 per unit; `quantity: 10` (total = 5000)
- **Steps:**
    1. Send gift request
- **Expected Result:**
    - HTTP 402 (Payment Required) or 422 with clear error message stating insufficient balance
    - `remaining_balance` NOT returned (or returned as current balance without deduction)
    - Sender wallet unchanged in DB
    - No `gift.sent` WebSocket event
- **Why it matters:** Prevents coin overdraft; a missing balance check means users can go negative and claim free gifts.

---

### TC-21: Room has zero viewers (only the sender is present)
- **Category:** Business logic
- **Priority:** P1
- **Preconditions:** User joins a room with no other viewers; `winners_count: 1`
- **Steps:**
    1. Send gift request
- **Expected Result:**
    - HTTP 422 with message indicating no eligible winners
    - No coins deducted
- **Why it matters:** Picking winners from an empty pool would either crash or award the sender themselves, which is likely a policy violation.

---

### TC-22: `winners_count` = 1 and the only eligible viewer is the sender themselves
- **Category:** Business logic
- **Priority:** P1
- **Preconditions:** Room has exactly 1 other viewer; spec is silent on whether sender can win
- **Steps:**
    1. Confirm via code review or test whether sender's `user_id` is excluded from winner pool
    2. If not excluded: send with `winners_count: 1` in a room where sender is the only non-bot viewer
- **Expected Result:**
    - Either: sender is excluded from pool and request fails (no eligible winners) / succeeds with another winner
    - OR: spec clarifies sender CAN win — but this must be an explicit business decision, not an accident
- **Why it matters:** A user who self-gifts is essentially getting a refund, which breaks the economics of the virtual gift system.

---

### TC-23: `gift_id` references a gift the user neither owns nor can purchase
- **Category:** Business logic
- **Priority:** P1
- **Preconditions:** Gift ID 999 requires prior unlock; user has not unlocked it
- **Steps:**
    1. Send `gift_id: 999`
- **Expected Result:**
    - HTTP 403 or 422 with error indicating gift is not available to this user
    - No coins deducted
- **Why it matters:** Without this check users could send exclusive/promotional gifts they never legitimately acquired.

---

## 7. Side Effects

### TC-24: WebSocket `gift.sent` event broadcast on success
- **Category:** Side effects
- **Priority:** P1
- **Preconditions:** At least one other user subscribed to room channel; successful gift send
- **Steps:**
    1. Subscribe a test client to the room's WebSocket channel
    2. Trigger a successful gift send
- **Expected Result:**
    - `gift.sent` event received by all room subscribers within acceptable latency (e.g., < 2s)
    - Event payload contains `transaction_id`, `gift_id`, `quantity`, `winners` array, and `sender_id`
    - Non-room subscribers do NOT receive the event
- **Why it matters:** If the broadcast never fires, the live stream UX breaks silently — users see no gift animation, which is the core product experience.

---

### TC-25: DB transaction rollback on broadcast failure — atomicity
- **Category:** Side effects
- **Priority:** P0
- **Preconditions:** Simulate WebSocket broadcast failure (e.g., mock the broadcast service to throw after DB commit)
- **Steps:**
    1. Force the WebSocket broadcast step to fail after the DB transaction has committed
- **Expected Result:**
    - **Scenario A (rollback):** DB is rolled back, coins are NOT deducted, HTTP 500 returned — user can retry safely
    - **Scenario B (eventual consistency):** DB commit stands, HTTP 500 returned, but a retry queue re-attempts the broadcast — coins are only charged once
    - **Never:** coins deducted, no event fired, no retry, and no error to the client (silent money loss)
- **Why it matters:** Partial success — money taken but gift not broadcast — is the worst user-facing outcome and a support nightmare.

---

## 8. Negative / Security

### TC-26: SQL injection attempt in `room_id`
- **Category:** Security
- **Priority:** P0
- **Preconditions:** Valid auth token
- **Steps:**
    1. Send `room_id: "1; DROP TABLE rooms; --"`
    2. Send `room_id: "1 OR 1=1"`
- **Expected Result:**
    - HTTP 422 (fails integer validation before hitting DB)
    - Database is unaffected
    - No 500 error that leaks a stack trace
- **Why it matters:** If `room_id` is interpolated unsafely, an attacker could manipulate or destroy the rooms table.

---

### TC-27: Abnormally large `quantity` as a string / type confusion
- **Category:** Security / Validation
- **Priority:** P1
- **Preconditions:** Valid auth token
- **Steps:**
    1. Send `quantity: "100"` (string instead of integer)
    2. Send `quantity: 9999999999` (integer overflow)
    3. Send `quantity: -1`
- **Expected Result:**
    - `"100"` as string: either coerced to integer 100 (acceptable if within bounds) or rejected with 422 — must not cause type error crash
    - `9999999999`: HTTP 422 — must not overflow to a small positive or negative number that passes validation
    - `-1`: HTTP 422 — negative quantity is below minimum of 1
- **Why it matters:** Integer overflow or type coercion bugs can flip a large debit into a credit, giving users free coins.

---

### TC-28: Rate limit enforcement — 31st request within a minute
- **Category:** Security / Performance
- **Priority:** P1
- **Preconditions:** Valid auth token; 30 requests have already been made in the current minute window
- **Steps:**
    1. Send the 31st `POST /api/gifts/send` within the same 60-second window
- **Expected Result:**
    - HTTP 429 Too Many Requests
    - `Retry-After` header present indicating when the window resets
    - No coins deducted for the rate-limited request
- **Why it matters:** Without rate limit enforcement, a compromised account or scripted attacker can drain a wallet (or spam a room) in seconds; at 30 req/min × gift cost, you also want to verify the rate limit actually bites before the wallet is empty.

---

### TC-29: Injection via `idempotency_key` field
- **Category:** Security
- **Priority:** P1
- **Preconditions:** Valid auth token
- **Steps:**
    1. Send `idempotency_key: "'; DELETE FROM idempotency_keys WHERE '1'='1"`
    2. Send `idempotency_key: "<script>alert(1)</script>"` (XSS probe if key is reflected in responses)
- **Expected Result:**
    - HTTP 422 — UUID v4 format validation rejects non-UUID values before they reach the DB
    - If UUID validation is server-side regex, confirm the regex cannot be bypassed by a crafted string
- **Why it matters:** If the idempotency key is stored and later reflected in admin UIs or logs without escaping, it becomes a stored XSS or SQL injection vector.

---

*Total: 29 test cases across 8 categories.*
