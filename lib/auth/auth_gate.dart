import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../license/license_service.dart';
import '../billing/bill_home_page.dart';
import '../license/license_page.dart' as billx_license;
import 'login_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool checking = true;
  bool authenticated = false;
  bool licensed = false;

  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _handleAuthState,
    );
  }

  Future<void> _handleAuthState(User? user) async {
    if (!mounted) return;

    if (user == null) {
      setState(() {
        authenticated = false;
        licensed = false;
        checking = false;
      });
      return;
    }

    setState(() {
      checking = true;
    });

    try {
      await user.reload();

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        if (!mounted) return;

        setState(() {
          authenticated = false;
          licensed = false;
          checking = false;
        });
        return;
      }

      if (!currentUser.emailVerified) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        setState(() {
          authenticated = false;
          licensed = false;
          checking = false;
        });
        return;
      }

      // IMPORTANT:
      // Authentication has already succeeded.
      // License verification must NOT send the user back
      // to the Login page when the license server is unavailable.
      bool licenseOk = false;

      try {
        final result = await LicenseService.verifyStoredLicense();
        licenseOk = result.success;
      } catch (e, stackTrace) {
        debugPrint('LICENSE CHECK ERROR: $e');
        debugPrint('LICENSE CHECK STACK: $stackTrace');

        // Keep the user authenticated.
        // They will see the License page instead of Login.
        licenseOk = false;
      }

      if (!mounted) return;

      setState(() {
        authenticated = true;
        licensed = licenseOk;
        checking = false;
      });
    } on FirebaseAuthException catch (e, stackTrace) {
      debugPrint('AUTH GATE FIREBASE ERROR: ${e.code}');
      debugPrint('AUTH GATE MESSAGE: ${e.message}');
      debugPrint('AUTH GATE STACK: $stackTrace');

      if (!mounted) return;

      setState(() {
        authenticated = false;
        licensed = false;
        checking = false;
      });
    } catch (e, stackTrace) {
      debugPrint('AUTH GATE ERROR: $e');
      debugPrint('AUTH GATE STACK: $stackTrace');

      // Do not automatically sign the user out here.
      // If Firebase has a valid current user, keep them authenticated.
      final currentUser = FirebaseAuth.instance.currentUser;

      if (!mounted) return;

      setState(() {
        authenticated = currentUser != null && currentUser.emailVerified;
        licensed = false;
        checking = false;
      });
    }
  }

  void _licenseActivated() {
    if (!mounted) return;

    setState(() {
      licensed = true;
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!authenticated) {
      return const LoginPage();
    }

    if (!licensed) {
      return billx_license.LicensePage(onActivated: _licenseActivated);
    }

    return const BillHomePage();
  }
}
