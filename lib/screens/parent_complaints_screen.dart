import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';
import '../widgets/parent_child_picker.dart';

// These are the categories the database accepts (the same ones students use).
const _categories = <String, (String, IconData)>{
  'driver_behavior': ('Driver behaviour', Icons.person_pin_rounded),
  'delay': ('Bus delay', Icons.schedule_rounded),
  'cleanliness': ('Cleanliness', Icons.cleaning_services_rounded),
  'safety': ('Safety', Icons.shield_rounded),
  'route_issue': ('Route or stop', Icons.alt_route_rounded),
  'other': ('Other', Icons.more_horiz_rounded),
};

/// A parent's complaints: raise a new one about the child's bus, and follow it
/// from "Received" to "Resolved" with the admin's reply.
/// Complaints go to the admin (the in-charge option appears once that dashboard exists).
class ParentComplaintsScreen extends StatefulWidget {
  const ParentComplaintsScreen({
    super.key,
    required this.children,
    required this.selected,
  });

  final List<Map<String, dynamic>> children;
  final int selected;

  @override
  State<ParentComplaintsScreen> createState() => _ParentComplaintsScreenState();
}

class _ParentComplaintsScreenState extends State<ParentComplaintsScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  RealtimeChannel? _chan;

  String _childName(dynamic id) {
    for (final c in widget.children) {
      if (c['id'].toString() == id?.toString()) {
        return (c['student_name'] ?? '').toString();
      }
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _load();
    final uid = _sb.auth.currentUser?.id;
    if (uid != null) {
      // the admin's reply shows up here as soon as it is sent
      _chan = _sb
          .channel('parent_complaints_$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'complaints',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'raised_by',
                value: uid),
            callback: (_) {
              if (mounted) _load(silent: true);
            },
          )
          .subscribe();
    }
  }

  @override
  void dispose() {
    _chan?.unsubscribe();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in.');
      final rows = await _sb
          .from('complaints')
          .select()
          .eq('raised_by', uid)
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _new() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewComplaintSheet(
        children: widget.children,
        selected: widget.selected,
      ),
    );
    if (ok == true && mounted) {
      _load(silent: true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Complaint sent to the school. You will get an alert when they reply.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  ({String label, Color color, IconData icon}) _status(String s) {
    switch (s) {
      case 'resolved':
        return (label: 'Resolved', color: Ym.green, icon: Icons.check_circle_rounded);
      case 'in_progress':
        return (label: 'Looking into it', color: Ym.blue, icon: Icons.manage_search_rounded);
      default:
        return (label: 'Received', color: Ym.amberDark, icon: Icons.mark_email_read_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'Complaints',
      subtitle: 'Tell the school about a problem',
      child: Column(
        children: [
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: YmSkeletonList(count: 4, height: 110),
                  )
                : _error != null
                    ? YmEmpty(
                        icon: Icons.cloud_off_rounded,
                        color: Ym.red,
                        title: 'Could not load complaints',
                        subtitle: _error,
                        action: YmButton(
                            label: 'Try again',
                            icon: Icons.refresh_rounded,
                            expanded: false,
                            onPressed: _load),
                      )
                    : RefreshIndicator(
                        color: Ym.amber,
                        onRefresh: _load,
                        child: _items.isEmpty ? _empty() : _list(),
                      ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: YmButton(
              label: 'New complaint',
              icon: Icons.edit_note_rounded,
              onPressed: _new,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 50),
          YmEmpty(
            icon: Icons.sentiment_satisfied_rounded,
            color: Ym.green,
            title: 'No complaints',
            subtitle:
                'If something is wrong with your child\'s bus, tap "New complaint" and the school will look into it.',
          ),
        ],
      );

  Widget _list() => ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final c = _items[i];
          final cat = _categories[c['category']?.toString()] ??
              ('Other', Icons.more_horiz_rounded);
          final st = _status((c['status'] ?? 'open').toString());
          final at = parseUtc(c['created_at']);
          final reply = (c['response'] ?? '').toString().trim();
          final child = _childName(c['student_id']);
          return YmFadeSlide(
            index: i > 6 ? 6 : i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: YmCard(
                padding: const EdgeInsets.all(16),
                radius: 22,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        YmIconBadge(icon: cat.$2, color: st.color, size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(cat.$1, style: Ym.h(14.5)),
                              if (child.isNotEmpty)
                                Text('About $child',
                                    style: Ym.t(11.5, color: Ym.grey)),
                            ],
                          ),
                        ),
                        YmChip(st.label, color: st.color, icon: st.icon),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text((c['description'] ?? '').toString(),
                        style: Ym.t(13, color: const Color(0xFF374151))
                            .copyWith(height: 1.45)),
                    if (reply.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Ym.green.withOpacity(0.09),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.reply_rounded,
                                  size: 15, color: Ym.green),
                              const SizedBox(width: 6),
                              Text('Reply from the school',
                                  style: Ym.t(11.5,
                                      color: Ym.green, w: FontWeight.w800)),
                            ]),
                            const SizedBox(height: 5),
                            Text(reply, style: Ym.t(13)),
                          ],
                        ),
                      ),
                    ],
                    if (at != null) ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        const Icon(Icons.schedule_rounded,
                            size: 13, color: Ym.grey),
                        const SizedBox(width: 4),
                        Text('${fmtDate(at)}  •  ${fmtClock(at)}',
                            style: Ym.t(11, color: Ym.grey)),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
}

