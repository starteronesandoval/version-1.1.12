import 'dart:async';

import 'package:flutter/material.dart';

import '../api_service.dart';

Future<void> showBookingChat(
  BuildContext context, {
  required ApiService api,
  required Map<String, dynamic> booking,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1235),
    showDragHandle: true,
    builder: (_) => BookingChatSheet(api: api, booking: booking),
  );
}

class BookingChatSheet extends StatefulWidget {
  const BookingChatSheet({super.key, required this.api, required this.booking});

  final ApiService api;
  final Map<String, dynamic> booking;

  @override
  State<BookingChatSheet> createState() => _BookingChatSheetState();
}

class _BookingChatSheetState extends State<BookingChatSheet> {
  final message = TextEditingController();
  final scroll = ScrollController();
  List<Map<String, dynamic>> messages = [];
  Timer? refreshTimer;
  bool loading = true;
  bool refreshing = false;
  bool sending = false;
  String? lockedMessage;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _loadMessages(silent: true),
    );
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (refreshing) return;
    refreshing = true;
    try {
      final response =
          await widget.api.get(
                '/api/bookings/${widget.booking['id']}/messages',
                timeout: const Duration(seconds: 5),
              )
              as List<dynamic>;
      if (!mounted) return;
      final updated = response.cast<Map<String, dynamic>>();
      final changed = updated.length != messages.length;
      setState(() {
        messages = updated;
        loading = false;
        lockedMessage = null;
      });
      if (changed) _scrollToEnd();
    } on ApiException catch (error) {
      if (error.statusCode == 403 && mounted) {
        setState(() {
          lockedMessage = error.message;
          loading = false;
        });
      } else if (!silent && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
        setState(() => loading = false);
      }
    } catch (error) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
        setState(() => loading = false);
      }
    } finally {
      refreshing = false;
    }
  }

  Future<void> _send() async {
    final text = message.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      final saved =
          await widget.api.post(
                '/api/bookings/${widget.booking['id']}/messages',
                {'text': text},
              )
              as Map<String, dynamic>;
      if (!mounted) return;
      message.clear();
      setState(() => messages = [...messages, saved]);
      _scrollToEnd();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _date(String value) {
    final parsed = DateTime.parse(value);
    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  String _time(dynamic value) {
    final text = value.toString();
    return text.length >= 16 ? text.substring(11, 16) : '';
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    message.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0x3335D8C6),
                        child: Icon(
                          Icons.forum_outlined,
                          color: Color(0xFF68DDCD),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.booking['group_name'].toString(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${_date(widget.booking['event_date'].toString())} · ${widget.booking['venue']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: .62),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Chat privado para acordar horarios y solicitar canciones.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white.withValues(alpha: .10), height: 1),
            Expanded(
              child:
                  lockedMessage != null
                      ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFE2A62B,
                              ).withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: const Color(0xFFECC35B),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.lock_clock_outlined,
                                  size: 48,
                                  color: Color(0xFFECC35B),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Chat fuera de horario',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  lockedMessage!,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      : loading
                      ? const Center(child: CircularProgressIndicator())
                      : messages.isEmpty
                      ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(
                            'Inicia la conversación. Puedes confirmar el horario o enviar la lista de canciones.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .55),
                            ),
                          ),
                        ),
                      )
                      : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (_, index) {
                          final item = messages[index];
                          final mine = item['mine'] as bool? ?? false;
                          return Align(
                            alignment:
                                mine
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * .76,
                              ),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                              decoration: BoxDecoration(
                                color:
                                    mine
                                        ? const Color(0xFF7651B7)
                                        : Colors.white.withValues(alpha: .10),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(18),
                                  topRight: const Radius.circular(18),
                                  bottomLeft: Radius.circular(mine ? 18 : 4),
                                  bottomRight: Radius.circular(mine ? 4 : 18),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!mine)
                                    Text(
                                      item['sender_name'].toString(),
                                      style: const TextStyle(
                                        color: Color(0xFF68DDCD),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  Text(item['text'].toString()),
                                  const SizedBox(height: 3),
                                  Text(
                                    _time(item['created_at']),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white.withValues(
                                        alpha: .48,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
            ),
            if (lockedMessage == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 9, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: message,
                        minLines: 1,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Horario, canción o indicación…',
                          prefixIcon: Icon(Icons.music_note_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: sending ? null : _send,
                      icon:
                          sending
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
