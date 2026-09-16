import 'dart:async';
import 'package:flutter/material.dart';
import '../api_service.dart';
import 'platinum_certificate.dart';
import 'social_widgets.dart';

class PlatinumRequestCard extends StatefulWidget {
  const PlatinumRequestCard({
    super.key,
    required this.api,
    required this.group,
    required this.onChanged,
  });
  final ApiService api;
  final Map<String, dynamic> group;
  final VoidCallback onChanged;
  @override
  State<PlatinumRequestCard> createState() => _PlatinumRequestCardState();
}

class _PlatinumRequestCardState extends State<PlatinumRequestCard> {
  Map<String, dynamic>? request;
  String? error;
  bool loading = false, sending = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (loading || sending) return;
    loading = true;
    try {
      final data =
          await widget.api.get('/api/musicians/me/platinum-request')
              as Map<String, dynamic>;
      if (!mounted) return;
      final changed = request != null && request!['status'] != data['status'];
      setState(() {
        request = data;
        error = null;
      });
      if (changed) widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      loading = false;
    }
  }

  Future<void> submit() async {
    final message = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Solicitar certificación Platino'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'La administración revisará tu agrupación y podrá coordinar una verificación presencial. Solo el administrador puede activar tu medalla.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: message,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Mensaje al administrador (opcional)',
                      hintText:
                          'Cuéntanos sobre tu agrupación y tu disponibilidad para una revisión.',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Enviar solicitud'),
              ),
            ],
          ),
    );
    final text = message.text.trim();
    message.dispose();
    if (send != true || !mounted) return;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final data =
          await widget.api.post('/api/musicians/me/platinum-request', {
                'message': text,
              })
              as Map<String, dynamic>;
      if (mounted) setState(() => request = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = request?['status'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Certificación Platino',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (status == 'certified') ...[
              const Text('Tu agrupación tiene Platino activo.'),
              Align(
                alignment: Alignment.centerLeft,
                child: PlatinumBadge(
                  api: widget.api,
                  group: {
                    ...widget.group,
                    'platinum_certificate': request!['certificate'],
                  },
                ),
              ),
            ] else if (status == 'pending') ...[
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.hourglass_top),
                title: Text('Solicitud enviada'),
                subtitle: Text('Pendiente de revisión por el administrador.'),
              ),
              if ((request?['message']?.toString() ?? '').isNotEmpty)
                Text(request!['message'].toString()),
            ] else if (request != null) ...[
              const Text(
                'Destaca a tu agrupación con la medalla Platino. Solicita la revisión de tu existencia, calidad de servicio y cumplimiento.',
              ),
              if (status == 'rejected' || status == 'revoked') ...[
                const SizedBox(height: 8),
                Text(
                  request?['response']?.toString() ??
                      'La administración solicita una nueva revisión.',
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: sending ? null : submit,
                icon: const Icon(Icons.workspace_premium_outlined),
                label: Text(
                  sending
                      ? 'Enviando…'
                      : status == 'not_requested'
                      ? 'Solicitar Platino'
                      : 'Solicitar nueva revisión',
                ),
              ),
            ],
            if (request == null && error == null)
              const LinearProgressIndicator(),
            if (error != null)
              TextButton(onPressed: load, child: Text('$error · Actualizar')),
          ],
        ),
      ),
    );
  }
}

class PlatinumReviewPage extends StatefulWidget {
  const PlatinumReviewPage({super.key, required this.api, required this.group});
  final ApiService api;
  final Map<String, dynamic> group;
  @override
  State<PlatinumReviewPage> createState() => _PlatinumReviewPageState();
}

