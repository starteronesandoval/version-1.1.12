import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_service.dart';
import '../widgets/booking_chat_sheet.dart';
import '../widgets/glass_ui.dart';

class MusicianProfileScreen extends StatefulWidget {
  const MusicianProfileScreen(
      {super.key, required this.api, required this.onLogout});
  final ApiService api;
  final VoidCallback onLogout;
  @override
  State<MusicianProfileScreen> createState() => _MusicianProfileScreenState();
}

class _MusicianProfileScreenState extends State<MusicianProfileScreen> {
  final form = GlobalKey<FormState>();
  final picker = ImagePicker();
  final fields = <String, TextEditingController>{
    for (final key in [
      'contact_name',
      'group_name',
      'group_type',
      'musical_style',
      'member_count',
      'hourly_rate',
      'subwoofer_count',
      'mid_speaker_count',
      'equipment_brands',
      'audience_capacity',
      'description',
    ])
      key: TextEditingController(),
  };
  Map<String, dynamic>? profile;
  bool sound = false;
  bool busy = false;
  bool loading = true;
  bool editing = false;
  final Set<String> busyDates = {};
  List<dynamic> bookings = [];

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    try {
      final data =
          await widget.api.get('/api/musicians/me') as Map<String, dynamic>;
      _fill(data);
      profile = data;
      editing = false;
      await Future.wait([_loadBusyDates(), _loadBookings()]);
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        editing = true;
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadBusyDates() async {
    final response =
        await widget.api.get('/api/musicians/me/busy-dates') as List<dynamic>;
    busyDates
      ..clear()
      ..addAll(response.map((item) => item['date'].toString()));
  }

  Future<void> _loadBookings() async {
    bookings =
        await widget.api.get('/api/musicians/me/bookings') as List<dynamic>;
  }

  String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _formatDate(String value) {
    final parsed = DateTime.parse(value);
    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  String _formatTime(dynamic value) {
    final text = value.toString();
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  Future<void> _openBusyCalendar() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var selected = today;
    var saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1235),
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) {
          final key = _dateKey(selected);
          final isBusy = busyDates.contains(key);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Agenda de la agrupación',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      'Selecciona un día para marcarlo como ocupado o volver a liberarlo.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Colors.white.withValues(alpha: .65)),
                    ),
                    const SizedBox(height: 14),
                    Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                              primary: isBusy
                                  ? const Color(0xFFE65A69)
                                  : const Color(0xFF55D6C2),
                            ),
                      ),
                      child: CalendarDatePicker(
                        initialDate: selected,
                        firstDate: today,
                        lastDate: today.add(const Duration(days: 730)),
                        onDateChanged: (value) =>
                            setSheetState(() => selected = value),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: (isBusy
                                ? const Color(0xFFE65A69)
                                : const Color(0xFF55D6C2))
                            .withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(children: [
                        Icon(isBusy ? Icons.event_busy : Icons.event_available,
                            color: isBusy
                                ? const Color(0xFFFF8A96)
                                : const Color(0xFF68DDCD)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(isBusy
                              ? 'Este día está marcado como ocupado.'
                              : 'Este día está libre.'),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: isBusy
                              ? const Color(0xFF3D8E80)
                              : const Color(0xFFB53F51)),
                      onPressed: saving
                          ? null
                          : () async {
                              setSheetState(() => saving = true);
                              try {
                                await widget.api.put(
                                    '/api/musicians/me/busy-dates/$key',
                                    {'busy': !isBusy});
                                if (!sheetContext.mounted) return;
                                if (isBusy) {
                                  busyDates.remove(key);
                                } else {
                                  busyDates.add(key);
                                }
                                if (mounted) setState(() {});
                                setSheetState(() => saving = false);
                              } catch (error) {
                                if (!sheetContext.mounted) return;
                                setSheetState(() => saving = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(error.toString())));
                                }
                              }
                            },
                      icon: Icon(
                          isBusy ? Icons.event_available : Icons.event_busy),
                      label: Text(saving
                          ? 'Guardando…'
                          : isBusy
                              ? 'Liberar esta fecha'
                              : 'Marcar como ocupado'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _fill(Map<String, dynamic> data) {
    for (final entry in fields.entries) {
      final value = data[entry.key];
      entry.value.text =
          value is List ? value.join(', ') : value?.toString() ?? '';
    }
    sound = data['includes_sound'] as bool? ?? false;
  }

  bool numeric(String key) => const {
        'member_count',
        'hourly_rate',
        'subwoofer_count',
        'mid_speaker_count',
        'audience_capacity',
      }.contains(key);

  String label(String key) => const {
        'contact_name': 'Nombre de contacto',
        'group_name': 'Nombre de la agrupación',
        'group_type': 'Tipo de grupo',
        'musical_style': 'Corriente musical',
        'member_count': 'Cantidad de integrantes',
        'hourly_rate': 'Costo por hora',
        'subwoofer_count': 'Subwoofers',
        'mid_speaker_count': 'Bocinas de medios',
        'equipment_brands': 'Marcas (separadas por coma)',
        'audience_capacity': 'Capacidad de público',
        'description': 'Historia y descripción',
      }[key]!;

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final saved = await widget.api.put('/api/musicians/me', {
        for (final entry in fields.entries)
          entry.key: numeric(entry.key)
              ? (entry.key == 'hourly_rate'
                  ? double.parse(entry.value.text)
                  : int.parse(entry.value.text))
              : entry.key == 'equipment_brands'
                  ? entry.value.text.split(',')
                  : entry.value.text,
        'includes_sound': sound,
      }) as Map<String, dynamic>;
      profile = saved;
      editing = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tu perfil ya está publicado')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pick(String type, int max) async {
    final file = type == 'video'
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (file == null || !mounted) return;
    final position = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Selecciona una posición (1–$max)'),
        children: [
          for (var i = 1; i <= max; i++)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, i),
                child: Text('Posición $i')),
        ],
      ),
    );
    if (position == null) return;
    await widget.api.uploadMedia(File(file.path), type, position);
    if (!mounted) return;
    setState(() => loading = true);
    await loadProfile();
  }

  Future<void> chooseAvatar() async {
    final selection = await showAvatarPicker(
      context,
      currentPreset: profile?['avatar_preset'] ?? 'jaguar_guitar',
      currentColor: profile?['avatar_color'] ?? '#8B5CF6',
    );
    if (selection == null) return;
    await widget.api.setAvatarPreset(selection.preset, selection.color);
    if (!mounted) return;
    setState(() => loading = true);
    await loadProfile();
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Mi espacio'),
          actions: [
            if (profile != null && !editing)
              IconButton(
                  onPressed: () => setState(() => editing = true),
                  icon: const Icon(Icons.edit_outlined)),
            IconButton(
                onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
          ],
        ),
        body: GlassBackground(
          child: SafeArea(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: editing ? _editor() : _socialProfile(),
                  ),
          ),
        ),
      );

  Widget _socialProfile() {
    final data = profile!;
    final media = data['media'] as List<dynamic>? ?? [];
    final avatar = media
        .cast<Map<String, dynamic>>()
        .where((item) => item['media_type'] == 'profile_photo')
        .firstOrNull;
    final photos = media
        .cast<Map<String, dynamic>>()
        .where((item) => item['media_type'] == 'photo')
        .toList();
    final videos = media
        .cast<Map<String, dynamic>>()
        .where((item) => item['media_type'] == 'video')
        .toList();
    return ListView(
      key: const ValueKey('profile'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
      children: [
        GlassCard(
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ProfileAvatar(
                    url: widget.api.mediaUrl(avatar?['url']),
                    fallback: data['group_name'],
                    preset: data['avatar_preset'] ?? 'jaguar_guitar',
                    color: data['avatar_color'] ?? '#8B5CF6',
                    radius: 58,
                    onTap: chooseAvatar,
                  ),
                  Positioned(
                      left: -4,
                      bottom: 2,
                      child: CircleAvatar(
                          radius: 17,
                          child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 17,
                              onPressed: chooseAvatar,
                              icon: const Icon(Icons.palette_outlined)))),
                  Positioned(
                      right: -4,
                      bottom: 2,
                      child: CircleAvatar(
                          radius: 17,
                          child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 17,
                              onPressed: () => pick('profile_photo', 1),
                              icon: const Icon(Icons.camera_alt)))),
                ],
              ),
              const SizedBox(height: 16),
              Text(data['group_name'],
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text('${data['group_type']} · ${data['musical_style']}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFBFA7ED))),
              const SizedBox(height: 14),
              const Chip(
                  avatar: Icon(Icons.verified, size: 18),
                  label: Text('Agrupación disponible')),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _stat('${data['member_count']}', 'Integrantes'),
                _stat('${data['audience_capacity']}', 'Personas'),
                _stat('\$${data['hourly_rate']}', 'Por hora'),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Nuestra historia',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(data['description'],
              style: TextStyle(
                  height: 1.45, color: Colors.white.withValues(alpha: .78))),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (data['includes_sound'])
              const Chip(
                  avatar: Icon(Icons.speaker, size: 17),
                  label: Text('Incluye sonido')),
            for (final brand in data['equipment_brands'])
              Chip(label: Text(brand)),
          ]),
        ])),
        if (bookings.isNotEmpty) ...[
          const SizedBox(height: 16),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  CircleAvatar(
                    backgroundColor: Color(0x3335D8C6),
                    child: Icon(Icons.notifications_active,
                        color: Color(0xFF68DDCD)),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '¡Felicidades! Has vendido una fecha. Revisa los datos.',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                for (final item in bookings.cast<Map<String, dynamic>>()) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: .10)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_formatDate(item['event_date'].toString()),
                            style: const TextStyle(
                                color: Color(0xFF68DDCD),
                                fontWeight: FontWeight.w800,
                                fontSize: 17)),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Icon(Icons.location_on_outlined, size: 19),
                          const SizedBox(width: 7),
                          Expanded(child: Text(item['venue'].toString())),
                        ]),
                        const SizedBox(height: 7),
                        Row(children: [
                          const Icon(Icons.schedule, size: 19),
                          const SizedBox(width: 7),
                          Text(
                              '${_formatTime(item['start_time'])} – ${_formatTime(item['end_time'])}'),
                        ]),
                        const SizedBox(height: 7),
                        Row(children: [
                          const Icon(Icons.person_outline, size: 19),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                                '${item['client_name']} · ${item['client_email']}'),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: () => showBookingChat(
                            context,
                            api: widget.api,
                            booking: item,
                          ),
                          icon: Icon(item['chat_active'] == true
                              ? Icons.forum_outlined
                              : Icons.lock_clock_outlined),
                          label: Text(item['chat_active'] == true
                              ? 'Chat del evento'
                              : 'Chat disponible en el evento'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.calendar_month, color: Color(0xFFBFA1FF)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Mi calendario',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                Text('${busyDates.length} ocupados',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: .58))),
              ]),
              const SizedBox(height: 8),
              Text(
                  'Estas fechas sólo se revelan cuando un cliente consulta un día.',
                  style: TextStyle(color: Colors.white.withValues(alpha: .66))),
              if (busyDates.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: (busyDates.toList()..sort())
                      .map((day) => Chip(
                            avatar: const Icon(Icons.event_busy, size: 16),
                            label: Text(_formatDate(day)),
                            backgroundColor:
                                const Color(0xFFE65A69).withValues(alpha: .18),
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                onPressed: _openBusyCalendar,
                icon: const Icon(Icons.edit_calendar),
                label: const Text('Administrar fechas'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle(
            'Momentos', '${photos.length}/5 fotos', () => pick('photo', 5)),
        const SizedBox(height: 10),
        SizedBox(
            height: 150,
            child: photos.isEmpty
                ? _emptyMedia(Icons.photo_library_outlined,
                    'Agrega tus mejores fotografías')
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.network(
                            widget.api.mediaUrl(photos[i]['url'])!,
                            width: 190,
                            fit: BoxFit.cover)))),
        const SizedBox(height: 20),
        _sectionTitle(
            'En escena', '${videos.length}/2 videos', () => pick('video', 2)),
        const SizedBox(height: 10),
        videos.isEmpty
            ? _emptyMedia(Icons.smart_display_outlined,
                'Comparte una presentación en vivo')
            : Wrap(spacing: 10, children: [
                for (var index = 0; index < videos.length; index++)
                  GlassCard(
                      padding: const EdgeInsets.all(14),
                      child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_circle_fill),
                            SizedBox(width: 8),
                            Text('Video en vivo')
                          ]))
              ]),
      ],
    );
  }

  Widget _stat(String value, String label) => Column(children: [
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: .58))),
      ]);

  Widget _sectionTitle(String title, String counter, VoidCallback action) =>
      Row(children: [
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700))),
        Text(counter,
            style: TextStyle(color: Colors.white.withValues(alpha: .55))),
        IconButton(
            onPressed: action, icon: const Icon(Icons.add_circle_outline)),
      ]);

  Widget _emptyMedia(IconData icon, String text) => GlassCard(
        child: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 38, color: const Color(0xFFBFA1FF)),
          const SizedBox(height: 8),
          Text(text)
        ])),
      );

  Widget _editor() => Form(
        key: form,
        child: ListView(
          key: const ValueKey('editor'),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: [
            GlassCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      profile == null
                          ? 'Crea tu identidad musical'
                          : 'Edita tu perfil',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('Esta información será visible para todos los clientes.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: .65))),
                  const SizedBox(height: 20),
                  for (final entry in fields.entries) ...[
                    TextFormField(
                      controller: entry.value,
                      keyboardType: numeric(entry.key)
                          ? TextInputType.number
                          : TextInputType.text,
                      maxLines: entry.key == 'description' ? 4 : 1,
                      decoration: InputDecoration(labelText: label(entry.key)),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Campo obligatorio'
                              : null,
                    ),
                    const SizedBox(height: 13),
                  ],
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: sound,
                      onChanged: (value) => setState(() => sound = value),
                      title: const Text('Incluye equipo de sonido'),
                      secondary: const Icon(Icons.speaker_group_outlined)),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54)),
                    onPressed: busy ? null : save,
                    icon: const Icon(Icons.publish),
                    label: Text(busy ? 'Guardando…' : 'Guardar y publicar'),
                  ),
                  if (profile != null)
                    TextButton(
                        onPressed: () => setState(() => editing = false),
                        child: const Text('Cancelar')),
                ])),
          ],
        ),
      );
}
