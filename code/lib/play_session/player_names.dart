import 'dart:math';

class PlayerNames {
  final String red;
  final String black;

  const PlayerNames({required this.red, required this.black});
}

PlayerNames getAssignedNames(
  String redDefault,
  String blackDefault,
  bool randomize,
) {
  if (!randomize) {
    return PlayerNames(red: redDefault, black: blackDefault);
  }
  final random = Random();
  if (random.nextBool()) {
    return PlayerNames(red: blackDefault, black: redDefault);
  }
  return PlayerNames(red: redDefault, black: blackDefault);
}
