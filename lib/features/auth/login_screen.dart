import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/scanner_theme.dart';
import 'auth_cubit.dart';

// One-tap demo login, same as the admin console: credentials are injected at
// build time and never committed.
// flutter run --dart-define=DEMO_EMAIL=... --dart-define=DEMO_PASSWORD=...
const String _demoEmail = String.fromEnvironment('DEMO_EMAIL');
const String _demoPassword = String.fromEnvironment('DEMO_PASSWORD');
const bool _demoLoginEnabled = _demoEmail != '' && _demoPassword != '';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    context.read<AuthCubit>().login(_email.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: BlocBuilder<AuthCubit, AuthState>(
                builder: (context, state) {
                  final busy = state.status == AuthStatus.signingIn;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 72,
                          height: 72,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: ScannerColors.brand.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 40,
                            color: ScannerColors.brand,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'TicOne Scanner',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Verify movie and bus tickets. Sign in with your TicOne admin account.',
                        style: TextStyle(
                          color: ScannerColors.textMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _email,
                        enabled: !busy,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Admin email',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _password,
                        enabled: !busy,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      if (state.error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          state.error!,
                          key: const Key('login-error'),
                          style: const TextStyle(color: ScannerColors.invalid),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: busy ? null : _submit,
                        child: busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text('Sign in'),
                      ),
                      if (_demoLoginEnabled) ...[
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () {
                                  _email.text = _demoEmail;
                                  _password.text = _demoPassword;
                                  _submit();
                                },
                          child: const Text('Demo login'),
                        ),
                      ],
                      const SizedBox(height: 32),
                      Text(
                        ApiConfig.baseUrl,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: ScannerColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
