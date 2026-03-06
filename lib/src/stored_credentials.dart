import 'package:shared_preferences/shared_preferences.dart';

const String _keyLastEmail = 'ia_secretary_last_email';

/// Saves the last used email locally (no password). Used to pre-fill the login form.
/// Supabase persists the session automatically, so the user stays logged in across app restarts.
Future<void> saveLastEmail(String email) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_keyLastEmail, email);
}

/// Returns the last saved email, or null.
Future<String?> getLastEmail() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_keyLastEmail);
}
