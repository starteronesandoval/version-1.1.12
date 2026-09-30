import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_service.dart';

Future<void> showSurpriseGroupSheet(
  BuildContext context, {
  required ApiService api,
  required Future<void> Function() onBookingCreated,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: const Color(0xFF17110B),
  showDragHandle: true,
  builder:
      (_) => _SurpriseGroupSheet(api: api, onBookingCreated: onBookingCreated),
);

class _SurpriseGroupSheet extends StatefulWidget {
  const _SurpriseGroupSheet({
    required this.api,
    required this.onBookingCreated,
  });

  final ApiService api;
  final Future<void> Function() onBookingCreated;

  @override
  State<_SurpriseGroupSheet> createState() => _SurpriseGroupSheetState();
}

class _SurpriseGroupSheetState extends State<_SurpriseGroupSheet> {
  final budget = TextEditingController();
  final venue = TextEditingController();
  final eventCity = TextEditingController();
  final eventMunicipality = TextEditingController();
  final eventState = TextEditingController();
  String genre = 'Norteño';
  DateTime? selectedDate;
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  bool noticeAccepted = false;
  bool submitting = false;
  bool openingCheckout = false;
  Map<String, dynamic>? quote;
  String? searchError;

  int? get durationMinutes =>
      startTime == null || endTime == null
          ? null
          : endTime!.hour * 60 +
              endTime!.minute -
              startTime!.hour * 60 -
              startTime!.minute;

  String dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String timeKey(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  String displayDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  @override
  void dispose() {
    budget.dispose();
    venue.dispose();
    eventCity.dispose();
    eventMunicipality.dispose();
    eventState.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final maxRate = double.tryParse(budget.text.replaceAll(',', '').trim());
    final minutes = durationMinutes;
    if (maxRate == null ||
        maxRate <= 0 ||
        eventCity.text.trim().length < 2 ||
        eventMunicipality.text.trim().length < 2 ||
        eventState.text.trim().length < 2 ||
        selectedDate == null ||
        startTime == null ||
        endTime == null ||
        minutes == null ||
        minutes < 180 ||
        venue.text.trim().length < 3 ||
        !noticeAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Completa ciudad, municipio y estado del evento; elige al menos 3 horas y acepta el aviso.',
          ),
        ),
      );
      return;
    }
    setState(() {
      submitting = true;
      searchError = null;
    });
    try {
      final response =
          await widget.api.post('/api/bookings/surprise', {
                'genre': genre,
                'max_hourly_rate': maxRate,
                'event_date': dateKey(selectedDate!),
                'venue': venue.text.trim(),
                'start_time': timeKey(startTime!),
                'end_time': timeKey(endTime!),
                'surprise_notice_accepted': noticeAccepted,
                'event_city': eventCity.text.trim(),
                'event_municipality': eventMunicipality.text.trim(),
                'event_state': eventState.text.trim(),
              })
              as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => quote = response);
      await widget.onBookingCreated();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          searchError =
              error.statusCode == 404
                  ? 'Aún no hay grupos disponibles con ese filtro de búsqueda.'
                  : error.message;
        });
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> checkout() async {
    if (openingCheckout) return;
    setState(() => openingCheckout = true);
    try {
      final response =
          await widget.api.post('/api/billing/checkout-sessions', {
                'booking_id': quote!['id'],
              })
              as Map<String, dynamic>;
      final url = Uri.tryParse(response['url']?.toString() ?? '');
      if (url == null || url.scheme != 'https' || url.host.isEmpty) {
        throw const FormatException('URL de pago inválida');
      }
      var opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened) {
        opened = await launchUrl(url, mode: LaunchMode.inAppBrowserView);
      }
      if (!opened) throw const FormatException('No se pudo abrir el pago');
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo abrir el pago seguro. Revisa tu conexión e inténtalo nuevamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => openingCheckout = false);
    }
  }

  Widget priceLine(String label, num cents, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          '\$${(cents / 100).toStringAsFixed(2)} MXN',
          style: TextStyle(
            color: strong ? const Color(0xFFFF9D00) : Colors.white,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.card_giftcard_rounded,
            size: 48,
            color: Color(0xFFFFA000),
          ),
          const SizedBox(height: 8),
          const Text(
            'Grupo Sorpresa',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          const Text(
            'Tú eliges género, presupuesto y condiciones. Garibaldy elige una agrupación disponible que cumpla tus requisitos.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 20),
          if (quote == null) ...formFields else ...quoteDetails,
        ],
      ),
    ),
  );

  List<Widget> get formFields => [
    DropdownButtonFormField<String>(
      initialValue: genre,
      decoration: const InputDecoration(
        labelText: 'Género musical',
        prefixIcon: Icon(Icons.library_music_outlined),
      ),
      items:
          const ['Norteño', 'Banda', 'Mariachi', 'Rock', 'Otros']
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList(),
      onChanged:
          submitting ? null : (value) => setState(() => genre = value ?? genre),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: budget,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'Presupuesto máximo por hora',
        prefixText: r'$ ',
        suffixText: 'MXN',
        prefixIcon: Icon(Icons.payments_outlined),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: eventCity,
      decoration: const InputDecoration(
        labelText: 'Ciudad del evento',
        prefixIcon: Icon(Icons.location_city_outlined),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: eventMunicipality,
      decoration: const InputDecoration(labelText: 'Municipio del evento'),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: eventState,
      decoration: const InputDecoration(labelText: 'Estado del evento'),
    ),
    const Padding(
      padding: EdgeInsets.only(top: 7),
      child: Text(
        'Calcularemos una distancia aproximada para encontrar grupos a máximo 30 km de su zona de servicio.',
        style: TextStyle(fontSize: 12, color: Colors.white70),
      ),
    ),
    const Padding(
      padding: EdgeInsets.only(top: 7),
      child: Text(
        'Participan grupos cuya tarifa sea igual a tu presupuesto o hasta \$500 menor.',
        style: TextStyle(fontSize: 12, color: Colors.white70),
      ),
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: () async {
        final now = DateTime.now();
        final value = await showDatePicker(
          context: context,
          firstDate: DateTime(now.year, now.month, now.day),
          lastDate: DateTime(now.year + 2, 12, 31),
          initialDate: selectedDate ?? now.add(const Duration(days: 1)),
          helpText: 'Fecha del evento sorpresa',
        );
        if (value != null && mounted) setState(() => selectedDate = value);
      },
      icon: const Icon(Icons.event_outlined),
      label: Text(
        selectedDate == null ? 'Elegir fecha' : displayDate(selectedDate!),
      ),
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => pickTime(true),
            icon: const Icon(Icons.play_circle_outline),
            label: Text(
              startTime == null
                  ? 'Hora inicial'
                  : MaterialLocalizations.of(
                    context,
                  ).formatTimeOfDay(startTime!),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => pickTime(false),
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(
              endTime == null
                  ? 'Hora final'
                  : MaterialLocalizations.of(context).formatTimeOfDay(endTime!),
            ),
          ),
        ),
      ],
    ),
    if (durationMinutes != null) ...[
      const SizedBox(height: 8),
      Text(
        durationMinutes! >= 180
            ? 'Duración: ${(durationMinutes! / 60).toStringAsFixed(durationMinutes! % 60 == 0 ? 0 : 1)} horas'
            : 'La duración mínima es de 3 horas.',
        style: TextStyle(
          color:
              durationMinutes! >= 180
                  ? const Color(0xFFFF9D00)
                  : const Color(0xFFFF8A80),
        ),
      ),
    ],
    const SizedBox(height: 12),
    TextField(
      controller: venue,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        labelText: 'Ubicación del evento',
        hintText: 'Salón, domicilio o dirección',
        prefixIcon: Icon(Icons.location_on_outlined),
      ),
    ),
    CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: noticeAccepted,
      onChanged:
          submitting
              ? null
              : (value) => setState(() => noticeAccepted = value ?? false),
      title: const Text(
        'Acepto que esta modalidad es para personas abiertas a recibir una agrupación sorpresa.',
      ),
      controlAffinity: ListTileControlAffinity.leading,
    ),
    if (searchError != null) ...[
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFF8A80).withValues(alpha: .14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF8A80)),
        ),
        child: Text(
          searchError!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
    FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
      onPressed: submitting ? null : submit,
      icon: const Icon(Icons.auto_awesome),
      label: Text(
        submitting ? 'Buscando agrupación…' : 'Buscar Grupo Sorpresa',
      ),
    ),
  ];

  Future<void> pickTime(bool start) async {
    final value = await showTimePicker(
      context: context,
      initialTime:
          start
              ? startTime ?? const TimeOfDay(hour: 18, minute: 0)
              : endTime ?? const TimeOfDay(hour: 22, minute: 0),
      helpText: start ? 'Hora de inicio' : 'Hora final',
    );
    if (value != null && mounted) {
      setState(() {
        if (start) {
          startTime = value;
        } else {
          endTime = value;
        }
      });
    }
  }

  List<Widget> get quoteDetails => [
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Text(
            'Encontramos una agrupación compatible',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Su identidad se revelará cuando Stripe confirme tu pago.',
            textAlign: TextAlign.center,
          ),
          const Divider(height: 28),
          priceLine('Precio real por hora', quote!['hourly_rate_cents'] as num),
          priceLine('Servicio', quote!['subtotal_cents'] as num),
          priceLine('Comisiones', quote!['service_fee_cents'] as num),
          const Divider(),
          priceLine(
            'Total a pagar',
            quote!['total_cents'] as num,
            strong: true,
          ),
        ],
      ),
    ),
    const SizedBox(height: 14),
    FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: const Color(0xFF27AE86),
      ),
      onPressed: openingCheckout ? null : checkout,
      icon: const Icon(Icons.lock_outline),
      label: Text(
        openingCheckout
            ? 'Abriendo pago seguro…'
            : 'Continuar al pago seguro',
      ),
    ),
  ];
}
