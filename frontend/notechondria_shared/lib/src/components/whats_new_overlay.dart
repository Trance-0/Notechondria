import 'package:flutter/material.dart';

import '../utils/blur_dialog.dart';

/// One user-visible feature shipped in an app version, rendered as a
/// card in the What's-New overlay. Each app keeps its own registry
/// (`lib/core/whats_new.dart`) of these, newest last; entries older
/// than the user's `last_seen_version` are filtered out by
/// [selectMissedUpdates].
class FeatureUpdate {
  const FeatureUpdate({
    required this.version,
    required this.title,
    required this.description,
    this.icon,
  });

  /// Repo VERSION string (e.g. `0.1.127`) the feature shipped in.
  final String version;
  final String title;
  final String description;
  final IconData? icon;
}

/// Numeric segment-wise comparison of dotted version strings
/// (`0.1.9` < `0.1.10`). Non-numeric segments compare as 0 so a
/// malformed version never throws during boot.
int compareAppVersions(String a, String b) {
  final aParts = a.split('.');
  final bParts = b.split('.');
  final length = aParts.length > bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < length; i++) {
    final aNum = i < aParts.length ? int.tryParse(aParts[i]) ?? 0 : 0;
    final bNum = i < bParts.length ? int.tryParse(bParts[i]) ?? 0 : 0;
    if (aNum != bNum) return aNum.compareTo(bNum);
  }
  return 0;
}

/// Returns the registry entries the user has not seen yet: strictly
/// newer than [lastSeenVersion] and not newer than [currentVersion],
/// oldest first. An empty [lastSeenVersion] yields an empty list —
/// fresh installs stamp the current version silently instead of
/// replaying the whole feature history at a brand-new user.
List<FeatureUpdate> selectMissedUpdates({
  required List<FeatureUpdate> registry,
  required String lastSeenVersion,
  required String currentVersion,
}) {
  if (lastSeenVersion.trim().isEmpty) return const [];
  final missed = registry
      .where((update) =>
          compareAppVersions(update.version, lastSeenVersion) > 0 &&
          compareAppVersions(update.version, currentVersion) <= 0)
      .toList()
    ..sort((a, b) => compareAppVersions(a.version, b.version));
  return missed;
}

/// Blur-backed "What's new" overlay listing the feature updates the
/// user missed since their last seen version. Resolves to `true` when
/// the user tapped "Got it", `false` for "Skip" (or dismissed the
/// barrier). Callers stamp the current version in **both** cases —
/// skip means "don't show me these again", not "ask me again next
/// boot".
Future<bool> showWhatsNewOverlay(
  BuildContext context, {
  required String appTitle,
  required String currentVersion,
  required List<FeatureUpdate> updates,
}) async {
  final acknowledged = await showBlurDialog<bool>(
    context: context,
    child: Builder(builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: Text("What's new in $appTitle"),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
          child: SizedBox(
            width: 480,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: updates.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final update = updates[index];
                return Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          update.icon ?? Icons.new_releases_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      update.title,
                                      style: theme.textTheme.titleSmall,
                                    ),
                                  ),
                                  Text(
                                    update.version,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                update.description,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Got it'),
          ),
        ],
      );
    }),
  );
  return acknowledged ?? false;
}
