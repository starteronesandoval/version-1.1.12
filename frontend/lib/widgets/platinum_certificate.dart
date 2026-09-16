import 'package:flutter/material.dart';
import '../api_service.dart';

class PlatinumBadge extends StatelessWidget {
  const PlatinumBadge({super.key, required this.api, required this.group});
  final ApiService api;
  final Map<String, dynamic> group;
  @override
  Widget build(BuildContext context) {
    if (group['platinum_certificate'] == null) return const SizedBox.shrink();
    return Tooltip(
      message: 'Ver certificado de Agrupación Platino',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap:
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder:
                    (_) => PlatinumCertificatePage(
                      api: api,
                      musicianId: group['id'] as int,
                    ),
              ),
            ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE9EEF5), Color(0xFFB8C5D5), Color(0xFFF4F7FB)],
            ),
            border: Border.all(color: const Color(0xFF8596AC)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                size: 18,
                color: Color(0xFF25364C),
              ),
              SizedBox(width: 4),
              Text(
                'Platino',
                style: TextStyle(
                  color: Color(0xFF25364C),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlatinumCertificatePage extends StatefulWidget {
  const PlatinumCertificatePage({
    super.key,
    required this.api,
    required this.musicianId,
  });
  final ApiService api;
  final int musicianId;
  @override
  State<PlatinumCertificatePage> createState() =>
      _PlatinumCertificatePageState();
}

class _PlatinumCertificatePageState extends State<PlatinumCertificatePage> {
  Map<String, dynamic>? certificate;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result =
          await widget.api.get('/api/musicians/${widget.musicianId}/platinum')
              as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          certificate = result;
          error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Certificado Platino')),
    body:
        error != null
            ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: load,
                      child: const Text('Actualizar'),
                    ),
                  ],
                ),
              ),
            )
            : certificate == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF142033),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFC9D4E2), width: 2),
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Color(0xFFE9EEF5),
                    fontSize: 15,
                    height: 1.6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.workspace_premium_rounded,
                        color: Color(0xFFE0E7EF),
                        size: 76,
                      ),
                      const Text(
                        'GARIBALDI',
                        textAlign: TextAlign.center,
                        style: TextStyle(letterSpacing: 4, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Agrupación Platino',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        certificate!['group_name'].toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Divider(height: 36, color: Color(0xFF8596AC)),
                      const Text(
                        'Recomendación de la administración',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        certificate!['recommendation'].toString(),
                        style: const TextStyle(
                          color: Color(0xFFE9EEF5),
                          height: 1.6,
                        ),
                      ),
                      const Divider(height: 36, color: Color(0xFF8596AC)),
                      Text(
                        certificate!['verification_method'] == 'in_person'
                            ? 'Verificación presencial'
                            : 'Verificación administrativa',
                      ),
                      Text(
                        'Fecha de verificación: ${certificate!['verified_on']}',
                      ),
                      const Text('Emitido por la administración de Garibaldi'),
                      const SizedBox(height: 12),
                      SelectableText(
                        certificate!['certificate_code'].toString(),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFBECBDD),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
  );
}

class PlatinumEditorPage extends StatefulWidget {
  const PlatinumEditorPage({super.key, required this.api, required this.group});
  final ApiService api;
  final Map<String, dynamic> group;
  @override
  State<PlatinumEditorPage> createState() => _PlatinumEditorPageState();
}

