import 'package:noor_mobile/l10n/nova_strings.dart';
import 'package:noor_mobile/shared/widgets/nova_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/data/custom_list_share.dart';
import '../../core/models/custom_list.dart';
import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../shared/widgets/image_decode.dart';
import '../../shared/widgets/noor_toast.dart';
import '../../shared/widgets/poster_card.dart';
import '../media/media_detail_page.dart';
import '../shell/nova_browse_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Sliver panel: collections are created only as they approach the viewport.
class CustomListsPanel extends StatelessWidget {
  const CustomListsPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return SliverMainAxisGroup(slivers: [
      SliverToBoxAdapter(
          child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
              child: Wrap(spacing: 12, runSpacing: 12, children: [
                FilledButton.icon(
                    onPressed: () => _createList(context),
                    icon: const Icon(LucideIcons.plus),
                    label: Text(app.tr('message605'))),
                OutlinedButton.icon(
                    onPressed: () => _importList(context),
                    icon: const Icon(LucideIcons.import),
                    label: Text(app.tr('message606'))),
              ]))),
      if (app.customLists.isEmpty)
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: _CollectionEmpty(english: app.english)))
      else
        SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
            sliver: SliverList.separated(
                itemCount: app.customLists.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final list = app.customLists[index];
                  return Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    CustomListDetailPage(listId: list.id))),
                        child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(children: [
                              SizedBox(
                                  width: 88,
                                  height: 96,
                                  child: Stack(children: [
                                    for (var i = 0;
                                        i <
                                            (list.items.length < 3
                                                ? list.items.length
                                                : 3);
                                        i++)
                                      PositionedDirectional(
                                          start: i * 18.0,
                                          top: i * 5.0,
                                          child: Transform.rotate(
                                              angle: (i - 1) * .07,
                                              child: _ListArtwork(
                                                  item: list.items[i]))),
                                    if (list.items.isEmpty)
                                      Center(
                                          child: Icon(LucideIcons.library,
                                              size: 36,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary)),
                                  ])),
                              const SizedBox(width: 16),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(list.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    const SizedBox(height: 8),
                                    Text(
                                        '${list.items.length} ${app.tr('message607')}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary)),
                                    if (list.description?.isNotEmpty ==
                                        true) ...[
                                      const SizedBox(height: 8),
                                      Text(list.description!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall)
                                    ],
                                  ])),
                              const SizedBox(width: 12),
                              Icon(Directionality.of(context) ==
                                      TextDirection.rtl
                                  ? LucideIcons.chevronLeft
                                  : LucideIcons.chevronRight),
                            ]))),
                  );
                })),
    ]);
  }
}

