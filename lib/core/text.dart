/// Tidies a merchant (or income source) name so the same place is always
/// written the same way: surrounding spaces dropped, inner runs of spaces
/// collapsed, and each word capitalised with the rest lower case
/// ("  trader JOE'S " → "Trader Joe's").
String normalizeMerchant(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');
