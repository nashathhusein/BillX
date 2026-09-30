import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../database/offline_database.dart';
import '../database/offline_sync_service.dart';

class BillsHistoryPage extends StatefulWidget {
  const BillsHistoryPage({super.key});

  @override
  State<BillsHistoryPage> createState() => _BillsHistoryPageState();
}

class _BillsHistoryPageState extends State<BillsHistoryPage> {
  bool loading = true;

  List<Map<String, dynamic>> bills = [];

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  // ------------------------------------------------------------
  // LOAD BILLS
  // ------------------------------------------------------------

  Future<void> _loadBills() async {
    if (!mounted) return;

    setState(() {
      loading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (!mounted) return;

        setState(() {
          bills = [];
          loading = false;
        });

        return;
      }

      final Map<String, Map<String, dynamic>> mergedBills = {};

      // --------------------------------------------------------
      // NATIVE: LOAD LOCAL DATABASE
      // --------------------------------------------------------

      if (!kIsWeb) {
        try {
          final localBills = await BillXLocalDatabase.getBills(user.uid);

          for (final bill in localBills) {
            final firebaseId = bill['firebaseId']?.toString();

            final localId = bill['id'] as int?;

            final key = firebaseId != null && firebaseId.isNotEmpty
                ? 'firebase_$firebaseId'
                : 'local_${localId ?? UniqueKey()}';

            mergedBills[key] = {
              ...bill,
              '_source': 'local',
              '_localId': localId,
            };
          }
        } catch (e) {
          debugPrint('Local bills loading error: $e');
        }
      }

      // --------------------------------------------------------
      // FIRESTORE
      // --------------------------------------------------------

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('bills')
            .where('userId', isEqualTo: user.uid)
            .get();

        for (final doc in snapshot.docs) {
          final data = doc.data();

          mergedBills['firebase_${doc.id}'] = {
            ...data,
            'firebaseId': doc.id,
            '_source': 'firebase',
          };
        }
      } catch (e) {
        debugPrint('Firestore bills loading error: $e');
      }

      final result = mergedBills.values.toList();

      result.sort((a, b) {
        final dateA = _getBillDate(a);

        final dateB = _getBillDate(b);

        return dateB.compareTo(dateA);
      });

      if (!mounted) return;

      setState(() {
        bills = result;
        loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Bills history error: $e');

      debugPrint('Bills history stack: $stackTrace');

      if (!mounted) return;

      setState(() {
        bills = [];
        loading = false;
      });

      _showMessage('Could not load bills history.');
    }
  }

  // ------------------------------------------------------------
  // DATE
  // ------------------------------------------------------------

  DateTime _getBillDate(Map<String, dynamic> bill) {
    final createdAt = bill['createdAt'];

    if (createdAt is Timestamp) {
      return createdAt.toDate();
    }

    final billDate = bill['billDate'];

    if (billDate is Timestamp) {
      return billDate.toDate();
    }

    if (createdAt is String) {
      return DateTime.tryParse(createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }

    if (billDate is String) {
      return DateTime.tryParse(billDate) ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ------------------------------------------------------------
  // TOTAL
  // ------------------------------------------------------------

  double _getTotal(Map<String, dynamic> bill) {
    final value = bill['total'] ?? bill['finalTotal'];

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  // ------------------------------------------------------------
  // ITEMS
  // ------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _getItems(
    Map<String, dynamic> bill,
  ) async {
    // Local bill
    if (bill['_source'] == 'local') {
      final localId = bill['_localId'];

      if (localId is int) {
        try {
          return await BillXLocalDatabase.getBillItems(localId);
        } catch (e) {
          debugPrint('Local bill items error: $e');
        }
      }
    }

    // Firestore bill
    final items = bill['items'];

    if (items is List) {
      return items
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return [];
  }

  // ------------------------------------------------------------
  // DELETE BILL
  // ------------------------------------------------------------

  Future<void> _deleteBill(Map<String, dynamic> bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Bill?'),
          content: const Text('Are you sure you want to delete this bill?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      // --------------------------------------------------------
      // DELETE LOCAL
      // --------------------------------------------------------

      if (bill['_source'] == 'local') {
        final localId = bill['_localId'];

        if (localId is int) {
          await BillXLocalDatabase.deleteBill(localId);
        }
      }

      // --------------------------------------------------------
      // DELETE FIRESTORE
      // --------------------------------------------------------

      final firebaseId = bill['firebaseId']?.toString();

      final user = FirebaseAuth.instance.currentUser;

      if (firebaseId != null && firebaseId.isNotEmpty && user != null) {
        await FirebaseFirestore.instance
            .collection('bills')
            .doc(firebaseId)
            .delete();
      }

      if (!mounted) return;

      _showMessage('Bill deleted successfully.', error: false);

      await _loadBills();
    } catch (e) {
      debugPrint('Delete bill error: $e');

      if (!mounted) return;

      _showMessage('Could not delete the bill.');
    }
  }

  // ------------------------------------------------------------
  // BILL DETAILS
  // ------------------------------------------------------------

  Future<void> _showBillDetails(Map<String, dynamic> bill) async {
    final items = await _getItems(bill);

    if (!mounted) return;

    final invoice = bill['invoiceNumber']?.toString() ?? 'Bill';

    final customer = bill['customerName']?.toString() ?? 'Walk-in Customer';

    final total = _getTotal(bill);

    final cash =
        double.tryParse(
          (bill['cash'] ?? bill['cashReceived'])?.toString() ?? '',
        ) ??
        0;

    final balance = double.tryParse((bill['balance'])?.toString() ?? '') ?? 0;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(invoice),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Customer: $customer',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 8),

                  Text('Date: ${_formatDate(_getBillDate(bill))}'),

                  const SizedBox(height: 20),

                  const Text(
                    'Items',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 10),

                  if (items.isEmpty) const Text('No item details available.'),

                  ...items.map((item) {
                    final name =
                        item['name'] ??
                        item['product'] ??
                        item['productName'] ??
                        'Product';

                    final quantity = item['quantity'] ?? 0;

                    final price =
                        double.tryParse(item['price']?.toString() ?? '') ?? 0;

                    final itemTotal =
                        double.tryParse(item['total']?.toString() ?? '') ??
                        quantity * price;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(child: Text('$name × $quantity')),
                          Text(
                            'Rs. ${itemTotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  }),

                  const Divider(),

                  _summaryRow('Total', total),

                  _summaryRow('Cash', cash),

                  _summaryRow(
                    balance >= 0 ? 'Balance' : 'Amount Due',
                    balance.abs(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _summaryRow(String title, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
            'Rs. ${value.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // FORMAT DATE
  // ------------------------------------------------------------

  String _formatDate(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) {
      return '-';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------
  // MESSAGE
  // ------------------------------------------------------------

  void _showMessage(String message, {bool error = true}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red : Colors.green,
        ),
      );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),

      appBar: AppBar(
        title: const Text(
          'Bills History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadBills,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : bills.isEmpty
          ? _emptyState()
          : RefreshIndicator(
              onRefresh: _loadBills,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: bills.length,
                itemBuilder: (context, index) {
                  return _billCard(bills[index]);
                },
              ),
            ),
    );
  }

  // ------------------------------------------------------------
  // EMPTY STATE
  // ------------------------------------------------------------

  Widget _emptyState() {
    return RefreshIndicator(
      onRefresh: _loadBills,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.30),
          const Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 15),
          const Center(
            child: Text(
              'No bills found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Saved bills will appear here.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // BILL CARD
  // ------------------------------------------------------------

  Widget _billCard(Map<String, dynamic> bill) {
    final invoice = bill['invoiceNumber']?.toString() ?? 'Bill';

    final customer = bill['customerName']?.toString() ?? 'Walk-in Customer';

    final total = _getTotal(bill);

    final date = _getBillDate(bill);

    final isLocal = bill['_source'] == 'local';

    final synced = bill['synced'] == 1 || !isLocal;

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade50,
          child: const Icon(Icons.receipt_long, color: Colors.blue),
        ),
        title: Text(
          invoice,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(customer, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              _formatDate(date),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (isLocal) ...[
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    synced ? Icons.cloud_done : Icons.cloud_upload,
                    size: 15,
                    color: synced ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    synced ? 'Synced' : 'Pending sync',
                    style: TextStyle(
                      fontSize: 12,
                      color: synced ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Rs. ${total.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              onSelected: (value) {
                if (value == 'view') {
                  _showBillDetails(bill);
                } else if (value == 'delete') {
                  _deleteBill(bill);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'view',
                  child: Row(
                    children: [
                      Icon(Icons.visibility_outlined),
                      SizedBox(width: 8),
                      Text('View'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete'),
                    ],
                  ),
                ),
              ],
              child: const Icon(Icons.more_vert),
            ),
          ],
        ),
        onTap: () {
          _showBillDetails(bill);
        },
      ),
    );
  }
}
