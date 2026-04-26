import 'package:flutter/material.dart';

import '../utils/compact_timestamp.dart';

/// Apple-style "Active sessions" card. Lists every non-revoked,
/// non-expired session the backend reports for the current user
/// (one row per device) and lets the user revoke individual rows.
///
/// Drives off the wire shape returned by
/// `GET /api/v1/auth/sessions/`:
///
/// ```json
/// {
///   "sessions": [
///     {
///       "id": 17,
///       "device_label": "Mac",
///       "user_agent": "Mozilla/5.0 ...",
///       "ip_hash_prefix": "deadbeef",
///       "created_at": "2026-04-26T18:30:00Z",
///       "last_seen_at": "2026-04-26T19:00:00Z",
///       "is_current": true
///     }
///   ],
///   "current_session_id": 17
/// }
/// ```
///
/// The host wires `onListSessions` and `onRevokeSession` so the
/// card stays self-contained — it doesn't know about the HTTP
/// client, only that it gets a list and can ask to revoke. After
/// a successful revoke the card re-fetches the list. If the user
/// revokes their own row, the card calls `onCurrentRevoked` so
/// the host can run the local sign-out flow (clear token,
/// `_loadInitialData`, etc.) — without that hook the local cache
/// would keep behaving as signed-in until the next API 401.
class ActiveSessionsCard extends StatefulWidget {
  const ActiveSessionsCard({
    super.key,
    required this.onListSessions,
    required this.onRevokeSession,
    this.onCurrentRevoked,
  });

  /// Called once on mount and again after every successful
  /// revoke. Returns the raw `Map<String, dynamic>` from
  /// `/auth/sessions/` so the card can read both `sessions` and
  /// `current_session_id`.
  final Future<Map<String, dynamic>> Function() onListSessions;

  /// Called when the user taps the trash icon on a row. The
  /// callback should hit `DELETE /auth/sessions/<id>/` on the
  /// host's HTTP client and re-throw on failure (the card
  /// catches and surfaces the error inline). The card refreshes
  /// the list on success.
  final Future<void> Function(int sessionId) onRevokeSession;

  /// Called once if the user revoked their own session. The host
  /// should run its local sign-out — clear `_token`, reset
  /// session metadata, run `_loadInitialData()`. If null the
  /// card just refreshes the list (which will then 401 on the
  /// next call and force the host's stale-token flow).
  final VoidCallback? onCurrentRevoked;

  @override
  State<ActiveSessionsCard> createState() => _ActiveSessionsCardState();
}

class _ActiveSessionsCardState extends State<ActiveSessionsCard> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sessions = const [];
  int? _currentSessionId;
  int? _revokingId;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.onListSessions();
      if (!mounted) return;
      final raw = (result['sessions'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      setState(() {
        _sessions = raw;
        _currentSessionId =
            (result['current_session_id'] as num?)?.toInt();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _confirmAndRevoke(Map<String, dynamic> session) async {
    final id = (session['id'] as num).toInt();
    final isCurrent = session['is_current'] == true ||
        (_currentSessionId != null && _currentSessionId == id);
    final label = session['device_label']?.toString() ?? 'this session';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isCurrent ? 'Sign out this device?' : 'Revoke session?'),
        content: Text(
          isCurrent
              ? 'Revoking your current session signs you out of this '
                  'device. You can sign back in afterward.'
              : 'Revoke "$label"? That device will be signed out the '
                  'next time it talks to the backend.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isCurrent ? 'Sign out' : 'Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _revokingId = id);
    try {
      await widget.onRevokeSession(id);
      if (!mounted) return;
      if (isCurrent) {
        // Defer to host's sign-out flow (clear local state, reload).
        // The host will rebuild the parent widget after, which will
        // dispose this card — so we don't need to refresh here.
        widget.onCurrentRevoked?.call();
        return;
      }
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _revokingId = null;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: const Text(
              'Active sessions',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Devices currently signed in to your account.',
            ),
            trailing: IconButton(
              tooltip: 'Refresh sessions list',
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _loading ? null : _refresh,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_loading && _sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: LinearProgressIndicator(),
            )
          else if (_sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('No active sessions reported by the backend.'),
            )
          else
            for (final session in _sessions) ...[
              const Divider(height: 0, indent: 16, endIndent: 16),
              _ActiveSessionRow(
                session: session,
                isRevoking: _revokingId == (session['id'] as num).toInt(),
                onRevoke: () => _confirmAndRevoke(session),
              ),
            ],
        ],
      ),
    );
  }
}

class _ActiveSessionRow extends StatelessWidget {
  const _ActiveSessionRow({
    required this.session,
    required this.isRevoking,
    required this.onRevoke,
  });

  final Map<String, dynamic> session;
  final bool isRevoking;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = session['device_label']?.toString() ?? 'Unknown device';
    final ua = session['user_agent']?.toString() ?? '';
    final isCurrent = session['is_current'] == true;
    final lastSeen = session['last_seen_at']?.toString() ?? '';
    final created = session['created_at']?.toString() ?? '';
    final ipHashPrefix = session['ip_hash_prefix']?.toString() ?? '';
    final lastSeenLabel = lastSeen.isEmpty
        ? 'unknown'
        : formatCompactTimestamp(lastSeen);
    final createdLabel = created.isEmpty
        ? 'unknown'
        : formatCompactTimestamp(created);
    return ListTile(
      leading: Icon(
        _iconFor(label, ua),
        color: isCurrent ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'This device',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Last seen $lastSeenLabel · created $createdLabel'),
          if (ipHashPrefix.isNotEmpty)
            Text(
              'IP fingerprint: $ipHashPrefix',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
        ],
      ),
      trailing: isRevoking
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              tooltip: isCurrent
                  ? 'Sign out this device'
                  : 'Revoke this session',
              icon: Icon(
                isCurrent ? Icons.logout : Icons.delete_outline,
                color: scheme.error,
              ),
              onPressed: onRevoke,
            ),
    );
  }

  /// Heuristic mapping of the backend's coarse `device_label`
  /// (set by `Session.create_for_user`'s User-Agent parse) to a
  /// Material icon. Falls back to a generic device icon when the
  /// label / UA doesn't match anything we recognize.
  IconData _iconFor(String label, String userAgent) {
    final s = '$label $userAgent'.toLowerCase();
    if (s.contains('iphone') || s.contains('ios')) return Icons.phone_iphone;
    if (s.contains('android')) return Icons.phone_android;
    if (s.contains('ipad')) return Icons.tablet_mac;
    if (s.contains('mac') || s.contains('macintosh')) return Icons.laptop_mac;
    if (s.contains('windows')) return Icons.laptop_windows;
    if (s.contains('linux')) return Icons.laptop_chromebook;
    return Icons.devices;
  }
}
