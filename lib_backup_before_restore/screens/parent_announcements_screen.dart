import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/ym_ui.dart';

/// All announcements that concern the parent, for the last 60 days:
/// for everyone, for parents, and for the buses or routes their children use.
class ParentAnnouncementsScreen extends StatefulWidget {
  const ParentAnnouncementsScreen({
    super.key,
    required this.children,
    this.audience = 'parent',
  });

  final List<Map<String, dynamic>> children;

  /// who is reading: 'parent' (the default) or 'faculty'. Decides which
  /// "for everyone of this kind" announcements are shown.
  final String audience;

  @override
  State<ParentAnnouncementsScreen> createState() =>
      _ParentAnnouncementsScreenState();
}

class _ParentAnnouncementsScreenState extends State<ParentAnnouncementsScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  final Set<dynamic> _open = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // who is this announcement for? everyone, parents, or a bus / route of a child
      final targets = <String>{'all', widget.audience};
      for (final c in widget.children) {
        final r = c['route_id']?.toString();
        final b = c['bus_id']?.toString();
        if (r != null && r.isNotEmpty) targets.add('route_$r');
        if (b != null && b.isNotEmpty) targets.add('bus_$b');
      }
      // a child's bus may only be known through the route
      final routeIds = [
        for (final c in widget.children)
          if (c['route_id'] != null) c['route_id'].toString(),
      ];
      if (routeIds.isNotEmpty) {
        try {
          final rows = await _sb
              .from('routes')
              .select('bus_id')
              .inFilter('id', routeIds);
          for (final r in rows) {
            if (r['bus_id'] != null) targets.add('bus_${r['bus_id']}');
          }
        } catch (_) {}
      }

      final since = DateTime.now().toUtc().subtract(const Duration(days: 60));
      var q = _sb
          .from('announcements')
          .select()
          .inFilter('target_role', targets.toList())
          .gte('created_at', since.toIso8601String());
      final inst = widget.children.isEmpty
          ? null
          : widget.children.first['institution_id'];
      if (inst != null) q = q.eq('institution_id', inst);
      final rows = await q.order('created_at', ascending: false).limit(80);

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

  String _ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return fmtDateLocal(d);
  }

  String fmtDateLocal(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
  }

  String _audience(String t) {
    if (t.startsWith('bus_')) return 'Your child\'s bus';
    if (t.startsWith('route_')) return 'Your child\'s route';
    if (t == 'parent') return 'Parents';
    if (t == 'faculty') return 'Faculty';
    return 'Everyone';
  }

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'Announcements',
      subtitle: 'From the school and the transport office',
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: YmSkeletonList(count: 4, height: 100),
            )
          : _error != null
              ? YmEmpty(
                  icon: Icons.cloud_off_rounded,
                  color: Ym.red,
                  title: 'Could not load announcements',
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
                  child: _items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 60),
                            YmEmpty(
                              icon: Icons.campaign_outlined,
                              color: Ym.amberDark,
                              title: 'No announcements',
                              subtitle:
                                  'Nothing has been announced in the last 60 days.',
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final a = _items[i];
                            final body = (a['body'] ?? '').toString();
                            final long = body.length > 110;
                            final open = _open.contains(a['id']);
                            final at = DateTime.tryParse('${a['created_at']}');
                            return YmFadeSlide(
                              index: i > 6 ? 6 : i,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: YmCard(
                                  onTap: long
                                      ? () => setState(() {
                                            if (open) {
                                              _open.remove(a['id']);
                                            } else {
                                              _open.add(a['id']);
                                            }
                                          })
                                      : null,
                                  padding: const EdgeInsets.all(16),
                                  radius: 22,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const YmIconBadge(
                                              icon: Icons.campaign_rounded,
                                              size: 42),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                    (a['title'] ?? 'Announcement')
                                                        .toString(),
                                                    style: Ym.h(14.5)),
                                                const SizedBox(height: 4),
                                                Wrap(spacing: 6, children: [
                                                  YmChip(
                                                      _audience(
                                                          (a['target_role'] ?? 'all')
                                                              .toString()),
                                                      color: Ym.blue),
                                                  if (at != null)
                                                    YmChip(_ago(at),
                                                        color: Ym.grey,
                                                        icon: Icons
                                                            .access_time_rounded),
                                                ]),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      AnimatedSize(
                                        duration: const Duration(milliseconds: 200),
                                        alignment: Alignment.topCenter,
                                        child: Text(
                                          body,
                                          maxLines: open ? null : 3,
                                          overflow: open
                                              ? TextOverflow.visible
                                              : TextOverflow.ellipsis,
                                          style: Ym.t(13, color: const Color(0xFF4B5563))
                                              .copyWith(height: 1.5),
                                        ),
                                      ),
                                      if (long)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Text(open ? 'Show less' : 'Read more',
                                              style: Ym.t(12,
                                                  color: Ym.amberDark,
                                                  w: FontWeight.w800)),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}