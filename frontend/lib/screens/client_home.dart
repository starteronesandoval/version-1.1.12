import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_service.dart';
import '../widgets/booking_chat_sheet.dart';
import '../widgets/glass_ui.dart';

class ClientHome extends StatefulWidget {
  const ClientHome({super.key, required this.api, required this.onLogout});
  final ApiService api;
  final VoidCallback onLogout;
  @override
  State<ClientHome> createState() => _ClientHomeState();
}

class _ClientHomeState extends State<ClientHome> {
  final search = TextEditingController();
  final picker = ImagePicker();
  List<dynamic> results = [];
  List<dynamic> bookings = [];
  Map<String, dynamic>? clientProfile;
  bool loading = true;
  Timer? debounce;

  @override
  void initState() {
    super.initState();
    load();
    loadClientProfile();
    loadClientBookings();
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      results = await widget.api
          .get('/api/musicians?q=${Uri.encodeQueryComponent(search.text)}');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadClientProfile() async {
    try {
      clientProfile =
          await widget.api.get('/api/clients/me') as Map<String, dynamic>;
      if (mounted) setState(() {});
    } on ApiException catch (error) {
      if (error.statusCode != 404 && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> loadClientBookings() async {
    try {
      bookings =
          await widget.api.get('/api/clients/me/bookings') as List<dynamic>;
      if (mounted) setState(() {});
    } on ApiException catch (error) {
      if (error.statusCode != 409 && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Descubre', style: TextStyle(fontWeight: FontWeight.w800)),
                Text('música para tu momento',
                    style: TextStyle(fontSize: 12, color: Color(0xFFC8B5EE))),
              ]),
          actions: [
            IconButton(
                tooltip: 'Mis contratos y chats',
                onPressed: () => _contractsSheet(context),
                icon: Badge(
                    isLabelVisible: bookings.isNotEmpty,
                    label: Text('${bookings.length}'),
                    child: const Icon(Icons.forum_outlined))),
            IconButton(
                onPressed: () => _profileSheet(context), icon: _smallAvatar()),
            IconButton(
                onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
          ],
        ),
        body: GlassBackground(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                  child: GlassCard(
                    padding: EdgeInsets.zero,
                    child: TextField(
                      controller: search,
                      onChanged: (_) {
                        debounce?.cancel();
                        debounce =
                            Timer(const Duration(milliseconds: 350), load);
                      },
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Busca nombre, estilo o tipo de grupo',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    const Expanded(
                        child: Text('Agrupaciones disponibles',
                            style: TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w700))),
                    Text('${results.length}',
                        style: const TextStyle(
                            color: Color(0xFFBFA1FF),
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(height: 10),
                if (loading) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: results.isEmpty && !loading
                      ? const Center(
                          child: Text('Aún no encontramos agrupaciones'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 6, 18, 100),
                          itemCount: results.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 14),
                          itemBuilder: (_, index) =>
                              _bandCard(results[index] as Map<String, dynamic>),
                        ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _profileSheet(context),
          icon: const Icon(Icons.person_outline),
          label: const Text('Mi perfil'),
        ),
      );

  Widget _smallAvatar() => ProfileAvatar(
        radius: 17,
        url: widget.api.mediaUrl(clientProfile?['avatar_url']),
        fallback: clientProfile?['name'] ?? 'C',
        preset: clientProfile?['avatar_preset'] ?? 'jaguar_guitar',
        color: clientProfile?['avatar_color'] ?? '#8B5CF6',
      );

  Widget _bandCard(Map<String, dynamic> band) {
    final media =
        (band['media'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final avatar = media
        .where((item) => item['media_type'] == 'profile_photo')
        .firstOrNull;
    return GlassCard(
      onTap: () => _showBand(context, band),
      child: Row(
        children: [
          ProfileAvatar(
              url: widget.api.mediaUrl(avatar?['url']),
              fallback: band['group_name'],
              preset: band['avatar_preset'] ?? 'jaguar_guitar',
              color: band['avatar_color'] ?? '#8B5CF6',
              radius: 38),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Expanded(
                      child: Text(band['group_name'],
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800))),
                  const Icon(Icons.verified, color: Color(0xFF68DDCD), size: 18)
                ]),
                const SizedBox(height: 4),
                Text('${band['group_type']} · ${band['musical_style']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: .67))),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.payments_outlined,
                      size: 17, color: Color(0xFFBFA1FF)),
                  Text('  \$${band['hourly_rate']} / hora',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (band['includes_sound'])
                    const Icon(Icons.speaker_group_outlined,
                        size: 19, color: Color(0xFF68DDCD)),
                ]),
              ])),
        ],
      ),
    );
  }

  void _showBand(BuildContext context, Map<String, dynamic> band) {
    final media =
        (band['media'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final avatar = media
        .where((item) => item['media_type'] == 'profile_photo')
        .firstOrNull;
    final photos =
        media.where((item) => item['media_type'] == 'photo').toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1235),
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: .72,
        maxChildSize: .94,
        expand: false,
        builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
            children: [
              Center(
                  child: ProfileAvatar(
                      url: widget.api.mediaUrl(avatar?['url']),
                      fallback: band['group_name'],
                      preset: band['avatar_preset'] ?? 'jaguar_guitar',
                      color: band['avatar_color'] ?? '#8B5CF6',
                      radius: 56)),
              const SizedBox(height: 14),
              Text(band['group_name'],
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              Text('${band['group_type']} · ${band['musical_style']}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFBFA1FF))),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _miniStat('${band['member_count']}', 'Integrantes'),
                _miniStat('${band['audience_capacity']}', 'Personas'),
                _miniStat('\$${band['hourly_rate']}', 'Por hora'),
              ]),
              const SizedBox(height: 20),
              Text(band['description'], style: const TextStyle(height: 1.5)),
              const SizedBox(height: 18),
              Wrap(spacing: 8, children: [
                if (band['includes_sound'])
                  const Chip(label: Text('Sonido incluido')),
                for (final brand in band['equipment_brands'])
                  Chip(label: Text(brand))
              ]),
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('Galería',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                SizedBox(
                    height: 150,
                    child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: photos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.network(
                                widget.api.mediaUrl(photos[i]['url'])!,
                                width: 190,
                                fit: BoxFit.cover)))),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54)),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _availabilitySheet(band);
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('Contratar / consultar fecha')),
            ]),
      ),
    );
  }

  String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  String _apiTime(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  Future<void> _availabilitySheet(Map<String, dynamic> band) async {
    DateTime? selectedDate;
    Map<String, dynamic>? availability;
    Map<String, dynamic>? bookingResult;
    final venue = TextEditingController();
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    var checking = false;
    var booking = false;
    var showContractForm = false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1235),
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) {
          final available = availability?['available'] as bool?;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                22,
                4,
                22,
                MediaQuery.viewInsetsOf(sheetContext).bottom + 28,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.calendar_month,
                        size: 46, color: Color(0xFFBFA1FF)),
                    const SizedBox(height: 12),
                    Text('Consulta antes de contratar',
                        textAlign: TextAlign.center,
                        style: Theme.of(sheetContext)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      'Elige la fecha de tu evento para consultar a ${band['group_name']}.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Colors.white.withValues(alpha: .66)),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52)),
                      onPressed: checking
                          ? null
                          : () async {
                              final selected = await showDatePicker(
                                context: sheetContext,
                                initialDate: selectedDate ?? today,
                                firstDate: today,
                                lastDate: today.add(const Duration(days: 730)),
                                helpText: 'Fecha del evento',
                                cancelText: 'Cancelar',
                                confirmText: 'Consultar',
                              );
                              if (selected == null || !sheetContext.mounted) {
                                return;
                              }
                              setSheetState(() {
                                selectedDate = selected;
                                availability = null;
                                bookingResult = null;
                                showContractForm = false;
                                checking = true;
                              });
                              try {
                                final response = await widget.api.get(
                                        '/api/musicians/${band['id']}/availability?date=${_dateKey(selected)}')
                                    as Map<String, dynamic>;
                                if (!sheetContext.mounted) return;
                                bookings = [...bookings, response];
                                if (mounted) setState(() {});
                                setSheetState(() {
                                  availability = response;
                                  checking = false;
                                });
                              } catch (error) {
                                if (!sheetContext.mounted) return;
                                setSheetState(() => checking = false);
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                    SnackBar(content: Text(error.toString())));
                              }
                            },
                      icon: const Icon(Icons.calendar_month),
                      label: Text(selectedDate == null
                          ? 'Seleccionar fecha'
                          : _formatDate(selectedDate!)),
                    ),
                    if (checking) ...[
                      const SizedBox(height: 18),
                      const Center(child: CircularProgressIndicator()),
                    ],
                    if (available != null) ...[
                      const SizedBox(height: 18),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: (available
                                  ? const Color(0xFF27AE86)
                                  : const Color(0xFFD84B5C))
                              .withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: available
                                ? const Color(0xFF68DDCD)
                                : const Color(0xFFFF7D8C),
                          ),
                        ),
                        child: Column(children: [
                          Icon(
                            available
                                ? Icons.event_available
                                : Icons.event_busy,
                            size: 42,
                            color: available
                                ? const Color(0xFF68DDCD)
                                : const Color(0xFFFF7D8C),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            available ? 'Fecha disponible' : 'Fecha ocupada',
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            availability!['message'].toString(),
                            textAlign: TextAlign.center,
                          ),
                        ]),
                      ),
                    ],
                    if (available == true && !showContractForm) ...[
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          backgroundColor: const Color(0xFF27AE86),
                        ),
                        onPressed: () {
                          if (clientProfile == null) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Completa primero tu perfil de cliente.'),
                              ),
                            );
                            return;
                          }
                          setSheetState(() => showContractForm = true);
                        },
                        icon: const Icon(Icons.handshake_outlined),
                        label: const Text('Contratar esta fecha'),
                      ),
                    ],
                    if (showContractForm && selectedDate != null) ...[
                      const SizedBox(height: 18),
                      const Text('Datos del evento',
                          style: TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: _formatDate(selectedDate!),
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Fecha del contrato / evento',
                          prefixIcon: Icon(Icons.event_available),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: venue,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Lugar del evento',
                          hintText: 'Salón, domicilio o dirección',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final value = await showTimePicker(
                                context: sheetContext,
                                initialTime: startTime ??
                                    const TimeOfDay(hour: 18, minute: 0),
                                helpText: 'Hora de inicio',
                              );
                              if (value != null && sheetContext.mounted) {
                                setSheetState(() => startTime = value);
                              }
                            },
                            icon: const Icon(Icons.play_circle_outline),
                            label: Text(startTime == null
                                ? 'Hora inicial'
                                : MaterialLocalizations.of(sheetContext)
                                    .formatTimeOfDay(startTime!)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final value = await showTimePicker(
                                context: sheetContext,
                                initialTime: endTime ??
                                    const TimeOfDay(hour: 23, minute: 0),
                                helpText: 'Hora final',
                              );
                              if (value != null && sheetContext.mounted) {
                                setSheetState(() => endTime = value);
                              }
                            },
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: Text(endTime == null
                                ? 'Hora final'
                                : MaterialLocalizations.of(sheetContext)
                                    .formatTimeOfDay(endTime!)),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54)),
                        onPressed: booking
                            ? null
                            : () async {
                                if (venue.text.trim().length < 3 ||
                                    startTime == null ||
                                    endTime == null) {
                                  ScaffoldMessenger.of(sheetContext)
                                      .showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Completa el lugar y ambos horarios.'),
                                    ),
                                  );
                                  return;
                                }
                                setSheetState(() => booking = true);
                                try {
                                  final response = await widget.api.post(
                                    '/api/bookings',
                                    {
                                      'musician_id': band['id'],
                                      'event_date': _dateKey(selectedDate!),
                                      'venue': venue.text.trim(),
                                      'start_time': _apiTime(startTime!),
                                      'end_time': _apiTime(endTime!),
                                    },
                                  ) as Map<String, dynamic>;
                                  if (!sheetContext.mounted) return;
                                  setSheetState(() {
                                    bookingResult = response;
                                    availability = null;
                                    showContractForm = false;
                                    booking = false;
                                  });
                                } on ApiException catch (error) {
                                  if (!sheetContext.mounted) return;
                                  if (error.statusCode == 409) {
                                    setSheetState(() {
                                      availability = {
                                        'available': false,
                                        'message': error.message,
                                      };
                                      showContractForm = false;
                                      booking = false;
                                    });
                                  } else {
                                    setSheetState(() => booking = false);
                                    ScaffoldMessenger.of(sheetContext)
                                        .showSnackBar(SnackBar(
                                            content: Text(error.message)));
                                  }
                                }
                              },
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(booking
                            ? 'Confirmando…'
                            : 'Confirmar contratación'),
                      ),
                    ],
                    if (bookingResult != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF27AE86).withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF68DDCD)),
                        ),
                        child: Column(children: [
                          const Icon(Icons.celebration,
                              size: 42, color: Color(0xFF68DDCD)),
                          const SizedBox(height: 8),
                          const Text('¡Fecha contratada!',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(
                            '${band['group_name']} recibió los datos de tu evento.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () {
                              final confirmed = bookingResult!;
                              Navigator.pop(sheetContext);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  showBookingChat(context,
                                      api: widget.api, booking: confirmed);
                                }
                              });
                            },
                            icon: Icon(bookingResult!['chat_active'] == true
                                ? Icons.forum_outlined
                                : Icons.lock_clock_outlined),
                            label: Text(bookingResult!['chat_active'] == true
                                ? 'Abrir chat del evento'
                                : 'Ver horario del chat'),
                          ),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    venue.dispose();
  }

  String _bookingTime(dynamic value) {
    final text = value.toString();
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  Future<void> _contractsSheet(BuildContext context) async {
    await loadClientBookings();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1235),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Mis contratos',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Entra al chat privado de cada evento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: .62))),
              const SizedBox(height: 16),
              if (bookings.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text('Todavía no tienes fechas contratadas.',
                      textAlign: TextAlign.center),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: bookings.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final item = bookings[index] as Map<String, dynamic>;
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['group_name'].toString(),
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 5),
                            Text(
                              '${_formatDate(DateTime.parse(item['event_date']))} · '
                              '${_bookingTime(item['start_time'])}–${_bookingTime(item['end_time'])}',
                              style: const TextStyle(color: Color(0xFF68DDCD)),
                            ),
                            const SizedBox(height: 4),
                            Text(item['venue'].toString()),
                            const SizedBox(height: 10),
                            FilledButton.tonalIcon(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (mounted) {
                                    showBookingChat(this.context,
                                        api: widget.api, booking: item);
                                  }
                                });
                              },
                              icon: Icon(item['chat_active'] == true
                                  ? Icons.forum_outlined
                                  : Icons.lock_clock_outlined),
                              label: Text(item['chat_active'] == true
                                  ? 'Abrir chat'
                                  : 'Disponible durante el evento'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String value, String label) => Column(children: [
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: .55)))
      ]);

  Future<void> _pickPreset() async {
    final selection = await showAvatarPicker(
      context,
      currentPreset: clientProfile?['avatar_preset'] ?? 'jaguar_guitar',
      currentColor: clientProfile?['avatar_color'] ?? '#8B5CF6',
    );
    if (selection == null) return;
    await widget.api.setAvatarPreset(selection.preset, selection.color);
    await loadClientProfile();
  }

  Future<void> _pickClientAvatar() async {
    final image =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (image == null) return;
    await widget.api.uploadClientAvatar(File(image.path));
    await loadClientProfile();
  }

  Future<void> _profileSheet(BuildContext context) async {
    final name = TextEditingController(text: clientProfile?['name'] ?? '');
    final tastes = TextEditingController(
        text: (clientProfile?['musical_tastes'] as List<dynamic>? ?? [])
            .join(', '));
    final favorites = TextEditingController(
        text: (clientProfile?['favorite_groups'] as List<dynamic>? ?? [])
            .join(', '));
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1235),
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            22, 4, 22, MediaQuery.viewInsetsOf(sheetContext).bottom + 28),
        child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(children: [
            ProfileAvatar(
                url: widget.api.mediaUrl(clientProfile?['avatar_url']),
                fallback: clientProfile?['name'] ?? 'C',
                preset: clientProfile?['avatar_preset'] ?? 'jaguar_guitar',
                color: clientProfile?['avatar_color'] ?? '#8B5CF6',
                radius: 50),
            if (clientProfile != null)
              Positioned(
                  left: 0,
                  bottom: 0,
                  child: CircleAvatar(
                      radius: 16,
                      child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          onPressed: _pickPreset,
                          icon: const Icon(Icons.palette_outlined)))),
            if (clientProfile != null)
              Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                      radius: 16,
                      child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          onPressed: _pickClientAvatar,
                          icon: const Icon(Icons.camera_alt)))),
          ]),
          const SizedBox(height: 12),
          Text(clientProfile == null ? 'Crea tu perfil' : 'Tu perfil',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          TextField(
              controller: name,
              decoration: const InputDecoration(
                  labelText: 'Nombre', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 12),
          TextField(
              controller: tastes,
              decoration: const InputDecoration(
                  labelText: 'Gustos musicales',
                  hintText: 'Norteño, banda, mariachi')),
          const SizedBox(height: 12),
          TextField(
              controller: favorites,
              decoration: const InputDecoration(labelText: 'Grupos favoritos')),
          const SizedBox(height: 18),
          FilledButton.icon(
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: () async {
              final saved = await widget.api.put('/api/clients/me', {
                'name': name.text,
                'musical_tastes': tastes.text.split(','),
                'favorite_groups': favorites.text.split(','),
              }) as Map<String, dynamic>;
              clientProfile = saved;
              if (!sheetContext.mounted || !mounted) return;
              Navigator.pop(sheetContext);
              setState(() {});
              ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(
                  content:
                      Text('Perfil guardado. Ya puedes agregar tu foto.')));
            },
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Guardar mi perfil'),
          ),
        ])),
      ),
    );
    name.dispose();
    tastes.dispose();
    favorites.dispose();
  }
}
