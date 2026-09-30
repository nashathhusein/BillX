import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'offline_database.dart';

class OfflineSyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // ------------------------------------------------------------
  // SYNC ALL
  // ------------------------------------------------------------

  static Future<void> syncAll() async {
    if (kIsWeb) return;

    final user = _auth.currentUser;

    if (user == null) return;

    try {
      await syncProducts();
      await syncBills();
    } catch (e) {
      print('Offline sync error: $e');
    }
  }

  // ------------------------------------------------------------
  // SYNC PRODUCTS
  // ------------------------------------------------------------

  static Future<void> syncProducts() async {
    if (kIsWeb) return;

    final user = _auth.currentUser;

    if (user == null) return;

    final products = await BillXLocalDatabase.getUnsyncedProducts();

    for (final product in products) {
      try {
        final productId = product['productId']?.toString();

        final barcode = product['barcode']?.toString() ?? '';

        final name = product['name']?.toString() ?? '';

        final price = (product['price'] as num?)?.toDouble() ?? 0;

        final stock = (product['stock'] as num?)?.toDouble() ?? 0;

        DocumentReference<Map<String, dynamic>> ref;

        if (productId != null && productId.isNotEmpty) {
          ref = _firestore
              .collection('users')
              .doc(user.uid)
              .collection('products')
              .doc(productId);
        } else {
          ref = _firestore
              .collection('users')
              .doc(user.uid)
              .collection('products')
              .doc();
        }

        await ref.set({
          'productId': ref.id,
          'barcode': barcode,
          'name': name,
          'price': price,
          'stock': stock,
          'userId': user.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await BillXLocalDatabase.markProductSynced(product['id'] as int);
      } catch (e) {
        print('Product sync failed: $e');
      }
    }
  }

  // ------------------------------------------------------------
  // SYNC BILLS
  // ------------------------------------------------------------

  static Future<void> syncBills() async {
    if (kIsWeb) return;

    final user = _auth.currentUser;

    if (user == null) return;

    final bills = await BillXLocalDatabase.getUnsyncedBills();

    for (final bill in bills) {
      try {
        final localId = bill['id'] as int;

        final items = await BillXLocalDatabase.getBillItems(localId);

        final billData = {
          'userId': user.uid,
          'invoiceNumber': bill['invoiceNumber'],
          'total': (bill['total'] as num?)?.toDouble() ?? 0,
          'cash': (bill['cash'] as num?)?.toDouble() ?? 0,
          'balance': (bill['balance'] as num?)?.toDouble() ?? 0,
          'createdAt': _timestampFromString(bill['createdAt']?.toString()),
          'items': items.map((item) {
            return {
              'productId': item['productId'],
              'barcode': item['barcode'],
              'name': item['name'],
              'price': (item['price'] as num?)?.toDouble() ?? 0,
              'quantity': (item['quantity'] as num?)?.toDouble() ?? 0,
              'total': (item['total'] as num?)?.toDouble() ?? 0,
            };
          }).toList(),
          'syncedAt': FieldValue.serverTimestamp(),
        };

        final firebaseId = bill['firebaseId']?.toString();

        DocumentReference<Map<String, dynamic>> ref;

        if (firebaseId != null && firebaseId.isNotEmpty) {
          ref = _firestore
              .collection('users')
              .doc(user.uid)
              .collection('bills')
              .doc(firebaseId);
        } else {
          ref = _firestore
              .collection('users')
              .doc(user.uid)
              .collection('bills')
              .doc();
        }

        await ref.set(billData, SetOptions(merge: true));

        await BillXLocalDatabase.markBillSynced(localId, firebaseId: ref.id);
      } catch (e) {
        print('Bill sync failed: $e');
      }
    }
  }

  // ------------------------------------------------------------
  // TIMESTAMP HELPER
  // ------------------------------------------------------------

  static dynamic _timestampFromString(String? value) {
    if (value == null || value.isEmpty) {
      return FieldValue.serverTimestamp();
    }

    try {
      final dateTime = DateTime.parse(value);

      return Timestamp.fromDate(dateTime);
    } catch (_) {
      return FieldValue.serverTimestamp();
    }
  }
}
