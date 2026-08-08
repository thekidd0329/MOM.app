class DeidentifiedText {
  const DeidentifiedText({
    required this.text,
    required this.redactionCount,
    required this.redactionKinds,
  });

  final String text;
  final int redactionCount;
  final Set<String> redactionKinds;

  bool get isUseful => text.replaceAll(RegExp(r'\[[A-Z_]+\]'), '').trim().isNotEmpty;
}

class MomPrivacyFilter {
  MomPrivacyFilter._();

  static DeidentifiedText deidentify(String raw) {
    var text = raw.trim();
    var count = 0;
    final kinds = <String>{};

    String replace(RegExp pattern, String label, String kind) {
      text = text.replaceAllMapped(pattern, (match) {
        count++;
        kinds.add(kind);
        return label;
      });
      return text;
    }

    replace(
      RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', caseSensitive: false),
      '[EMAIL]',
      'email',
    );
    replace(
      RegExp(r'https?://\S+|www\.\S+', caseSensitive: false),
      '[URL]',
      'url',
    );
    replace(
      RegExp(r'(?<!\w)@[A-Za-z0-9_]{2,32}\b'),
      '[HANDLE]',
      'handle',
    );
    replace(
      RegExp(r'\b\d{3}-\d{2}-\d{4}\b'),
      '[SSN]',
      'ssn',
    );
    replace(
      RegExp(r'(?<!\d)(?:\+?1[ .-]?)?\(?[2-9]\d{2}\)?[ .-]?\d{3}[ .-]?\d{4}(?!\d)'),
      '[PHONE]',
      'phone',
    );
    replace(
      RegExp(r'\b(?:\d[ -]*?){13,19}\b'),
      '[ACCOUNT_NUMBER]',
      'account_number',
    );
    replace(
      RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
      '[IP_ADDRESS]',
      'ip_address',
    );
    replace(
      RegExp(r'(?<!\w)-?\d{1,3}\.\d{4,}\s*,\s*-?\d{1,3}\.\d{4,}(?!\w)'),
      '[COORDINATES]',
      'coordinates',
    );
    replace(
      RegExp(
        r'\b\d{1,6}\s+[A-Za-z0-9.\- ]{2,50}\s+(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct|Way|Place|Pl|Highway|Hwy)\b(?:[, ]+[^\n.!?]{0,45})?',
        caseSensitive: false,
      ),
      '[ADDRESS]',
      'address',
    );

    text = text.replaceAllMapped(
      RegExp(
        r"\b(?:my\s+name\s+is|i\s+am|i'm|call\s+me)\s+([A-Z][a-z]{1,30})(?:\s+[A-Z][a-z]{1,30})?\b",
      ),
      (match) {
        count++;
        kinds.add('person');
        final prefix = match.group(0)!.substring(0, match.group(0)!.indexOf(match.group(1)!));
        return '${prefix}[PERSON]';
      },
    );

    text = text.replaceAllMapped(
      RegExp(
        r'\b((?:my\s+)?(?:mom|mother|dad|father|parent|sister|brother|daughter|son|friend|girlfriend|boyfriend|wife|husband|partner|boss|manager|coworker|doctor|teacher|caseworker|lawyer|attorney|officer|detective|pastor|senator|representative|mayor|governor)\s+)([A-Z][a-z]{1,30})(?:\s+[A-Z][a-z]{1,30})?\b',
        caseSensitive: false,
      ),
      (match) {
        count++;
        kinds.add('person');
        return '${match.group(1)}[PERSON]';
      },
    );

    text = text.replaceAllMapped(
      RegExp(
        r'\b(?:i\s+live|i\s+stay|i\s+am\s+staying|i\s+moved|we\s+live|we\s+moved)\s+(?:in|at|near)\s+([A-Z][A-Za-z.\-]*(?:\s+[A-Z][A-Za-z.\-]*){0,3})\b',
        caseSensitive: false,
      ),
      (match) {
        count++;
        kinds.add('location');
        final full = match.group(0)!;
        final location = match.group(1)!;
        return full.replaceFirst(location, '[LOCATION]');
      },
    );

    text = text
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    return DeidentifiedText(
      text: text,
      redactionCount: count,
      redactionKinds: kinds,
    );
  }
}