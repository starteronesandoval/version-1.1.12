import 'dart:math';

import 'package:flutter/material.dart';

import '../api_service.dart';
import 'glass_ui.dart';

class AdminMessenger extends StatefulWidget {
  const AdminMessenger({super.key, required this.api});

  final ApiService api;

  @override
  State<AdminMessenger> createState() => _AdminMessengerState();
}

class _AdminMessengerState extends State<AdminMessenger> {
  final title = TextEditingController();
  final body = TextEditingController();
  List<Map<String, dynamic>> recipients = [];
  Map<String, dynamic>? selected;
  bool allUsers = true;
  bool loading = true;
  bool sending = false;
  String? error;
  String? pendingMessageId;

  @override
  void initState() {
    super.initState();
    _loadRecipients();
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> _loadRecipients() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result =
          await widget.api.get('/api/notifications/admin/recipients') as List;
      if (mounted) {
        setState(() => recipients = result.cast<Map<String, dynamic>>());
      }
    } on ApiException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _recipientLabel(Map<String, dynamic> recipient) {
    final name = recipient['name']?.toString() ?? 'Usuario';
    final email = recipient['email']?.toString() ?? '';
    return '$name · $email';
  }

  Future<void> _chooseRecipient() async {
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecipientPicker(recipients: recipients),
    );
    if (chosen != null && mounted) {
      setState(() {
        selected = chosen;
        pendingMessageId = null;
      });
    }
  }

  String _newMessageId() {
    final random = Random.secure();
    return '${DateTime.now().microsecondsSinceEpoch}'
        '${List.generate(4, (_) => random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')).join()}';
  }

  Future<void> _send() async {
    final subject = title.text.trim();
    final message = body.text.trim();
    if (subject.length < 3 ||
        subject.length > 120 ||
        message.length < 5 ||
        message.length > 250) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Escribe un título y un mensaje de hasta 250 caracteres.',
          ),
        ),
      );
      return;
    }
    if (!allUsers && selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige primero un destinatario.')),
      );
      return;
    }
    final destination =
        allUsers
            ? 'todos los ${recipients.length} usuarios activos'
            : _recipientLabel(selected!);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Enviar notificación'),
            content: Text('Para: $destination\n\n$subject\n\n$message'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Enviar'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => sending = true);
    pendingMessageId ??= _newMessageId();
    try {
      final result =
          await widget.api.post('/api/notifications/admin/send', {
                'message_id': pendingMessageId,
                'title': subject,
                'body': message,
                if (!allUsers) 'recipient_user_id': selected!['id'],
              })
              as Map<String, dynamic>;
      if (!mounted) return;
      title.clear();
      body.clear();
      pendingMessageId = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Aviso guardado para ${result['recipient_count']} usuario(s); '
            '${result['queued_devices']} teléfono(s) con envío programado.',
          ),
        ),
      );
    } on ApiException catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(exception.message)));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _loadRecipients,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Mensajes y avisos',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Los avisos llegan a la bandeja de la app y al teléfono cuando el usuario tiene notificaciones habilitadas.',
              ),
              const SizedBox(height: 20),
              if (loading) const Center(child: CircularProgressIndicator()),
              if (error != null) ...[
                Text(error!),
                TextButton(
                  onPressed: _loadRecipients,
                  child: const Text('Reintentar'),
                ),
              ],
              if (!loading && error == null) ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Todos'),
                      icon: Icon(Icons.campaign_outlined),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Uno'),
                      icon: Icon(Icons.person_outline),
                    ),
                  ],
                  selected: {allUsers},
                  onSelectionChanged:
                      (choice) => setState(() {
                        allUsers = choice.first;
                        pendingMessageId = null;
                      }),
                ),
                const SizedBox(height: 12),
                if (allUsers)
                  Text('Destinatarios: ${recipients.length} usuarios activos')
                else
                  OutlinedButton.icon(
                    onPressed: _chooseRecipient,
                    icon: const Icon(Icons.search),
                    label: Text(
                      selected == null
                          ? 'Elegir usuario'
                          : _recipientLabel(selected!),
                    ),
                  ),
                const SizedBox(height: 18),
                TextField(
                  controller: title,
                  maxLength: 120,
                  onChanged: (_) => pendingMessageId = null,
                  decoration: const InputDecoration(
                    labelText: 'Título de la notificación',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: body,
                  maxLength: 250,
                  maxLines: 5,
                  minLines: 3,
                  onChanged: (_) => pendingMessageId = null,
                  decoration: const InputDecoration(labelText: 'Mensaje'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: sending || recipients.isEmpty ? null : _send,
                  icon: const Icon(Icons.send_outlined),
                  label: Text(sending ? 'Enviando…' : 'Revisar y enviar'),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _RecipientPicker extends StatefulWidget {
  const _RecipientPicker({required this.recipients});

  final List<Map<String, dynamic>> recipients;

  @override
  State<_RecipientPicker> createState() => _RecipientPickerState();
}

class _RecipientPickerState extends State<_RecipientPicker> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String _label(Map<String, dynamic> recipient) {
    final name = recipient['name']?.toString() ?? 'Usuario';
    final email = recipient['email']?.toString() ?? '';
    return '$name · $email';
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final matches = widget.recipients
        .where((recipient) => _label(recipient).toLowerCase().contains(query))
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          20,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              const Text('Elegir destinatario',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Buscar por nombre o correo',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final recipient = matches[index];
                    return ListTile(
                      title: Text(recipient['name']?.toString() ?? 'Usuario'),
                      subtitle: Text(recipient['email']?.toString() ?? ''),
                      trailing: Icon(recipient['push_enabled'] == true
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined),
                      onTap: () => Navigator.of(context).pop(recipient),
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
}
