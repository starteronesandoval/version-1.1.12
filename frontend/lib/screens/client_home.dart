import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_service.dart';
import '../widgets/booking_chat_sheet.dart';
import '../widgets/booking_review_sheet.dart';
import '../widgets/glass_ui.dart';
import 'rhythm_game_screen.dart';

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
  bool profileLoading = true;
  Timer? debounce;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await loadClientProfile();
    if (clientProfile?['profile_complete'] == true) {
      await Future.wait([load(), loadClientBookings()]);
    }
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      final query =
          Uri(
            queryParameters: {
              'q': search.text,
              if (clientProfile?['city'] != null)
                'city': clientProfile!['city'],
              if (clientProfile?['municipality'] != null)
                'municipality': clientProfile!['municipality'],
              if (clientProfile?['state'] != null)
                'state': clientProfile!['state'],
            },
          ).query;
      results = await widget.api.get('/api/musicians?$query');
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      _showConnectionError();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      _showConnectionError();
    } finally {
      if (mounted) setState(() => profileLoading = false);
    }
  }

  Future<void> loadClientBookings() async {
    try {
      bookings =
          await widget.api.get('/api/clients/me/bookings') as List<dynamic>;
      if (mounted) setState(() {});
    } on ApiException catch (error) {
      if (error.statusCode != 409 && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      _showConnectionError();
    }
  }

  void _showConnectionError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No se pudo conectar con Balam. Verifica que el servidor esté encendido.',
        ),
      ),
    );
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
          Text(
            'música para tu momento',
            style: TextStyle(fontSize: 12, color: Color(0xFFC8B5EE)),
          ),
        ],
      ),
      actions:
          clientProfile?['profile_complete'] == true
              ? [
                IconButton(
                  tooltip: 'Salto musical',
                  onPressed:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RhythmGameScreen(),
                        ),
                      ),
                  icon: const Icon(Icons.sports_esports_rounded),
                ),
                IconButton(
                  tooltip: 'Mis contratos y chats',
                  onPressed: () => _contractsSheet(context),
                  icon: Badge(
                    isLabelVisible: bookings.isNotEmpty,
                    label: Text('${bookings.length}'),
                    child: const Icon(Icons.forum_outlined),
                  ),
                ),
                IconButton(
                  tooltip: 'Contratos finalizados',
                  onPressed: () => _finishedContractsSheet(context),
                  icon: Badge(
                    isLabelVisible: bookings.any(
                      (item) => item is Map && item['event_finished'] == true,
                    ),
                    label: Text(
                      '${bookings.where((item) => item is Map && item['event_finished'] == true).length}',
                    ),
                    child: const Icon(Icons.history_rounded),
                  ),
                ),
                IconButton(
                  onPressed: () => _profileSheet(context),
                  icon: _smallAvatar(),
                ),
                IconButton(
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout),
                ),
              ]
              : [
                IconButton(
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout),
                ),
              ],
    ),
    body: GlassBackground(
      child: SafeArea(
        child:
            profileLoading
                ? const Center(child: CircularProgressIndicator())
                : clientProfile?['profile_complete'] != true
                ? _completeProfileRequired()
                : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                      child: GlassCard(
                        padding: EdgeInsets.zero,
                        child: TextField(
                          controller: search,
                          onChanged: (_) {
                            debounce?.cancel();
                            debounce = Timer(
                              const Duration(milliseconds: 350),
                              load,
                            );
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
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Agrupaciones disponibles',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${results.length}',
                            style: const TextStyle(
                              color: Color(0xFFBFA1FF),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (loading) const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                      child:
                          results.isEmpty && !loading
                              ? const Center(
                                child: Text('Aún no encontramos agrupaciones'),
                              )
                              : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  6,
                                  18,
                                  100,
                                ),
                                itemCount: results.length,
                                separatorBuilder:
                                    (_, __) => const SizedBox(height: 14),
                                itemBuilder:
                                    (_, index) => _bandCard(
                                      results[index] as Map<String, dynamic>,
                                    ),
                              ),
                    ),
                  ],
                ),
      ),
    ),
    floatingActionButton:
        clientProfile?['profile_complete'] == true
            ? FloatingActionButton.extended(
              onPressed: () => _profileSheet(context),
              icon: const Icon(Icons.person_outline),
              label: const Text('Mi perfil'),
            )
            : null,
  );

  Widget _completeProfileRequired() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.assignment_ind_outlined,
              size: 62,
              color: Color(0xFFBFA1FF),
            ),
            const SizedBox(height: 16),
            const Text(
              'Termina tu perfil',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Antes de explorar y contratar agrupaciones necesitamos tus datos de cliente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: .70)),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _profileSheet(context),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Completar mi perfil'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _smallAvatar() => ProfileAvatar(
    radius: 17,
    url: widget.api.mediaUrl(clientProfile?['avatar_url']),
    fallback: clientProfile?['name'] ?? 'C',
    preset: clientProfile?['avatar_preset'] ?? 'jaguar_guitar',
    color: clientProfile?['avatar_color'] ?? '#8B5CF6',
  );

  String _bandLocation(Map<String, dynamic> band) {
    final parts =
        [band['city'], band['municipality'], band['state']]
            .where(
              (value) => value != null && value.toString().trim().isNotEmpty,
            )
            .map((value) => value.toString())
            .toList();
    return parts.isEmpty ? 'Ubicación pendiente' : parts.join(', ');
  }

  Widget _bandCard(Map<String, dynamic> band) {
    final media =
        (band['media'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final avatar =
        media
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
            radius: 38,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        band['group_name'],
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.verified,
                      color: Color(0xFF68DDCD),
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Corriente musical: ${band['musical_style']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: .67)),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: Color(0xFF68DDCD),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _bandLocation(band),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: .62),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Icon(
                      band['rating'] == null
                          ? Icons.star_border_rounded
                          : Icons.star_rounded,
                      size: 18,
                      color: const Color(0xFFFFC857),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      band['rating'] == null
                          ? 'Sin calificaciones'
                          : '${band['rating']} (${band['review_count']})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.payments_outlined,
                      size: 17,
                      color: Color(0xFFBFA1FF),
                    ),
                    Text(
                      '  \$${band['hourly_rate']} / hora',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (band['includes_sound'])
                      const Icon(
                        Icons.speaker_group_outlined,
                        size: 19,
                        color: Color(0xFF68DDCD),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showBand(BuildContext context, Map<String, dynamic> band) {
    final media =
        (band['media'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final avatar =
        media
            .where((item) => item['media_type'] == 'profile_photo')
            .firstOrNull;
    final photos =
        media.where((item) => item['media_type'] == 'photo').toList()..sort(
          (first, second) =>
              (first['position'] as num).compareTo(second['position'] as num),
        );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1235),
      showDragHandle: true,
      builder:
          (sheetContext) => DraggableScrollableSheet(
            initialChildSize: .72,
            maxChildSize: .94,
            expand: false,
            builder:
                (_, controller) => ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
                  children: [
                    Center(
                      child: ProfileAvatar(
                        url: widget.api.mediaUrl(avatar?['url']),
                        fallback: band['group_name'],
                        preset: band['avatar_preset'] ?? 'jaguar_guitar',
                        color: band['avatar_color'] ?? '#8B5CF6',
                        radius: 56,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      band['group_name'],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Corriente musical: ${band['musical_style']}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFBFA1FF)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _bandLocation(band),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF68DDCD)),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Chip(
                        avatar: Icon(
                          band['rating'] == null
                              ? Icons.star_border_rounded
                              : Icons.star_rounded,
                          color: const Color(0xFFFFC857),
                        ),
                        label: Text(
                          band['rating'] == null
                              ? 'Aún sin calificaciones'
                              : '${band['rating']} de 5 · ${band['review_count']} ${band['review_count'] == 1 ? 'calificación' : 'calificaciones'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _miniStat(
                            '${band['member_count']}',
                            'Integrantes',
                          ),
                        ),
                        Expanded(
                          child: _miniStat(
                            '${band['audience_capacity']} personas',
                            'Sonido aproximado para',
                          ),
                        ),
                        Expanded(
                          child: _miniStat(
                            '\$${band['hourly_rate']}',
                            'Por hora',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      band['description'],
                      style: const TextStyle(height: 1.5),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (band['includes_sound'])
                          const Chip(label: Text('Sonido incluido')),
                        for (final brand in band['equipment_brands'])
                          Chip(label: Text(brand)),
                      ],
                    ),
                    if (photos.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'Galería',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final photo in photos) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: ColoredBox(
                            color: Colors.black26,
                            child: Image.network(
                              widget.api.mediaUrl(photo['url'])!,
                              width: double.infinity,
                              fit: BoxFit.fitWidth,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _availabilitySheet(band);
                      },
                      icon: const Icon(Icons.calendar_month),
                      label: const Text('Contratar / consultar fecha'),
                    ),
                  ],
                ),
          ),
    );
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
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
      builder:
          (sheetContext) => StatefulBuilder(
            builder: (_, setSheetState) {
              final available = availability?['available'] as bool?;
              final startMinutes =
                  startTime == null
                      ? null
                      : startTime!.hour * 60 + startTime!.minute;
              final endMinutes =
                  endTime == null ? null : endTime!.hour * 60 + endTime!.minute;
              final durationMinutes =
                  startMinutes == null || endMinutes == null
                      ? null
                      : endMinutes - startMinutes;
              final hourlyRateCents =
                  ((band['hourly_rate'] as num).toDouble() * 100).round();
              final subtotalCents =
                  durationMinutes != null && durationMinutes > 0
                      ? (hourlyRateCents * durationMinutes / 60).round()
                      : null;
              final totalCents = subtotalCents;
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
                        const Icon(
                          Icons.calendar_month,
                          size: 46,
                          color: Color(0xFFBFA1FF),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Consulta antes de contratar',
                          textAlign: TextAlign.center,
                          style: Theme.of(sheetContext).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Elige la fecha de tu evento para consultar a ${band['group_name']}.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .66),
                          ),
                        ),
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed:
                              checking
                                  ? null
                                  : () async {
                                    final selected = await showDatePicker(
                                      context: sheetContext,
                                      initialDate: selectedDate ?? today,
                                      firstDate: today,
                                      lastDate: today.add(
                                        const Duration(days: 730),
                                      ),
                                      helpText: 'Fecha del evento',
                                      cancelText: 'Cancelar',
                                      confirmText: 'Consultar',
                                    );
                                    if (selected == null ||
                                        !sheetContext.mounted) {
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
                                      final response =
                                          await widget.api.get(
                                                '/api/musicians/${band['id']}/availability?date=${_dateKey(selected)}',
                                              )
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
                                      ScaffoldMessenger.of(
                                        sheetContext,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(error.toString()),
                                        ),
                                      );
                                    }
                                  },
                          icon: const Icon(Icons.calendar_month),
                          label: Text(
                            selectedDate == null
                                ? 'Seleccionar fecha'
                                : _formatDate(selectedDate!),
                          ),
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
                                color:
                                    available
                                        ? const Color(0xFF68DDCD)
                                        : const Color(0xFFFF7D8C),
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  available
                                      ? Icons.event_available
                                      : Icons.event_busy,
                                  size: 42,
                                  color:
                                      available
                                          ? const Color(0xFF68DDCD)
                                          : const Color(0xFFFF7D8C),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  available
                                      ? 'Fecha disponible'
                                      : 'Fecha ocupada',
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  availability!['message'].toString(),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
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
                                      'Completa primero tu perfil de cliente.',
                                    ),
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
                          const Text(
                            'Datos del evento',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
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
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final value = await showTimePicker(
                                      context: sheetContext,
                                      initialTime:
                                          startTime ??
                                          const TimeOfDay(hour: 18, minute: 0),
                                      helpText: 'Hora de inicio',
                                    );
                                    if (value != null && sheetContext.mounted) {
                                      setSheetState(() => startTime = value);
                                    }
                                  },
                                  icon: const Icon(Icons.play_circle_outline),
                                  label: Text(
                                    startTime == null
                                        ? 'Hora inicial'
                                        : MaterialLocalizations.of(
                                          sheetContext,
                                        ).formatTimeOfDay(startTime!),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final value = await showTimePicker(
                                      context: sheetContext,
                                      initialTime:
                                          endTime ??
                                          const TimeOfDay(hour: 23, minute: 0),
                                      helpText: 'Hora final',
                                    );
                                    if (value != null && sheetContext.mounted) {
                                      setSheetState(() => endTime = value);
                                    }
                                  },
                                  icon: const Icon(Icons.stop_circle_outlined),
                                  label: Text(
                                    endTime == null
                                        ? 'Hora final'
                                        : MaterialLocalizations.of(
                                          sheetContext,
                                        ).formatTimeOfDay(endTime!),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (totalCents != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .07),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  _priceLine(
                                    'Precio final por hora',
                                    hourlyRateCents / 100,
                                  ),
                                  _priceLine(
                                    '${(durationMinutes! / 60).toStringAsFixed(durationMinutes % 60 == 0 ? 0 : 2)} horas',
                                    subtotalCents! / 100,
                                  ),
                                  const Divider(),
                                  _priceLine(
                                    'Total a pagar',
                                    totalCents / 100,
                                    strong: true,
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(54),
                            ),
                            onPressed:
                                booking
                                    ? null
                                    : () async {
                                      if (venue.text.trim().length < 3 ||
                                          startTime == null ||
                                          endTime == null) {
                                        ScaffoldMessenger.of(
                                          sheetContext,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Completa el lugar y ambos horarios.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      setSheetState(() => booking = true);
                                      try {
                                        final response =
                                            await widget.api.post(
                                                  '/api/bookings',
                                                  {
                                                    'musician_id': band['id'],
                                                    'event_date': _dateKey(
                                                      selectedDate!,
                                                    ),
                                                    'venue': venue.text.trim(),
                                                    'start_time': _apiTime(
                                                      startTime!,
                                                    ),
                                                    'end_time': _apiTime(
                                                      endTime!,
                                                    ),
                                                  },
                                                )
                                                as Map<String, dynamic>;
                                        if (!sheetContext.mounted) return;
                                        setSheetState(() {
                                          bookingResult = response;
                                          availability = null;
                                          showContractForm = false;
                                          booking = false;
                                        });
                                        try {
                                          await _openBookingCheckout(
                                            response['id'] as int,
                                          );
                                        } on ApiException catch (error) {
                                          if (sheetContext.mounted) {
                                            ScaffoldMessenger.of(
                                              sheetContext,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'La contratación quedó guardada. ${error.message}',
                                                ),
                                              ),
                                            );
                                          }
                                        }
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
                                          ScaffoldMessenger.of(
                                            sheetContext,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(error.message),
                                            ),
                                          );
                                        }
                                      }
                                    },
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(
                              booking
                                  ? 'Confirmando…'
                                  : 'Confirmar contratación',
                            ),
                          ),
                        ],
                        if (bookingResult != null) ...[
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF27AE86,
                              ).withValues(alpha: .18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF68DDCD),
                              ),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.celebration,
                                  size: 42,
                                  color: Color(0xFF68DDCD),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Contratación creada',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Completa el pago de ${band['group_name']} en Stripe.',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: () async {
                                    try {
                                      await _openBookingCheckout(
                                        bookingResult!['id'] as int,
                                      );
                                    } on ApiException catch (error) {
                                      if (sheetContext.mounted) {
                                        ScaffoldMessenger.of(
                                          sheetContext,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(error.message),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.lock_outline),
                                  label: const Text('Ir al pago seguro'),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    final confirmed = bookingResult!;
                                    Navigator.pop(sheetContext);
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (mounted) {
                                            showBookingChat(
                                              context,
                                              api: widget.api,
                                              booking: confirmed,
                                            );
                                          }
                                        });
                                  },
                                  icon: Icon(
                                    bookingResult!['chat_active'] == true
                                        ? Icons.forum_outlined
                                        : Icons.lock_clock_outlined,
                                  ),
                                  label: Text(
                                    bookingResult!['chat_active'] == true
                                        ? 'Abrir chat del evento'
                                        : 'Ver horario del chat',
                                  ),
                                ),
                              ],
                            ),
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

  Widget _priceLine(String label, double amount, {bool strong = false}) {
    final style = TextStyle(
      fontSize: strong ? 17 : 14,
      fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
      color: strong ? const Color(0xFF68DDCD) : Colors.white,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text('\$${amount.toStringAsFixed(2)} MXN', style: style),
        ],
      ),
    );
  }

  Future<void> _openBookingCheckout(int bookingId) async {
    final checkout =
        await widget.api.post('/api/billing/checkout-sessions', {
              'booking_id': bookingId,
            })
            as Map<String, dynamic>;
    final opened = await launchUrl(
      Uri.parse(checkout['url'] as String),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw ApiException('No fue posible abrir la pantalla de pago.', 0);
    }
  }

  Future<void> _reportBookingProblem(
    BuildContext dialogContext,
    Map<String, dynamic> booking,
  ) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder:
          (context) => AlertDialog(
            title: const Text('Reportar un problema'),
            content: TextField(
              controller: reason,
              minLines: 3,
              maxLines: 6,
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
    try {
      await widget.api.post('/api/bookings/${booking['id']}/dispute', {
        'reason': reason.text.trim(),
      });
      booking['payout_status'] = 'disputed';
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Liberación detenida para revisión.')),
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
    }
  }

  Future<void> _contractsSheet(BuildContext context) async {
    await loadClientBookings();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1235),
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Mis contratos',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Entra al chat privado de cada evento.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .62),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (bookings.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        'Todavía no tienes fechas contratadas.',
                        textAlign: TextAlign.center,
                      ),
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
                                Text(
                                  item['group_name'].toString(),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${_formatDate(DateTime.parse(item['event_date']))} · '
                                  '${_bookingTime(item['start_time'])}–${_bookingTime(item['end_time'])}',
                                  style: const TextStyle(
                                    color: Color(0xFF68DDCD),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(item['venue'].toString()),
                                const SizedBox(height: 5),
                                Text(
                                  item['payment_status'] == 'paid'
                                      ? 'Pago confirmado'
                                      : 'Pago pendiente · Total \$${((item['total_cents'] as num) / 100).toStringAsFixed(2)} MXN',
                                  style: TextStyle(
                                    color:
                                        item['payment_status'] == 'paid'
                                            ? const Color(0xFF68DDCD)
                                            : const Color(0xFFFFC857),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (item['payment_status'] != 'paid') ...[
                                  const SizedBox(height: 8),
                                  FilledButton.icon(
                                    onPressed: () async {
                                      try {
                                        await _openBookingCheckout(
                                          item['id'] as int,
                                        );
                                      } on ApiException catch (error) {
                                        if (sheetContext.mounted) {
                                          ScaffoldMessenger.of(
                                            sheetContext,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(error.message),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.payment),
                                    label: const Text('Pagar ahora'),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                FilledButton.tonalIcon(
                                  onPressed: () {
                                    Navigator.pop(sheetContext);
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (mounted) {
                                            showBookingChat(
                                              this.context,
                                              api: widget.api,
                                              booking: item,
                                            );
                                          }
                                        });
                                  },
                                  icon: Icon(
                                    item['chat_active'] == true
                                        ? Icons.forum_outlined
                                        : Icons.lock_clock_outlined,
                                  ),
                                  label: Text(
                                    item['chat_active'] == true
                                        ? 'Abrir chat'
                                        : 'Disponible durante el evento',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (item['event_finished'] == true &&
                                    item['payment_status'] == 'paid' &&
                                    item['payout_status'] ==
                                        'musician_funds_held') ...[
                                  OutlinedButton.icon(
                                    onPressed:
                                        () => _reportBookingProblem(
                                          sheetContext,
                                          item,
                                        ),
                                    icon: const Icon(
                                      Icons.report_problem_outlined,
                                    ),
                                    label: const Text('Reportar un problema'),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                if (item['can_review'] == true)
                                  FilledButton.icon(
                                    onPressed: () async {
                                      final result = await showModalBottomSheet<
                                        Map<String, dynamic>
                                      >(
                                        context: sheetContext,
                                        isScrollControlled: true,
                                        backgroundColor: const Color(
                                          0xFF1C1235,
                                        ),
                                        showDragHandle: true,
                                        builder:
                                            (_) => BookingReviewSheet(
                                              api: widget.api,
                                              booking: item,
                                            ),
                                      );
                                      if (result != null) {
                                        item['can_review'] = false;
                                        item['review_score'] =
                                            result['overall_score'];
                                        item['review_status'] =
                                            'Ya calificaste este evento.';
                                        item['payout_status'] =
                                            'approved_for_payout';
                                        if (mounted) setState(() {});
                                      }
                                    },
                                    icon: const Icon(Icons.star_rounded),
                                    label: const Text('Calificar agrupación'),
                                  )
                                else
                                  Row(
                                    children: [
                                      Icon(
                                        item['review_score'] != null
                                            ? Icons.verified_rounded
                                            : Icons.schedule_rounded,
                                        size: 18,
                                        color: const Color(0xFFFFC857),
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          item['review_score'] != null
                                              ? 'Tu calificación: ${item['review_score']} ★'
                                              : item['review_status']
                                                  .toString(),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.white.withValues(
                                              alpha: .7,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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

  Future<void> _finishedContractsSheet(BuildContext context) async {
    await loadClientBookings();
    if (!context.mounted) return;
    final finished =
        bookings
            .where((item) => item is Map && item['event_finished'] == true)
            .cast<Map<String, dynamic>>()
            .toList()
          ..sort(
            (a, b) => b['event_date'].toString().compareTo(
              a['event_date'].toString(),
            ),
          );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1235),
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Mis contratos finalizados',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Califica la experiencia que viviste con cada agrupación.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .62),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (finished.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        'Aún no tienes eventos finalizados.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: finished.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final item = finished[index];
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .10),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.event_available_rounded,
                                      color: Color(0xFF68DDCD),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        item['group_name'].toString(),
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_formatDate(DateTime.parse(item['event_date']))} · '
                                  '${_bookingTime(item['start_time'])}–${_bookingTime(item['end_time'])}',
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item['venue'].toString(),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: .68),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                if (item['event_finished'] == true &&
                                    item['payment_status'] == 'paid' &&
                                    item['payout_status'] ==
                                        'musician_funds_held') ...[
                                  OutlinedButton.icon(
                                    onPressed:
                                        () => _reportBookingProblem(
                                          sheetContext,
                                          item,
                                        ),
                                    icon: const Icon(
                                      Icons.report_problem_outlined,
                                    ),
                                    label: const Text('Reportar un problema'),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                if (item['can_review'] == true)
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size.fromHeight(48),
                                    ),
                                    onPressed: () async {
                                      final result = await showModalBottomSheet<
                                        Map<String, dynamic>
                                      >(
                                        context: sheetContext,
                                        isScrollControlled: true,
                                        backgroundColor: const Color(
                                          0xFF1C1235,
                                        ),
                                        showDragHandle: true,
                                        builder:
                                            (_) => BookingReviewSheet(
                                              api: widget.api,
                                              booking: item,
                                            ),
                                      );
                                      if (result != null) {
                                        item['can_review'] = false;
                                        item['review_score'] =
                                            result['overall_score'];
                                        item['payout_status'] =
                                            'approved_for_payout';
                                        await loadClientBookings();
                                        if (sheetContext.mounted) {
                                          Navigator.pop(sheetContext);
                                        }
                                        if (mounted) {
                                          _finishedContractsSheet(this.context);
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.star_rounded),
                                    label: const Text('Calificar agrupación'),
                                  )
                                else
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFFFC857,
                                      ).withValues(alpha: .12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      item['review_score'] != null
                                          ? 'Calificación enviada: ${item['review_score']} ★'
                                          : item['review_status'].toString(),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFFFFC857),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
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

  Widget _miniStat(String value, String label) => Column(
    children: [
      Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
      ),
      Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: Colors.white.withValues(alpha: .55),
        ),
      ),
    ],
  );

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
    try {
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (image == null) return;
      await widget.api.uploadClientAvatar(
        File(image.path),
        mimeType: image.mimeType,
      );
      await loadClientProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto de perfil actualizada.')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      _showConnectionError();
    }
  }

  Future<void> _profileSheet(BuildContext context) async {
    final name = TextEditingController(text: clientProfile?['name'] ?? '');
    final phone = TextEditingController();
    final city = TextEditingController(text: clientProfile?['city'] ?? '');
    final municipality = TextEditingController(
      text: clientProfile?['municipality'] ?? '',
    );
    final state = TextEditingController(text: clientProfile?['state'] ?? '');
    final tastes = TextEditingController(
      text: (clientProfile?['musical_tastes'] as List<dynamic>? ?? []).join(
        ', ',
      ),
    );
    final favorites = TextEditingController(
      text: (clientProfile?['favorite_groups'] as List<dynamic>? ?? []).join(
        ', ',
      ),
    );
    final savedProfile = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1235),
      showDragHandle: true,
      builder:
          (sheetContext) => Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              4,
              22,
              MediaQuery.viewInsetsOf(sheetContext).bottom + 28,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      ProfileAvatar(
                        url: widget.api.mediaUrl(clientProfile?['avatar_url']),
                        fallback: clientProfile?['name'] ?? 'C',
                        preset:
                            clientProfile?['avatar_preset'] ?? 'jaguar_guitar',
                        color: clientProfile?['avatar_color'] ?? '#8B5CF6',
                        radius: 50,
                      ),
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
                              icon: const Icon(Icons.palette_outlined),
                            ),
                          ),
                        ),
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
                              icon: const Icon(Icons.camera_alt),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    clientProfile == null ? 'Crea tu perfil' : 'Tu perfil',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (clientProfile?['admin_phone_saved'] != true) ...[
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Número celular',
                        prefixIcon: Icon(Icons.phone_outlined),
                        helperText: 'Privado; sólo para soporte administrativo',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: city,
                    decoration: const InputDecoration(
                      labelText: 'Ciudad',
                      prefixIcon: Icon(Icons.location_city_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: municipality,
                    decoration: const InputDecoration(
                      labelText: 'Municipio',
                      prefixIcon: Icon(Icons.map_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: state,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      prefixIcon: Icon(Icons.public_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tastes,
                    decoration: const InputDecoration(
                      labelText: 'Gustos musicales',
                      hintText: 'Norteño, banda, mariachi',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: favorites,
                    decoration: const InputDecoration(
                      labelText: 'Grupos favoritos',
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                    onPressed: () async {
                      if (clientProfile?['admin_phone_saved'] != true &&
                          phone.text.trim().isEmpty) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text('El número celular es obligatorio'),
                          ),
                        );
                        return;
                      }
                      if ([
                        city.text,
                        municipality.text,
                        state.text,
                      ].any((value) => value.trim().length < 2)) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Completa ciudad, municipio y estado',
                            ),
                          ),
                        );
                        return;
                      }
                      try {
                        final saved =
                            await widget.api.put('/api/clients/me', {
                                  'name': name.text,
                                  if (phone.text.trim().isNotEmpty)
                                    'admin_phone': phone.text.trim(),
                                  'city': city.text.trim(),
                                  'municipality': municipality.text.trim(),
                                  'state': state.text.trim(),
                                  'musical_tastes': tastes.text.split(','),
                                  'favorite_groups': favorites.text.split(','),
                                })
                                as Map<String, dynamic>;
                        if (!sheetContext.mounted) return;
                        Navigator.pop(sheetContext, saved);
                      } on ApiException catch (error) {
                        if (sheetContext.mounted) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(content: Text(error.message)),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Guardar mi perfil'),
                  ),
                ],
              ),
            ),
          ),
    );
    name.dispose();
    phone.dispose();
    city.dispose();
    municipality.dispose();
    state.dispose();
    tastes.dispose();
    favorites.dispose();
    if (savedProfile != null && mounted) {
      clientProfile = savedProfile;
      setState(() {});
      await Future.wait([load(), loadClientBookings()]);
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(
          content: Text('Perfil completo. Ya puedes contratar grupos.'),
        ),
      );
    }
  }
}