class _PlatinumEditorPageState extends State<PlatinumEditorPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController recommendation;
  String method = 'administrative';
  DateTime verifiedOn = DateTime.now();
  bool existence = false, quality = false, commitments = false, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final previous =
        widget.group['platinum_certificate'] as Map<String, dynamic>?;
    recommendation = TextEditingController(
      text: previous?['recommendation']?.toString() ?? '',
    );
    method = previous?['verification_method']?.toString() ?? 'administrative';
    verifiedOn =
        DateTime.tryParse(previous?['verified_on']?.toString() ?? '') ??
        DateTime.now();
  }

  @override
  void dispose() {
    recommendation.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (!existence || !quality || !commitments) {
      setState(
        () => error = 'Confirma los tres criterios antes de otorgar Platino.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api
          .put('/api/admin/musicians/${widget.group['id']}/platinum', {
            'recommendation': recommendation.text.trim(),
            'verification_method': method,
            'verified_on': verifiedOn.toIso8601String().substring(0, 10),
            'existence_confirmed': existence,
            'excellent_service_confirmed': quality,
            'commitments_confirmed': commitments,
          });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> revoke() async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Retirar certificación Platino'),
            content: TextField(
              controller: reason,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Motivo administrativo',
                helperText: 'Mínimo 10 caracteres. El motivo no es público.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Retirar certificado'),
              ),
            ],
          ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted) return;
    if (text.length < 10) {
      setState(() => error = 'Describe el motivo con al menos 10 caracteres.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api.post(
        '/api/admin/musicians/${widget.group['id']}/platinum/revoke',
        {'reason': text},
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> history() async {
    try {
      final records =
          await widget.api.get(
                '/api/admin/musicians/${widget.group['id']}/platinum/history',
              )
              as List;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Historial de certificación'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (records.isEmpty)
                      const Text('Todavía no se ha emitido una certificación.'),
                    for (final record in records)
                      ListTile(
                        title: Text(
                          '${const {'issued': 'Emitido', 'updated': 'Actualizado', 'revoked': 'Retirado'}[record['action']] ?? record['action']} · ${record['created_at']}',
                        ),
                        subtitle: Text(
                          '${record['certificate_code']}\n${record['details']['reason'] ?? record['details']['recommendation'] ?? ''}',
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Certificación Platino')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.group['group_name'].toString(),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Otorga este reconocimiento únicamente después de verificar a la agrupación y su trabajo. La recomendación será pública.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: method,
            decoration: const InputDecoration(labelText: 'Cómo se verificó'),
            items: const [
              DropdownMenuItem(
                value: 'administrative',
                child: Text('Verificación administrativa'),
              ),
              DropdownMenuItem(
                value: 'in_person',
                child: Text('Verificación presencial'),
              ),
            ],
            onChanged:
                saving ? null : (value) => setState(() => method = value!),
          ),
          TextButton.icon(
            icon: const Icon(Icons.event),
            label: Text(
              'Verificado el ${verifiedOn.toIso8601String().substring(0, 10)}',
            ),
            onPressed:
                saving
                    ? null
                    : () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: verifiedOn,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (date != null && mounted) {
                        setState(() => verifiedOn = date);
                      }
                    },
          ),
          CheckboxListTile(
            value: existence,
            onChanged:
                saving ? null : (value) => setState(() => existence = value!),
            title: const Text(
              'Confirmo que la agrupación existe y está activa',
            ),
          ),
          CheckboxListTile(
            value: quality,
            onChanged:
                saving ? null : (value) => setState(() => quality = value!),
            title: const Text('Verifiqué que ofrece un servicio excelente'),
          ),
          CheckboxListTile(
            value: commitments,
            onChanged:
                saving ? null : (value) => setState(() => commitments = value!),
            title: const Text(
              'Confirmo que cumple cabalmente sus compromisos como agrupación',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: recommendation,
            enabled: !saving,
            minLines: 10,
            maxLines: 24,
            maxLength: 12000,
            decoration: const InputDecoration(
              labelText: 'Recomendación extensa de la administración',
              alignLabelWithHint: true,
              helperText:
                  'De 300 a 12,000 caracteres. Describe únicamente lo que verificaste.',
            ),
            validator:
                (value) =>
                    (value?.trim().length ?? 0) < 300
                        ? 'Escribe una recomendación de al menos 300 caracteres.'
                        : null,
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          FilledButton.icon(
            onPressed: saving ? null : save,
            icon: const Icon(Icons.workspace_premium_rounded),
            label: Text(saving ? 'Guardando…' : 'Confirmar Agrupación Platino'),
          ),
          if (widget.group['platinum_certificate'] != null)
            TextButton(
              onPressed: saving ? null : revoke,
              child: const Text('Retirar certificación Platino'),
            ),
          TextButton(
            onPressed: saving ? null : history,
            child: const Text('Ver historial'),
          ),
        ],
      ),
    ),
  );
}
