import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_service.dart';
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
                    radius: 58,
                    onTap: () => pick('profile_photo', 1),
                  ),
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
