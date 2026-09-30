import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class OwnerLicensePage extends StatefulWidget {
  const OwnerLicensePage({super.key});

  @override
  State<OwnerLicensePage> createState() => _OwnerLicensePageState();
}

class _OwnerLicensePageState extends State<OwnerLicensePage> {
  static const String backendBaseUrl = 'http://localhost:3000';

  final TextEditingController customerEmailController = TextEditingController();

  final TextEditingController daysController = TextEditingController(
    text: '365',
  );

  bool _loading = false;

  String generatedLicense = '';

  @override
  void dispose() {
    customerEmailController.dispose();
    daysController.dispose();
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

  Future<String?> _getFirebaseToken() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('Please login first.');
      return null;
    }

    try {
      final token = await user.getIdToken();

      if (token == null || token.isEmpty) {
        _showMessage('Unable to verify your account.');
        return null;
      }

      return token;
    } catch (e) {
      debugPrint('Firebase token error: $e');

      _showMessage('Unable to verify your account.');

      return null;
    }
  }

  Future<void> _createLicense() async {
    FocusScope.of(context).unfocus();

    if (_loading) return;

    final customerEmail = customerEmailController.text.trim().toLowerCase();

    final days = int.tryParse(daysController.text.trim()) ?? 365;

    if (customerEmail.isEmpty) {
      _showMessage('Please enter customer Gmail.');
      return;
    }

    if (!customerEmail.contains('@gmail.com')) {
      _showMessage('Please enter a valid Gmail address.');
      return;
    }

    if (days <= 0) {
      _showMessage('License days must be greater than 0.');
      return;
    }

    if (days > 3650) {
      _showMessage('Maximum license period is 3650 days.');
      return;
    }

    setState(() {
      _loading = true;
      generatedLicense = '';
    });

    try {
      final token = await _getFirebaseToken();

      if (token == null) return;

      final response = await http
          .post(
            Uri.parse('$backendBaseUrl/admin/license/create'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'email': customerEmail, 'days': days}),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('Create license status: ${response.statusCode}');

      debugPrint('Create license response: ${response.body}');

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (e) {
        debugPrint('Invalid JSON response: $e');
      }

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        final key = data['licenseKey']?.toString() ?? '';

        if (key.isEmpty) {
          _showMessage('License was created but no key was returned.');
          return;
        }

        await Clipboard.setData(ClipboardData(text: key));

        if (!mounted) return;

        setState(() {
          generatedLicense = key;
        });

        _showMessage('License created successfully. Key copied.', error: false);

        customerEmailController.clear();
      } else {
        _showMessage(
          data['message']?.toString() ?? 'Could not create license.',
        );
      }
    } on http.ClientException catch (e) {
      debugPrint('License ClientException: $e');

      _showMessage('Cannot connect to BillX server.');
    } catch (e) {
      debugPrint('Create license error: $e');

      _showMessage('License creation failed.');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _copyLicense() async {
    if (generatedLicense.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: generatedLicense));

    _showMessage('License key copied.', error: false);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 850;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      body: SafeArea(
        child: Row(
          children: [
            if (desktop)
              Container(
                width: 245,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0B2A52), Color(0xFF123F78)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 28),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 22),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 23,
                            backgroundColor: Colors.white,
                            child: Icon(
                              Icons.receipt_long_rounded,
                              color: Color(0xFF1769E0),
                              size: 27,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'BillX',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 35),
                    _sideItem(Icons.dashboard_rounded, 'Dashboard', false),
                    _sideItem(
                      Icons.vpn_key_rounded,
                      'License Management',
                      true,
                    ),
                    _sideItem(Icons.people_alt_rounded, 'Users', false),
                    _sideItem(Icons.business_rounded, 'Businesses', false),
                    _sideItem(Icons.bar_chart_rounded, 'Reports', false),
                    _sideItem(Icons.settings_rounded, 'Settings', false),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Color(0xFF1769E0),
                              child: Text(
                                'A',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                user?.email ?? 'Admin',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(desktop ? 28 : 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (!desktop)
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Admin Dashboard',
                                    style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF14213D),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Manage BillX customer licenses',
                                    style: TextStyle(
                                      color: Color(0xFF718096),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircleAvatar(
                                    radius: 17,
                                    backgroundColor: Color(0xFF1769E0),
                                    child: Icon(
                                      Icons.person,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                  if (width >= 600) ...[
                                    const SizedBox(width: 9),
                                    Text(
                                      user?.email ?? 'Admin',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 25),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final count = constraints.maxWidth >= 900
                                ? 4
                                : constraints.maxWidth >= 600
                                ? 2
                                : 1;
                            final cardWidth =
                                (constraints.maxWidth - ((count - 1) * 14)) /
                                count;
                            return Wrap(
                              spacing: 14,
                              runSpacing: 14,
                              children: [
                                _statCard(
                                  width: cardWidth,
                                  icon: Icons.vpn_key_rounded,
                                  value: generatedLicense.isEmpty
                                      ? 'Ready'
                                      : 'Created',
                                  label: 'License Manager',
                                  iconColor: const Color(0xFF1769E0),
                                ),
                                _statCard(
                                  width: cardWidth,
                                  icon: Icons.verified_rounded,
                                  value: 'Active',
                                  label: 'License System',
                                  iconColor: const Color(0xFF10A36A),
                                ),
                                _statCard(
                                  width: cardWidth,
                                  icon: Icons.security_rounded,
                                  value: 'Admin',
                                  label: 'Access Level',
                                  iconColor: const Color(0xFF7C3AED),
                                ),
                                _statCard(
                                  width: cardWidth,
                                  icon: Icons.cloud_done_rounded,
                                  value: 'Online',
                                  label: 'Backend Status',
                                  iconColor: const Color(0xFFF59E0B),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 760;
                            final form = _licenseForm();
                            final info = _generateInfoCard();
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x12000000),
                                    blurRadius: 24,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: wide
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: form),
                                        const SizedBox(width: 28),
                                        SizedBox(width: 300, child: info),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        form,
                                        const SizedBox(height: 20),
                                        info,
                                      ],
                                    ),
                            );
                          },
                        ),
                        if (generatedLicense.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _generatedLicenseCard(),
                        ],
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF3FF),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFD4E7FF)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: Color(0xFF1769E0),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Enter the customer Gmail and license period. '
                                  'BillX will generate a unique license key. '
                                  'Copy the key and give it to the customer for activation.',
                                  style: TextStyle(
                                    color: Color(0xFF38506E),
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideItem(IconData icon, String title, bool selected) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF1769E0) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 21),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required double width,
    required IconData icon,
    required String value,
    required String label,
    required Color iconColor,
  }) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE7ECF3)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 15,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF718096),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _licenseForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.key_rounded, color: Color(0xFF1769E0), size: 27),
            SizedBox(width: 10),
            Text(
              'Create New License Key',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 7),
        const Text(
          'Generate a license for a BillX customer account.',
          style: TextStyle(color: Color(0xFF718096)),
        ),
        const SizedBox(height: 22),
        _modernField(
          controller: customerEmailController,
          label: 'Customer Gmail',
          hint: 'customer@gmail.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _modernField(
          controller: daysController,
          label: 'License Period',
          hint: '365',
          icon: Icons.calendar_month_outlined,
          keyboardType: TextInputType.number,
          suffix: const Text('days'),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _createLicense,
            icon: _loading
                ? const SizedBox(
                    width: 21,
                    height: 21,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.vpn_key_outlined),
            label: Text(
              _loading ? 'CREATING LICENSE...' : 'GENERATE LICENSE KEY',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1769E0),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _modernField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF718096)),
        suffix: suffix,
        filled: true,
        fillColor: const Color(0xFFF8FAFD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFF1769E0), width: 1.5),
        ),
      ),
    );
  }

  Widget _generateInfoCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: Colors.white,
            child: Icon(Icons.key_rounded, size: 34, color: Color(0xFF1769E0)),
          ),
          SizedBox(height: 16),
          Text(
            'Generate New License',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 8),
          Text(
            'Create a unique BillX license key for your customer and activate their account.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF5E7189),
              height: 1.45,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _generatedLicenseCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFEAFBF3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBCEBD4)),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF10A36A)),
              SizedBox(width: 9),
              Text(
                'License Created Successfully',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF9AD9BB)),
            ),
            child: SelectableText(
              generatedLicense,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: Color(0xFF123B2A),
              ),
            ),
          ),
          const SizedBox(height: 13),
          OutlinedButton.icon(
            onPressed: _copyLicense,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('COPY LICENSE KEY'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF10A36A),
              side: const BorderSide(color: Color(0xFF10A36A)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
