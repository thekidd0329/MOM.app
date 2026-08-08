class DeidentifiedText {
  const DeidentifiedText({
    required this.text,
    required this.redactionCount,
    required this.redactionKinds,
    required this.safeForCloud,
  });

  final String text;
  final int redactionCount;
  final Set<String> redactionKinds;
  final bool safeForCloud;

  bool get isUseful =>
      safeForCloud &&
      text.replaceAll(RegExp(r'\[[A-Z_]+\]'), '').trim().isNotEmpty;
}

class MomPrivacyFilter {
  MomPrivacyFilter._();

  static final List<RegExp> _directIdentifierPatterns = [
    RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', caseSensitive: false),
    RegExp(r'https?://\S+|www\.\S+', caseSensitive: false),
    RegExp(r'(?<!\w)@[A-Za-z0-9_]{2,32}\b'),
    RegExp(r'\b\d{3}-\d{2}-\d{4}\b'),
    RegExp(r'(?<!\d)(?:\+?1[ .-]?)?\(?[2-9]\d{2}\)?[ .-]?\d{3}[ .-]?\d{4}(?!\d)'),
    RegExp(r'\b(?:\d[ -]*?){13,19}\b'),
    RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
    RegExp(r'(?<!\w)-?\d{1,3}\.\d{4,}\s*,\s*-?\d{1,3}\.\d{4,}(?!\w)'),
  ];

  static const _safeCapitalizedWords = <String>{
    'I',
    'MOM',
    'Mom',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
    'Today',
    'Tonight',
    'Tomorrow',
    'Yesterday',
  };

