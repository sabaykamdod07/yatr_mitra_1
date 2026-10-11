import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';

class _C {
  static const bg = Color(0xFFFFF8F1);
  static const navy = Color(0xFF0F1B4D);
  static const orange = Color(0xFFFF9800);
  static const grey = Color(0xFF8E94A9);
  static const green = Color(0xFF0E9F6E);
  static const red = Color(0xFFE53935);
  static const blue = Color(0xFF3B6FF5);
}

const _categories = <String, String>{
  'driver_behavior': 'Driver Behavior',
  'delay': 'Bus Delay',
  'cleanliness': 'Cleanliness',
  'safety': 'Safety',
  'route_issue': 'Route Issue',
  'other': 'Other',
};

const _targets = <String, String>{
  'incharge': 'Incharge',
  'faculty': 'Faculty',
  'admin': 'Admin',
};

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  final _sb = Supabase.instance.client;

  StudentContext? _ctx;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _listen();
  }

  @override
  void dispose() {
    if (_channel != null) _sb.removeChannel(_channel!);
    super.dispose();
  }

  /// When the admin/incharge changes a complaint's status, it updates here live.
  void _listen() {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    _channel = _sb
        .channel('my_complaints_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'complaints',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'raised_by',
            value: uid,
          ),
          callback: (_) => _load(silent: true),
        )
        .subscribe();
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
      _ctx ??= await StudentContext.load();

      final rows = await _sb
          .from('complaints')
          .select()
          .eq('raised_by', uid)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _newComplaint() async {
    final ctx = _ctx;
    if (ctx == null) return;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _NewComplaintSheet(ctx: ctx),
    );
    if (sent == true) {
      _load(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Complaint submitted.'),
          backgroundColor: _C.navy,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  (String, Color) _status(String? s) => switch (s) {
        'resolved' => ('Resolved', _C.green),
        'in_progress' => ('In Progress', _C.orange),
        _ => ('Open', _C.red),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        size: 20, color: _C.navy),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text('Complaints',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _C.navy)),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading || _ctx == null ? null : _newComplaint,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('New Complaint'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.orange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('My Complaints',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _C.navy)),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _C.orange))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: _C.grey)),
                          ),
                        )
                      : RefreshIndicator(
                          color: _C.orange,
                          onRefresh: _load,
                          child: _items.isEmpty
                              ? ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  children: const [
                                    SizedBox(height: 100),
                                    Center(
                                        child: Text('No complaints yet',
                                            style:
                                                TextStyle(color: _C.grey))),
                                  ],
                                )
                              : ListView.separated(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                  itemCount: _items.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (_, i) => _card(_items[i]),
                                ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> c) {
    final (label, color) = _status(c['status']?.toString());
    final cat = _categories[c['category']?.toString()] ?? 'Other';
    final to = _targets[c['send_to']?.toString()] ?? 'Admin';
    final at = parseUtc(c['created_at']);
    final response = c['response']?.toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(cat,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: _C.navy)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(c['description']?.toString() ?? '',
              style: const TextStyle(color: _C.grey, fontSize: 13)),
          const SizedBox(height: 6),
          Text('Sent to $to${at != null ? '  •  ${fmtDate(at)}' : ''}',
              style: const TextStyle(color: _C.grey, fontSize: 11.5)),
          if (response != null && response.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _C.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Iconsax.message_text,
                      size: 16, color: _C.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(response,
                        style: const TextStyle(
                            color: _C.navy, fontSize: 12.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NewComplaintSheet extends StatefulWidget {
  const _NewComplaintSheet({required this.ctx});

  final StudentContext ctx;

  @override
  State<_NewComplaintSheet> createState() => _NewComplaintSheetState();
}

class _NewComplaintSheetState extends State<_NewComplaintSheet> {
  final _sb = Supabase.instance.client;
  final _text = TextEditingController();

  String _category = 'delay';
  String _sendTo = 'incharge';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final desc = _text.text.trim();
    if (desc.length < 5) {
      setState(() => _error = 'Please describe the problem (a few words).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _sb.from('complaints').insert({
        'raised_by': _sb.auth.currentUser!.id,
        'bus_id': widget.ctx.busId,
        'category': _category,
        'description': desc,
        'send_to': _sendTo,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not submit: $e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Complaint',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: _C.navy)),
            const SizedBox(height: 16),
            const Text('What is it about?',
                style: TextStyle(color: _C.grey, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in _categories.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _category == e.key,
                    selectedColor: _C.orange.withOpacity(0.2),
                    onSelected: (_) => setState(() => _category = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Send to',
                style: TextStyle(color: _C.grey, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final e in _targets.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _sendTo == e.key,
                    selectedColor: _C.blue.withOpacity(0.18),
                    onSelected: (_) => setState(() => _sendTo = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Describe the problem…',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: const TextStyle(color: _C.red, fontSize: 12.5)),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.orange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}