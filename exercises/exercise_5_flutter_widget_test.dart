// =============================================================================
// EXERCISE 5: Flutter Widget Test — Login Form
// =============================================================================
//
// PACKAGES ADDED TO pubspec.yaml (dev_dependencies):
//   mocktail: ^1.0.4
//
// HELPER FUNCTIONS:
//   - FakeAuthService: manual fake implementing AuthService for full control
//     over login behavior (success, failure, delay). Chose manual fake over
//     mocktail for clarity and to demonstrate both approaches.
//   - pumpLoginForm: helper to reduce boilerplate in each test — wraps
//     LoginForm in MaterialApp + Scaffold (required for SnackBar).
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// SERVICE CONTRACT (do not modify — your tests will mock this)
// ---------------------------------------------------------------------------

abstract class AuthService {
  Future<int> login({required String email, required String password});
}

class AuthException implements Exception {
  final int statusCode;
  final String message;
  AuthException(this.statusCode, this.message);
}

// ---------------------------------------------------------------------------
// WIDGET UNDER TEST (do not modify)
// ---------------------------------------------------------------------------

class LoginForm extends StatefulWidget {
  final AuthService authService;
  final void Function(int userId) onLoginSuccess;

  const LoginForm({
    super.key,
    required this.authService,
    required this.onLoginSuccess,
  });

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;