// ───────────────────────── new complaint ─────────────────────────

class _NewComplaintSheet extends StatefulWidget {
  const _NewComplaintSheet({required this.children, required this.selected});

  final List<Map<String, dynamic>> children;
  final int selected;

  @override
  State<_NewComplaintSheet> createState() => _NewComplaintSheetState();
}

class _NewComplaintSheetState extends State<_NewComplaintSheet> {
  final _sb = Supabase.instance.client;
  final _text = TextEditingController();

  late int _sel = widget.selected;
  String _category = 'delay';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final desc = _text.text.trim();
    if (desc.length < 10) {
      setState(() => _error = 'Please describe the problem in a few words.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final child = widget.children[_sel];
      String? busId;
      try {
        final ctx = await StudentContext.load(studentId: child['id'].toString());
        busId = ctx.busId;
      } catch (_) {}

      await _sb.from('complaints').insert({
        'raised_by': _sb.auth.currentUser!.id,
        'student_id': child['id'],
        'bus_id': busId,
        'category': _category,
        'description': desc,
        'send_to': 'admin',
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not send the complaint: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.fromLTRB(
          22, 14, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
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
                  decoration: BoxDecoration(
                      color: Ym.line, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              Text('New complaint', style: Ym.h(21)),
              const SizedBox(height: 4),
              Text('It goes to the school admin, and you will get an alert when they reply.',
                  style: Ym.t(12.5, color: Ym.grey)),
              const SizedBox(height: 18),
              if (widget.children.length > 1) ...[
                Text('About which child?',
                    style: Ym.t(12.5, color: Ym.grey, w: FontWeight.w700)),
                const SizedBox(height: 8),
                ParentChildPicker(
                  children: widget.children,
                  selected: _sel,
                  onChanged: (i) => setState(() => _sel = i),
                ),
              ],
              Text('What is it about?',
                  style: Ym.t(12.5, color: Ym.grey, w: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in _categories.entries)
                    YmPressable(
                      onTap: () => setState(() => _category = e.key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: _category == e.key
                              ? const LinearGradient(
                                  colors: [Ym.amber, Ym.amberDark])
                              : null,
                          color: _category == e.key ? null : Ym.creamTop,
                          border: Border.all(
                              color:
                                  _category == e.key ? Ym.amberDark : Ym.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(e.value.$2,
                                size: 15,
                                color: _category == e.key ? Ym.navy : Ym.grey),
                            const SizedBox(width: 6),
                            Text(e.value.$1,
                                style: Ym.t(12.5,
                                    color:
                                        _category == e.key ? Ym.navy : Ym.grey,
                                    w: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _text,
                maxLines: 5,
                maxLength: 500,
                style: Ym.t(14),
                decoration: InputDecoration(
                  hintText: 'Describe what happened (for example: the bus came 20 minutes late today)',
                  hintStyle: Ym.t(13, color: Ym.grey),
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
              const SizedBox(height: 14),
              YmButton(
                label: 'Send complaint',
                icon: Icons.send_rounded,
                loading: _saving,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}