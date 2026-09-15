import 'dart:async';

import 'package:flutter/material.dart';

import '../api_service.dart';

class BookingPayoutActions extends StatefulWidget {
  const BookingPayoutActions({
    super.key,
    required this.api,
    required this.booking,
    required this.onChanged,
  });

  final ApiService api;
  final Map<String, dynamic> booking;
  final VoidCallback onChanged;

  @override
  State<BookingPayoutActions> createState() => _BookingPayoutActionsState();
}

class _BookingPayoutActionsState extends State<BookingPayoutActions> {
  Timer? timer;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  DateTime? get deadline =>
      DateTime.tryParse(
        widget.booking['payout_release_deadline']?.toString() ?? '',
      )?.toLocal();

  bool get windowOpen {
    final value = deadline;
    return value != null && DateTime.now().isBefore(value);
  }

  String get countdown {
    final value = deadline;
    if (value == null) return 'Plazo no disponible';
    final remaining = value.difference(DateTime.now());
    if (remaining <= Duration.zero) return 'El plazo terminó';
    final hours = remaining.inHours.toString().padLeft(2, '0');
    final minutes = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds para decidir';
  }

  Future<void> releaseNow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('¿Liberar el pago ahora?'),
            content: Text(
              'Confirmas que el evento de ${widget.booking['group_name']} terminó '
              'correctamente. Esta acción no se puede deshacer.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Todavía no'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sí, liberar pago'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => sending = true);
    try {
      final result =
          await widget.api.post(
                '/api/bookings/${widget.booking['id']}/release',
                {},
              )
              as Map<String, dynamic>;
      widget.booking['payout_status'] = result['payout_status'];
      widget.booking['can_release_payment'] = false;
      widget.booking['can_dispute_payment'] = false;
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pago liberado para la agrupación.')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> reportProblem() async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Reportar un problema'),
            content: TextField(
              controller: reason,
              minLines: 3,
              maxLines: 6,
              maxLength: 1500,
              decoration: const InputDecoration(
                labelText: 'Describe lo ocurrido',
                hintText: 'La liberación al músico quedará detenida.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Detener liberación'),
              ),
            ],
          ),
    );
    if (confirmed != true) {
      reason.dispose();
      return;
    }
    if (reason.text.trim().length < 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Describe el problema con más detalle.'),
          ),
        );
      }
      reason.dispose();
      return;
    }
    setState(() => sending = true);
    try {
      await widget.api.post('/api/bookings/${widget.booking['id']}/dispute', {
        'reason': reason.text.trim(),
      });
      widget.booking['payout_status'] = 'disputed';
      widget.booking['can_release_payment'] = false;
      widget.booking['can_dispute_payment'] = false;
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pago detenido para revisión.')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      reason.dispose();
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.booking['payout_status']?.toString();
    if (status == 'disputed') {
      return const _PayoutNotice(
        icon: Icons.gpp_maybe_outlined,
        text: 'Pago detenido: el equipo revisará el reporte.',
        color: Color(0xFFFFC857),
      );
    }
    if (status != 'musician_funds_held') {
      return const _PayoutNotice(
        icon: Icons.verified_outlined,
        text: 'El pago ya fue autorizado para la agrupación.',
        color: Color(0xFF68DDCD),
      );
    }
    if (widget.booking['event_finished'] != true ||
        widget.booking['payment_status'] != 'paid') {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF68DDCD).withValues(alpha: .09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF68DDCD).withValues(alpha: .28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            windowOpen ? countdown : 'Liberación automática en proceso',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            'Si no eliges una opción, el pago se libera automáticamente.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: .68),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: sending ? null : releaseNow,
            icon: const Icon(Icons.price_check_rounded),
            label: Text(sending ? 'Procesando…' : 'Liberar ahora'),
          ),
          if (windowOpen) ...[
            const SizedBox(height: 7),
            OutlinedButton.icon(
              onPressed: sending ? null : reportProblem,
              icon: const Icon(Icons.report_problem_outlined),
              label: const Text('Reportar un problema'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PayoutNotice extends StatelessWidget {
  const _PayoutNotice({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
