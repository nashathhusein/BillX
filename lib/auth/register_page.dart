import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/session_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _auth = FirebaseAuth.instance;

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _isValidGmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@gmail\.com$')
        .hasMatch(email.trim().toLowerCase());
  }

  bool _isValidPassword(String password) {
    if (password.length < 6) return false;

    final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);

    final hasLowercase = RegExp(r'[a-z]').hasMatch(password);

    final hasNumber = RegExp(r'[0-9]').hasMatch(password);

    return hasUppercase && hasLowercase && hasNumber;
  }

  void _showMessage(String message, {bool error = true}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red : Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim().toLowerCase();

    final password = _passwordController.text;

    final confirmPassword = _confirmPasswordController.text;

    if (email.isEmpty) {
      _showMessage('Please enter your Gmail address.');
      return;
    }

    if (!_isValidGmail(email)) {
      _showMessage('Please use a valid Gmail address ending with @gmail.com.');
      return;
    }

    if (password.isEmpty) {
      _showMessage('Please enter a password.');
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

    if (password != confirmPassword) {
      _showMessage('Passwords do not match.');
      return;
    }

    if (_loading) return;

    setState(() {
      _loading = true;
    });

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        _showMessage('Registration failed. Please try again.');
        return;
      }

      // Send Firebase email verification.
      await user.sendEmailVerification();

      // We don't keep a login session before
      // the user verifies the email.
      await SessionService.clearSession(user);

      if (!mounted) return;

      _showMessage(
        'Account created successfully. '
        'Please check your Gmail and verify your email.',
        error: false,
      );

      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      debugPrint('Register Firebase error code: ${e.code}');

      debugPrint('Register Firebase message: ${e.message}');

      String message;

      switch (e.code) {
        case 'email-already-in-use':
          message = 'This Gmail address is already registered.';
          break;

        case 'invalid-email':
          message = 'Please enter a valid Gmail address.';
          break;

        case 'weak-password':
          message = 'Password is too weak. Use at least 6 characters with uppercase, lowercase and number.';
          break;

        case 'operation-not-allowed':
          message = 'Email/password registration is not enabled in Firebase.';
          break;

        case 'network-request-failed':
          message = 'Network error. Please check your internet connection.';
          break;

        case 'too-many-requests':
          message = 'Too many requests. Please try again later.';
          break;

        default:
          message = e.message == null || e.message!.isEmpty
              ? 'Registration failed. Firebase error: ${e.code}'
              : 'Registration failed: ${e.message}';
      }

      _showMessage(message);
    } catch (e, stackTrace) {
      debugPrint('REGISTER ERROR: $e');

      debugPrint('REGISTER STACK TRACE: $stackTrace');

      _showMessage('Registration error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text('Create Account'), centerTitle: true),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.person_add_alt_1,
                        size: 64,
                        color: Colors.blue,
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'Create your BillX account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 28),

                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Gmail',
                          hintText: 'example@gmail.com',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 16),

                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      const Text(
                        'Password must have at least 6 characters, '
                        'uppercase, lowercase and number.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),

                      const SizedBox(height: 16),

                      TextField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _register(),
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          prefixIcon: const Icon(Icons.lock_reset),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                              });
                            },
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _register,
                          child: _loading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'CREATE ACCOUNT',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'After registration, check your Gmail '
                        'and verify your email before logging in.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
