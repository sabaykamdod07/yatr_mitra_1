/// Reads an amount typed by a person.
///
/// Accepts the ways people really write money:
///   15000      15,000      1,50,000      15000.50      Rs. 15,000      ₹15,000
/// and returns null for anything that is not a sensible amount (letters, two dots, more
/// than two decimals, empty). Commas, spaces and the rupee sign are ignored.
num? parseMoney(String? input) {
  if (input == null) return null;
  var s = input.trim();
  if (s.isEmpty) return null;

  // the rupee sign, "Rs", "Rs." and "INR"
  s = s.replaceAll(RegExp(r'(rs\.?|inr|\u20B9)', caseSensitive: false), '');
  // commas (any grouping, Indian or not) and spaces
  s = s.replaceAll(RegExp(r'[,\s]'), '');

  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) return null;
  return num.tryParse(s);
}