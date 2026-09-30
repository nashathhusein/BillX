BillX - Structured Source

இந்த package-ல் BillX main.dart feature-wise files ஆக பிரிக்கப்பட்டுள்ளது.

1) உங்கள் C:\BillX project-ஐ backup எடுக்கவும்.
2) இந்த ZIP-ல் உள்ள lib folder-ஐ C:\BillX-ல் replace செய்யவும்.
3) firebase_options.dart உங்கள் existing project-ல் ஏற்கனவே இருப்பதை வைத்துக்கொள்ளவும்.
4) backend, assets, android, ios, web, windows folders-ஐ இந்த ZIP மாற்றாது.

Main files:
- lib/main.dart
- lib/app/billx_app.dart
- lib/auth/auth_gate.dart
- lib/auth/login_page.dart
- lib/auth/register_page.dart
- lib/license/license_service.dart
- lib/license/license_page.dart
- lib/products/barcode_scanner.dart
- lib/billing/bill_home_page.dart
- lib/history/bills_history_page.dart
- lib/database/offline_database.dart
- lib/database/offline_sync_service.dart

Original main source backup:
- lib/main_original_backup.dart

IMPORTANT:
Current source still keeps the original BillHome logic together. Later we can split Billing UI, PDF, product logic and services further without changing the app behavior.
