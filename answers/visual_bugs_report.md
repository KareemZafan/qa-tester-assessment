# Exercise 7: Visual Bug Hunt — Buggy Admin Panel

---

## Bug #1: Total Cost Calculated Using Addition Instead of Multiplication
- **Where:** Send Gift tab → Total cost summary row
- **Steps to reproduce:**
  1. Open the Send Gift tab
  2. Select "Diamond (1,500 coins)" from the gift dropdown
  3. Enter "10" in the Quantity field
  4. Observe the "Total cost" display
- **Expected behavior:** Total cost should show `15,000 coins` (1500 × 10)
- **Actual behavior:** Total cost shows `1510 coins` (1500 + 10) — addition instead of multiplication
- **Severity:** Critical
- **Severity reasoning:** This is a money bug. Users see a misleading total cost before confirming the gift send. The actual charge (server-side) uses correct multiplication, so the user is charged ~10× more than displayed. This would cause immediate support escalation and potential chargebacks.
- **Suspected root cause:** Frontend logic — in the `updateTotal()` function, `price + qty` is used instead of `price * qty`
- **Proposed fix:** Change the total calculation from `const total = price + qty` to `const total = price * qty`

---

## Bug #2: Send Gift Button Permanently Disabled After First Send
- **Where:** Send Gift tab → "Send Gift" button
- **Steps to reproduce:**
  1. Fill in valid values (Room ID, select gift, quantity=1, winners=1)
  2. Click "Send Gift"
  3. Wait for the success toast to appear
  4. Try to send another gift
- **Expected behavior:** Button should re-enable and reset to "Send Gift" text after the operation completes
- **Actual behavior:** Button stays greyed out with text "Sending..." permanently. The user cannot send any more gifts without refreshing the page.
- **Severity:** High
- **Severity reasoning:** Completely blocks core functionality after first use. Not a money-loss bug but renders the feature unusable within a session.
- **Suspected root cause:** Frontend logic — the `setTimeout` callback disables the button but never re-enables it or resets its text
- **Proposed fix:** Add `sendBtn.disabled = false; sendBtn.textContent = 'Send Gift';` inside the setTimeout callback after the wallet update

---

## Bug #3: Header Wallet Balance Never Updates After Sending a Gift
- **Where:** Header → green "10000 coins" pill (top-right)
- **Steps to reproduce:**
  1. Note the wallet balance in the header (10000 coins)
  2. Send a gift successfully (e.g., Rose × 1 = 100 coins)
  3. Observe the header wallet balance
  4. Navigate to the Wallet tab and check balance there
- **Expected behavior:** Both the header wallet pill and the Wallet tab should show the same updated balance (9900 coins)
- **Actual behavior:** The Wallet tab updates to 9900 coins, but the header pill still shows 10000 coins. The two balances are out of sync.
- **Severity:** High
- **Severity reasoning:** Users see conflicting balance information, which undermines trust in a financial feature. Could cause them to overspend thinking they have more coins than they do.
- **Suspected root cause:** Frontend logic — the gift send handler only updates `#wallet-current` but not `#wallet-balance` in the header
- **Proposed fix:** Add `document.getElementById('wallet-balance').textContent = walletBalance + ' coins';` in the setTimeout callback

---

## Bug #4: Sensitive Credentials Stored in localStorage in Plaintext
- **Where:** Application → DevTools → Application tab → localStorage
- **Steps to reproduce:**
  1. Open the app in any browser
  2. Open DevTools → Application → Local Storage → current domain
  3. Observe the stored keys
- **Expected behavior:** No credentials should be stored in localStorage. Session tokens should be in httpOnly cookies or at minimum not alongside plaintext passwords.
- **Actual behavior:** localStorage contains `session_token` (a hardcoded JWT) and `admin_password` with the value `SuperSecret123!` in plaintext
- **Severity:** Critical
- **Severity reasoning:** This is a security vulnerability. Any XSS attack or malicious browser extension can read localStorage and steal both the session token and the admin password. Plaintext password storage is a critical security failure.
- **Suspected root cause:** Frontend logic — the initialization script explicitly stores credentials in localStorage on page load
- **Proposed fix:** Remove the password from localStorage entirely. Session tokens should use httpOnly cookies set by the server, never client-side storage.

