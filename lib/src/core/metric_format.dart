/// Metres up to a kilometre, then kilometres — a squad total passes 1 km
/// within a few minutes and reads badly as five digits.
String formatMetres(double metres) => metres >= 1000
    ? '${(metres / 1000).toStringAsFixed(2)} km'
    : '${metres.toStringAsFixed(1)} m';

String formatSpeed(double metresPerSecond) =>
    '${metresPerSecond.toStringAsFixed(1)} m/s';

/// A share of a whole as a percentage, without decimals.
///
/// Clamped, because it labels a slice of something: a band of a bar or a
/// fraction of a total can never honestly read above 100%.
String formatShare(double fraction) =>
    '${(fraction.clamp(0.0, 1.0) * 100).round()}%';

/// A ratio as a percentage, unclamped.
///
/// Separate from [formatShare] because a comparison is not a share: a player
/// who ran twice the team average is +100%, and clamping that would quietly
/// turn the most interesting figure on the page into the least.
String formatPercent(double ratio) => '${(ratio * 100).round()}%';
