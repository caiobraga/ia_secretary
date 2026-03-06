import 'package:supabase_flutter/supabase_flutter.dart';

/// Email sign-in with no verification (disable "Confirm email" in Supabase → Auth → Providers → Email).
class AuthService {
  static User? get currentUser => Supabase.instance.client.auth.currentUser;

  static bool get isSignedIn => currentUser != null;

  /// Sign up with email and password. No email verification if disabled in Supabase.
  static Future<void> signUpWithEmail({required String email, required String password}) async {
    await Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: null,
    );
  }

  /// Sign in with email and password.
  static Future<void> signInWithEmail({required String email, required String password}) async {
    await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Sign out (clears session).
  static Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
  }
}
