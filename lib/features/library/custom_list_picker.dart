import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/custom_list.dart';
import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';

Future<void> showCustomListPicker(BuildContext context, MediaItem item) async {
  final app = context.read<AppState>();
  final english = app.english;
  if (app.customLists.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(english
          ? 'Create a collection in My Library first.'
          : 'أنشئ قائمة من مكتبتي أولًا.'),
    ));
    return;
  }
  final list = await showModalBottomSheet<CustomMediaList>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 12),
            child: Text(english ? 'Add to a collection' : 'أضف إلى قائمة',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          for (final list in app.customLists)
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text(list.name),
              subtitle: Text('${list.items.length}'),
              onTap: () => Navigator.of(context).pop(list),
            ),
        ],
      ),
    ),
  );
  if (list == null || !context.mounted) return;
  final added = await app.addToCustomList(list.id, item);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(added
        ? (english ? 'Added to ${list.name}.' : 'أُضيف إلى ${list.name}.')
        : (english ? 'Already in this list.' : 'العنوان موجود في القائمة.')),
  ));
}