class _PlatinumReviewPageState extends State<PlatinumReviewPage> {
  bool saving = false;
  String? error;
  String get draft =>
      'La administración de Garibaldi otorga a ${widget.group['group_name'].toString().trim()} '
      'el reconocimiento de Agrupación Platino y recomienda su propuesta musical a los clientes de la plataforma. '
      'Mediante esta certificación, la administración confirma que verificó la existencia y actividad de la agrupación, '
      'valoró favorablemente la calidad de su servicio y reconoció su cumplimiento de los compromisos como equipo de trabajo.\n\n'
      'Este reconocimiento destaca su seriedad frente al cliente y su compromiso con un servicio excelente. '
      'La recomendación se emite después de la revisión y aprobación manual de la administración de Garibaldi.';
  Future<void> activatePlatinum() async {
    final recommendation = TextEditingController(text: draft);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Activar Platino'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Al confirmar, certificas que ${widget.group['group_name']} existe, trabaja con excelencia y cumple sus compromisos. La medalla será visible para los clientes.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: recommendation,
                    minLines: 5,
                    maxLines: 12,
                    maxLength: 12000,
                    decoration: const InputDecoration(
                      labelText: 'Recomendación pública (puedes editarla)',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmar y activar'),
              ),
            ],
          ),
    );
    final text = recommendation.text.trim();
    recommendation.dispose();
    if (confirmed != true || !mounted) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api
          .put('/api/admin/musicians/${widget.group['id']}/platinum', {
            'recommendation': text,
            'verification_method': 'administrative',
            'verified_on': DateTime.now().toIso8601String().substring(0, 10),
            'existence_confirmed': true,
            'excellent_service_confirmed': true,
            'commitments_confirmed': true,
          });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> reject() async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Responder a la agrupación'),
            content: TextField(
              controller: reason,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Qué falta para obtener Platino',
                helperText:
                    'Mínimo 10 caracteres. La agrupación verá este mensaje.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('No aprobar por ahora'),
              ),
            ],
          ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api.post(
        '/api/admin/musicians/${widget.group['id']}/platinum-request/reject',
        {'reason': text},
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final request = group['platinum_request'] as Map<String, dynamic>?;
    final media = (group['media'] as List? ?? []).cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(title: const Text('Revisar agrupación')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            group['group_name'].toString(),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          PlatinumBadge(api: widget.api, group: group),
          Text('${group['group_type']} · ${group['musical_style']}'),
          Text(
            [
              group['city'],
              group['municipality'],
              group['state'],
            ].where((value) => value != null).join(', '),
          ),
          Text('${group['member_count']} integrantes'),
          if (group['admin_phone'] != null)
            SelectableText('Contacto: ${group['admin_phone']}'),
          const SizedBox(height: 12),
          Text(group['description']?.toString() ?? ''),
          if (request?['status'] == 'pending')
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Solicitud pendiente',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('Recibida: ${request!['submitted_at']}'),
                    Text(
                      request['message']?.toString().isNotEmpty == true
                          ? request['message'].toString()
                          : 'La agrupación solicita su verificación Platino.',
                    ),
                  ],
                ),
              ),
            ),
          if (group['can_manage_platinum'] == true) ...[
            const SizedBox(height: 16),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.redAccent)),
            if (group['platinum_certificate'] == null)
              FilledButton.icon(
                onPressed: saving ? null : activatePlatinum,
                icon: const Icon(Icons.workspace_premium_rounded),
                label: Text(saving ? 'Guardando…' : 'Activar Platino'),
              ),
            OutlinedButton(
              onPressed:
                  saving
                      ? null
                      : () async {
                        final changed = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder:
                                (_) => PlatinumEditorPage(
                                  api: widget.api,
                                  group: group,
                                ),
                          ),
                        );
                        if (changed == true && context.mounted) {
                          Navigator.pop(context, true);
                        }
                      },
              child: Text(
                group['platinum_certificate'] != null
                    ? 'Gestionar certificado'
                    : 'Recomendación detallada o visita presencial',
              ),
            ),
            if (request?['status'] == 'pending')
              TextButton(
                onPressed: saving ? null : reject,
                child: const Text('Solicitar mejoras antes de aprobar'),
              ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Fotos y videos del perfil',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (media.isEmpty)
            const Text('La agrupación todavía no ha publicado fotos o videos.'),
          for (final item in media)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: socialMedia(widget.api, item),
            ),
        ],
      ),
    );
  }
}
