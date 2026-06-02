<?php

// =============================================================================
// BUGS FOUND IN THE ORIGINAL TEST:
// 1. Missing `use RefreshDatabase` — test pollutes DB between runs, causing
//    non-deterministic failures when tests run in parallel or in sequence.
// 2. Vague test name `test_it_works` — doesn't describe the behavior under test;
//    makes it impossible to know what regressed when the test fails.
// 3. Raw DB::table inserts instead of model factories — brittle, bypasses model
//    events/observers, and hard-codes IDs that may conflict.
// 4. Hard-coded bearer token (`'Bearer fake-token-123'`) instead of using
//    Sanctum::actingAs() — the test never actually authenticates; it either
//    always fails (if middleware is active) or silently skips auth (if middleware
//    is disabled in testing), hiding auth bugs.
// 5. No wallet balance assertion after the request — the test would pass even if
//    the endpoint forgot to deduct coins from the sender's wallet.
// 6. Only asserts HTTP 200 status — doesn't validate response body shape,
//    transaction_id, winners array, coins_charged, or remaining_balance.
// 7. No assertion that winners were credited — missing DB check on winner wallets.
// 8. No idempotency replay test — doesn't verify that sending the same
//    idempotency_key twice results in a single charge.
// 9. No Event::fake() / broadcast assertion — doesn't verify the `gift.sent`
//    WebSocket event was dispatched.
// 10. No cleanup (consequence of missing RefreshDatabase) — test data leaks into
//     subsequent tests.
//
// REFACTOR NOTES:
// - Used Sanctum::actingAs() for proper auth simulation
// - Used Laravel factories (User::factory(), etc.) for clean, isolated data setup
// - Added RefreshDatabase trait for test isolation
// - Each test method has a descriptive name matching the behavior it asserts
// - Added wallet-debit regression test, auth tests, rate-limit test, idempotency
//   replay test, and Event::fake() broadcast test
// =============================================================================

namespace Tests\Feature;

use Tests\TestCase;
use App\Models\User;
use App\Models\Room;
use App\Models\Gift;
use App\Models\Wallet;
use App\Events\GiftSent;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Laravel\Sanctum\Sanctum;

class SendGiftTest extends TestCase
{
    use RefreshDatabase;

    private User $sender;
    private Room $room;
    private Gift $gift;

    protected function setUp(): void
    {
        parent::setUp();

        $this->sender = User::factory()->create();
        Wallet::factory()->create([
            'user_id' => $this->sender->id,
            'coins' => 10000,
        ]);

        $this->room = Room::factory()->create(['is_live' => true]);
        $this->gift = Gift::factory()->create(['coin_price' => 500]);

        // Seed room with viewers so winners_count is satisfiable
        $viewers = User::factory()->count(10)->create();
        foreach ($viewers as $viewer) {
            $this->room->join($viewer);
            Wallet::factory()->create(['user_id' => $viewer->id, 'coins' => 0]);
        }
        $this->room->join($this->sender);
    }

    private function validPayload(array $overrides = []): array
    {
        return array_merge([
            'room_id' => $this->room->id,
            'gift_id' => $this->gift->id,
            'quantity' => 10,
            'winners_count' => 5,
            'idempotency_key' => fake()->uuid(),
        ], $overrides);
    }

    // =========================================================================
    // TASK 2: Fixed happy-path test with wallet-debit regression assertion
    // =========================================================================

    public function test_send_gift_deducts_coins_from_sender_wallet_and_credits_winners(): void
    {
        Sanctum::actingAs($this->sender);

        $balanceBefore = $this->sender->wallet->coins;
        $expectedCharge = $this->gift->coin_price * 10; // quantity=10

        $response = $this->postJson('/api/gifts/send', $this->validPayload());

        $response->assertStatus(200)
            ->assertJsonStructure([
                'transaction_id',
                'coins_charged',
                'winners' => [['user_id', 'coins_awarded']],
                'remaining_balance',
            ])
            ->assertJsonPath('coins_charged', $expectedCharge)
            ->assertJsonCount(5, 'winners');

        // REGRESSION GUARD: verify wallet was actually debited in the database
        $this->sender->wallet->refresh();
        $this->assertEquals(
            $balanceBefore - $expectedCharge,
            $this->sender->wallet->coins,
            'Sender wallet was not debited by the correct amount'
        );

        // Verify remaining_balance in response matches DB
        $response->assertJsonPath('remaining_balance', $this->sender->wallet->coins);

        // Verify at least one winner was credited
        $winnersData = $response->json('winners');
        foreach ($winnersData as $winner) {
            $winnerWallet = Wallet::where('user_id', $winner['user_id'])->first();
            $this->assertGreaterThan(0, $winnerWallet->coins, 'Winner was not credited');
        }
    }

