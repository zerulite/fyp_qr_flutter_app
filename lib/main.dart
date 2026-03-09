import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:local_auth/local_auth.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: QRBiometricPage());
  }
}

class QRBiometricPage extends StatefulWidget {
  const QRBiometricPage({super.key});

  @override
  State<QRBiometricPage> createState() => _QRBiometricPageState();
}

class _QRBiometricPageState extends State<QRBiometricPage> {
  final LocalAuthentication auth = LocalAuthentication();
  String qrResult = "No QR scanned";

  Future<bool> authenticate() async {
    try {
      bool authenticated = await auth.authenticate(
        localizedReason: 'Authenticate to confirm transaction',
        options: const AuthenticationOptions(biometricOnly: true),
      );

      return authenticated;
    } catch (e) {
      return false;
    }
  }

  void handleQRCode(String code) async {
    bool success = await authenticate();

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Biometric authentication failed")),
      );
      return;
    }

    setState(() {
      qrResult = code;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("QR Accepted: $code")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("QR Scanner + Biometrics")),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: MobileScanner(
              onDetect: (BarcodeCapture capture) {
                final List<Barcode> barcodes = capture.barcodes;

                for (final barcode in barcodes) {
                  final String? code = barcode.rawValue;

                  if (code != null) {
                    handleQRCode(code);
                  }
                }
              },
            ),
          ),

          Expanded(
            flex: 1,
            child: Center(
              child: Text(qrResult, style: const TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}
