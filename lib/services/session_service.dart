import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class SessionService {
  static const String _sessionKey = 'billx_session_id';

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<String> _getOrCreateSessionId() async {
    final prefs = await SharedPreferences.getInstance();

    final existingSession = prefs.getString(_sessionKey);

    if (existingSession != null && existingSession.isNotEmpty) {
      return existingSession;
    }

    final sessionId = const Uuid().v4();

    await prefs.setString(_sessionKey, sessionId);

    return sessionId;
  }

  static Future<bool> startSession(User user) async {
    try {
      if (!user.emailVerified) {
        return false;
      }

      final sessionId = await _getOrCreateSessionId();

      final ref = _firestore.collection('billx_sessions').doc(user.uid);

      final snapshot = await ref.get();

      if (snapshot.exists) {
        final data = snapshot.data();

        final activeSession = data?['sessionId']?.toString();

        if (activeSession != null &&
            activeSession.isNotEmpty &&
            activeSession != sessionId) {
          return false;
        }
      }

      await ref.set({
        'sessionId': sessionId,
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<String?> currentSessionId() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_sessionKey);
  }

  static Future<void> clearSession(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final localSession = prefs.getString(_sessionKey);

      final ref = _firestore.collection('billx_sessions').doc(user.uid);

      final snapshot = await ref.get();

      if (localSession != null &&
          snapshot.exists &&
          snapshot.data()?['sessionId'] == localSession) {
        await ref.delete();
      }

      await prefs.remove(_sessionKey);

      await _auth.signOut();
    } catch (e) {
      await _auth.signOut();
    }
  }
}
