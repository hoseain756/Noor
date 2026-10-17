"""Replace stray Material accent/neutral literals with supplied NOVA roles."""
from pathlib import Path
import re

root = Path('lib')
skip = {
    'core/theme/nova_theme.dart',
    # These parsers deliberately accept user-selected subtitle colors.
    'shared/widgets/color_picker_dialog.dart',
    'features/settings/settings_preferences_page.dart',
    'features/player/widgets/subtitle_overlay.dart',
}
variants = {
    'black12': ('ink', '.12'), 'black26': ('ink', '.26'),
    'black38': ('ink', '.38'), 'black45': ('ink', '.45'),
    'black54': ('scrim', None), 'black87': ('ink', '.87'),
    'white12': ('white', '.12'), 'white24': ('white', '.24'),
    'white30': ('white', '.30'), 'white38': ('white', '.38'),
    'white54': ('white', '.54'), 'white70': ('white', '.70'),
}
changed = 0
for path in root.rglob('*.dart'):
    rel = path.as_posix().removeprefix('lib/')
    if rel in skip:
        continue
    source = path.read_text(encoding='utf-8')
    original = source
    for name, (role, alpha) in variants.items():
        replacement = f'NovaColors.{role}' if alpha is None else f'NovaColors.{role}.withValues(alpha: {alpha})'
        source = source.replace(f'Colors.{name}', replacement)
    source = re.sub(r'Colors\.black(?![A-Za-z0-9_])', 'NovaColors.ink', source)
    source = re.sub(r'Colors\.white(?![A-Za-z0-9_])', 'NovaColors.white', source)
    source = source.replace('Colors.red', 'NovaColors.red')
    source = source.replace('Colors.green', 'NovaColors.success')
    source = source.replace('Colors.orange', 'NovaColors.warning')
    source = source.replace('Colors.yellow', 'NovaColors.rating')
    source = source.replace('Color(0xB808080A)', 'NovaColors.scrim')
    source = source.replace('Color(0x99000000)', 'NovaColors.scrim')
    if source != original and "import 'package:noor_mobile/core/theme/nova_theme.dart';" not in source and \
       "import 'core/theme/nova_theme.dart';" not in source and \
       "import '../../core/theme/nova_theme.dart';" not in source and \
       "import '../../../core/theme/nova_theme.dart';" not in source and \
       "import '../../../../core/theme/nova_theme.dart';" not in source and \
       "import 'horse_theme.dart';" not in source and 'horse_theme.dart' not in source:
        source = "import 'package:noor_mobile/core/theme/nova_theme.dart';\n" + source
    if source != original:
        path.write_text(source, encoding='utf-8', newline='')
        changed += 1
print(f'Applied supplied NOVA palette roles in {changed} Dart files.')