  String? _validateEmail(String? v) {
    if (v == null || v.isEmpty) return 'Email is required';
    final emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRe.hasMatch(v)) return 'Invalid email format';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final userId = await widget.authService.login(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
      widget.onLoginSuccess(userId);
    } on AuthException catch (e) {
      if (!mounted) return;
      final message = e.statusCode == 401 ? 'Invalid credentials' : e.message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            key: const Key('email_field'),
            controller: _emailCtrl,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: _validateEmail,
          ),
          TextFormField(
            key: const Key('password_field'),
            controller: _passwordCtrl,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
            validator: _validatePassword,
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('submit_button'),
            onPressed: _loading ? null : _onSubmit,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Log in'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TEST HELPERS
// ---------------------------------------------------------------------------

class FakeAuthService implements AuthService {
  int callCount = 0;
  String? lastEmail;
  String? lastPassword;

  Completer<int>? _completer;
  int? _resultUserId;
  AuthException? _exception;

  void succeedWith(int userId) {
    _resultUserId = userId;
    _exception = null;
    _completer = null;
  }

  void failWith(AuthException exception) {
    _exception = exception;
    _resultUserId = null;
    _completer = null;
  }

  void hang() {
    _completer = Completer<int>();
    _resultUserId = null;
    _exception = null;
  }

  void complete(int userId) {
    _completer?.complete(userId);
  }

  @override
  Future<int> login({required String email, required String password}) async {
    callCount++;
    lastEmail = email;
    lastPassword = password;

    if (_completer != null) {
      return _completer!.future;
    }
    if (_exception != null) {
      throw _exception!;
    }
    return _resultUserId ?? 1;
  }
}

Widget buildTestApp({
  required AuthService authService,
  required void Function(int) onLoginSuccess,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LoginForm(
          authService: authService,
          onLoginSuccess: onLoginSuccess,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// TESTS
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // Test 1: Form renders both fields and the submit button
  // =========================================================================
  testWidgets('renders email field, password field, and submit button',
      (tester) async {
    final fakeAuth = FakeAuthService()..succeedWith(1);

    await tester.pumpWidget(buildTestApp(
      authService: fakeAuth,
      onLoginSuccess: (_) {},
    ));

    expect(find.byKey(const Key('email_field')), findsOneWidget);
    expect(find.byKey(const Key('password_field')), findsOneWidget);
    expect(find.byKey(const Key('submit_button')), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });

  // =========================================================================
  // Test 2: Tapping submit with empty fields shows two validation errors
  // =========================================================================
  testWidgets('shows validation errors when submitting empty fields',
      (tester) async {
    final fakeAuth = FakeAuthService()..succeedWith(1);

    await tester.pumpWidget(buildTestApp(
      authService: fakeAuth,
      onLoginSuccess: (_) {},
    ));

    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pump();

    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    expect(fakeAuth.callCount, 0);
  });

  // =========================================================================
  // Test 3: Invalid email format shows email validation error
  // =========================================================================
  testWidgets('shows email validation error for invalid email format',
      (tester) async {
    final fakeAuth = FakeAuthService()..succeedWith(1);

    await tester.pumpWidget(buildTestApp(
      authService: fakeAuth,
      onLoginSuccess: (_) {},
    ));

    await tester.enterText(find.byKey(const Key('email_field')), 'notanemail');
    await tester.enterText(
        find.byKey(const Key('password_field')), 'validpass123');
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pump();

    expect(find.text('Invalid email format'), findsOneWidget);
    expect(fakeAuth.callCount, 0);
  });

  // =========================================================================
  // Test 4: Valid credentials calls AuthService.login() exactly once
  // =========================================================================
  testWidgets(
      'calls AuthService.login() exactly once with correct credentials',
      (tester) async {
    final fakeAuth = FakeAuthService()..succeedWith(42);

    await tester.pumpWidget(buildTestApp(
      authService: fakeAuth,
      onLoginSuccess: (_) {},
    ));

    await tester.enterText(
        find.byKey(const Key('email_field')), 'user@test.com');
    await tester.enterText(
        find.byKey(const Key('password_field')), 'secure123');
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pumpAndSettle();

    expect(fakeAuth.callCount, 1);
    expect(fakeAuth.lastEmail, 'user@test.com');
    expect(fakeAuth.lastPassword, 'secure123');
  });

  // =========================================================================
  // Test 5: Loading state — button disabled + CircularProgressIndicator shown
  // =========================================================================
  testWidgets(
      'shows loading indicator and disables button while login is in-flight',
      (tester) async {
    final fakeAuth = FakeAuthService()..hang();

    await tester.pumpWidget(buildTestApp(
      authService: fakeAuth,
      onLoginSuccess: (_) {},
    ));

    await tester.enterText(
        find.byKey(const Key('email_field')), 'user@test.com');
    await tester.enterText(
        find.byKey(const Key('password_field')), 'secure123');
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pump(); // single pump — captures in-flight frame

    // CircularProgressIndicator should be visible
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // "Log in" text should be gone (replaced by spinner)
    expect(find.text('Log in'), findsNothing);

    // Button should be disabled (onPressed == null)
    final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('submit_button')));
    expect(button.onPressed, isNull);

    // Complete the future to avoid pending timers
    fakeAuth.complete(1);
    await tester.pumpAndSettle();
  });

  // =========================================================================
  // Test 6: Successful login calls onLoginSuccess with returned user_id
  // =========================================================================
  testWidgets('calls onLoginSuccess with correct userId on success',
      (tester) async {
    final fakeAuth = FakeAuthService()..succeedWith(42);
    int? receivedUserId;

    await tester.pumpWidget(buildTestApp(
      authService: fakeAuth,
      onLoginSuccess: (userId) => receivedUserId = userId,
    ));

    await tester.enterText(
        find.byKey(const Key('email_field')), 'user@test.com');
    await tester.enterText(
        find.byKey(const Key('password_field')), 'secure123');
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pumpAndSettle();

    expect(receivedUserId, 42);
  });

  // =========================================================================
  // Test 7: 401 response shows "Invalid credentials" SnackBar
  // =========================================================================
  testWidgets('shows "Invalid credentials" SnackBar on 401 AuthException',
      (tester) async {
    final fakeAuth = FakeAuthService()
      ..failWith(AuthException(401, 'Unauthorized'));

    await tester.pumpWidget(buildTestApp(
      authService: fakeAuth,
      onLoginSuccess: (_) {},
    ));

    await tester.enterText(
        find.byKey(const Key('email_field')), 'user@test.com');
    await tester.enterText(
        find.byKey(const Key('password_field')), 'secure123');
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pump(); // trigger the async
    await tester.pump(); // let the SnackBar appear

    expect(find.text('Invalid credentials'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
