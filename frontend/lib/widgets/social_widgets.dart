import 'dart:async';
import 'package:flutter/material.dart';
import '../api_service.dart';
import 'network_video_player.dart';

class AjuaActions extends StatefulWidget {
  const AjuaActions({super.key, required this.api, required this.mediaId});
  final ApiService api;
  final int mediaId;
  @override
  State<AjuaActions> createState() => _AjuaActionsState();
}

class _AjuaActionsState extends State<AjuaActions> {
  Map<String, dynamic>? state;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await widget.api.get('/api/media/${widget.mediaId}/ajua');
      if (mounted) {
        setState(() {
          state = value as Map<String, dynamic>;
          error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> change(bool share) async {
    final active = state?[share ? 'shared' : 'active'] == true;
    if (share && !active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Compartir en mi perfil'),
              content: const Text(
                'Esta publicación aparecerá en tu perfil de Garibaldi con el nombre del grupo. Otros usuarios de Garibaldi podrán verla. Puedes quitarla cuando quieras.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Compartir'),
                ),
              ],
            ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => busy = true);
    try {
      final value = await widget.api.put(
        '/api/media/${widget.mediaId}/${share ? 'share' : 'ajua'}',
        {'active': !active},
      );
      if (mounted) setState(() => state = value as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return TextButton(onPressed: load, child: Text('$error · Reintentar'));
    }
    if (state == null) return const LinearProgressIndicator();
    final active = state!['active'] == true;
    final shared = state!['shared'] == true;
    return Wrap(
      spacing: 12,
      children: [
        TextButton.icon(
          onPressed: busy ? null : () => change(false),
          icon: Icon(
            active ? Icons.favorite : Icons.favorite_border,
            color: active ? Colors.pinkAccent : null,
          ),
          label: Text('Ajua · ${state!['count']}'),
        ),
        TextButton.icon(
          onPressed: busy ? null : () => change(true),
          icon: Icon(shared ? Icons.check_circle : Icons.share_outlined),
          label: Text(
            shared ? 'Quitar de mi perfil' : 'Compartir en mi perfil',
          ),
        ),
      ],
    );
  }
}

Widget socialMedia(ApiService api, Map<String, dynamic> item) =>
    item['media_type'] == 'video'
        ? NetworkVideoPlayer(url: api.mediaUrl(item['url'])!)
        : Image.network(
          api.mediaUrl(item['url'])!,
          fit: BoxFit.contain,
          errorBuilder:
              (_, _, _) => const Text('La imagen no está disponible.'),
        );

class SharedProfilePage extends StatefulWidget {
  const SharedProfilePage({
    super.key,
    required this.api,
    required this.clientId,
    this.openGroup,
  });
  final ApiService api;
  final int clientId;
  final void Function(BuildContext, Map<String, dynamic>)? openGroup;
  @override
  State<SharedProfilePage> createState() => _SharedProfilePageState();
}

class _SharedProfilePageState extends State<SharedProfilePage> {
  final List<Map<String, dynamic>> items = [];
  String name = '';
  String? error;
  bool loading = false, more = true, owner = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool refresh = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data =
          await widget.api.get(
                '/api/clients/${widget.clientId}/shared-media?offset=${refresh ? 0 : items.length}',
              )
              as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        if (refresh) items.clear();
        final next = (data['items'] as List).cast<Map<String, dynamic>>();
        items.addAll(next);
        more = next.length == 20;
        name = data['client_name'] as String;
        owner = data['owner'] == true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> remove(Map<String, dynamic> item) async {
    try {
      await widget.api.put('/api/media/${item['id']}/share', {'active': false});
      await load(refresh: true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> original(Map<String, dynamic> item) async {
    try {
      final group =
          await widget.api.get('/api/musicians/${item['musician_id']}')
              as Map<String, dynamic>;
      if (!mounted) return;
      if (widget.openGroup != null) {
        widget.openGroup!(context, group);
        return;
      }
      await showDialog<void>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(group['group_name'].toString()),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(group['description'].toString()),
                    socialMedia(widget.api, item),
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        name.isEmpty ? 'Publicaciones compartidas' : 'Perfil de $name',
      ),
    ),
    body: RefreshIndicator(
      onRefresh: () => load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Publicaciones compartidas',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          if (items.isEmpty && !loading && error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Todavía no hay fotos ni videos compartidos.'),
            ),
          for (final item in items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextButton.icon(
                      onPressed: () => original(item),
                      icon: const Icon(Icons.music_note),
                      label: Text('Original de ${item['group_name']}'),
                    ),
                    socialMedia(widget.api, item),
                    if (owner)
                      TextButton.icon(
                        onPressed: loading ? null : () => remove(item),
                        icon: const Icon(Icons.remove_circle_outline),
                        label: const Text('Quitar de mi perfil'),
                      ),
                  ],
                ),
              ),
            ),
          if (loading) const Center(child: CircularProgressIndicator()),
          if (error != null)
            TextButton(
              onPressed: () => load(),
              child: Text('$error · Reintentar'),
            ),
          if (more && !loading && error == null)
            TextButton(
              onPressed: () => load(),
              child: const Text('Cargar más'),
            ),
        ],
      ),
    ),
  );
}

class AjuaInbox extends StatefulWidget {
  const AjuaInbox({super.key, required this.api});
  final ApiService api;
  @override
  State<AjuaInbox> createState() => _AjuaInboxState();
}

class _AjuaInboxState extends State<AjuaInbox> {
  Timer? timer;
  List<Map<String, dynamic>> items = [];
  bool loading = false;
  String? error;
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
    if (loading) return;
    loading = true;
    try {
      final result =
          await widget.api.get('/api/musicians/me/ajua-notifications') as List;
      if (mounted) {
        setState(() {
          items = result.cast<Map<String, dynamic>>();
          error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      loading = false;
    }
  }

  Future<void> open(Map<String, dynamic> item) async {
    try {
      await widget.api.put(
        '/api/musicians/me/ajua-notifications/${item['id']}/read',
        {},
      );
      if (!mounted) return;
      setState(() => item['read'] = true);
      await showDialog<void>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text('${item['client_name']} dijo ¡Ajua!'),
              content: SingleChildScrollView(
                child: socialMedia(widget.api, item),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.of(this.context).push(
                      MaterialPageRoute<void>(
                        builder:
                            (_) => SharedProfilePage(
                              api: widget.api,
                              clientId: item['client_id'] as int,
                            ),
                      ),
                    );
                  },
                  child: const Text('Ver perfil del cliente'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      leading: const Icon(Icons.notifications_active_outlined),
      title: Text(
        'Ajua · ${items.where((item) => item['read'] != true).length} nuevos',
      ),
      subtitle: const Text('Reacciones a tus fotos y videos'),
      children: [
        if (error != null)
          TextButton(onPressed: load, child: Text('$error · Reintentar')),
        if (items.isEmpty && error == null)
          const ListTile(
            title: Text('Aquí recibirás los Ajua de tus clientes.'),
          ),
        for (final item in items)
          ListTile(
            leading: Icon(
              item['read'] == true ? Icons.favorite_border : Icons.favorite,
              color: Colors.pinkAccent,
            ),
            title: Text('${item['client_name']} dijo ¡Ajua!'),
            subtitle: Text(
              item['media_type'] == 'video' ? 'En tu video' : 'En tu foto',
            ),
            onTap: () => open(item),
          ),
      ],
    ),
  );
}
