import 'package:flutter/material.dart';

import '../api_service.dart';
import '../widgets/booking_chat_sheet.dart';
import '../widgets/glass_ui.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    required this.api,
    required this.onLogout,
  });

  final ApiService api;
  final VoidCallback onLogout;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> clients = [];
  List<Map<String, dynamic>> groups = [];
  List<Map<String, dynamic>> bookings = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final responses = await Future.wait([
        widget.api.get('/api/admin/clients'),
        widget.api.get('/api/admin/groups'),
        widget.api.get('/api/admin/bookings'),
      ]);
      clients = (responses[0] as List<dynamic>).cast<Map<String, dynamic>>();
      groups = (responses[1] as List<dynamic>).cast<Map<String, dynamic>>();
      bookings = (responses[2] as List<dynamic>).cast<Map<String, dynamic>>();
    } on ApiException catch (exception) {
      error = exception.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> payoutAction(int bookingId, String action) async {
    try {
      await widget.api.put('/api/admin/bookings/$bookingId/payout', {
        'action': action,
      });
      await load();
    } on ApiException catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(exception.message)));
      }
    }
  }

  Future<void> linkStripeAccount(Map<String, dynamic> group) async {
    final controller = TextEditingController(
      text: group['stripe_connected_account_id']?.toString() ?? '',
    );
    final save = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Vincular Stripe Connect'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'ID de cuenta conectada',
                hintText: 'acct_...',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Vincular'),
              ),
            ],
          ),
    );
    if (save == true) {
      try {
        await widget.api.put(
          '/api/admin/musicians/${group['id']}/stripe-connect',
          {'account_id': controller.text.trim()},
        );
        await load();
      } on ApiException catch (exception) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(exception.message)));
        }
      }
    }
    controller.dispose();
  }

  String label(String key) =>
      const {
        'id': 'ID',
        'user_id': 'Usuario',
        'name': 'Nombre',
        'contact_name': 'Contacto',
        'group_name': 'Agrupación',
        'account_email': 'Correo de acceso',
        'account_phone': 'Celular de acceso',
        'admin_phone': 'Celular administrativo',
        'city': 'Ciudad',
        'municipality': 'Municipio',
        'state': 'Estado',
        'musical_tastes': 'Gustos musicales',
        'favorite_groups': 'Grupos favoritos',
        'group_type': 'Tipo',
        'musical_style': 'Estilo',
        'member_count': 'Integrantes',
        'hourly_rate': 'Costo por hora',
        'includes_sound': 'Incluye sonido',
        'audience_capacity': 'Capacidad',
        'equipment_brands': 'Equipo',
        'description': 'Descripción',
        'is_active': 'Cuenta activa',
        'created_at': 'Registro',
        'review_count': 'Calificaciones',
        'rating': 'Promedio',
        'deposit_account_type': 'Tipo de depósito',
        'deposit_account': 'Cuenta para depósito',
        'stripe_connected_account_id': 'Stripe Connect',
      }[key] ??
      key;

  String value(dynamic data) {
    if (data == null) return 'Sin registrar';
    if (data is bool) return data ? 'Sí' : 'No';
    if (data is List) return data.isEmpty ? 'Ninguno' : data.join(', ');
    return data.toString();
  }

  Widget recordCard(Map<String, dynamic> item, {required String title}) {
    const omitted = {
      'media',
      'avatar_preset',
      'avatar_color',
      'profile_complete',
      'admin_phone_saved',
      'rules_acceptances',
      'user_id',
    };
    final entries = item.entries.where((entry) => !omitted.contains(entry.key));
    final rules = item['rules_acceptances'] as List<dynamic>? ?? [];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const Divider(height: 22),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 132,
                    child: Text(
                      label(entry.key),
                      style: const TextStyle(color: Color(0xFFBFA1FF)),
                    ),
                  ),
                  Expanded(child: Text(value(entry.value))),
                ],
              ),
            ),
          if (rules.isNotEmpty) ...[
            const Divider(height: 22),
            const Text(
              'Aceptaciones de reglas',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            for (final rule in rules.cast<Map<String, dynamic>>())
              Text(
                '${rule['rules_version']} · ${rule['accepted_at']} · ${rule['group_name_snapshot'] ?? title}',
              ),
          ],
          if (item['group_name'] != null) ...[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => linkStripeAccount(item),
              icon: const Icon(Icons.link),
              label: Text(
                item['stripe_connected_account_id'] == null
                    ? 'Vincular Stripe Connect'
                    : 'Cambiar cuenta Stripe Connect',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget records(
    List<Map<String, dynamic>> items,
    String empty,
    String Function(Map<String, dynamic>) title,
  ) =>
      items.isEmpty
          ? Center(child: Text(empty))
          : RefreshIndicator(
            onRefresh: load,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder:
                  (_, index) =>
                      recordCard(items[index], title: title(items[index])),
            ),
          );

  Widget contracts({
    List<Map<String, dynamic>>? source,
    bool disputesOnly = false,
  }) {
    final visible = source ?? bookings;
    return visible.isEmpty
        ? Center(
          child: Text(
            disputesOnly
                ? 'No hay disputas pendientes'
                : 'No hay contratos registrados',
          ),
        )
        : RefreshIndicator(
          onRefresh: load,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: visible.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, index) {
              final item = visible[index];
              return GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contrato #${item['id']} · ${item['group_name']}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('Cliente: ${item['client_name']}'),
                    Text('Contacto: ${item['client_email']}'),
                    Text('Evento: ${item['event_date']}'),
                    Text(
                      'Horario: ${item['start_time']} – ${item['end_time']}',
                    ),
                    Text('Lugar: ${item['venue']}'),
                    Text('Creado: ${item['created_at']}'),
                    Text('Pago del cliente: ${item['payment_status']}'),
                    Text('Liberación: ${item['payout_status']}'),
                    Text(
                      'Para el músico: \$${((item['musician_earnings_cents'] as num) / 100).toStringAsFixed(2)} MXN',
                    ),
                    Text(
                      'Ingreso Balam: \$${((item['platform_fee_cents'] as num) / 100).toStringAsFixed(2)} MXN',
                    ),
                    if (item['dispute_reason'] != null)
                      Text(
                        'Disputa: ${item['dispute_reason']}',
                        style: const TextStyle(color: Color(0xFFFFC857)),
                      ),
                    if (item['review_score'] != null)
                      Text('Calificación: ${item['review_score']} ★'),
                    if (item['review_recommendation'] != null)
                      Text('Recomendación: ${item['review_recommendation']}'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed:
                          () => showBookingChat(
                            context,
                            api: widget.api,
                            booking: item,
                          ),
                      icon: const Icon(Icons.forum_outlined),
                      label: const Text('Mensaje con cliente y agrupación'),
                    ),
                    if (item['payout_status'] == 'disputed')
                      FilledButton.tonalIcon(
                        onPressed:
                            () => payoutAction(
                              item['id'] as int,
                              'reject_dispute',
                            ),
                        icon: const Icon(Icons.gavel_outlined),
                        label: const Text('Resolver y autorizar pago'),
                      ),
                    if (item['payout_status'] == 'transfer_failed')
                      FilledButton.tonalIcon(
                        onPressed:
                            () => payoutAction(item['id'] as int, 'approve'),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar dispersión Stripe'),
                      ),
                  ],
                ),
              );
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Panel administrativo'),
        actions: [
          IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(icon: Icon(Icons.people_outline), text: 'Clientes'),
            Tab(icon: Icon(Icons.groups_outlined), text: 'Agrupaciones'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Contratos'),
            Tab(icon: Icon(Icons.gavel_outlined), text: 'Disputas'),
          ],
        ),
      ),
      body: GlassBackground(
        child:
            loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(child: Text(error!))
                : TabBarView(
                  children: [
                    records(
                      clients,
                      'No hay clientes',
                      (item) => item['name'].toString(),
                    ),
                    records(
                      groups,
                      'No hay agrupaciones',
                      (item) => item['group_name'].toString(),
                    ),
                    contracts(),
                    contracts(
                      source:
                          bookings
                              .where(
                                (item) => item['payout_status'] == 'disputed',
                              )
                              .toList(),
                      disputesOnly: true,
                    ),
                  ],
                ),
      ),
    ),
  );
}
