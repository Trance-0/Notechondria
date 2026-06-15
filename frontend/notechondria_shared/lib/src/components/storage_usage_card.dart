import 'package:flutter/material.dart';

import '../utils/format_bytes.dart';
import '../utils/storage_estimate.dart'
    if (dart.library.html) '../utils/storage_estimate_web.dart';

/// Cross-app "Local data" visualization. Shows which backend the app
/// talks to and where that backend stores files, a decomposition of
/// local browser/device storage by bucket, the total used, the space
/// left (web only, via the StorageManager quota), and low-storage
/// suggestions.
///
/// The caller computes the synchronous inputs (per-bucket byte sizes
/// from the local store, attachment bytes from `LocalAttachmentStore`,
/// the backend host, and the storage-arch label from the handshake);
/// this widget fetches the browser quota itself and renders the rest.
class StorageUsageCard extends StatefulWidget {
  const StorageUsageCard({
    super.key,
    required this.backendHost,
    required this.bucketSizes,
    required this.attachmentBytes,
    this.storageArchLabel = '',
  });

  /// Backend host the app is using (e.g. `notechondria.trance-0.com`),
  /// already extracted from the API base URL.
  final String backendHost;

  /// Human label for the backend's media-storage architecture
  /// (e.g. "Cloudflare R2" / "Local disk"). Empty hides the line.
  final String storageArchLabel;

  /// Local persisted buckets by display label → byte size
  /// (settings / drafts / categories / cache / logs / recycle bin / …).
  final Map<String, int> bucketSizes;

  /// Total local attachment bytes (IndexedDB on web, files on native).
  final int attachmentBytes;

  @override
  State<StorageUsageCard> createState() => _StorageUsageCardState();
}

class _StorageUsageCardState extends State<StorageUsageCard> {
  int? _quotaBytes;
  int? _quotaUsageBytes;
  bool _estimateLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadEstimate();
  }

  Future<void> _loadEstimate() async {
    final est = await readStorageEstimate();
    if (!mounted) return;
    setState(() {
      _quotaUsageBytes = est.usageBytes;
      _quotaBytes = est.quotaBytes;
      _estimateLoaded = true;
    });
  }

  int get _localTotal {
    var sum = widget.attachmentBytes;
    for (final v in widget.bucketSizes.values) {
      sum += v;
    }
    return sum;
  }

  /// Ordered, non-empty buckets plus attachments, largest first.
  List<MapEntry<String, int>> get _entries {
    final entries = <MapEntry<String, int>>[
      ...widget.bucketSizes.entries.where((e) => e.value > 0),
      if (widget.attachmentBytes > 0)
        MapEntry('Attachments', widget.attachmentBytes),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Fraction of quota used (web only), or null when unknown.
  double? get _quotaFraction {
    final quota = _quotaBytes;
    final usage = _quotaUsageBytes;
    if (quota == null || quota <= 0 || usage == null) return null;
    return (usage / quota).clamp(0.0, 1.0);
  }

  List<String> get _suggestions {
    final out = <String>[];
    final frac = _quotaFraction;
    if (frac != null && frac >= 0.8) {
      out.add('You are using ${(frac * 100).round()}% of this browser\'s '
          'storage for this site. Free space by clearing the cache or '
          'exporting and removing old local notes.');
    }
    if (widget.attachmentBytes > 200 * 1024 * 1024) {
      out.add('Attachments take up ${formatBytes(widget.attachmentBytes)}. '
          'Sign in and push to the cloud, then clear local data to reclaim '
          'space, or export a backup first.');
    }
    if (out.isEmpty && frac == null && _localTotal > 300 * 1024 * 1024) {
      out.add('Local data is ${formatBytes(_localTotal)}. Consider exporting '
          'a backup and clearing data you have already synced to the cloud.');
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _localTotal;
    final frac = _quotaFraction;
    final suggestions = _suggestions;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage_outlined,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Storage usage',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            _kv(theme, 'Backend',
                widget.backendHost.isEmpty ? 'offline' : widget.backendHost),
            if (widget.storageArchLabel.isNotEmpty)
              _kv(theme, 'Backend storage', widget.storageArchLabel),
            _kv(theme, 'Local data used', formatBytes(total)),
            if (frac != null && _quotaBytes != null) ...[
              _kv(
                theme,
                'Browser storage',
                '${formatBytes(_quotaUsageBytes ?? 0)} of '
                    '${formatBytes(_quotaBytes!)} used',
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: frac >= 0.8
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatBytes((_quotaBytes! - (_quotaUsageBytes ?? 0)).clamp(0, _quotaBytes!))} free',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else if (_estimateLoaded) ...[
              _kv(theme, 'Space left', 'not reported by this platform'),
            ],
            const SizedBox(height: 12),
            Text('Breakdown',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (_entries.isEmpty)
              Text('No local data stored yet.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else
              for (final entry in _entries)
                _breakdownRow(theme, entry.key, entry.value, total),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline,
                            size: 16, color: theme.colorScheme.tertiary),
                        const SizedBox(width: 6),
                        Text('Suggestions',
                            style: theme.textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (final s in suggestions)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('• $s', style: theme.textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(ThemeData theme, String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(key,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(ThemeData theme, String label, int bytes, int total) {
    final frac = total > 0 ? (bytes / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
              Text(formatBytes(bytes),
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 5,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
