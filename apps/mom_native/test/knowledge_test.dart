import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/knowledge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('live repository files become searchable knowledge', () async {
    final root = await Directory.systemTemp.createTemp('mom_knowledge_test_');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/personality.md').writeAsString('MOM values direct accountability and grounded warmth.');
    await Directory('${root.path}/models').create();
    await File('${root.path}/models/ignored.txt').writeAsString('secret model folder marker');

    final service = KnowledgeService();
    await service.load(repoRoot: root.path);

    expect(service.search('accountability').any((h) => h.entry.path.contains('personality.md')), isTrue);
    expect(service.search('secret model folder marker').any((h) => h.entry.path.contains('ignored.txt')), isFalse);
  });
}
