import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/main.dart';

void main() {
  test('MOM app root is MomApp', () {
    const app = MomApp();
    expect(app, isA<MomApp>());
  });
}
