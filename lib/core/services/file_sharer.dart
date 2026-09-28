import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a file to the platform's share sheet.
///
/// It is an interface rather than a direct call to `share_plus` so the flows
/// that produce a file — the timesheet PDF and the JSON backup — can be
/// tested without a share sheet appearing, and so there is one place that
/// knows how sharing works.
abstract class FileSharer {
  /// Shares the file at [path]. [subject] is used where the target supports it
  /// (mail clients, for instance).
  Future<void> shareFile({required String path, String? subject});
}

class PlatformFileSharer implements FileSharer {
  const PlatformFileSharer();

  @override
  Future<void> shareFile({required String path, String? subject}) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: subject),
    );
  }
}

final fileSharerProvider =
    Provider<FileSharer>((ref) => const PlatformFileSharer());
