import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../services/session_service.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // ============================================================
  // CONTROLLERS
  // ============================================================

  final TextEditingController _emailController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  // ============================================================
  // FIREBASE
  // ============================================================

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ============================================================
  // BIOMETRIC
  // ============================================================

  final LocalAuthentication _localAuth = LocalAuthentication();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static const String _biometricEmailKey = 'billx_biometric_email';

  static const String _biometricPasswordKey = 'billx_biometric_password';

  // ============================================================
  // STATE
  // ============================================================

  bool _loading = false;
  bool _biometricLoading = false;
  bool _obscurePassword = true;

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ============================================================
  // GMAIL VALIDATION
  // ============================================================

  bool _isValidGmail(String email) {
    final value = email.trim().toLowerCase();

    return RegExp(r'^[a-zA-Z0-9._%+-]+@gmail\.com$').hasMatch(value);
  }

  // ============================================================
  // PASSWORD VALIDATION
  // ============================================================

  bool _isValidPassword(String password) {
    if (password.length < 6) {
      return false;
    }

    final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);

    final hasLowercase = RegExp(r'[a-z]').hasMatch(password);

    final hasNumber = RegExp(r'[0-9]').hasMatch(password);

    return hasUppercase && hasLowercase && hasNumber;
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message, {bool error = true}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red : Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  // ============================================================
  // SAVE BIOMETRIC LOGIN
  // ============================================================

  Future<void> _saveBiometricCredentials(String email, String password) async {
    if (kIsWeb) return;

    try {
      await _secureStorage.write(key: _biometricEmailKey, value: email);

      await _secureStorage.write(key: _biometricPasswordKey, value: password);

      debugPrint('Biometric credentials saved.');
    } catch (e) {
      debugPrint('Biometric credential save error: $e');
    }
  }

  // ============================================================
  // NORMAL LOGIN
  // ============================================================

  Future<void> _login() async {
    // Hide keyboard
    FocusScope.of(context).unfocus();

    // Prevent double click
    if (_loading) {
      return;
    }

    final email = _emailController.text.trim().toLowerCase();

    final password = _passwordController.text;

    // ==========================================================
    // EMAIL VALIDATION
    // ==========================================================

    if (email.isEmpty) {
      _showMessage('Please enter your Gmail address.');
      return;
    }

    if (!_isValidGmail(email)) {
      _showMessage(
        'Please enter a valid Gmail address ending with @gmail.com.',
      );
      return;
    }

    // ==========================================================
    // PASSWORD VALIDATION
    // ==========================================================

    if (password.isEmpty) {
      _showMessage('Please enter your password.');
      return;
    }

    if (!_isValidPassword(password)) {
      _showMessage(
        'Password must contain at least 6 characters, '
        'one uppercase letter, one lowercase letter, '
        'and one number.',
      );
      return;
    }

    // ==========================================================
    // START LOADING
    // ==========================================================

    setState(() {
      _loading = true;
    });

    try {
      debugPrint('========================================');

      debugPrint('BILLX LOGIN START');

      debugPrint('Email: $email');

      debugPrint(
        'Firebase Project: '
        '${_auth.app.options.projectId}',
      );

      debugPrint('========================================');

      // ========================================================
      // FIREBASE LOGIN
      // ========================================================

      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = credential.user;

      // ========================================================
      // USER CHECK
      // ========================================================

      if (user == null) {
        throw FirebaseAuthException(
          code: 'login-failed',
          message: 'Firebase did not return a user.',
        );
      }

      debugPrint('Firebase sign-in successful.');

      debugPrint('UID: ${user.uid}');

      debugPrint('Email: ${user.email}');

      // ========================================================
      // REFRESH USER
      // ========================================================

      await user.reload();

      final User? currentUser = _auth.currentUser;

      if (currentUser == null) {
        throw FirebaseAuthException(
          code: 'login-failed',
          message: 'User session was lost after login.',
        );
      }

      debugPrint(
        'Current Firebase user: '
        '${currentUser.email}',
      );

      debugPrint(
        'Email verified: '
        '${currentUser.emailVerified}',
      );

      // ========================================================
      // EMAIL VERIFICATION
      // ========================================================

      if (!currentUser.emailVerified) {
        debugPrint('Email is not verified.');

        await _auth.signOut();

        _showMessage('Please verify your Gmail before logging in.');

        return;
      }

      debugPrint('Email verification successful.');

      // ========================================================
      // SESSION
      // ========================================================
      //
      // IMPORTANT:
      // Session failure will NOT automatically logout
      // the Firebase account.
      //
      // This prevents the login from returning to LoginPage
      // because of a session service problem.
      // ========================================================

      try {
        final bool sessionStarted = await SessionService.startSession(
          currentUser,
        );

        debugPrint('Session started: $sessionStarted');

        if (!sessionStarted) {
          debugPrint('WARNING: Session could not be started.');
        }
      } catch (e) {
        debugPrint('SessionService error: $e');

        // Do NOT sign out here.
      }

      // ========================================================
      // SAVE BIOMETRIC CREDENTIALS
      // ========================================================

      if (!kIsWeb) {
        try {
          await _saveBiometricCredentials(email, password);
        } catch (e) {
          debugPrint('Biometric save failed: $e');
        }
      }

      // ========================================================
      // LOGIN SUCCESS
      // ========================================================

      debugPrint('========================================');

      debugPrint('BILLX LOGIN SUCCESS');

      debugPrint(
        'Logged in user: '
        '${currentUser.email}',
      );

      debugPrint('========================================');

      if (!mounted) {
        return;
      }

      _showMessage('Login successful.', error: false);

      // ========================================================
      // VERY IMPORTANT
      // ========================================================
      //
      // DO NOT DO THIS:
      //
      // Navigator.push(...)
      //
      // DO NOT DO THIS:
      //
      // Navigator.pushAndRemoveUntil(...)
      //
      // DO NOT OPEN AuthGate HERE.
      //
      // Root AuthGate is already listening to:
      //
      // FirebaseAuth.instance.authStateChanges()
      //
      // So Firebase authentication state will automatically
      // move the application from LoginPage to the next page.
      // ========================================================
    } on FirebaseAuthException catch (e) {
      // ========================================================
      // FIREBASE ERROR
      // ========================================================

      debugPrint('========================================');

      debugPrint('FIREBASE LOGIN ERROR');

      debugPrint('Code: ${e.code}');

      debugPrint('Message: ${e.message}');

      debugPrint('========================================');

      String message;

      switch (e.code) {
        case 'invalid-credential':
          message = 'Gmail or password is incorrect.';
          break;

        case 'wrong-password':
          message = 'Gmail or password is incorrect.';
          break;

        case 'user-not-found':
          message = 'This Gmail account was not found.';
          break;

        case 'invalid-email':
          message = 'Please enter a valid Gmail address.';
          break;

        case 'too-many-requests':
          message =
              'Too many login attempts. '
              'Please try again later.';
          break;

        case 'network-request-failed':
          message =
              'Network error. '
              'Please check your internet connection.';
          break;

        case 'user-disabled':
          message = 'This Firebase account has been disabled.';
          break;

        case 'operation-not-allowed':
          message =
              'Email/password login is disabled '
              'in Firebase Authentication.';
          break;

        case 'invalid-api-key':
          message = 'Firebase API key is invalid.';
          break;

        case 'app-not-authorized':
          message =
              'This app is not authorized '
              'for the Firebase project.';
          break;

        case 'internal-error':
          message =
              'Firebase internal error. '
              'Please check Firebase configuration.';
          break;

        case 'login-failed':
          message = e.message ?? 'Login failed.';
          break;

        default:
          message =
              'Firebase login error: '
              '${e.message ?? e.code}';
      }

      if (mounted) {
        _showMessage(message);
      }
    } catch (e, stackTrace) {
      // ========================================================
      // OTHER ERROR
      // ========================================================

      debugPrint('========================================');

      debugPrint('BILLX LOGIN INTERNAL ERROR');

      debugPrint('Error: $e');

      debugPrint('StackTrace: $stackTrace');

      debugPrint('========================================');

      if (mounted) {
        _showMessage('Login error: $e');
      }
    } finally {
      // ========================================================
      // STOP LOADING
      // ========================================================

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // BIOMETRIC LOGIN
  // ============================================================

  Future<void> _biometricLogin() async {
    if (kIsWeb) {
      _showMessage('Biometric login is not available on Web.');
      return;
    }

    if (_biometricLoading) {
      return;
    }

    setState(() {
      _biometricLoading = true;
    });

    try {
      // ========================================================
      // READ SAVED LOGIN
      // ========================================================

      final String? email = await _secureStorage.read(key: _biometricEmailKey);

      final String? password = await _secureStorage.read(
        key: _biometricPasswordKey,
      );

      if (email == null ||
          email.isEmpty ||
          password == null ||
          password.isEmpty) {
        _showMessage(
          'No biometric login is saved. '
          'Please login with Gmail and password first.',
        );

        return;
      }

      // ========================================================
      // CHECK BIOMETRIC SUPPORT
      // ========================================================

      final bool canCheckBiometrics = await _localAuth.canCheckBiometrics;

      final bool isDeviceSupported = await _localAuth.isDeviceSupported();

      if (!canCheckBiometrics && !isDeviceSupported) {
        _showMessage(
          'Biometric authentication is not available on this device.',
        );

        return;
      }

      // ========================================================
      // BIOMETRIC AUTHENTICATION
      // ========================================================

      final bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to login to BillX',
        biometricOnly: false,
      );

      if (!authenticated) {
        _showMessage('Biometric authentication was cancelled.');

        return;
      }

      // ========================================================
      // FIREBASE LOGIN
      // ========================================================

      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = credential.user;

      if (user == null) {
        _showMessage('Biometric login failed.');

        return;
      }

      // ========================================================
      // REFRESH USER
      // ========================================================

      await user.reload();

      final User? currentUser = _auth.currentUser;

      if (currentUser == null) {
        _showMessage('Login failed. Please try again.');

        return;
      }

      // ========================================================
      // EMAIL VERIFICATION
      // ========================================================

      if (!currentUser.emailVerified) {
        await _auth.signOut();

        _showMessage('Please verify your Gmail before logging in.');

        return;
      }

      // ========================================================
      // SESSION
      // ========================================================

      try {
        final bool sessionStarted = await SessionService.startSession(
          currentUser,
        );

        debugPrint(
          'Biometric session started: '
          '$sessionStarted',
        );
      } catch (e) {
        debugPrint('Biometric SessionService error: $e');

        // Do NOT sign out.
      }

      // ========================================================
      // SUCCESS
      // ========================================================

      debugPrint('Biometric login successful.');

      if (mounted) {
        _showMessage('Biometric login successful.', error: false);
      }

      // No Navigator here.
      // AuthGate handles the Firebase state.
    } on LocalAuthException catch (e) {
      debugPrint('LocalAuthException: ${e.code}');

      _showMessage('Biometric authentication failed.');
    } on FirebaseAuthException catch (e) {
      debugPrint('Biometric Firebase error: ${e.code}');

      debugPrint(
        'Biometric Firebase message: '
        '${e.message}',
      );

      _showMessage(
        'Biometric login failed: '
        '${e.message ?? e.code}',
      );
    } catch (e, stackTrace) {
      debugPrint('BIOMETRIC LOGIN ERROR: $e');

      debugPrint('BIOMETRIC LOGIN STACK: $stackTrace');

      _showMessage('Biometric login error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _biometricLoading = false;
        });
      }
    }
  }

  // ============================================================
  // REGISTER PAGE
  // ============================================================

  Future<void> _openRegisterPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterPage()),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 850;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEAF3FF), Color(0xFFF7F5FF), Color(0xFFEFF6FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: -110,
                left: -90,
                child: _blob(260, const Color(0x332E7CF6)),
              ),
              Positioned(
                bottom: -120,
                right: -90,
                child: _blob(300, const Color(0x332D5BFF)),
              ),
              SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: desktop ? 55 : 20,
                  vertical: desktop ? 35 : 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: desktop
                      ? SizedBox(
                          height: MediaQuery.of(context).size.height - 70,
                          child: Row(
                            children: [
                              Expanded(flex: 5, child: _brandPanel()),
                              const SizedBox(width: 35),
                              Expanded(flex: 4, child: _loginCard()),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            const SizedBox(height: 18),
                            _mobileBrand(),
                            const SizedBox(height: 25),
                            _loginCard(),
                            const SizedBox(height: 20),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _mobileBrand() {
    return Column(
      children: [
        _billxLogo(size: 72),
        const SizedBox(height: 12),
        const Text(
          'BillX',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1769E0),
          ),
        ),
        const Text(
          'Smart Billing for Your Business',
          style: TextStyle(color: Color(0xFF527096), fontSize: 13),
        ),
      ],
    );
  }

  Widget _brandPanel() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _billxLogo(size: 86),
          const SizedBox(height: 18),
          const Text(
            'BillX',
            style: TextStyle(
              fontSize: 58,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1769E0),
              height: 1,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Smart Billing for Your Business',
            style: TextStyle(
              fontSize: 19,
              color: Color(0xFF527096),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 38),
          const Text(
            'Simple. Fast. Professional.',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Color(0xFF172B4D),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Create invoices, manage products and keep your billing workflow organized with BillX.',
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 35),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _featureChip(Icons.bolt_rounded, 'Fast'),
              _featureChip(Icons.security_rounded, 'Secure'),
              _featureChip(Icons.cloud_done_rounded, 'Cloud Ready'),
              _featureChip(Icons.bar_chart_rounded, 'Business Tools'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _featureChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE8F7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: const Color(0xFF1769E0)),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF334E68),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _billxLogo({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * .25),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Icon(
        Icons.receipt_long_rounded,
        color: const Color(0xFF1769E0),
        size: size * .55,
      ),
    );
  }

  Widget _loginCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Welcome Back',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w800,
              color: Color(0xFF172B4D),
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Sign in to access your BillX account',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF718096), fontSize: 14),
          ),
          const SizedBox(height: 28),
          _loginField(
            controller: _emailController,
            label: 'Email Address',
            hint: 'example@gmail.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 15),
          _loginField(
            controller: _passwordController,
            label: 'Password',
            hint: 'Enter your password',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscurePassword,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
            suffixIcon: IconButton(
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            'Minimum 6 characters • uppercase • lowercase • number',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF8A99AB)),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1769E0), Color(0xFF6545E8)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton(
                onPressed: _loading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 23,
                        height: 23,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Login',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(width: 10),
                          Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
              ),
            ),
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 13),
            OutlinedButton.icon(
              onPressed: _biometricLoading ? null : _biometricLogin,
              icon: _biometricLoading
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fingerprint_rounded),
              label: const Text('LOGIN WITH BIOMETRIC'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                foregroundColor: const Color(0xFF1769E0),
                side: const BorderSide(color: Color(0xFFD7E3F4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Divider(color: Color(0xFFE3E8EF))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'OR',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: Color(0xFFE3E8EF))),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Use your registered Gmail and password to continue.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF718096), fontSize: 12.5),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Don't have an account? ",
                style: TextStyle(color: Color(0xFF64748B)),
              ),
              TextButton(
                onPressed: _openRegisterPage,
                child: const Text(
                  'Sign Up',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _loginField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Iterable<String>? autofillHints,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF7B8CA5)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE1E8F2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE1E8F2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1769E0), width: 1.5),
        ),
      ),
    );
  }
}
