import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'offline_database.dart';

class BillXSyncService {
  static StreamSubscription<dynamic>? _connectivitySubscription;
  static bool _syncing = false;
  static bool _started = false;

  static Future<void> start() async {
    if (_started) {
      await syncNow();
      return;
    }

    _started = true;

    // Try once when the app/home page starts.
    await syncNow();

    // Try again whenever the device gets a network connection.
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((_) async {
      await syncNow();
    });
  }

  static Future<void> syncNow() async {
    if (_syncing) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _syncing = true;

    try {
      await _syncProducts(user.uid);
      await _syncBills(user.uid);
    } catch (e) {
      // Keep local data. The next connectivity event/startup will retry.
      print('BillX sync error: $e');
    } finally {
      _syncing = false;
    }
  }

  static Future<void> _syncProducts(String userId) async {
    final products = await BillXLocalDatabase.getUnsyncedProducts();

    for (final product in products) {
      final barcode = product['barcode']?.toString().trim() ?? '';
      final productName = product['productName']?.toString().trim() ?? '';
      final rawPrice = product['price'];
      final price = rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse(rawPrice?.toString() ?? '');

      if (barcode.isEmpty || productName.isEmpty || price == null) continue;

      try {
        await FirebaseFirestore.instance
            .collection('products')
            .doc(barcode)
            .set({
          'barcode': barcode,
          'productName': productName,
          'price': price,
          'updatedAt': FieldValue.serverTimestamp(),
          'userId': userId,
        }, SetOptions(merge: true));

        final localId = product['id'];
        if (localId is int) {
          await BillXLocalDatabase.markProductSynced(localId);
        }
      } catch (e) {
        print('Product sync failed for $barcode: $e');
        // Stop this batch when Firebase is unavailable.
        break;
      }
    }
  }

  static Future<void> _syncBills(String userId) async {
    final bills = await BillXLocalDatabase.getUnsyncedBills();

    for (final bill in bills) {
      final localId = bill['id'];
      if (localId is! int) continue;

      try {
        final items = await BillXLocalDatabase.getBillItems(localId);

        final invoiceNumber = bill['invoiceNumber']?.toString() ?? '';
        final customerName = bill['customerName']?.toString() ?? '';
        final billDate = bill['billDate']?.toString() ?? '';
        final createdAt = bill['createdAt']?.toString() ?? '';

        final docId = 'offline_${userId}_$localId';

        await FirebaseFirestore.instance.collection('bills').doc(docId).set({
          'userId': userId,
          'invoiceNumber': invoiceNumber,
          'customerName': customerName,
          'billDate': _timestampOrNull(billDate),
          'createdAt': _timestampOrNull(createdAt),
          'items': items
              .map(
                (item) => {
                  'product': item['product']?.toString() ?? '',
                  'quantity': (item['quantity'] as num?)?.toInt() ?? 0,
                  'price': (item['price'] as num?)?.toDouble() ?? 0,
                  'total': (item['total'] as num?)?.toDouble() ?? 0,
                },
              )
              .toList(),
          'subTotal': (bill['subTotal'] as num?)?.toDouble() ?? 0,
          'discount': (bill['discount'] as num?)?.toDouble() ?? 0,
          'finalTotal': (bill['finalTotal'] as num?)?.toDouble() ?? 0,
          'cashReceived': (bill['cashReceived'] as num?)?.toDouble() ?? 0,
          'balance': (bill['balance'] as num?)?.toDouble() ?? 0,
          'syncedFromDevice': true,
        }, SetOptions(merge: true));

        await BillXLocalDatabase.markBillSynced(
          localId,
          firebaseId: docId,
        );
      } catch (e) {
        print('Bill sync failed for local bill $localId: $e');
        break;
      }
    }
  }

  static Timestamp? _timestampOrNull(String value) {
    if (value.isEmpty) return null;

    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;

    return Timestamp.fromDate(parsed);
  }

  static Future<void> stop() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _started = false;
  }
}