class CustomListDetailPage extends StatelessWidget {
  const CustomListDetailPage({super.key, required this.listId});
  final String listId;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list =
        app.customLists.where((entry) => entry.id == listId).firstOrNull;
    return Scaffold(
        appBar: AppBar(title: Text(app.tr('message608'))),
        body: list == null
            ? Center(child: Text(app.tr('message609')))
            : Center(
                child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: CustomScrollView(slivers: [
                  SliverToBoxAdapter(
                      child: NovaBrowseHeader(
                          compact: true,
                          title: list.name,
                          eyebrow:
                              '${list.items.length} ${app.tr('message610')}',
                          subtitle: list.description ?? app.tr('message611'),
                          actions: [
                        FilledButton.tonalIcon(
                            onPressed: () => _copyList(context, list),
                            icon: const Icon(LucideIcons.share2),
                            label: Text(app.tr('message139'))),
                        OutlinedButton.icon(
                            onPressed: () => _editList(context, list),
                            icon: const Icon(LucideIcons.pencil),
                            label: Text(app.tr('message612'))),
                        IconButton(
                            tooltip: app.tr('message613'),
                            onPressed: () => _deleteList(context, list),
                            icon: const Icon(LucideIcons.trash2)),
                      ])),
                  if (list.items.isEmpty)
                    SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                            child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(LucideIcons.library,
                                          size: 48,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary),
                                      const SizedBox(height: 16),
                                      Text(app.tr('message614'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge,
                                          textAlign: TextAlign.center),
                                      const SizedBox(height: 8),
                                      Text(app.tr('message615'),
                                          textAlign: TextAlign.center),
                                    ]))))
                  else
                    SliverPadding(
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 48),
                        sliver: SliverLayoutBuilder(
                            builder: (context, constraints) {
                          final columns = (constraints.crossAxisExtent / 190)
                              .floor()
                              .clamp(2, 7);
                          final width = (constraints.crossAxisExtent -
                                  (columns - 1) * 20) /
                              columns;
                          return SliverGrid.builder(
                              itemCount: list.items.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisExtent: width / .72 +
                                          78 *
                                              MediaQuery.textScalerOf(context)
                                                  .scale(1),
                                      crossAxisSpacing: 20,
                                      mainAxisSpacing: 24),
                              itemBuilder: (_, index) {
                                final entry = list.items[index];
                                final item = _toMediaItem(entry);
                                return Stack(
                                    alignment: AlignmentDirectional.topEnd,
                                    children: [
                                      PosterCard(
                                          item: item,
                                          width: width,
                                          onTap: () => Navigator.of(context)
                                              .push(MaterialPageRoute<void>(
                                                  builder: (_) =>
                                                      MediaDetailPage(
                                                          item: item)))),
                                      Material(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHigh,
                                          shape: const CircleBorder(),
                                          child: IconButton(
                                              tooltip: app.tr('message616'),
                                              constraints:
                                                  const BoxConstraints.tightFor(
                                                      width: 48, height: 48),
                                              onPressed: () {
                                                app.removeFromCustomList(
                                                    list.id, entry.id);
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                        content: Text(app
                                                            .tr('message617')),
                                                        action: SnackBarAction(
                                                            label: app.tr(
                                                                'message618'),
                                                            onPressed: () => app
                                                                .addToCustomList(
                                                                    list.id,
                                                                    item))));
                                              },
                                              icon: const Icon(LucideIcons.x,
                                                  size: 20))),
                                    ]);
                              });
                        })),
                ]),
              )));
  }
}

Future<void> createNovaCollection(BuildContext context) => _createList(context);

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
      icon: const Icon(LucideIcons.library, size: 32),
      title: Text(NovaStrings.lookup(widget.english, 'message619')),
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
                    labelText:
                        NovaStrings.lookup(widget.english, 'message620')),
                validator: (value) => value?.trim().isNotEmpty == true
                    ? null
                    : (NovaStrings.lookup(widget.english, 'message621')),
              ),
              TextField(
                controller: _description,
                maxLength: 200,
                maxLines: 3,
                decoration: InputDecoration(
                    labelText:
                        NovaStrings.lookup(widget.english, 'message622')),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(NovaStrings.lookup(widget.english, 'cancel'))),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.pop(
              context,
              (_name.text.trim(), _description.text.trim()),
            );
          },
          child: Text(NovaStrings.lookup(widget.english, 'save')),
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
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(NovaStrings.lookup(english, 'message623'))));
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
        icon: const Icon(LucideIcons.import, size: 32),
        title: Text(NovaStrings.lookup(widget.english, 'message624')),
        content: TextField(
          controller: _code,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: NovaStrings.lookup(widget.english, 'message625'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(NovaStrings.lookup(widget.english, 'cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, _code.text.trim()),
              child: Text(NovaStrings.lookup(widget.english, 'message626'))),
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
    NovaStrings.lookup(english, 'message627'),
  );
}

Future<void> _deleteList(BuildContext context, CustomMediaList list) async {
  final app = context.read<AppState>();
  final english = app.english;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(LucideIcons.trash2, size: 32),
      title: Text(NovaStrings.lookup(english, 'message628')),
      content: Text(NovaStrings.lookup(english, 'message629')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(NovaStrings.lookup(english, 'cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(NovaStrings.lookup(english, 'message384'))),
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
          color: NovaTheme.of(context).surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NovaTheme.of(context).line),
        ),
        child: Text(
          NovaStrings.lookup(english, 'message630'),
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: NovaTheme.of(context).muted),
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
            ? ColoredBox(
                color: NovaTheme.of(context).raised,
                child:
                    Icon(LucideIcons.film, color: NovaTheme.of(context).gold),
              )
            : NovaNetworkImage(poster,
                fit: BoxFit.cover,
                // Task 136: decode at the 42px list thumbnail size.
                cacheWidth: imageCacheWidth(context, 42),
                errorBuilder: (_, __, ___) => ColoredBox(
                    color: NovaTheme.of(context).raised,
                    child: Icon(LucideIcons.film,
                        color: NovaTheme.of(context).gold))),
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
