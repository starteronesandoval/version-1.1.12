import 'package:flutter/material.dart';

import '../api_service.dart';

class BookingReviewSheet extends StatefulWidget {
  const BookingReviewSheet({
    super.key,
    required this.api,
    required this.booking,
  });
  final ApiService api;
  final Map<String, dynamic> booking;

  @override
  State<BookingReviewSheet> createState() => _BookingReviewSheetState();
}

class _BookingReviewSheetState extends State<BookingReviewSheet> {
  final recommendation = TextEditingController();
  final scores = <String, double>{
    'agreed_duration': 5,
    'punctuality': 5,
    'uniform': 5,
    'atmosphere': 5,
    'kindness': 5,
    'song_requests': 5,
    'would_hire_again': 5,
  };
  bool sending = false;

  static const labels = <String, String>{
    'agreed_duration': 'Cumplieron el tiempo acordado',
    'punctuality': 'Comenzaron a tiempo',
    'uniform': 'Presentación y uniforme',
    'atmosphere': 'Ambiente que crearon',
    'kindness': 'Amabilidad y trato',
    'song_requests': 'Te dieron gusto con tus temas',
    'would_hire_again': '¿Los volverías a contratar?',
  };

  @override
  void dispose() {
    recommendation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (recommendation.text.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe un consejo o recomendación amable.'),
        ),
      );
      return;
    }
    setState(() => sending = true);
    try {
      final result =
          await widget.api.post(
                '/api/bookings/${widget.booking['id']}/review',
                {...scores, 'recommendation': recommendation.text.trim()},
              )
              as Map<String, dynamic>;
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
        setState(() => sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        4,
        18,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            'Califica a ${widget.booking['group_name']}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Puedes elegir estrellas completas o medias estrellas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: .65)),
          ),
          const SizedBox(height: 18),
          for (final entry in labels.entries) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      fontWeight:
                          entry.key == 'would_hire_again'
                              ? FontWeight.w800
                              : FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  scores[entry.key]!.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Color(0xFFFFA000),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Slider(
              value: scores[entry.key]!,
              min: .5,
              max: 5,
              divisions: 9,
              label: '${scores[entry.key]!.toStringAsFixed(1)} ★',
              onChanged: (value) => setState(() => scores[entry.key] = value),
            ),
            if (entry.key == 'would_hire_again')
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Esta respuesta representa el 30% de la calificación final.',
                  style: TextStyle(color: Color(0xFFFFA000), fontSize: 12),
                ),
              ),
          ],
          TextField(
            controller: recommendation,
            maxLength: 1000,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Consejo amable para la agrupación',
              hintText: '¿Qué hicieron bien y qué podrían mejorar?',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: sending ? null : submit,
            icon: const Icon(Icons.star_rounded),
            label: Text(sending ? 'Enviando…' : 'Enviar calificación'),
          ),
        ],
      ),
    ),
  );
}
