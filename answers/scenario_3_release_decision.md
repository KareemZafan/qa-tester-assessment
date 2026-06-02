# Scenario 3: Release Deadline vs Mobile Regression Coverage

---

## 1. My Recommendation to the CEO

Here's what I'd say in that meeting:

"Honestly — no, we can't ship in 9 days with full regression across every flavor without accepting significant risk elsewhere. A full regression pass takes 3 days, which gives us 6 days of buffer. That sounds fine until something breaks — and with a brand new flavor launching in a new country, the probability of issues is higher than a routine release.

Here's what I recommend instead: we regress PartyChat exhaustively — it's the new flavor, the one tied to the marketing campaign, the one where bugs would be most visible. We also regress the top 5 highest-revenue flavors because a regression there has direct financial impact. For the remaining flavors, we run a targeted smoke test — auth, payment, and send-gift only — which takes about 4 hours per flavor instead of a full day. This gives us 8 days of buffer for fixes, and our risk exposure is limited to edge-case regressions in lower-traffic flavors that we can hotfix post-launch if needed.

The honest answer is: zero risk is not on the table with zero automation. I can tell you which risks we're accepting and why they're the right ones to accept."

---

## 2. Risk-Based Prioritization: Which Flavors to Regress vs Skip

**Full regression (3 days):**
- **PartyChat** — new flavor, new country, marketing campaign tied to it. Any bug here is a PR disaster.
- **Top 5 revenue flavors** — ranked by monthly revenue. A payment regression in a top-revenue flavor costs real money immediately.

**Targeted smoke test (4 hours each):**
- All remaining flavors get a focused pass on: login/signup, in-app purchase flow, send gift (happy path), video stream join, and push notification receipt.

**How I decide which 5 are "top revenue":**
I ask the product team for the revenue dashboard. If that doesn't exist, I use active user count as a proxy (more users = more revenue). I don't guess — I get data.

**What I skip entirely:**
- Admin-only features in non-PartyChat flavors (low user impact)
- Settings screens (rarely change between flavors)
- Onboarding tutorials (cosmetic, non-critical)

---

## 3. Smallest Test Set for 80% Confidence Across Every Flavor

For each flavor, this is the minimum test set:

| # | Test Case | Why It's Critical |
|---|-----------|-------------------|
| 1 | **Login with valid credentials** | If auth is broken, nothing else matters |
| 2 | **Login with invalid credentials → error shown** | Auth security check |
| 3 | **Purchase coins (in-app purchase flow)** | Revenue — must work |
| 4 | **Send gift in a live room (happy path)** | Core product feature |
| 5 | **Send gift with insufficient balance → error** | Money guard |
| 6 | **Join a live video stream** | Core product — users came for this |
| 7 | **Send a chat message in a room** | Engagement feature |
| 8 | **Receive a push notification** | Retention feature |
| 9 | **View wallet balance (matches after transaction)** | Data integrity check |
| 10 | **Logout and re-login** | Session management |

That's 10 test cases per flavor. For a flavor with no customization beyond branding, this takes ~30-45 minutes manually. For PartyChat (new), I'd add country-specific checks: language/locale, currency formatting, and any region-specific payment provider.

80% confidence comes from covering the critical user journey (discover → join → pay → gift → watch) end-to-end. The 20% we're missing is edge cases, accessibility, and feature-specific customizations per flavor.

---

## 4. Automation Seeding: The ONE Test I'd Write First

**I write a flutter_test widget test for the Login Form.**

Why login:
- Every flavor uses the same login form with minor branding differences
- It's the entry point — if login breaks, nothing else is testable
- It has clear, testable behavior: email validation, password validation, loading state, error handling, success callback
- The test is reusable: parameterize it with flavor-specific config (brand name, API endpoint) and you've just automated the most repeated manual check across all flavors

The test covers: renders fields, validates empty submission, validates email format, calls auth service with correct credentials, shows loading spinner, handles 401 error, and calls success callback. That's 7 widget tests that run in under 2 seconds and replace 15 minutes of manual testing per flavor.

This is the same test from Exercise 5 — I'd land it this week so it's already providing value before the PartyChat launch.

---

## 5. Post-Launch Monitoring: First 72 Hours

**What I watch:**

| Signal | Tool | Threshold for Action |
|--------|------|---------------------|
| **Crash rate** | Firebase Crashlytics / Sentry | > 1% crash rate in PartyChat = investigate immediately |
| **API error rate** | Server monitoring (Datadog/Grafana) | > 2% 5xx error rate on any endpoint = page on-call |
| **Payment success rate** | Payment provider dashboard | Drop below 95% = immediate escalation |
| **Login failure rate** | Server logs | Spike above baseline = auth issue |
| **User complaints** | App store reviews + support tickets | Any mention of "can't login" or "money" = P0 |
| **Gift send volume** | Analytics dashboard | Drop > 30% compared to similar flavors at launch = investigate |

**Rollback trigger:**
- Crash rate > 3% sustained for 30 minutes
- Payment success rate drops below 90%
- Any data corruption or money-loss bug confirmed
- Auth is completely broken (users can't login at all)

**Rollback plan:** Revert to the previous app version via staged rollout (roll back to 0% on PartyChat, keep other flavors on the new version). If it's a server-side issue, revert the backend deploy independently.

I set up a dedicated Slack channel `#partychat-launch` and post a monitoring dashboard link. I'm online and checking every 30 minutes for the first 6 hours, then every 2 hours for the next 66 hours.

---

## 6. If the CEO Says "No, Regress Everything"

If the CEO insists on full regression across all flavors, I don't argue further — I ask for resources:

1. **Two additional QA testers for the 9-day sprint.** Each tester takes a third of the flavor list. With 3 testers running in parallel, we can complete full regression in 1 day instead of 3, giving us 8 days of buffer.

2. **A 2-day delay on the marketing campaign launch** as a contingency. If we find a critical bug in day 7, we need time to fix and retest. Without buffer, we'd ship known bugs under marketing pressure — and that's worse than a 2-day delay.

3. **An explicit agreement on rollback authority.** If QA finds a critical bug on day 8, I need the authority to recommend blocking the release without going through a 3-hour meeting chain. "QA can block" must be agreed upon now, not negotiated during a crisis.

4. **Budget for a contract QA tester next quarter** to start building Flutter automation so we never have this 3-day manual regression bottleneck again.

The key message: "I can do what you're asking, but it requires more people or more time. Which one can you give me?"
