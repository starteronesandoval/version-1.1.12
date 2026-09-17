import 'package:flutter/material.dart';

import '../api_service.dart';

class NotificationInboxButton extends StatelessWidget {
  const NotificationInboxButton({super.key, required this.api});

  final ApiService api;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Avisos',
    icon: const Icon(Icons.notifications_outlined),
    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NotificationInboxScreen(api: api),
    )),
  );
}

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({super.key, required this.api});
  final ApiService api;

  @override
  State<NotificationInboxScreen> createState() => _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  List<dynamic> notices = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      notices = await widget.api.get('/api/notifications') as List<dynamic>;
    } catch (_) {
      error = 'No pudimos cargar los avisos. Inténtalo de nuevo.';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _read(Map<String, dynamic> notice) async {
    if (notice['read'] == true) return;
    try {
      await widget.api.put('/api/notifications/${notice['id']}/read', {});
      if (mounted) setState(() => notice['read'] = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pudimos marcar el aviso como leído.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Avisos')),
    body: RefreshIndicator(
      onRefresh: _load,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? ListView(children: [
              const SizedBox(height: 40),
              Center(child: Text(error!)),
              TextButton(onPressed: _load, child: const Text('Reintentar')),
            ])
          : notices.isEmpty
          ? ListView(children: const [
              SizedBox(height: 80),
              Center(child: Text('Todavía no tienes avisos.')),
            ])
          : ListView.builder(
              itemCount: notices.length,
              itemBuilder: (context, index) {
                final notice = notices[index] as Map<String, dynamic>;
                return ListTile(
                  leading: Icon(notice['kind'] == 'payment'
                      ? Icons.payments_outlined
                      : notice['kind'] == 'ajua'
                      ? Icons.favorite_outline
                      : notice['kind'] == 'share'
                      ? Icons.share_outlined
                      : notice['kind'] == 'message'
                      ? Icons.chat_bubble_outline
                      : Icons.event_available_outlined),
                  title: Text(notice['title']?.toString() ?? ''),
                  subtitle: Text(notice['body']?.toString() ?? ''),
                  trailing: notice['read'] == true
                      ? null : const Icon(Icons.circle, size: 9),
                  onTap: () => _read(notice),
                );
              },
            ),
    ),
  );
}
