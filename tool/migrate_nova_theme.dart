import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class Edit {
  Edit(this.start, this.end, this.value);
  final int start, end;
  final String value;
}

class ThemeVisitor extends RecursiveAstVisitor<void> {
  final changes = <Edit>[];
  final constants = <int, Edit>{};
  bool hasContext(AstNode node) {
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      if (p.runtimeType.toString().contains('FormalParameter')) return false;
      if (p is MethodDeclaration && p.isStatic) return false;
      if (p is MethodDeclaration &&
          (p.parameters?.toSource().contains('BuildContext context') ??
              false)) {
        return true;
      }
      if (p is FunctionExpression &&
          (p.parameters?.toSource().contains('context') ?? false)) {
        return true;
      }
      if (p is ClassDeclaration &&
          (p.extendsClause?.superclass.toSource().startsWith('State<') ??
              false)) {
        return true;
      }
    }
    return false;
  }

  void unconst(AstNode node) {
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      if (p is InstanceCreationExpression && p.keyword?.lexeme == 'const') {
        final k = p.keyword!;
        constants[k.offset] = Edit(k.offset, k.end, '');
      }
      if (p is TypedLiteral && p.constKeyword != null) {
        final k = p.constKeyword!;
        constants[k.offset] = Edit(k.offset, k.end, '');
      }
      if (p is VariableDeclarationList && p.keyword?.lexeme == 'const') {
        final k = p.keyword!;
        constants[k.offset] = Edit(k.offset, k.end, 'final');
      }
    }
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'HorseTheme' &&
        const ['canvas', 'surface', 'raised', 'line', 'gold', 'ink', 'muted']
            .contains(node.identifier.name) &&
        hasContext(node)) {
      changes.add(Edit(node.offset, node.end,
          'NovaTheme.of(context).${node.identifier.name}'));
      unconst(node);
    }
    super.visitPrefixedIdentifier(node);
  }
}

void main(List<String> args) {
  var total = 0;
  for (final file in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    final path = file.path.replaceAll('\\', '/');
    if (path.contains('/theme/') || path.contains('/player/')) continue;
    if (args.isNotEmpty && !args.any(path.startsWith)) continue;
    var source = file.readAsStringSync();
    final visitor = ThemeVisitor();
    parseString(content: source).unit.accept(visitor);
    final changes = [...visitor.changes, ...visitor.constants.values]
      ..sort((a, b) => b.start.compareTo(a.start));
    for (final e in changes) {
      source = source.replaceRange(e.start, e.end, e.value);
    }
    if (changes.isNotEmpty) {
      file.writeAsStringSync(source);
      total += visitor.changes.length;
    }
  }
  stdout.writeln('Migrated $total context-bound palette roles.');
}
