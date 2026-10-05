import 'package:checkers/engine/checkers.dart';
import 'package:checkers/history/game_history_controller.dart';
import 'package:checkers/history/persistence/in_memory_game_history_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('GameHistoryController state handles uninitialized case', () async {
    final store = InMemoryGameHistoryStore();
    final history = GameHistoryController(Future.value(store));

    expect(history, isNotNull);
    expect(await history.games(), isEmpty);
  });

  test('GameHistoryController tracks player names correctly', () async {
    final store = InMemoryGameHistoryStore();
    final history = GameHistoryController(Future.value(store));

    final game = Game.standard();
    history.beginGame(
      initialFen: game.fen,
      variant: RuleVariant.defaultVariant,
      redPlayerName: 'Alice',
      blackPlayerName: 'Bob',
    );

    // Record a move to ensure game is persisted
    final move = game.legalMoves().first;
    game.applyMove(move);
    await history.recordMove(move);
    await history.completeGame(
      outcome: GameOutcome.inProgress,
      termination: null,
    );

    final games = await history.games();
    expect(games.length, 1);
    expect(games.first.redPlayerName, 'Alice');
    expect(games.first.blackPlayerName, 'Bob');
  });

  test('GameHistoryController works without player names', () async {
    final store = InMemoryGameHistoryStore();
    final history = GameHistoryController(Future.value(store));

    final game = Game.standard();
    history.beginGame(
      initialFen: game.fen,
      variant: RuleVariant.defaultVariant,
    );

    final move = game.legalMoves().first;
    game.applyMove(move);
    await history.recordMove(move);
    await history.completeGame(
      outcome: GameOutcome.inProgress,
      termination: null,
    );

    final games = await history.games();
    expect(games.length, 1);
    expect(games.first.redPlayerName, isNull);
    expect(games.first.blackPlayerName, isNull);
    expect(games.first.redName, 'Red');
    expect(games.first.blackName, 'Black');
  });
}
