# Scenario 2: Flaky Test Suite Eating Friday Afternoons

---

## 1. Triage: Which Tests First, On What Criteria

I don't investigate alphabetically or by suite — I triage by **blast radius × flake frequency**.

**Step 1:** Pull the last 30 days of CI runs and build a flake leaderboard. Every test that failed at least twice where the re-run passed gets a row. Columns: test name, flake count, suite type (PHPUnit/Selenium/Newman), last investigated date, linked to a real bug (yes/no).

**Step 2:** Prioritize in this order:
1. **Tests that have masked a real bug** — the wallet-balance test goes first. Period. This already caused a shipped bug.
2. **High-frequency flakers** (failed 5+ times in 30 days) — these are what devs see most and what erodes trust fastest.
3. **Selenium tests that flake on timing** — these are the easiest to diagnose (usually a missing wait) and they dominate the 22-minute runtime.

I do NOT start with the newest flaky test or the easiest to fix. I start with the one that already cost us a shipped bug.

---

## 2. Quarantine Policy

**Yes, I quarantine — but with strict rules:**

- A test enters quarantine only after I've identified the root cause and filed a ticket with the fix. No "skip it, we'll look later."
- Quarantined tests run in a **separate CI job** that's visible but non-blocking. They still run — they just don't gate PRs.
- **Maximum quarantine duration: 5 business days.** After 5 days, either the fix is merged and the test is restored, or I escalate to the tech lead. No exceptions.
- **Accountability:** the developer whose code change introduced the flake is the default owner of the fix ticket. If it's an infrastructure issue (CI runner flakiness, Docker timing), I own it.

I track quarantine in a simple table in our wiki — test name, date quarantined, root cause, owner, due date. I review it in Monday standup.

---

## 3. Root Causes: 5 Specific Reasons Tests Flake

### 3a. **Missing explicit waits in Selenium (race condition with DOM)**
The test clicks a button before the page has finished rendering, or asserts on an element that hasn't appeared yet. Diagnosis: add a `WebDriverWait` with `ExpectedConditions.visibilityOfElementLocated`. Prevention: ban `Thread.sleep` in code review; enforce explicit waits in our POM base class.

### 3b. **Database state leaking between PHPUnit tests**
A test doesn't use `RefreshDatabase` or `DatabaseTransactions`, so data from test A affects test B. Passes alone, fails when run after another test. Diagnosis: run the failing test in isolation (`--filter=test_name`) — if it passes alone, it's a state leak. Fix: ensure every test class uses `RefreshDatabase`.

### 3c. **Non-deterministic order of database query results**
A test asserts `$response->json('winners.0.user_id') === 222` but the query doesn't have an `ORDER BY`, so the DB returns rows in unpredictable order. Diagnosis: run the test 20 times — if it fails intermittently with different user_ids in the response, it's ordering. Fix: either add `ORDER BY` to the query, or change the assertion to check set membership instead of position.

### 3d. **Shared external service state (rate limits, API quotas)**
Tests that hit a real staging API or use a shared test Stripe account can flake when rate limits kick in or when another developer is testing concurrently. Diagnosis: check if the flake correlates with time of day or parallel PR runs. Fix: mock external services in CI; use dedicated test API keys with higher quotas.

### 3e. **Selenium browser/driver version mismatch in CI**
The CI runner updates Chrome but not ChromeDriver, or vice versa. Tests crash with `SessionNotCreatedException`. Diagnosis: check CI logs for driver version errors. Fix: pin Chrome + ChromeDriver versions in the CI Docker image, or use `webdriver-manager` to auto-match.

---

## 4. The Wallet Test That "Cried Wolf": Post-Mortem

**What happened:** The wallet-balance regression test had been flaking for 2 weeks. Developers had been re-running it and seeing it pass on retry. When a real wallet-balance bug was introduced, the test caught it — but the developer assumed it was another flake, hit "Re-run", it happened to pass (the bug was intermittent), and the buggy code shipped.

**Root cause of the flake (before the real bug):** Likely a timing issue — the test was reading the wallet balance before the async debit had committed, so it intermittently saw the old balance.

**Process changes I propose:**

1. **Flake ≠ ignore.** Any test that flakes more than twice in a week gets a mandatory investigation ticket before the next sprint. This is the cultural fix — see section 6.

2. **Re-run limit:** CI allows a maximum of 1 automatic re-run per test. If it fails twice, it blocks the PR and requires human investigation. No more infinite "Re-run failed jobs."

3. **"Known flake" label in CI output:** When a quarantined test fails, CI clearly labels it "KNOWN FLAKE — quarantined" so developers can distinguish it from a real failure. A non-quarantined test failure always blocks.

4. **The wallet test specifically:** I fix the timing issue (add a wait/retry for the async debit), then add a second assertion that directly queries the DB balance instead of relying on the API response timing.

---

## 5. Cutting the 22-Minute CI Run

The 22-minute run is 50% Selenium. Here's my plan:

### Immediate wins (week 1):
- **Parallel PHPUnit execution:** `php artisan test --parallel` with 4 workers. PHPUnit tests are isolated (RefreshDatabase), so they're safe to parallelize. Expected: 30-40% reduction in PHPUnit time.
- **Headless Chrome in Selenium:** If not already headless, switch. Saves ~20% Selenium time from not rendering a visible window.

### Medium-term (weeks 2-3):
- **Shard Selenium tests across 2-3 CI runners.** Split the Selenium suite into groups (auth flow, gift flow, admin flow) and run them in parallel jobs. GitHub Actions supports matrix strategies for this.
- **Selective test execution on PR:** If a PR only changes files in `app/Http/Controllers/Auth/`, only run auth-related tests + the full smoke suite. Use a script that maps changed file paths to test directories. Full suite still runs on merge to main.

### Longer-term (month 2):
- **Replace Selenium tests with API-level tests where possible.** Many Selenium tests are just "fill form, submit, check result" — these can be PHPUnit Feature tests that are 10× faster. Keep Selenium only for tests that need real browser interaction (file uploads, drag-and-drop, responsive layout).
- **Target: 8-10 minute CI run** — fast enough that developers don't context-switch while waiting.

---

## 6. Cultural Fix: Stop the "Re-Run" Mash

The "Re-run" button is a symptom, not the problem. The problem is that developers don't trust the test suite, and fixing flakes isn't anyone's responsibility.

**Changes I implement:**

1. **Make flake cost visible.** I add a weekly Slack bot message to the engineering channel: "This week: 14 CI re-runs due to flaky tests. Estimated developer time wasted: ~3.5 hours." People change behavior when the cost is quantified.

2. **"You flake it, you own it" policy.** When a test starts flaking after a specific commit, the author of that commit gets the investigation ticket by default. This isn't punitive — it's just that they have the most context. If it's an infra issue, I take it back.

3. **Re-run budget:** Each PR gets 1 free automatic re-run. After that, CI posts a comment: "This PR has failed tests twice. Please investigate before re-running. If this is a known flake, tag it in the quarantine tracker." This adds just enough friction to break the mash habit.

4. **Celebrate fixes.** When someone fixes a persistent flake, I call it out in standup. "Alex fixed the gift-send timing flake — that test has flaked 23 times in the last month. Zero flakes since his fix." Positive reinforcement works better than shaming.

5. **Sprint hygiene:** Every sprint planning, I review the quarantine tracker. If there are more than 3 quarantined tests, I advocate for allocating 1-2 story points to flake fixes. This prevents the quarantine from becoming a graveyard.
