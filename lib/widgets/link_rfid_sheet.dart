import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/ym_ui.dart';

/// Link an RFID card to a student (or unlink it). Used by the help desk and the admin.
///
/// How to enter the card number:
///   * tap the card on a USB card reader plugged into the computer: it types the
///     number into the box by itself, or
///   * type the number printed on the card.
/// The number is tidied (capitals, no spaces or colons). It has to be the same number
/// the bus reader sends. One card can belong to only one student.
Future<void> showLinkRfidSheet(
  BuildContext context,
  Map<String, dynamic> student, {
  VoidCallback? onDone,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LinkRfidSheet(student: student),
  );
  if (changed == true) onDone?.call();
}

class _LinkRfidSheet extends StatefulWidget {
  const _LinkRfidSheet({required this.student});

  final Map<String, dynamic> student;

  @override
  State<_LinkRfidSheet> createState() => _LinkRfidSheetState();
}

class _LinkRfidSheetState extends State<_LinkRfidSheet> {
  final _sb = Supabase.instance.client;
  final _card = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _current;
  String? _error;

  String get _name => (widget.student['student_name'] ?? 'this student').toString();

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _card.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    try {
      final row = await _sb
          .from('students')
          .select('rfid_uid')
          .eq('id', widget.student['id'])
          .maybeSingle();
      final c = (row?['rfid_uid'] ?? '').toString();
      if (!mounted) return;
      setState(() {
        _current = c.isEmpty ? null : c;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _tidy(String s) => s.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toUpperCase();

  Future<void> _save(String? card) async {
    final tidy = card == null ? '' : _tidy(card);
    if (card != null && tidy.length < 4) {
      setState(() => _error = 'Please enter the card number, at least 4 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _sb.rpc('link_student_rfid', params: {
        'p_student': widget.student['id'],
        'p_card': tidy,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tidy.isEmpty
            ? 'Card removed from $_name.'
            : 'Card $tidy is now linked to $_name.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is PostgrestException ? e.message : e.toString();
      });
    }
  }

  Future<void> _unlink() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Unlink this card?', style: Ym.h(18)),
        content: Text(
            '$_name will no longer be marked as boarded when this card is tapped. '
            'The card can then be given to another student.',
            style: Ym.t(13.5, color: Ym.grey).copyWith(height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Unlink', style: Ym.t(14, color: Ym.red, w: FontWeight.w800))),
        ],
      ),
    );
    if (ok == true) await _save(null);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _tidy(_card.text);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.fromLTRB(22, 14, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4.5,
                  decoration:
                      BoxDecoration(color: Ym.line, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                const YmIconBadge(icon: Icons.contactless_rounded, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('RFID card', style: Ym.h(19)),
                      Text(_name, style: Ym.t(12.5, color: Ym.grey)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(color: Ym.amber)),
                )
              else ...[
                if (_current != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Ym.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle_rounded, color: Ym.green, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Linked card', style: Ym.t(11.5, color: Ym.grey)),
                            Text(_current!, style: Ym.h(16)),
                          ],
                        ),
                      ),
                      YmPressable(
                        onTap: _saving ? null : _unlink,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('Unlink',
                              style: Ym.t(13, color: Ym.red, w: FontWeight.w800)),
                        ),
                      ),
                    ]),
                  ),
                Text(_current == null ? 'Card number' : 'Replace with another card',
                    style: Ym.t(12, color: Ym.grey, w: FontWeight.w700)),
                const SizedBox(height: 6),
                TextField(
                  controller: _card,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _save(_card.text),
                  style: Ym.h(18),
                  decoration: InputDecoration(
                    hintText: 'Tap the card on the reader, or type it',
                    hintStyle: Ym.t(13, color: Ym.grey),
                    helperText: preview.isEmpty ? null : 'Will be saved as $preview',
                    filled: true,
                    fillColor: Ym.creamTop,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: Ym.t(12.5, color: Ym.red)),
                ],
                const SizedBox(height: 8),
                Text(
                  'Use the same number the bus reader sends. Spaces and colons are removed.',
                  style: Ym.t(11.5, color: Ym.grey),
                ),
                const SizedBox(height: 14),
                YmButton(
                  label: _current == null ? 'Link card' : 'Replace card',
                  icon: Icons.link_rounded,
                  loading: _saving,
                  onPressed: () => _save(_card.text),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}