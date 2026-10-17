// One-time migration helper. ARB remains editable and is the source of truth.
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

final enFile = File('lib/l10n/app_en.arb');
final arFile = File('lib/l10n/app_ar.arb');
final en = jsonDecode(enFile.readAsStringSync()) as Map<String, dynamic>;
final ar = jsonDecode(arFile.readAsStringSync()) as Map<String, dynamic>;
int sequence = en.keys.map((key) => int.tryParse(key.replaceFirst('message', '')) ?? 0).fold(0, (a,b) => a > b ? a : b);
String keyFor(String english, String arabic) {
  for (final entry in en.entries) {
    if (!entry.key.startsWith('@') && entry.value == english && ar[entry.key] == arabic) return entry.key;
  }
  final key = 'message${++sequence}'; en[key] = english; ar[key] = arabic; return key;
}

class Patch { Patch(this.start, this.end, this.value); final int start, end; final String value; }
String? template(StringLiteral node, List<String> expressions) {
  if (node is SimpleStringLiteral) return node.value;
  if (node is AdjacentStrings) {
    final parts = node.strings.map((part) => template(part, expressions)).toList();
    if (parts.contains(null)) return null; return parts.join();
  }
  if (node is StringInterpolation) {
    final result = StringBuffer();
    for (final element in node.elements) {
      if (element is InterpolationString) result.write(element.value);
      if (element is InterpolationExpression) {
        final source = element.expression.toSource();
        if (!expressions.contains(source)) expressions.add(source);
        result.write('{p${expressions.indexOf(source)}}');
      }
    }
    return result.toString();
  }
  return null;
}
class Extractor extends RecursiveAstVisitor<void> {
  final edits = <Patch>[];
  final constEdits = <int, Patch>{};
  void pair(StringLiteral english, StringLiteral arabic) {
    final expressions = <String>[];
    final a = template(english, expressions), b = template(arabic, expressions);
    if (a == null || b == null || expressions.isNotEmpty) return;
    final key = keyFor(a, b);
    edits.add(Patch(english.offset, english.end, "NovaStrings.lookup(true, '$key')"));
    edits.add(Patch(arabic.offset, arabic.end, "NovaStrings.lookup(false, '$key')"));
    unconst(english); unconst(arabic);
  }
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final named = <String, Expression>{for (final arg in node.argumentList.arguments.whereType<NamedArgument>()) arg.name.lexeme.toLowerCase(): arg.argumentExpression};
    for (final names in [['english', 'arabic'], ['en', 'ar'], ['labelen','labelar'], ['titleen','titlear'], ['subtitleen','subtitlear']]) {
      final a = named[names[0]], b = named[names[1]];
      if (a is StringLiteral && b is StringLiteral) pair(a,b);
    }
    final positional = node.argumentList.arguments.where((a) => a is! NamedArgument).map((a) => a.argumentExpression).whereType<StringLiteral>().toList();
    if (node.constructorName.type.toSource() == '_Option' && positional.length >= 3) {
      pair(positional[2], positional[1]);
    }
    super.visitInstanceCreationExpression(node);
  }
  void unconst(AstNode node) {
    for (AstNode? parent = node.parent; parent != null; parent = parent.parent) {
      if (parent is InstanceCreationExpression && parent.keyword?.lexeme == 'const') {
        final token = parent.keyword!; constEdits[token.offset] = Patch(token.offset, token.end, '');
      }
      if (parent is TypedLiteral && parent.constKeyword != null) {
        final token = parent.constKeyword!; constEdits[token.offset] = Patch(token.offset, token.end, '');
      }
      if (parent is VariableDeclarationList && parent.keyword?.lexeme == 'const') {
        final token = parent.keyword!; constEdits[token.offset] = Patch(token.offset, token.end, 'final');
      }
    }
  }
  bool replace(AstNode node, StringLiteral english, StringLiteral arabic, String prefix) {
    final expressions = <String>[];
    final a = template(english, expressions), b = template(arabic, expressions);
    if (a == null || b == null || (const ['en','ar','en-US','ar-SA','ltr','rtl'].contains(a) && const ['en','ar','en-US','ar-SA','ltr','rtl'].contains(b))) return false;
    final key = keyFor(a, b);
    final args = expressions.isEmpty ? '' : ", {${[for (var i=0;i<expressions.length;i++) "'p$i': ${expressions[i]}"].join(', ')}}";
    edits.add(Patch(node.offset, node.end, "$prefix'$key'$args)"));
    unconst(node); return true;
  }
  @override
  void visitConditionalExpression(ConditionalExpression node) {
    final condition = node.condition.toSource();
    if (condition.toLowerCase().contains('english') && node.thenExpression is StringLiteral && node.elseExpression is StringLiteral) {
      if (replace(node, node.thenExpression as StringLiteral, node.elseExpression as StringLiteral, 'NovaStrings.lookup($condition, ')) return;
    }
    super.visitConditionalExpression(node);
  }
  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 't' && node.argumentList.arguments.length == 2 && node.target != null &&
        node.argumentList.arguments.every((arg) => arg.argumentExpression is StringLiteral)) {
      if (replace(node, node.argumentList.arguments[0].argumentExpression as StringLiteral, node.argumentList.arguments[1].argumentExpression as StringLiteral,
          '${node.target!.toSource()}.tr(')) return;
    }
    super.visitMethodInvocation(node);
  }
}
void main(List<String> args) {
  var files = 0, messages = 0;
  final writes = <File,String>{};
  for (final file in Directory('lib').listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart') && !file.path.contains('l10n') && !file.path.replaceAll('\\','/').contains('/core/'))) {
    if (args.isNotEmpty && !args.any((arg) => file.path.replaceAll('\\', '/').startsWith(arg))) continue;
    var source = file.readAsStringSync();
    final visitor = Extractor();
    parseString(content: source).unit.accept(visitor);
    if (visitor.edits.isEmpty) continue;
    final edits = [...visitor.edits, ...visitor.constEdits.values.where((e) => !visitor.edits.any((p) => e.start >= p.start && e.end <= p.end))]
      ..sort((a,b) => b.start.compareTo(a.start));
    for (final edit in edits) { source = source.replaceRange(edit.start, edit.end, edit.value); }
    if (source.contains('NovaStrings.') && !source.contains("import 'package:noor_mobile/l10n/nova_strings.dart'")) {
      final found = source.indexOf('import ');
      final first = found < 0 ? 0 : found;
      source = source.replaceRange(first, first, "import 'package:noor_mobile/l10n/nova_strings.dart';\n");
    }
    writes[file] = source; files++; messages += visitor.edits.length;
  }
  const encoder = JsonEncoder.withIndent('  ');
  enFile.writeAsStringSync(encoder.convert(en)); arFile.writeAsStringSync(encoder.convert(ar));
  for (final entry in writes.entries) { entry.key.writeAsStringSync(entry.value); }
  stdout.writeln('Extracted $messages expressions across $files files; ${en.length-1} ARB entries.');
}
