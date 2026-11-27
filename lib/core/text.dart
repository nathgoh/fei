/// Trims a merchant or income source name and collapses each run of spaces inside it into one space. Each word gets a
/// capital first letter and lowercase for the rest, so "  trader JOE'S " becomes "Trader Joe's".
String normalizeMerchant(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');
