import 'package:flutter/material.dart';

import 'license_service.dart';

class LicensePage extends StatefulWidget {
  final VoidCallback? onActivated;

  const LicensePage({super.key, this.onActivated});

  @override
  State<LicensePage> createState() => _LicensePageState();
}

class _LicensePageState extends State<LicensePage> {
  final _licenseController = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

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

  Future<void> _activateLicense() async {
    FocusScope.of(context).unfocus();

    final licenseKey = _licenseController.text.trim();

    if (licenseKey.isEmpty) {
      _showMessage('Please enter your license key.');
      return;
    }

    if (_loading) return;

    setState(() {
      _loading = true;
    });

    try {
      final result = await LicenseService.activateLicense(licenseKey);

      if (!mounted) return;

      if (result.success) {
        _showMessage(result.message, error: false);

        widget.onActivated?.call();
      } else {
        _showMessage(result.message);
      }
    } catch (e) {
      debugPrint('License activation error: $e');

      if (!mounted) return;

      _showMessage('License activation failed.');
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
                        Icons.verified_user_outlined,
                        size: 70,
                        color: Colors.blue,
                      ),

                      const SizedBox(height: 20),

                      const Text(
                        'Activate BillX',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 10),

                      const Text(
                        'Enter your BillX license key to continue.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 15),
                      ),

                      const SizedBox(height: 30),

                      TextField(
                        controller: _licenseController,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _activateLicense(),
                        decoration: const InputDecoration(
                          labelText: 'License Key',
                          hintText: 'XXXX-XXXX-XXXX-XXXX',
                          prefixIcon: Icon(Icons.key_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 24),

                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _activateLicense,
                          child: _loading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'ACTIVATE LICENSE',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      const Text(
                        'A valid license is required to use BillX.',
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
