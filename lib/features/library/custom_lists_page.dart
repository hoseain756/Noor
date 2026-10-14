import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/data/custom_list_share.dart';
import '../../core/models/custom_list.dart';
import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../shared/widgets/noor_toast.dart';
import '../../shared/widgets/poster_card.dart';
import '../media/media_detail_page.dart';

class CustomListsPanel extends StatelessWidget {
  const CustomListsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(english ? 'Your collections' : 'قوائمك',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              IconButton.filledTonal(
                tooltip: english ? 'Import list' : 'استيراد قائمة',
                onPressed: () => _importList(context),
                icon: const Icon(Icons.file_download_outlined),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () => _createList(context),
                icon: const Icon(Icons.add_rounded),
                label: Text(english ? 'New list' : 'قائمة جديدة'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (app.customLists.isEmpty)
            _CollectionEmpty(english: english)
          else
            for (final list in app.customLists)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: HorseTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    leading: _ListArtwork(item: list.items.firstOrNull),
                    title: Text(list.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${list.items.length} ${english ? 'titles' : 'عناوين'}'
                      '${list.description == null ? '' : ' · ${list.description}'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CustomListDetailPage(listId: list.id),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class CustomListDetailPage extends StatelessWidget {
  const CustomListDetailPage({super.key, required this.listId});
  final String listId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    final list =
        app.customLists.where((entry) => entry.id == listId).firstOrNull;
    if (list == null) {
      return Scaffold(
        appBar: AppBar(title: Text(english ? 'Collection' : 'القائمة')),
        body: Center(
          child: Text(english
              ? 'This list no longer exists.'
              : 'لم تعد هذه القائمة موجودة.'),
        ),
      );
    }
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final posterWidth = MediaQuery.sizeOf(context).width >= 800 ? 184.0 : 160.0;
    final rowExtent = posterWidth / .72 + 70 * scale + 18;
    return Scaffold(
      appBar: AppBar(
        title: Text(list.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: english ? 'Edit list' : 'تعديل القائمة',
            onPressed: () => _editList(context, list),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: english ? 'Copy share code' : 'نسخ رمز المشاركة',
            onPressed: () => _copyList(context, list),
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: english ? 'Delete list' : 'حذف القائمة',
            onPressed: () => _deleteList(context, list),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: list.items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.playlist_add_rounded,
                        size: 42, color: HorseTheme.gold),
                    const SizedBox(height: 12),
                    Text(
                      english
                          ? 'This list is empty. Add titles from their detail pages.'
                          : 'هذه القائمة فارغة. أضف العناوين من صفحات التفاصيل.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1250),
                child: GridView.builder(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: posterWidth,
                    mainAxisExtent: rowExtent,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: list.items.length,
                  itemBuilder: (context, index) {
                    final entry = list.items[index];
                    final item = _toMediaItem(entry);
                    return Stack(
                      alignment: AlignmentDirectional.topEnd,
                      children: [
                        PosterCard(
                          item: item,
                          width: double.infinity,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => MediaDetailPage(item: item)),
                          ),
                        ),
                        Material(
                          color: Colors.black.withValues(alpha: .72),
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: english
                                ? 'Remove from list'
                                : 'إزالة من القائمة',
                            iconSize: 18,
                            constraints: const BoxConstraints.tightFor(
                                width: 38, height: 38),
                            onPressed: () =>
                                app.removeFromCustomList(list.id, entry.id),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
    );
  }
}

Future<void> _createList(BuildContext context) async {
  final app = context.read<AppState>();
  final english = app.english;
  final values = await _listForm(context, english: english);
  if (values == null || !context.mounted) return;
  try {
    await app.createCustomList(values.$1, description: values.$2);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(error.toString().replaceFirst('FormatException: ', ''))));
    }
  }
}

Future<void> _editList(BuildContext context, CustomMediaList list) async {
  final app = context.read<AppState>();
  final values = await _listForm(
    context,
    english: app.english,
    initialName: list.name,
    initialDescription: list.description ?? '',
  );
  if (values == null || !context.mounted) return;
  try {
    await app.renameCustomList(list.id,
        name: values.$1, description: values.$2);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(error.toString().replaceFirst('FormatException: ', ''))));
    }
  }
}

Future<(String, String?)?> _listForm(
  BuildContext context, {
  required bool english,
  String initialName = '',
  String initialDescription = '',
}) {
  return showDialog<(String, String?)>(
    context: context,
    builder: (_) => _CollectionFormDialog(
      english: english,
      initialName: initialName,
      initialDescription: initialDescription,
    ),
  );
}

class _CollectionFormDialog extends StatefulWidget {
  const _CollectionFormDialog({
    required this.english,
    required this.initialName,
    required this.initialDescription,
  });

  final bool english;
  final String initialName;
  final String initialDescription;

  @override
  State<_CollectionFormDialog> createState() => _CollectionFormDialogState();
}

class _CollectionFormDialogState extends State<_CollectionFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _description = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.english ? 'Collection details' : 'بيانات القائمة'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                maxLength: 80,
                autofocus: true,
                decoration: InputDecoration(
                    labelText: widget.english ? 'Name' : 'الاسم'),
                validator: (value) => value?.trim().isNotEmpty == true
                    ? null
                    : (widget.english ? 'Enter a name.' : 'أدخل اسم القائمة.'),
              ),
              TextField(
                controller: _description,
                maxLength: 200,
                maxLines: 3,
                decoration: InputDecoration(
                    labelText: widget.english ? 'Description' : 'الوصف'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.english ? 'Cancel' : 'إلغاء')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.pop(
              context,
              (_name.text.trim(), _description.text.trim()),
            );
          },
          child: Text(widget.english ? 'Save' : 'حفظ'),
        ),
      ],
    );
  }
}

