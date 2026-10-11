import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/change_password_screen.dart';
import '../theme/ym_ui.dart';

/// A small "My account" sheet: who is logged in, Change password, Log out.
/// Used by roles that have no profile page of their own (help desk, admin).
Future<void> showAccountSheet(
  BuildContext context, {
  required String roleLabel,
  required Future<void> Function() onLogout,
}) {
  final email = Supabase.instance.client.auth.currentUser?.email ?? '';
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
      child: SafeArea(
        top: false,
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
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Ym.amber, Ym.amberDark]),
                  ),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white,
                    child: Text(
                      email.isEmpty ? '?' : email[0].toUpperCase(),
                      style: Ym.h(20, color: Ym.amberDark),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('My account', style: Ym.h(17)),
                      Text(email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Ym.t(12.5, color: Ym.grey)),
                    ],
                  ),
                ),
                YmChip(roleLabel, color: Ym.green),
              ],
            ),
            const SizedBox(height: 20),
            YmCard(
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                );
              },
              padding: const EdgeInsets.all(14),
              radius: 20,
              child: Row(
                children: [
                  const YmIconBadge(icon: Icons.lock_reset_rounded, size: 42),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Change password', style: Ym.h(14.5))),
                  const Icon(Icons.chevron_right_rounded, color: Ym.grey),
                ],
              ),
            ),
            const SizedBox(height: 10),
            YmCard(
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await onLogout();
              },
              padding: const EdgeInsets.all(14),
              radius: 20,
              child: Row(
                children: [
                  const YmIconBadge(
                      icon: Icons.logout_rounded, color: Ym.red, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text('Log out',
                          style: Ym.h(14.5, color: Ym.red))),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}