"""Idempotent migration of legacy icons, palette literals and network images."""
from pathlib import Path
import re, sys
icons = dict(zip('add auto_awesome bolt bookmark brightness_6 center_focus_strong check_circle_outline check_circle check chevron_left chevron_right close cloud_off content_paste delete_outline error_outline extension fast_forward grid_view history info_outline keyboard_arrow_down lock_outline lock movie play_arrow playlist_add_check playlist_add playlist_remove radio_button_unchecked refresh remove save search_off search skip_next star swap_vert view_list visibility volume_up'.split(), 'plus sparkles zap bookmark sunMoon scan circleCheck circleCheck check chevronLeft chevronRight x cloudOff clipboard trash2 circleAlert puzzle fastForward layoutGrid history info chevronDown lockKeyhole lockKeyhole film play listChecks listPlus listX circle refreshCw minus save searchX search skipForward star arrowDownUp list eye volume2'.split()))
palette = {'D13B47':'red','9E2A34':'redDeep','E8858D':'redSoft','F9E4E6':'blush','141417':'ink','232329':'graphite','2E2E35':'surfaceHigh','3A3A42':'divider','FFFFFF':'white','A4A4AC':'mist','6E6E78':'textDisabled','3FB27F':'success','E8A93B':'warning','4C8DE0':'info','E5484D':'error','F5C451':'rating','F6F6F7':'lightBackground','585862':'lightTextSecondary','B82C39':'lightAccent','DCDCE0':'lightDivider'}
def closest(value):
    rgb=[int(value[i:i+2],16) for i in (0,2,4)]
    return min(palette, key=lambda h:sum((rgb[i]-int(h[i*2:i*2+2],16))**2 for i in range(3)))
for p in Path('lib').rglob('*.dart'):
    path=p.as_posix()
    if '/l10n/' in path or '/theme/' in path or '/player/' in path:continue
    if len(sys.argv)>1 and not any(path.startswith(arg) for arg in sys.argv[1:]):continue
    s=p.read_text(encoding='utf-8'); old=s
    def icon(m):
        raw=m.group(1); name=re.sub(r'_(rounded|outlined|sharp)$','',raw)
        target=icons.get(name)
        if not target: print('UNMAPPED',raw,p);return m[0]
        return 'LucideIcons.'+target
    s=re.sub(r'(?<!Lucide)Icons\.([a-zA-Z0-9_]+)',icon,s)
    def color(m):
        h=m[1].upper();a=h[:2];rgb=h[2:]
        if a=='FF':return 'NovaColors.'+palette.get(rgb,palette[closest(rgb)])
        if rgb=='000000':return f'NovaColors.ink.withAlpha({int(a,16)})'
        return f'NovaColors.{palette.get(rgb,palette[closest(rgb)])}.withAlpha({int(a,16)})'
    # Preserve constant alpha colours until AST migration can de-const safely.
    s=re.sub(r'(?:const\s+)?Color\(0x(FF[0-9A-Fa-f]{6})\)',color,s)
    s=s.replace('Image.network(', 'NovaNetworkImage(')
    imports=[]
    if 'LucideIcons.' in s and "package:lucide_icons_flutter/lucide_icons.dart" not in s:imports.append("import 'package:lucide_icons_flutter/lucide_icons.dart';")
    if 'NovaNetworkImage(' in s and 'nova_network_image.dart' not in s:imports.append("import 'package:nova_mobile/shared/widgets/nova_network_image.dart';")
    if 'NovaColors.' in s and 'horse_theme.dart' not in s and 'nova_theme.dart' not in s:imports.append("import 'package:nova_mobile/core/theme/nova_theme.dart';")
    if imports:
        i=s.find('import ');s=s[:i]+'\n'.join(imports)+'\n'+s[i:]
    if s!=old:p.write_text(s,encoding='utf-8')