Future<void> _importList(BuildContext context) async {
  final app = context.read<AppState>();
  final english = app.english;
  final input = await showDialog<String>(
    context: context,
    builder: (_) => _ImportListDialog(english: english),
  );
  if (input == null || !context.mounted) return;
  final shared = decodeCustomListShare(input);
  if (shared == null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(english
            ? 'That share code is invalid.'
            : 'رمز المشاركة غير صالح.')));
    return;
  }
  try {
    await app.importCustomList(
      name: shared.name,
      description: shared.description,
      items: shared.items,
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(error.toString().replaceFirst('FormatException: ', ''))));
    }
  }
}

class _ImportListDialog extends StatefulWidget {
  const _ImportListDialog({required this.english});
  final bool english;

  @override
  State<_ImportListDialog> createState() => _ImportListDialogState();
}

class _ImportListDialogState extends State<_ImportListDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.english ? 'Import a collection' : 'استيراد قائمة'),
        content: TextField(
          controller: _code,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: widget.english
                ? 'Share code or link'
                : 'رمز المشاركة أو الرابط',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(widget.english ? 'Cancel' : 'إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _code.text.trim()),
              child: Text(widget.english ? 'Import' : 'استيراد')),
        ],
      );
}

Future<void> _copyList(BuildContext context, CustomMediaList list) async {
  final english = context.read<AppState>().english;
  final code = encodeCustomListShare(list);
  if (code == null) return;
  await Clipboard.setData(ClipboardData(text: code));
  if (!context.mounted) return;
  NoorToast.show(
    context,
    english
        ? 'Share code copied. The recipient can import it in My Library.'
        : 'نُسخ رمز المشاركة. يمكن استيراده من مكتبتي.',
  );
}

Future<void> _deleteList(BuildContext context, CustomMediaList list) async {
  final app = context.read<AppState>();
  final english = app.english;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(english ? 'Delete this collection?' : 'حذف هذه القائمة؟'),
      content: Text(english
          ? 'Its saved titles will be removed from this collection.'
          : 'ستُزال العناوين المحفوظة من هذه القائمة.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(english ? 'Cancel' : 'إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(english ? 'Delete' : 'حذف')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await app.deleteCustomList(list.id);
  if (context.mounted) Navigator.of(context).pop();
}

class _CollectionEmpty extends StatelessWidget {
  const _CollectionEmpty({required this.english});
  final bool english;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: HorseTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HorseTheme.line),
        ),
        child: Text(
          english
              ? 'Create a collection for films and series you want to keep together.'
              : 'أنشئ قائمة لتجميع الأفلام والمسلسلات التي تريد حفظها معًا.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: HorseTheme.muted),
        ),
      );
}

class _ListArtwork extends StatelessWidget {
  const _ListArtwork({required this.item});
  final CustomListItem? item;

  @override
  Widget build(BuildContext context) {
    final poster = item?.poster;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: 42,
        height: 58,
        child: poster == null
            ? const ColoredBox(
                color: HorseTheme.raised,
                child: Icon(Icons.movie_outlined, color: HorseTheme.gold),
              )
            : Image.network(poster,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                    color: HorseTheme.raised,
                    child: Icon(Icons.movie_outlined, color: HorseTheme.gold))),
      ),
    );
  }
}

MediaItem _toMediaItem(CustomListItem item) => MediaItem(
      id: item.id,
      type: item.type,
      name: item.name,
      poster: item.poster,
      releaseInfo: item.releaseInfo,
      rating: item.rating,
    );
