import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/session_store.dart';
import 'auth_repository.dart';

enum AuthStatus { unknown, signedOut, signingIn, signedIn }

class AuthState extends Equatable {
  final AuthStatus status;
  final StaffSession? session;
  final String? error;

  const AuthState(this.status, {this.session, this.error});

  @override
  List<Object?> get props => [status, session, error];
}

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository _auth;

  AuthCubit(this._auth) : super(const AuthState(AuthStatus.unknown));

  Future<void> restore() async {
    final session = await _auth.restore();
    emit(
      session == null
          ? const AuthState(AuthStatus.signedOut)
          : AuthState(AuthStatus.signedIn, session: session),
    );
  }

  Future<void> login(String email, String password) async {
    if (email.trim().isEmpty || password.isEmpty) {
      emit(
        const AuthState(
          AuthStatus.signedOut,
          error: 'Enter your admin email and password.',
        ),
      );
      return;
    }
    emit(const AuthState(AuthStatus.signingIn));
    try {
      final session = await _auth.login(email, password);
      emit(AuthState(AuthStatus.signedIn, session: session));
    } on ApiFailure catch (e) {
      emit(AuthState(AuthStatus.signedOut, error: e.message));
    }
  }

  Future<void> logout() async {
    await _auth.logout();
    emit(const AuthState(AuthStatus.signedOut));
  }

  /// The refresh token was rejected; staff must sign in again.
  void sessionExpired() {
    if (state.status != AuthStatus.signedIn) return;
    _auth.logout();
    emit(
      const AuthState(
        AuthStatus.signedOut,
        error: 'Your session expired. Please sign in again.',
      ),
    );
  }
}
