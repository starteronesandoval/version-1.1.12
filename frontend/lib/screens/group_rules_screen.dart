import 'package:flutter/material.dart';

import '../widgets/glass_ui.dart';

class GroupRulesScreen extends StatefulWidget {
  const GroupRulesScreen({
    super.key,
    required this.onAccept,
    required this.onDecline,
  });

  final Future<void> Function() onAccept;
  final VoidCallback onDecline;

  @override
  State<GroupRulesScreen> createState() => _GroupRulesScreenState();
}

class _GroupRulesScreenState extends State<GroupRulesScreen> {
  bool accepted = false;
  bool busy = false;

  static const sections = <(String, String)>[
    (
      '1. La agrupación debe existir realmente',
      'El nombre, fotografías, videos, audios y demás material publicado deben corresponder a una agrupación real y activa. No está permitido usar material de una agrupación para después enviar músicos diferentes o formar un grupo únicamente para cubrir una contratación.',
    ),
    (
      '2. Formación estable',
      'La agrupación deberá contar habitualmente con una formación estable. Se espera que al menos el 75% de sus integrantes habituales formen parte de la agrupación presentada en Garibaldy, para que el cliente reciba sustancialmente lo que vio y escuchó antes de contratar.',
    ),
    (
      '3. Los cambios de integrantes sí están permitidos',
      'Enfermedades, emergencias u otras circunstancias pueden exigir una sustitución ocasional. Cuando el cambio modifique de forma importante el producto contratado —especialmente cantantes principales o músicos responsables de melodías características— deberá informarse al cliente y obtener su aceptación.',
    ),
    (
      '4. No se permiten agrupaciones improvisadas',
      'No está permitido usar Garibaldy sólo para conseguir contratos y después buscar músicos disponibles para formar una agrupación diferente en cada evento. Garibaldy podrá revisar sustituciones recurrentes y pedir nuevamente evidencia de la formación habitual.',
    ),
    (
      '5. Material auténtico',
      'Las fotografías, videos y audios deben representar razonablemente el producto que recibirá el cliente. Garibaldy podrá solicitar material en vivo e información adicional para verificar la existencia y trayectoria de la agrupación.',
    ),
    (
      '6. Cambios antes del evento',
      'Garibaldy podrá solicitar confirmar la formación que asistirá. Cualquier cambio relevante deberá reportarse desde la aplicación para que el cliente pueda aceptarlo.',
    ),
    (
      '7. Enviar deliberadamente otra agrupación es una falta grave',
      'Garibaldy podrá retener temporalmente la liberación del pago mientras revisa el caso, abrir una mediación, registrar una infracción, suspender la verificación o cancelar permanentemente perfiles en casos graves o recurrentes.',
    ),
  ];

  Future<void> submit() async {
    if (!accepted || busy) return;
    setState(() => busy = true);
    try {
      await widget.onAccept();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
    children: [
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Icon(
                Icons.gavel_rounded,
                size: 58,
                color: Color(0xFFFFC857),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Reglas para Agrupaciones',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC857).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Antes de continuar: leer y marcar este acuerdo constituye una aceptación contractual dentro de Garibaldy. Estas reglas protegen al cliente, a la agrupación y a Garibaldy en los tratos realizados mediante la aplicación.',
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.4),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Garibaldy busca nuevas oportunidades para agrupaciones que han construido su trabajo con talento, preparación, constancia y profesionalismo. Para proteger a clientes y agrupaciones serias, debes aceptar lo siguiente:',
              style: TextStyle(height: 1.5),
            ),
            for (final section in sections) ...[
              const SizedBox(height: 18),
              Text(
                section.$1,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                section.$2,
                style: TextStyle(
                  height: 1.5,
                  color: Colors.white.withValues(alpha: .78),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Nuestro principio',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            const Text(
              'No buscamos impedir sustituciones normales del trabajo musical. Buscamos impedir que alguien venda como propia una agrupación que realmente no tiene. El cliente debe saber qué agrupación contrata y la agrupación profesional debe recibir el valor que su trabajo merece.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 22),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: accepted,
              onChanged:
                  busy
                      ? null
                      : (value) => setState(() => accepted = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'He leído y acepto las Reglas para Agrupaciones de Garibaldy. Declaro que la agrupación que estoy registrando existe realmente y que la información y material proporcionados representan razonablemente a la formación que ofreceré a los clientes.',
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.4),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              onPressed: accepted && !busy ? submit : null,
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(
                busy ? 'Registrando aceptación…' : 'Aceptar y continuar',
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: busy ? null : widget.onDecline,
              child: const Text('No acepto'),
            ),
          ],
        ),
      ),
    ],
  );
}