---

## Bug #5: Refresh Wallet Button Silently Fails but Shows Success Toast
- **Where:** Wallet tab → "Refresh Wallet" button
- **Steps to reproduce:**
  1. Navigate to the Wallet tab
  2. Click "Refresh Wallet"
  3. Observe the toast notification
  4. Open DevTools Console
- **Expected behavior:** Wallet should refresh from the server and either show updated data or an honest error message if the refresh fails
- **Actual behavior:** A "Wallet refreshed!" success toast appears, but the console shows `TypeError: Cannot read properties of undefined (reading 'coins')`. The balance is NOT actually refreshed — the user is misled.
- **Severity:** High
- **Severity reasoning:** Silent data corruption — user believes their balance is current when it isn't. In a real app, this could mask a stale balance that leads to failed transactions.
- **Suspected root cause:** Frontend logic — `fetchedWallet` is undefined (no actual API call), the error is caught silently, and a misleading success toast is shown
- **Proposed fix:** Implement actual API call to fetch wallet balance, and show an error toast if it fails instead of a success message

---

## Bug #6: Ban Button Visible to All Users (Broken Role Check)
- **Where:** Users tab → "Ban" button on each user row
- **Steps to reproduce:**
  1. Navigate to the Users tab
  2. Observe that every user row has a "Ban" button
  3. Inspect the code: the role check uses `currentUser.is_admin` which is undefined
