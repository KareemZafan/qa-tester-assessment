# Scenario 1: Greenfield Automation on a 400-Endpoint Laravel API

---

## 1. Week 1-2: What I Build First

**First thing: a smoke-test suite for the payment and wallet endpoints, running in CI.**

Specifically, I spend week 1 reading `routes/api.php` and categorizing every endpoint by risk tier. I'm not writing tests yet — I'm building a spreadsheet of all endpoints with columns: route, HTTP method, auth required, touches money (yes/no), has existing test coverage (yes/no), last changed (from git log). This takes ~2 days and becomes the single source of truth for prioritization.

By end of week 1, I pair with a backend dev (using my 4h/week budget) to understand the gift-sending flow, wallet debit/credit lifecycle, and the Stripe/PayPal webhook handlers. I ask them: "Which endpoint has caused the most production incidents in the last 6 months?" That's my starting point.

Week 2: I write **5-8 PHPUnit Feature tests** covering the gift send endpoint (`POST /api/gifts/send`) — happy path, insufficient balance, expired token, idempotency replay. These are the highest-value tests because they guard real money movement. I also add the CI step to run `php artisan test` in the GitHub Actions workflow — even if it only runs 25 tests total (the existing 20 + my new 5-8).

**What I explicitly do NOT do in weeks 1-2:**
- I don't build a Postman collection yet — PHPUnit Feature tests are more maintainable for a Laravel stack and can share factories/seeders.
- I don't try to document all 400 endpoints. Documentation is valuable but doesn't catch regressions.
- I don't touch UI/Selenium automation — the ROI is too low when there's zero API coverage.
- I don't attempt to build a test framework, base classes, or helper libraries. I write plain tests.

---

## 2. Week 3-6: Roll-Out Plan

**Prioritization framework: Risk × Change Frequency.**

From my week 1 inventory, I rank endpoints into 3 tiers:

| Tier | Criteria | Example Endpoints | Target |
|------|----------|-------------------|--------|
| **P0** | Touches money OR auth/session management | `/api/gifts/send`, `/api/wallets/*`, `/api/payments/webhook/*`, `/api/auth/login`, `/api/auth/refresh` | 100% coverage by week 6 |
| **P1** | User-facing + changed in last 3 months | `/api/rooms/join`, `/api/chat/send`, `/api/users/profile` | Happy path + top 2 negative cases |
| **P2** | Everything else (admin, reporting, rarely changed) | `/api/admin/reports/*`, `/api/internal/*` | Deferred to after week 8 |

**Weekly cadence (weeks 3-6):**
- Week 3: Complete all P0 endpoint tests. Set up factory classes (UserFactory, WalletFactory, RoomFactory, GiftFactory) that I'll reuse everywhere.
- Week 4: P1 endpoints — auth flow (login, refresh, logout, password reset), room lifecycle (join, leave, audience list).
- Week 5: Payment webhook handlers (Stripe, PayPal). This is tricky — see section 6 below.
- Week 6: Chat endpoints, user profile, remaining P1 routes. Also: write a few concurrency tests using Laravel's `artisan test --parallel` and explicit DB transaction tests.

I use my 4h/week dev pairing to: review test PR diffs (they catch "you're testing the wrong contract" fast), understand undocumented business rules, and get context on known flaky areas.

---

## 3. Week 7-8: CI Integration & Gating Policy

**What goes into CI:**
- All PHPUnit tests run on every PR (this was set up in week 2)
- Newman/Postman smoke suite runs nightly against a staging environment
- Migration safety check: `php artisan migrate --pretend` in CI to catch destructive migrations early

**Gating policy (proposed, not enforced yet):**

Week 7 I propose this to the team: "Starting next sprint, PRs that touch P0 routes (payment, wallet, auth) must have green tests to merge. All other PRs run tests as informational — failures are flagged but don't block."

