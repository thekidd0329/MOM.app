import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/privacy_filter.dart';

void main() {
  group('MomPrivacyFilter', () {
    test('redacts direct contact identifiers before cloud upload', () {
      final result = MomPrivacyFilter.deidentify(
        'My friend Sarah called from (253) 555-0182 and emailed sarah@example.com.',
      );

      expect(result.text, contains('[PERSON]'));
      expect(result.text, contains('[PHONE]'));
      expect(result.text, contains('[EMAIL]'));
      expect(result.text, isNot(contains('Sarah')));
      expect(result.text, isNot(contains('253')));
      expect(result.text, isNot(contains('sarah@example.com')));
      expect(result.redactionCount, greaterThanOrEqualTo(3));
    });

    test('redacts street addresses and account-like numbers', () {
      final result = MomPrivacyFilter.deidentify(
        'Send it to 123 Main Street, Tacoma WA 98402. Card 4111 1111 1111 1111.',
      );

      expect(result.text, contains('[ADDRESS]'));
      expect(result.text, contains('[ACCOUNT_NUMBER]'));
      expect(result.text, isNot(contains('123 Main')));
      expect(result.text, isNot(contains('4111 1111')));
    });

    test('redacts self-identification and named public figures', () {
      final result = MomPrivacyFilter.deidentify(
        "My name is Jordan and my senator Alex Rivera called me.",
      );

      expect(result.text, isNot(contains('Jordan')));
      expect(result.text, isNot(contains('Alex Rivera')));
      expect(result.text, contains('[PERSON]'));
    });

    test('preserves non-identifying emotional and temporal context', () {
      final result = MomPrivacyFilter.deidentify(
        "I'm stressed because rent is due tomorrow and I need help planning.",
      );

      expect(result.text, contains('stressed'));
      expect(result.text, contains('rent is due tomorrow'));
      expect(result.redactionCount, 0);
      expect(result.isUseful, isTrue);
    });
  });
}