- **Expected behavior:** Ban buttons should only be visible to admin users. The role check should use `currentUser.role === 'admin'`.
- **Actual behavior:** The condition `!currentUser.is_admin` evaluates to `!undefined` = `true`, so the Ban button is always shown regardless of the user's role. This is an inverted authorization check.
- **Severity:** Critical
- **Severity reasoning:** Authorization bypass — any user can ban other users including admins. In a real system this would be a privilege escalation vulnerability.
- **Suspected root cause:** Frontend logic — the role check references `currentUser.is_admin` (which doesn't exist on the object) and the boolean logic is inverted
- **Proposed fix:** Change the condition to `currentUser.role === 'admin'` and invert the display logic correctly

---

## Bug #7: Ban Action Doesn't Update the Users Table (Stale UI)
- **Where:** Users tab → "Ban" button
- **Steps to reproduce:**
  1. Navigate to the Users tab
  2. Click "Ban" on any user (e.g., DJ_Master)
  3. Observe the toast says "User banned (id 101)"
  4. Look at the users table — DJ_Master is still visible
- **Expected behavior:** The banned user should disappear from the users table immediately after banning
- **Actual behavior:** The user is removed from the internal array but the table is not re-rendered. The UI is stale.
- **Severity:** Medium
- **Severity reasoning:** Functional bug but not a security or money issue. Confusing UX — admin thinks the ban didn't work and may try again.
- **Suspected root cause:** Frontend logic — `banUser()` splices from the array but doesn't call `renderUsers()`
- **Proposed fix:** Add `renderUsers()` at the end of the `banUser` function

---

## Bug #8: No Viewport Meta Tag — Broken Mobile Layout
- **Where:** Entire page when viewed on mobile or narrow browser
- **Steps to reproduce:**
  1. Open the app in a mobile browser or resize desktop browser to < 480px width
  2. Observe the layout
- **Expected behavior:** Page should be responsive and scale appropriately on mobile devices
- **Actual behavior:** Page renders at desktop width and requires horizontal scrolling. Text and inputs are tiny and unusable on mobile.
- **Severity:** Medium
- **Severity reasoning:** UX degradation on mobile but not a data/money/security issue. Admin panels are typically desktop-focused, but basic responsiveness is expected.
- **Suspected root cause:** Frontend layout — the `<meta name="viewport">` tag is intentionally missing from the `<head>`
- **Proposed fix:** Add `<meta name="viewport" content="width=device-width, initial-scale=1.0">` to the HTML head

---

## Bug #9: Quantity Field Accepts Invalid Input (Text, Negatives, Decimals)
- **Where:** Send Gift tab → Quantity input field
- **Steps to reproduce:**
  1. Open the Send Gift tab
  2. Type "abc" into the Quantity field — it accepts it
  3. Type "-5" — it accepts it
  4. Type "3.7" — it accepts it
- **Expected behavior:** Field should be `type="number"` with `min="1"` and `max="100"` and `step="1"`. Should reject non-numeric, negative, and decimal input.
- **Actual behavior:** Field is `type="text"` with no validation. Any string is accepted. Submitting non-numeric values results in `parseInt` returning NaN, which leads to 0 charge.
- **Severity:** High
- **Severity reasoning:** Allows zero-cost gift sends (typing letters results in NaN → 0 charge) which is a money bug. Also allows negative quantities.
- **Suspected root cause:** Frontend — input type is "text" instead of "number", and no client-side or submit-time validation exists
- **Proposed fix:** Change `type="text"` to `type="number"` and add `min="1" max="100" step="1"` attributes. Add submit-time validation.

---

## Bug #10: Very Low Contrast on `.muted` Description Text
- **Where:** Multiple tabs — description text below headings (e.g., "Charge coins from your wallet...")
- **Steps to reproduce:**
  1. Look at the description text below "Send Gift (with audience bonus)" heading
  2. The text color is `#d8dde5` on a white `#ffffff` background
- **Expected behavior:** Description text should have sufficient contrast (WCAG AA requires 4.5:1 ratio for normal text)
- **Actual behavior:** Contrast ratio is approximately 1.4:1 — the text is nearly invisible against the white panel background
- **Severity:** Low
- **Severity reasoning:** Accessibility issue. Users with low vision or in bright environments cannot read these descriptions. Not a functional bug.
- **Suspected root cause:** Frontend CSS — `.muted` class uses `color: #d8dde5` which is far too light for a white background
- **Proposed fix:** Change to a darker gray like `#6b7280` which achieves ~4.6:1 contrast ratio

---

## Bug #11: Long Username Breaks Table Layout
- **Where:** Users tab → username column for user "TheVeryLongUsernameThatProbablyBreaksTheLayoutInTheTableColumn_2026_Edition"
- **Steps to reproduce:**
  1. Navigate to the Users tab
  2. Observe the row with ID 103
- **Expected behavior:** Long text should be truncated with ellipsis or the table should handle overflow gracefully
- **Actual behavior:** The username extends beyond the column, pushing other columns off-screen or causing horizontal overflow
- **Severity:** Low
- **Severity reasoning:** Layout/cosmetic issue. Doesn't break functionality but degrades admin UX.
- **Suspected root cause:** Frontend CSS — no `overflow`, `text-overflow`, or `max-width` on the username cell
- **Proposed fix:** Add `max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;` to the username `<td>`

---

## Bug #12: XSS Vulnerability — Username Rendered via innerHTML Without Escaping
- **Where:** Users tab → username column
- **Steps to reproduce:**
  1. If a user had the username `<img src=x onerror=alert(1)>`, it would execute JavaScript
  2. In the current code, `u.username` is inserted via template literal into `innerHTML` with no escaping
- **Expected behavior:** Usernames should be escaped or inserted via `textContent` to prevent script execution
- **Actual behavior:** Raw HTML from the username is rendered directly into the DOM. A malicious username could execute arbitrary JavaScript (stored XSS).
- **Severity:** Critical
- **Severity reasoning:** Stored XSS in an admin panel. An attacker registers a username containing a script payload, and every admin who views the Users tab gets compromised. Could steal admin session tokens, modify data, or escalate privileges.
- **Suspected root cause:** Frontend logic — `renderUsers()` uses `tr.innerHTML` with unescaped `${u.username}`
- **Proposed fix:** Use `document.createTextNode()` or a sanitization function instead of raw `innerHTML` interpolation

---

## How I Tested

I started with a systematic smoke test — visiting each tab (Send Gift, Users, Wallet, Bans) and trying the happy path first. Then I moved to edge cases: empty inputs, negative numbers, text in numeric fields, and very long strings. I opened DevTools Console immediately on load and watched for JS errors during every interaction (which caught the Refresh Wallet TypeError). I checked localStorage in the Application tab for any sensitive data exposure. I also inspected the source code to identify logic bugs that wouldn't be visible from UI interaction alone (the addition-vs-multiplication bug, the XSS vulnerability, and the broken role check). Finally, I resized the browser to mobile width to test responsive behavior.
