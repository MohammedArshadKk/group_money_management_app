import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; // for QR scan
import 'package:url_launcher/url_launcher.dart';

class PayScreen extends StatefulWidget {
  const PayScreen({super.key});

  @override
  State<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends State<PayScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  // Navigate to QR scanner
  void _scanQr() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (result != null) {
      String upiId = result.toString();
      String amount = _amountController.text.trim();
      String desc = _descController.text.trim();
      log("upiId : $upiId");
      if (upiId.isNotEmpty && amount.isNotEmpty) {
        _launchGPay(upiId, amount, desc);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Enter amount & scan a valid UPI QR")),
        );
      }
    }
  }

  // Open UPI intent
  Future<void> _launchGPay(String upiId, String amount, String desc) async {
    Uri? uri;
    try {
      final parsed = Uri.parse(upiId);

      if (parsed.scheme == 'upi' && parsed.host == 'pay') {
        final qp = Map<String, String>.from(parsed.queryParameters);
        qp['am'] = amount;
        if (desc.isNotEmpty) {
          qp['tn'] = desc;
        }
        qp.putIfAbsent('cu', () => 'INR');
        uri = parsed.replace(queryParameters: qp);
      } else if (RegExp(r'^[\w\.\-]+@[\w\.\-]+$').hasMatch(upiId)) {
        final qp = <String, String>{'pa': upiId, 'am': amount, 'cu': 'INR'};
        if (desc.isNotEmpty) {
          qp['tn'] = desc;
        }
        uri = Uri(scheme: 'upi', host: 'pay', queryParameters: qp);
      } else {
        uri = parsed;
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid UPI link scanned')));
      return;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No UPI app found!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pay")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Enter Amount",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: "Enter Description",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _scanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text("Pay with Google Pay"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QRScannerScreen extends StatelessWidget {
  const QRScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan UPI QR")),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              Navigator.pop(context, barcode.rawValue!); // return result
              break;
            }
          }
        },
      ),
    );
  }
}
