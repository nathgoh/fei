/// Trims a merchant or income source name and collapses each run of spaces inside it into one space. The casing stays
/// exactly as typed, so "  PG&E " becomes "PG&E" and "e  Bay" becomes "e Bay".
String normalizeMerchant(String name) => name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');

/// Returns the key that two merchant names share when they differ only in case or spacing. Dart's toLowerCase handles
/// letters outside ASCII, so "ÉLAN" and "élan" share a key.
String merchantKey(String name) => normalizeMerchant(name).toLowerCase();
