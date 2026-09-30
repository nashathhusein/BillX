import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LicenseResult {
  final bool success;
  final String message;

  const LicenseResult({required this.success, required this.message});
}

class LicenseService {
  // Development server.
  // Commercial release-க்கு public HTTPS backend URL மாற்ற வேண்டும்.
  static const String backendBaseUrl = 'http://172.20.10.13:3000';

  static const String _licenseKey = 'billx_license_key';

  static Future<LicenseResult> activateLicense(String licenseKey) async {
    final cleanKey = licenseKey.trim();

    if (cleanKey.isEmpty) {
      return const LicenseResult(
        success: false,
        message: 'Please enter a license key.',
      );
    }

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        return const LicenseResult(
          success: false,
          message: 'Please login first.',
        );
      }

      final idToken = await user.getIdToken();

      if (idToken == null || idToken.isEmpty) {
        return const LicenseResult(
          success: false,
          message: 'Unable to verify your account.',
        );
      }

      final response = await http
          .post(
            Uri.parse('$backendBaseUrl/license/verify'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'licenseKey': cleanKey}),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('License HTTP status: ${response.statusCode}');

      debugPrint('License response: ${response.body}');

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {
        // Response was not valid JSON.
      }

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString(_licenseKey, cleanKey);

        return LicenseResult(
          success: true,
          message:
              data['message']?.toString() ?? 'License activated successfully.',
        );
      }

      return LicenseResult(
        success: false,
        message: data['message']?.toString() ?? 'License verification failed.',
      );
    } on http.ClientException catch (e) {
      debugPrint('License ClientException: $e');

      return const LicenseResult(
        success: false,
        message: 'Cannot connect to the license server.',
      );
    } catch (e) {
      debugPrint('License verification error: $e');

      return LicenseResult(
        success: false,
        message: 'License verification error: $e',
      );
    }
  }

  static Future<LicenseResult> verifyStoredLicense() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final savedKey = prefs.getString(_licenseKey);

      if (savedKey == null || savedKey.trim().isEmpty) {
        return const LicenseResult(
          success: false,
          message: 'No license found.',
        );
      }

      return await activateLicense(savedKey);
    } catch (e) {
      debugPrint('Stored license verification error: $e');

      return LicenseResult(
        success: false,
        message: 'Unable to check saved license: $e',
      );
    }
  }

  static Future<String?> getStoredLicense() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_licenseKey);
  }

  static Future<void> clearStoredLicense() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_licenseKey);
  }
}