I don't gate all PRs immediately because the team won't accept it (per the constraints), and forcing it before we have confidence in test reliability would just train developers to ignore failures. Instead, I propose a 2-week trial: gate only P0 routes, track false-positive rate. If flake rate stays below 5%, we expand gating to P1 in the next cycle.

By week 8, I also add a test coverage report to CI (using `--coverage-html`) so the team can see coverage trends without me nagging.

---

## 4. Tooling: PHPUnit Feature Tests (Primary) + Postman for Exploration

**I pick PHPUnit Feature tests as the primary automation tool.** Here's why:

- **Native to Laravel:** factories, RefreshDatabase, Sanctum::actingAs, Event::fake, and DB assertions all work out of the box. No HTTP overhead, no server to run.
- **Runs in CI trivially:** `php artisan test` — no additional infra.
- **Devs already know it:** the 3 backend devs can read and contribute to PHPUnit tests. Postman collections are opaque JSON blobs that nobody reviews in PRs.
- **Concurrency testing:** Laravel's test framework can directly test DB transactions and locking. Postman can't.

**Postman/Newman as secondary tool:** I maintain a small Postman collection (~20 requests) for integration-level smoke tests that hit a real staging server. This catches deployment issues (wrong env var, missing migration, config mismatch) that in-process PHPUnit tests miss. Newman runs this nightly, not on every PR.

I do NOT use both tools for the same endpoints — that's duplicate effort. PHPUnit owns the contract; Postman owns the deployment check.

---

## 5. Coverage Target at Week 8

**Committed target: 45-55 endpoint routes covered out of ~400 (roughly 12-14%).**

That sounds low, but here's the math:
- P0 (money + auth): ~30 routes → 100% covered = 30 routes
- P1 (user-facing, recently changed): ~80 routes → 25% covered = 20 routes
- P2 (everything else): 0% covered

This covers **100% of the financial risk surface** and the most actively developed areas. The remaining ~300 endpoints are low-risk, stable, and rarely changed. Automating them would be padding the coverage number without reducing production risk.

I set a secondary metric: **0 money-related production bugs that an existing test should have caught.** This is what actually matters.

---

## 6. Payment Webhook Strategy

**Approach: signature-verified fixture replay + Stripe CLI for local testing.**

1. **PHPUnit tests:** I create fixture JSON files with real webhook payload structures (from Stripe/PayPal docs), with test API keys. Tests call the webhook controller directly via `$this->postJson('/api/payments/webhook/stripe', $fixturePayload, ['Stripe-Signature' => $testSignature])`. Laravel's test environment uses a test Stripe secret, so signature verification still works.

2. **Stripe CLI (local/CI):** `stripe listen --forward-to localhost:8000/api/payments/webhook/stripe` with `stripe trigger payment_intent.succeeded`. This fires a real webhook from Stripe's test mode. I use this during development, not in CI (too slow and flaky).

3. **What I explicitly avoid:** Hitting real payment endpoints, using production API keys in tests, or disabling signature verification in tests (that would hide a whole class of bugs).

4. **Edge cases I test:** duplicate webhook delivery (idempotency), out-of-order events (payment_intent.created arriving after payment_intent.succeeded), and webhook timeout (server takes >30s to respond).

---

## 7. What I Push Back On

**"Can you write regression tests for all 400 endpoints by the end of month 1?"**

I say no. Here's what I'd actually say in that conversation:

"I understand the urgency — zero test coverage is scary. But writing 400 shallow tests that only check status codes would give us a false sense of security. The gift-sending endpoint alone needs 10+ test cases to cover the concurrency and money-movement edge cases. I'd rather have 50 tests that actually catch production bugs than 400 tests that check `assertStatus(200)` and miss every real regression.

My plan gives us 100% coverage on every endpoint that touches money by week 6. If a production bug ships after that, I want it to be in a low-risk admin reporting endpoint — not in the payment flow. Let me focus where the risk is."