    // =========================================================================
    // TASK 3a: Auth — missing token returns 401
    // =========================================================================

    public function test_returns_401_when_token_is_missing(): void
    {
        // Do NOT call Sanctum::actingAs — send request without auth
        $response = $this->postJson('/api/gifts/send', $this->validPayload());

        $response->assertStatus(401);

        // Verify no wallet deduction occurred
        $this->sender->wallet->refresh();
        $this->assertEquals(10000, $this->sender->wallet->coins);
    }

    // =========================================================================
    // TASK 3b: Rate limit — 429 after 30 requests in one minute
    // =========================================================================

    public function test_returns_429_after_30_requests_in_one_minute(): void
    {
        Sanctum::actingAs($this->sender);

        // Give sender enough coins for 30+ sends
        $this->sender->wallet->update(['coins' => 999999]);

        for ($i = 0; $i < 30; $i++) {
            $this->postJson('/api/gifts/send', $this->validPayload());
        }

        // The 31st request should be throttled
        $response = $this->postJson('/api/gifts/send', $this->validPayload());
        $response->assertStatus(429);
        $response->assertHeader('Retry-After');
    }

    // =========================================================================
    // TASK 3c: winners_count exceeds audience → no charge
    // =========================================================================

    public function test_does_not_charge_sender_when_winners_count_exceeds_audience(): void
    {
        Sanctum::actingAs($this->sender);

        $balanceBefore = $this->sender->wallet->coins;

        // Room has 10 viewers + sender = 11, request 50 winners
        $response = $this->postJson('/api/gifts/send', $this->validPayload([
            'winners_count' => 50,
        ]));

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['winners_count']);

        // Verify wallet was NOT debited
        $this->sender->wallet->refresh();
        $this->assertEquals(
            $balanceBefore,
            $this->sender->wallet->coins,
            'Sender was charged despite validation failure'
        );
    }

    // =========================================================================
    // TASK 5: Idempotency replay — same key returns same result, no double debit
    // =========================================================================

    public function test_idempotency_replay_returns_same_transaction_without_double_debit(): void
    {
        Sanctum::actingAs($this->sender);

        $idempotencyKey = fake()->uuid();
        $payload = $this->validPayload(['idempotency_key' => $idempotencyKey]);

        // First request
        $first = $this->postJson('/api/gifts/send', $payload);
        $first->assertStatus(200);
        $firstTransactionId = $first->json('transaction_id');
        $balanceAfterFirst = $this->sender->wallet->refresh()->coins;

        // Replay with same idempotency_key
        $second = $this->postJson('/api/gifts/send', $payload);
        $second->assertStatus(200);

        // Must return the SAME transaction, not a new one
        $this->assertEquals(
            $firstTransactionId,
            $second->json('transaction_id'),
            'Replay created a new transaction instead of returning the cached one'
        );

        // Wallet must NOT be debited a second time
        $this->sender->wallet->refresh();
        $this->assertEquals(
            $balanceAfterFirst,
            $this->sender->wallet->coins,
            'Idempotency replay caused a double debit'
        );
    }

    // =========================================================================
    // TASK 6: Event::fake() — broadcast event dispatched exactly once
    // =========================================================================

    public function test_gift_sent_event_is_broadcast_exactly_once_on_success(): void
    {
        Event::fake([GiftSent::class]);

        Sanctum::actingAs($this->sender);

        $response = $this->postJson('/api/gifts/send', $this->validPayload());
        $response->assertStatus(200);

        Event::assertDispatched(GiftSent::class, function ($event) use ($response) {
            return $event->transactionId === $response->json('transaction_id')
                && $event->roomId === $this->room->id
                && $event->senderId === $this->sender->id;
        });

        Event::assertDispatchedTimes(GiftSent::class, 1);
    }
}
