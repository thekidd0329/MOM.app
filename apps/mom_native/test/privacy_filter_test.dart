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
      expect(result.safeForCloud, isTrue);
    });

    test('redacts street addresses and account-like numbers', () {
      final result = MomPrivacyFilter.deidentify(
        'Send it to 123 Main Street, Tacoma WA 98402. Card 4111 1111 1111 1111.',
      );

      expect(result.text, contains('[ADDRESS]'));
      expect(result.text, contains('[ACCOUNT_NUMBER]'));
      expect(result.text, isNot(contains('123 Main')));
      expect(result.text, isNot(contains('4111 1111')));
      expect(result.safeForCloud, isTrue);
    });

    test('redacts self-identification and named public figures', () {
      final result = MomPrivacyFilter.deidentify(
        "My name is Jordan and my senator Alex Rivera called me.",
      );

      expect(result.text, isNot(contains('Jordan')));
      expect(result.text, isNot(contains('Alex Rivera')));
      expect(result.text, contains('[PERSON]'));
      expect(result.safeForCloud, isTrue);
    });

    test('generalizes a person named after an interaction verb', () {
      final result = MomPrivacyFilter.deidentify(
        'I talked to Marcus about school and I need advice.',
      );

      expect(result.text, isNot(contains('Marcus')));
      expect(result.text, contains('[PERSON]'));
      expect(result.safeForCloud, isTrue);
    });

    test('generalizes a named person leading a sentence', () {
      final result = MomPrivacyFilter.deidentify(
        'Sarah told me I should slow down and think about it.',
      );

      expect(result.text, isNot(contains('Sarah')));
      expect(result.text, contains('[PERSON]'));
      expect(result.safeForCloud, isTrue);
    });

    test('generalizes an exact home location', () {
      final result = MomPrivacyFilter.deidentify(
        'I live in Tacoma and I am trying to find a new job.',
      );

      expect(result.text, isNot(contains('Tacoma')));
      expect(result.text, contains('[LOCATION]'));
      expect(result.safeForCloud, isTrue);
    });

    test('fails closed when an unexplained proper name remains', () {
      final result = MomPrivacyFilter.deidentify(
        'I think Sarah upset me yesterday and I need to vent.',
      );

      expect(result.safeForCloud, isFalse);
      expect(result.isUseful, isFalse);
    });

    test('preserves non-identifying emotional and temporal context', () {
      final result = MomPrivacyFilter.deidentify(
        "I'm stressed because rent is due tomorrow and I need help planning.",
      );

      expect(result.text, contains('stressed'));
      expect(result.text, contains('rent is due tomorrow'));
      expect(result.redactionCount, 0);
      expect(result.safeForCloud, isTrue);
      expect(result.isUseful, isTrue);
    });
  });
}
