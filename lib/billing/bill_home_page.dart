import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:whatsapp_share_plus/whatsapp_share_plus.dart';

import '../products/barcode_scanner.dart';

import 'package:billx/history/bills_history_page.dart';

import '../database/offline_database.dart';
import '../database/offline_sync_service.dart';
import '../auth/login_page.dart';
import '../license/owner_license_page.dart';

class BillHomePage extends StatefulWidget {
  const BillHomePage({super.key});

  @override
  State<BillHomePage> createState() => _BillHomePageState();
}

class _BillHomePageState extends State<BillHomePage> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      OfflineSyncService.syncAll();
    }
  }

  // =========================
  // CONTROLLERS
  // =========================

  final TextEditingController customerController = TextEditingController();
  final TextEditingController customerPhoneController = TextEditingController();

  final TextEditingController invoiceController = TextEditingController(
    text: 'INV-001',
  );

  final TextEditingController productController = TextEditingController();

  final TextEditingController quantityController = TextEditingController(
    text: '1',
  );

  final TextEditingController priceController = TextEditingController();

  // USB barcode scanner input (works like a keyboard on Windows PC)
  final TextEditingController barcodeInputController = TextEditingController();
  final FocusNode barcodeFocusNode = FocusNode();

  final TextEditingController discountController = TextEditingController(
    text: '0',
  );

  final TextEditingController cashController = TextEditingController(text: '0');

  // =========================
  // BILL ITEMS
  // =========================

  final List<Map<String, dynamic>> items = [];

  DateTime billDate = DateTime.now();

  // =========================
  // SUB TOTAL
  // =========================

  double get subTotal {
    double total = 0.0;

    for (final item in items) {
      final int quantity = (item['quantity'] as num?)?.toInt() ?? 0;

      final double price = (item['price'] as num?)?.toDouble() ?? 0.0;

      total += quantity * price;
    }

    return total;
  }

  // =========================
  // DISCOUNT
  // =========================

  double get discount {
    final value = double.tryParse(discountController.text.trim());

    if (value == null || value < 0) {
      return 0.0;
    }

    return value;
  }

  // =========================
  // FINAL TOTAL
  // =========================

  double get finalTotal {
    final total = subTotal - discount;

    if (total < 0) {
      return 0.0;
    }

    return total;
  }

  // =========================
  // CASH RECEIVED
  // =========================

  double get cashReceived {
    final value = double.tryParse(cashController.text.trim());

    if (value == null || value < 0) {
      return 0.0;
    }

    return value;
  }

  // =========================
  // BALANCE
  // =========================

  double get balance {
    return cashReceived - finalTotal;
  }

  // =========================
  // BARCODE SCANNER + PRODUCT LOOKUP
  // =========================

  Future<void> lookupBarcode(String barcode) async {
    final code = barcode.trim();

    if (code.isEmpty) return;

    // Remove the scanned code from the input box immediately.
    barcodeInputController.clear();

    // =====================================================
    // STEP 1: LOCAL DATABASE FIRST (native only)
    // =====================================================
    if (!kIsWeb) {
      try {
        final localProduct = await BillXLocalDatabase.getProduct(code);

        if (localProduct != null) {
          final productName = localProduct['name']?.toString().trim() ?? '';

          final productPrice = (localProduct['price'] as num?)?.toDouble();

          if (productName.isNotEmpty &&
              productPrice != null &&
              productPrice > 0) {
            if (!mounted) return;

            setState(() {
              productController.text = productName;
              priceController.text = productPrice.toStringAsFixed(2);
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Offline product found: $productName • '
                  'Rs. ${productPrice.toStringAsFixed(2)}',
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );

            barcodeFocusNode.requestFocus();
            return;
          }
        }
      } catch (e) {
        debugPrint('Local product lookup error: $e');
      }
    }

    // =====================================================
    // STEP 2: LOCAL NOT FOUND -> FIREBASE
    // =====================================================
    try {
      final productDoc = await FirebaseFirestore.instance
          .collection('products')
          .doc(code)
          .get();

      if (!mounted) return;

      if (productDoc.exists) {
        final data = productDoc.data() ?? {};
        final productName = data['productName']?.toString().trim() ?? '';
        final rawPrice = data['price'];

        final productPrice = rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice?.toString() ?? '');

        if (productName.isNotEmpty &&
            productPrice != null &&
            productPrice > 0) {
          // Cache Firebase product locally for future offline use
          // on native platforms only. Web uses Firestore directly.
          if (!kIsWeb) {
            try {
              await BillXLocalDatabase.saveProduct(
                barcode: code,
                name: productName,
                price: productPrice,
              );
            } catch (e) {
              debugPrint('Could not cache Firebase product locally: $e');
            }
          }

          if (!mounted) return;

          setState(() {
            productController.text = productName;
            priceController.text = productPrice.toStringAsFixed(2);
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Online product found: $productName • '
                'Rs. ${productPrice.toStringAsFixed(2)}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );

          barcodeFocusNode.requestFocus();
          return;
        }
      }

      // Product does not exist online or locally.
      await _addNewBarcodeProduct(code);

      if (mounted) {
        barcodeFocusNode.requestFocus();
      }
    } catch (e) {
      // Firebase failed (for example, no internet).
      // We can still create and save the product locally.
      debugPrint('Firebase product lookup failed: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Product was not found online. You can save it offline.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );

      await _addNewBarcodeProduct(code);

      if (mounted) {
        barcodeFocusNode.requestFocus();
      }
    }
  }

  // Camera scanner for supported mobile/web platforms.
  Future<void> scanBarcode() async {
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );

    if (!mounted || barcode == null || barcode.trim().isEmpty) return;

    await lookupBarcode(barcode);
  }

  Future<void> _addNewBarcodeProduct(String barcode) async {
    final nameController = TextEditingController();
    final newPriceController = TextEditingController();

    try {
      final result = await showDialog<Map<String, String>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('New Product'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Barcode: $barcode',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Product Name',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPriceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Selling Price (Rs.)',
                      prefixIcon: Icon(Icons.currency_exchange),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final name = nameController.text.trim();
                  final price = newPriceController.text.trim();
                  final parsedPrice = double.tryParse(price);

                  if (name.isEmpty || parsedPrice == null || parsedPrice <= 0) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Enter a product name and a valid price.',
                        ),
                      ),
                    );
                    return;
                  }

                  Navigator.pop(dialogContext, {
                    'name': name,
                    'price': parsedPrice.toString(),
                  });
                },
                icon: const Icon(Icons.save),
                label: const Text('Save Product'),
              ),
            ],
          );
        },
      );

      if (!mounted || result == null) return;

      final name = result['name']!;
      final price = double.parse(result['price']!);
      final user = FirebaseAuth.instance.currentUser;

      bool savedOnline = false;
      bool savedLocal = false;

      // =====================================================
      // SAVE LOCAL FIRST (native only)
      // =====================================================
      if (!kIsWeb) {
        try {
          await BillXLocalDatabase.saveProduct(
            barcode: barcode,
            name: name,
            price: price,
          );
          savedLocal = true;
        } catch (e) {
          debugPrint('Local product save failed: $e');
        }
      }

      // =====================================================
      // TRY FIREBASE
      // =====================================================
      if (user != null) {
        try {
          await FirebaseFirestore.instance
              .collection('products')
              .doc(barcode)
              .set({
                'barcode': barcode,
                'productName': name,
                'price': price,
                'updatedAt': FieldValue.serverTimestamp(),
                'userId': user.uid,
              });

          savedOnline = true;
        } catch (e) {
          debugPrint('Firebase product save failed: $e');
        }
      }

      if (!savedLocal && !savedOnline) {
        throw Exception('Product could not be saved.');
      }

      if (!mounted) return;

      setState(() {
        productController.text = name;
        priceController.text = price.toStringAsFixed(2);
      });

      final message = savedOnline
          ? (kIsWeb
                ? 'Product saved successfully.'
                : 'Product saved online and offline.')
          : 'Product saved offline. It will sync when internet is available.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: savedOnline ? Colors.green : Colors.orange,
        ),
      );
    } finally {
      nameController.dispose();
      newPriceController.dispose();
    }
  }

  // =========================
  // ADD ITEM
  // =========================

  Future<void> addItem() async {
    final product = productController.text.trim();

    final quantity = int.tryParse(quantityController.text.trim()) ?? 0;

    final price = double.tryParse(priceController.text.trim()) ?? 0.0;

    if (product.isEmpty || quantity <= 0 || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter product, quantity and price'),
        ),
      );

      return;
    }

    // =====================================================
    // SAVE MANUALLY TYPED PRODUCT TO FIRESTORE
    // =====================================================
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        final productId = 'manual_${const Uuid().v4()}';

        await FirebaseFirestore.instance
            .collection('products')
            .doc(productId)
            .set({
              'productId': productId,
              'barcode': '',
              'productName': product,
              'price': price,
              'userId': user.uid,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
              'source': 'manual',
            });
      } catch (e) {
        debugPrint('Manual product Firestore save failed: $e');
      }
    }

    final itemTotal = quantity * price;

    setState(() {
      items.add({
        'product': product,
        'quantity': quantity,
        'price': price,
        'total': itemTotal,
      });
    });

    productController.clear();
    quantityController.text = '1';
    priceController.clear();

    // Ready for the next USB barcode scan.
    barcodeFocusNode.requestFocus();
  }

  // =========================
  // REMOVE ITEM
  // =========================

  void removeItem(int index) {
    setState(() {
      items.removeAt(index);
    });
  }

  // =========================
  // CLEAR BILL
  // =========================

  void clearBill() {
    setState(() {
      items.clear();

      customerController.clear();
      customerPhoneController.clear();

      invoiceController.text = 'INV-001';

      productController.clear();

      quantityController.text = '1';

      priceController.clear();

      barcodeInputController.clear();

      discountController.text = '0';

      cashController.text = '0';

      billDate = DateTime.now();
    });
  }

  // =========================
  // DATE
  // =========================

  String formattedDate() {
    return '${billDate.day.toString().padLeft(2, '0')}/'
        '${billDate.month.toString().padLeft(2, '0')}/'
        '${billDate.year}';
  }

  // =========================
  // SAVE BILL TO FIRESTORE
  // =========================

  Future<void> saveBillToHistory() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('User is not logged in');
    }

    final billItems = items.map((item) {
      return {
        'product': item['product'].toString(),
        'quantity': (item['quantity'] as num).toInt(),
        'price': (item['price'] as num).toDouble(),
        'total': (item['total'] as num).toDouble(),
      };
    }).toList();

    if (kIsWeb) {
      // Flutter Web: save directly to Firestore.
      // SQLite/sqflite_common_ffi is not used on Web.
      await FirebaseFirestore.instance.collection('bills').add({
        'userId': user.uid,
        'invoiceNumber': invoiceController.text.trim(),
        'customerName': customerController.text.trim(),
        'billDate': Timestamp.fromDate(billDate),
        'createdAt': FieldValue.serverTimestamp(),
        'items': billItems,
        'subTotal': subTotal,
        'discount': discount,
        'finalTotal': finalTotal,
        'cashReceived': cashReceived,
        'balance': balance,
      });
      return;
    }

    // Native platforms: save locally first for offline support.
    await BillXLocalDatabase.saveBill(
      userId: user.uid,
      invoiceNumber: invoiceController.text.trim(),
      total: finalTotal,
      cash: cashReceived,
      balance: balance,
      items: billItems,
    );

    // Then try an immediate Firebase sync.
    await OfflineSyncService.syncAll();
  }

  // =========================
  // GENERATE PDF
  // =========================

  Future<void> generateBill() async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one product')),
      );
      return;
    }

    if (cashReceived < finalTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cash received is less than the bill total'),
        ),
      );
      return;
    }

    try {
      // Save the bill first. PDF is NOT created automatically.
      await saveBillToHistory();

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.blue),
                const SizedBox(width: 10),
                const Expanded(child: Text('Bill Preview')),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invoice: ${invoiceController.text}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('Date: ${formattedDate()}'),
                    if (customerController.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Customer: ${customerController.text.trim()}'),
                    ],
                    if (customerPhoneController.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('WhatsApp: ${customerPhoneController.text.trim()}'),
                    ],
                    const SizedBox(height: 16),
                    const Divider(),

                    const Text(
                      'Products',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),

                    ...items.map((item) {
                      final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
                      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                      final total =
                          (item['total'] as num?)?.toDouble() ??
                          quantity * price;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item['product'].toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text('$quantity × Rs. ${price.toStringAsFixed(2)}'),
                            const SizedBox(width: 12),
                            Text(
                              'Rs. ${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    const Divider(height: 24),

                    _billPreviewRow(
                      'Sub Total',
                      'Rs. ${subTotal.toStringAsFixed(2)}',
                    ),
                    const SizedBox(height: 6),
                    _billPreviewRow(
                      'Discount',
                      'Rs. ${discount.toStringAsFixed(2)}',
                    ),
                    const SizedBox(height: 8),
                    _billPreviewRow(
                      'Final Total',
                      'Rs. ${finalTotal.toStringAsFixed(2)}',
                      bold: true,
                      fontSize: 18,
                    ),
                    const SizedBox(height: 6),
                    _billPreviewRow(
                      'Cash Received',
                      'Rs. ${cashReceived.toStringAsFixed(2)}',
                    ),
                    const SizedBox(height: 6),
                    _billPreviewRow(
                      balance >= 0 ? 'Balance' : 'Amount Due',
                      'Rs. ${balance.abs().toStringAsFixed(2)}',
                      bold: true,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                icon: const Icon(Icons.close),
                label: const Text('Close'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  shareBillOnWhatsApp();
                },
                icon: const Icon(Icons.chat, color: Colors.green),
                label: const Text('WhatsApp'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  generatePdf();
                },
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Download PDF'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save bill: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _billPreviewRow(
    String label,
    String value, {
    bool bold = false,
    double fontSize = 15,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Future<Uint8List> _createPdfBytes() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'BillX',
                  style: pw.TextStyle(
                    fontSize: 30,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue,
                  ),
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Center(
                child: pw.Text(
                  'SALES INVOICE',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 25),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Invoice No:',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(invoiceController.text),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'Date:',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(formattedDate()),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Customer:',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        customerController.text.isEmpty
                            ? 'Walk-in Customer'
                            : customerController.text,
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 25),
              pw.TableHelper.fromTextArray(
                headers: ['Product', 'Qty', 'Price', 'Total'],
                data: items.map((item) {
                  final quantity = (item['quantity'] as num).toInt();
                  final price = (item['price'] as num).toDouble();
                  final total = quantity * price;
                  return [
                    item['product'].toString(),
                    quantity.toString(),
                    'Rs. ${price.toStringAsFixed(2)}',
                    'Rs. ${total.toStringAsFixed(2)}',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue),
                cellPadding: const pw.EdgeInsets.all(8),
                border: pw.TableBorder.all(color: PdfColors.grey),
              ),
              pw.SizedBox(height: 25),
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Sub Total: Rs. ${subTotal.toStringAsFixed(2)}'),
                    pw.SizedBox(height: 6),
                    pw.Text('Discount: Rs. ${discount.toStringAsFixed(2)}'),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Grand Total: Rs. ${finalTotal.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Cash Received: Rs. ${cashReceived.toStringAsFixed(2)}',
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Balance: Rs. ${balance.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Divider(),
              pw.Center(child: pw.Text('Thank you for your business!')),
              pw.SizedBox(height: 5),
              pw.Center(
                child: pw.Text(
                  'Generated by BillX',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<void> shareBillOnWhatsApp() async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one product')),
      );
      return;
    }

    if (cashReceived < finalTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cash received is less than the bill total'),
        ),
      );
      return;
    }

    final phone = customerPhoneController.text.trim();

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the customer WhatsApp number'),
        ),
      );
      return;
    }

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WhatsApp PDF sharing is available on the mobile app.'),
        ),
      );
      return;
    }

    try {
      final pdfBytes = await _createPdfBytes();

      await WhatsAppShare.share(
        phone: phone,
        text:
            'Hello ${customerController.text.trim().isEmpty ? '' : customerController.text.trim() + ', '}your BillX invoice ${invoiceController.text.trim()} is ready. Total: Rs. ${finalTotal.toStringAsFixed(2)}.',
        files: [
          ShareFile.fromBytes(
            pdfBytes,
            name: 'BillX_${invoiceController.text.trim()}.pdf',
            mimeType: 'application/pdf',
          ),
        ],
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share bill on WhatsApp: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> generatePdf() async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one product')),
      );
      return;
    }

    if (cashReceived < finalTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cash received is less than the bill total'),
        ),
      );
      return;
    }

    try {
      final pdfBytes = await _createPdfBytes();

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'BillX_${invoiceController.text}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // =========================
  // LOGOUT
  // =========================

  Future<void> logout() async {
    try {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  // =========================
  // DISPOSE
  // =========================

  @override
  void dispose() {
    if (!kIsWeb) {}
    customerController.dispose();
    customerPhoneController.dispose();
    invoiceController.dispose();
    productController.dispose();
    quantityController.dispose();
    priceController.dispose();
    barcodeInputController.dispose();
    barcodeFocusNode.dispose();
    discountController.dispose();
    cashController.dispose();

    super.dispose();
  }

  // =========================
  // UI
  // =========================

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 1000;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(desktop),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(desktop ? 28 : 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1250),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _pageHeader(),
                        const SizedBox(height: 22),
                        if (desktop)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 6,
                                child: Column(
                                  children: [
                                    _invoiceCard(),
                                    const SizedBox(height: 18),
                                    _productCard(),
                                    const SizedBox(height: 18),
                                    _itemsCard(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 4,
                                child: Column(
                                  children: [
                                    _summaryCard(),
                                    const SizedBox(height: 18),
                                    _paymentCard(),
                                    const SizedBox(height: 18),
                                    _generateCard(),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            children: [
                              _invoiceCard(),
                              const SizedBox(height: 18),
                              _productCard(),
                              const SizedBox(height: 18),
                              _itemsCard(),
                              const SizedBox(height: 18),
                              _summaryCard(),
                              const SizedBox(height: 18),
                              _paymentCard(),
                              const SizedBox(height: 18),
                              _generateCard(),
                            ],
                          ),
                        const SizedBox(height: 20),
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

  Widget _topBar(bool desktop) {
    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: desktop ? 28 : 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 14,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1769E0), Color(0xFF6545E8)],
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'BillX',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: Color(0xFF14213D),
            ),
          ),
          const SizedBox(width: 10),
          if (desktop)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Billing',
                style: TextStyle(
                  color: Color(0xFF1769E0),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          const Spacer(),
          if (desktop)
            const Text(
              'New Invoice',
              style: TextStyle(
                color: Color(0xFF718096),
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(width: 8),
          _topIcon(Icons.vpn_key_outlined, 'License Manager', () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OwnerLicensePage()),
            );
          }),
          _topIcon(Icons.history_rounded, 'Bills History', () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BillsHistoryPage()),
            );
          }),
          _topIcon(Icons.refresh_rounded, 'Clear Bill', clearBill),
          _topIcon(Icons.logout_rounded, 'Logout', logout),
        ],
      ),
    );
  }

  Widget _topIcon(IconData icon, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: const Color(0xFF53657D)),
      ),
    );
  }

  Widget _pageHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Create New Bill',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF14213D),
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Create a professional customer invoice quickly and easily.',
                style: TextStyle(color: Color(0xFF718096), fontSize: 14),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEAFBF3),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFFC8EEDB)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 9, color: Color(0xFF10A36A)),
              SizedBox(width: 7),
              Text(
                'Ready',
                style: TextStyle(
                  color: Color(0xFF16845A),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(20),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6EBF2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF1769E0)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF172B4D),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF7B8CA5),
                ),
              ),
            ],
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
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF7B8CA5)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF8FAFD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE0E7F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE0E7F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFF1769E0), width: 1.5),
        ),
      ),
    );
  }

  Widget _invoiceCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            Icons.receipt_long_rounded,
            'Invoice Information',
            'Customer and invoice details',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 620;

              final fields = [
                _modernField(
                  controller: invoiceController,
                  label: 'Invoice Number',
                  hint: 'INV-001',
                  icon: Icons.tag_rounded,
                ),
                _modernField(
                  controller: customerController,
                  label: 'Customer Name',
                  hint: 'Enter customer name',
                  icon: Icons.person_outline_rounded,
                ),
                _modernField(
                  controller: customerPhoneController,
                  label: 'WhatsApp Number',
                  hint: '+947XXXXXXXX',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFE0E7F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: Color(0xFF1769E0),
                      ),
                      const SizedBox(width: 11),
                      const Text(
                        'Date',
                        style: TextStyle(
                          color: Color(0xFF7B8CA5),
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formattedDate(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF334E68),
                        ),
                      ),
                    ],
                  ),
                ),
              ];

              if (!twoColumns) {
                return Column(
                  children: [
                    fields[0],
                    const SizedBox(height: 12),
                    fields[1],
                    const SizedBox(height: 12),
                    fields[2],
                    const SizedBox(height: 12),
                    fields[3],
                  ],
                );
              }

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: fields
                    .map(
                      (field) => SizedBox(
                        width: (constraints.maxWidth - 12) / 2,
                        child: field,
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _productCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            Icons.inventory_2_rounded,
            'Add Product',
            'Scan a barcode or enter product details manually',
          ),
          const SizedBox(height: 20),
          _modernField(
            controller: barcodeInputController,
            label: 'Barcode Scanner',
            hint: 'Scan barcode and press Enter',
            icon: Icons.qr_code_scanner_rounded,
            keyboardType: TextInputType.number,
            onSubmitted: lookupBarcode,
            suffixIcon: IconButton(
              tooltip: 'Clear barcode',
              onPressed: () {
                barcodeInputController.clear();
                barcodeFocusNode.requestFocus();
              },
              icon: const Icon(Icons.clear_rounded),
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'PC: connect a USB barcode scanner. Mobile: use the camera scanner below.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF8A99AB)),
          ),
          const SizedBox(height: 14),
          _modernField(
            controller: productController,
            label: 'Product Name',
            hint: 'Enter product name',
            icon: Icons.shopping_bag_outlined,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: scanBarcode,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text(
                'SCAN PRODUCT WITH CAMERA',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1769E0),
                side: const BorderSide(color: Color(0xFFBBD5F7)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final two = constraints.maxWidth >= 500;

              final quantity = _modernField(
                controller: quantityController,
                label: 'Quantity',
                hint: '1',
                icon: Icons.numbers_rounded,
                keyboardType: TextInputType.number,
              );

              final price = _modernField(
                controller: priceController,
                label: 'Selling Price',
                hint: '0.00',
                icon: Icons.currency_exchange_rounded,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              );

              if (!two) {
                return Column(
                  children: [quantity, const SizedBox(height: 12), price],
                );
              }

              return Row(
                children: [
                  Expanded(child: quantity),
                  const SizedBox(width: 12),
                  Expanded(child: price),
                ],
              );
            },
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: addItem,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'ADD ITEM',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: .3,
                ),
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
      ),
    );
  }

  Widget _itemsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _sectionTitle(
                  Icons.shopping_cart_outlined,
                  'Bill Items',
                  '${items.length} item${items.length == 1 ? '' : 's'} added',
                ),
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF3FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${items.length}',
                    style: const TextStyle(
                      color: Color(0xFF1769E0),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 17),
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 35),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFD),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: const Color(0xFFE5EBF2)),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 48,
                    color: Color(0xFFA8B5C6),
                  ),
                  SizedBox(height: 9),
                  Text(
                    'No items added yet',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Add a product to start building the bill.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ],
              ),
            ),
          if (items.isNotEmpty)
            ...List.generate(items.length, (index) {
              final item = items[index];
              final quantity = (item['quantity'] as num).toInt();
              final price = (item['price'] as num).toDouble();
              final total = quantity * price;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5EBF2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 43,
                      height: 43,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF3FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.shopping_bag_outlined,
                        color: Color(0xFF1769E0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['product'].toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF263A53),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$quantity × Rs. ${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Color(0xFF718096),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Rs. ${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF172B4D),
                      ),
                    ),
                    IconButton(
                      onPressed: () => removeItem(index),
                      tooltip: 'Remove item',
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFE05252),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            Icons.calculate_outlined,
            'Bill Summary',
            'Review totals before payment',
          ),
          const SizedBox(height: 20),
          _summaryRow('Subtotal', 'Rs. ${subTotal.toStringAsFixed(2)}'),
          const SizedBox(height: 14),
          _modernField(
            controller: discountController,
            label: 'Discount',
            hint: '0.00',
            icon: Icons.discount_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 17),
          const Divider(),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Final Total',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF172B4D),
                ),
              ),
              Text(
                'Rs. ${finalTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1769E0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF263A53),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _paymentCard() {
    final positive = balance >= 0;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            Icons.payments_outlined,
            'Payment',
            'Enter cash received from the customer',
          ),
          const SizedBox(height: 20),
          _modernField(
            controller: cashController,
            label: 'Cash Received',
            hint: '0.00',
            icon: Icons.payments_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 15),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: positive
                  ? const Color(0xFFEAFBF3)
                  : const Color(0xFFFFF1F1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: positive
                    ? const Color(0xFFC8EEDB)
                    : const Color(0xFFF4CCCC),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  positive
                      ? Icons.check_circle_outline_rounded
                      : Icons.warning_amber_rounded,
                  color: positive
                      ? const Color(0xFF10A36A)
                      : const Color(0xFFD64545),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    positive ? 'Balance' : 'Amount Due',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334E68),
                    ),
                  ),
                ),
                Text(
                  'Rs. ${balance.abs().toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: positive
                        ? const Color(0xFF10865A)
                        : const Color(0xFFD64545),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _generateCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1769E0), Color(0xFF6545E8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x241769E0),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.picture_as_pdf_rounded,
            color: Colors.white,
            size: 34,
          ),
          const SizedBox(height: 13),
          const Text(
            'Ready to generate?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Save the bill and open the professional PDF preview.',
            style: TextStyle(
              color: Color(0xDFFFFFFF),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: items.isEmpty ? null : generateBill,
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text(
                'GENERATE PDF BILL',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1769E0),
                disabledBackgroundColor: Colors.white54,
                disabledForegroundColor: Colors.white70,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