  static DeidentifiedText deidentify(String raw) {
    var text = raw.trim();
    var count = 0;
    final kinds = <String>{};

    void replace(RegExp pattern, String label, String kind) {
      text = text.replaceAllMapped(pattern, (_) {
        count++;
        kinds.add(kind);
        return label;
      });
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
    replace(RegExp(r'\b\d{3}-\d{2}-\d{4}\b'), '[SSN]', 'ssn');
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
    replace(
      RegExp(
        r'\b(?:born|birthday|date\s+of\s+birth|dob)\s*(?:is|was|:)?\s*(?:on\s+)?(?:\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s+\d{4})?)',
        caseSensitive: false,
      ),
      '[BIRTH_DATE]',
      'birth_date',
    );

    text = text.replaceAllMapped(
      RegExp(
        r'\b(?:my\s+name\s+is|call\s+me)\s+([A-Za-z][A-Za-z\-]{1,30})(?:\s+[A-Za-z][A-Za-z\-]{1,30})?\b',
        caseSensitive: false,
      ),
      (match) {
        count++;
        kinds.add('person');
        final whole = match.group(0)!;
        final firstName = match.group(1)!;
        final prefixEnd = whole.toLowerCase().indexOf(firstName.toLowerCase());
        if (prefixEnd < 0) return '[PERSON]';
        return '${whole.substring(0, prefixEnd)}[PERSON]';
      },
    );

    text = text.replaceAllMapped(
      RegExp(
        r"\b(?:I\s+am|I'm|i\s+am|i'm)\s+([A-Z][a-z]{1,30})(?:\s+[A-Z][a-z]{1,30})?\b",
      ),
      (match) {
        count++;
        kinds.add('person');
        final whole = match.group(0)!;
        final firstName = match.group(1)!;
        final prefixEnd = whole.indexOf(firstName);
        if (prefixEnd < 0) return '[PERSON]';
        return '${whole.substring(0, prefixEnd)}[PERSON]';
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
        r'\b((?:with|from|to|about|called|texted|messaged|met|saw|visited|helped|asked|told|talked\s+to|spoke\s+with)\s+)([A-Z][a-z]{1,30})(?:\s+[A-Z][a-z]{1,30})?\b',
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
        r'(^|[.!?]\s+)([A-Z][a-z]{1,30})(?:\s+[A-Z][a-z]{1,30})?(?=\s+(?:said|told|asked|called|texted|messaged|thinks|thought|wants|wanted|needs|needed|is|was|has|had)\b)',
        multiLine: true,
      ),
      (match) {
        final candidate = match.group(2)!;
        if (_safeCapitalizedWords.contains(candidate)) return match.group(0)!;
        count++;
        kinds.add('person');
        return '${match.group(1)}[PERSON]';
      },
    );

    text = text.replaceAllMapped(
      RegExp(r"\b([A-Z][a-z]{1,30})'s\b"),
      (match) {
        final word = match.group(1)!;
        if (_safeCapitalizedWords.contains(word)) return match.group(0)!;
        count++;
        kinds.add('person');
        return "[PERSON]'s";
      },
    );

    text = text.replaceAllMapped(
      RegExp(
        r'\b((?:i\s+live|i\s+stay|i\s+am\s+staying|i\s+moved|we\s+live|we\s+moved|i\s+am\s+from|i\s+grew\s+up)\s+(?:in|at|near|to|from)\s+)([A-Z][A-Za-z.\-]*(?:\s+[A-Z][A-Za-z.\-]*){0,3})\b',
        caseSensitive: false,
      ),
      (match) {
        count++;
        kinds.add('location');
        return '${match.group(1)}[LOCATION]';
      },
    );

    text = text.replaceAllMapped(
      RegExp(
        r'(^|[.!?]\s+)([A-Z][A-Za-z.\-]*(?:\s+[A-Z][A-Za-z.\-]*){0,3})(?=\s+is\s+where\s+(?:i|we)\s+live\b)',
        multiLine: true,
      ),
      (match) {
        count++;
        kinds.add('location');
        return '${match.group(1)}[LOCATION]';
      },
    );

    text = text.replaceAllMapped(
      RegExp(
        r'\b((?:going|went|driving|drove|traveling|travelling|flew|flying|staying|working|worked|school|hospital|court)\s+(?:in|at|to|near)\s+)([A-Z][A-Za-z.\-]*(?:\s+[A-Z][A-Za-z.\-]*){0,3})\b',
        caseSensitive: false,
      ),
      (match) {
        count++;
        kinds.add('location');
        return '${match.group(1)}[LOCATION]';
      },
    );

    text = text.replaceAllMapped(
      RegExp(
        r'\b((?:work|worked|working|employed|school|study|studied|attend|attended)\s+(?:for|at)\s+)([A-Z][A-Za-z0-9&.\-]*(?:\s+[A-Z][A-Za-z0-9&.\-]*){0,4})\b',
        caseSensitive: false,
      ),
      (match) {
        count++;
        kinds.add('organization');
        return '${match.group(1)}[ORGANIZATION]';
      },
    );

    text = text
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    final safe = !_containsDirectIdentifier(text) &&
        !_containsResidualProperName(text);

    return DeidentifiedText(
      text: text,
      redactionCount: count,
      redactionKinds: kinds,
      safeForCloud: safe,
    );
  }

  static bool _containsDirectIdentifier(String text) =>
      _directIdentifierPatterns.any((pattern) => pattern.hasMatch(text));

  static bool _containsResidualProperName(String text) {
    final cleaned = text.replaceAll(RegExp(r'\[[A-Z_]+\]'), '');
    final matches = RegExp(r'\b[A-Z][a-z]{1,30}\b').allMatches(cleaned);
    for (final match in matches) {
      final word = match.group(0)!;
      if (_safeCapitalizedWords.contains(word)) continue;

      final index = match.start;
      var atSentenceStart = index == 0;
      if (!atSentenceStart) {
        var cursor = index - 1;
        while (cursor >= 0 && cleaned[cursor].trim().isEmpty) {
          cursor--;
        }
        atSentenceStart = cursor < 0 || '.!?\n'.contains(cleaned[cursor]);
      }
      if (atSentenceStart) continue;
      return true;
    }
    return false;
  }
}
