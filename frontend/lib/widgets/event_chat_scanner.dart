import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api_service.dart';
import 'booking_chat_sheet.dart';

Future<void> scanEventChatQr(BuildContext context, ApiService api) async {
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => _EventChatScanner(api: api)),
  );
}

class _EventChatScanner extends StatefulWidget {
  const _EventChatScanner({required this.api});
  final ApiService api;

  @override
  State<_EventChatScanner> createState() => _EventChatScannerState();
}

class _EventChatScannerState extends State<_EventChatScanner> {
  final controller = MobileScannerController();
  bool processing = false;

  Future<void> _detected(BarcodeCapture capture) async {
    if (processing || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue ?? '';
    const prefix = 'GARIBALDI_EVENT:';
    if (!raw.startsWith(prefix)) return;
    final token = raw.substring(prefix.length);
    if (token.isEmpty) return;
    setState(() => processing = true);
    await controller.stop();
    try {
      final booking = await widget.api.get('/api/event-chat/$token')
          as Map<String, dynamic>;
      if (!mounted) return;
      await showBookingChat(
        context,
        api: widget.api,
        booking: booking,
        inviteToken: token,
      );
      if (mounted) Navigator.pop(context);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      setState(() => processing = false);
      await controller.start();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Entrar al chat de la fiesta')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: controller, onDetect: _detected),
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFF0B35D), width: 4),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        const Positioned(
          left: 28,
          right: 28,
          bottom: 48,
          child: Text(
            'Escanea el QR que muestra el anfitrión del evento.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
