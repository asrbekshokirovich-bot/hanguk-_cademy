import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hanguk_online/features/lessons/domain/models.dart';
import 'package:hanguk_online/features/lessons/presentation/board_canvas.dart';

/// The lesson's whiteboard.
///
/// Its whole state — what is drawn, and whether it is on screen at all —
/// arrives as one ordered list of rows, so that a student joining twenty
/// minutes late replays the same board the room has been looking at. These
/// tests hold the replay rules, and the one thing the drawing surface must
/// never get wrong: where on the board a point lands.
BoardStroke _row(String kind, {String id = 'x', int seq = 0}) =>
    BoardStroke(id: id, kind: kind, seq: seq);

BoardStroke _ink(String id, {int seq = 0}) => BoardStroke(
      id: id,
      kind: 'stroke',
      seq: seq,
      color: 0xFFFFFFFF,
      width: 0.005,
      points: const [Offset(0.1, 0.1), Offset(0.2, 0.2)],
    );

void main() {
  group('replaying a board', () {
    test('nothing drawn is a closed, empty board', () {
      final board = BoardState.from(const []);
      expect(board.open, isFalse);
      expect(board.strokes, isEmpty);
    });

    test('open puts it on screen and the ink stays in order', () {
      final board = BoardState.from([
        _row('open'),
        _ink('a', seq: 1),
        _ink('b', seq: 2),
      ]);
      expect(board.open, isTrue);
      expect(board.strokes.map((s) => s.id), ['a', 'b']);
    });

    test('close takes it off without rubbing anything out', () {
      // The teacher showing the video again has not wiped the board, and the
      // lesson's page has to be able to show what was on it.
      final board = BoardState.from([_row('open'), _ink('a'), _row('close')]);
      expect(board.open, isFalse);
      expect(board.strokes.map((s) => s.id), ['a']);
    });

    test('clear rubs out what came before it and nothing after', () {
      final board = BoardState.from([
        _row('open'),
        _ink('a', seq: 1),
        _row('clear', seq: 2),
        _ink('b', seq: 3),
      ]);
      expect(board.strokes.map((s) => s.id), ['b']);
      expect(board.open, isTrue, reason: 'clearing is not closing');
    });

    test('ink drawn before the board was opened is still on it', () {
      // The markers say what is on screen; they do not say what exists. A
      // teacher who writes, closes the board to show a video and opens it
      // again expects to find their writing where they left it.
      final board = BoardState.from([_ink('a'), _row('open', seq: 1)]);
      expect(board.strokes.map((s) => s.id), ['a']);
      expect(board.open, isTrue);
    });

    test('the last marker wins, however many there are', () {
      final board = BoardState.from([
        _row('open', seq: 1),
        _row('close', seq: 2),
        _row('open', seq: 3),
        _row('close', seq: 4),
      ]);
      expect(board.open, isFalse);
    });
  });

  group('reading a row off the wire', () {
    test('points come back as fractions of the board', () {
      final stroke = BoardStroke.fromMap({
        'id': 'a',
        'kind': 'stroke',
        'seq': 3,
        'color': 0xFFD4E94C,
        'width': 0.01,
        'points': [
          [0.25, 0.5],
          [0.75, 0.5],
        ],
      });
      expect(stroke.points, [const Offset(0.25, 0.5), const Offset(0.75, 0.5)]);
      expect(stroke.isInk, isTrue);
    });

    test('a marker carries no geometry and is not ink', () {
      final stroke = BoardStroke.fromMap({'id': 'a', 'kind': 'clear'});
      expect(stroke.isInk, isFalse);
      expect(stroke.points, isEmpty);
      expect(stroke.color, isNull);
    });

    test('a malformed row is dropped, not crashed on', () {
      // The column is jsonb and the app is not the only thing that can write
      // to it. A board that throws on one bad row shows nothing at all.
      final stroke = BoardStroke.fromMap({
        'id': 'a',
        'kind': 'stroke',
        'points': [
          [0.1],
          'nonsense',
          [0.2, 0.3],
        ],
      });
      expect(stroke.points, [const Offset(0.2, 0.3)]);
    });
  });

  group('the drawing surface', () {
    /// Drags across the board and answers with what was filed.
    ///
    /// `from` and `to` are fractions of the board itself, measured off the
    /// rendered surface rather than off the box handed to the editor: the
    /// tools sit under the board and the 16:9 ratio is kept, so the board is
    /// never quite the size of its container. Asking in fractions is also the
    /// invariant under test — a quarter of the way across, whatever the size.
    Future<List<Offset>> draw(
      WidgetTester tester, {
      required Size size,
      required Offset from,
      required Offset to,
    }) async {
      List<Offset> filed = const [];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: HkBoardEditor(
                  strokes: const [],
                  onStroke: (color, width, points) async {
                    filed = points;
                    return 'row-1';
                  },
                  onUndo: () {},
                  onClear: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final board = tester.getRect(find.byType(HkBoardView));
      Offset at(Offset fraction) => board.topLeft +
          Offset(board.width * fraction.dx, board.height * fraction.dy);

      final gesture = await tester.startGesture(at(from));
      await gesture.moveTo(at(to));
      await gesture.up();
      await tester.pumpAndSettle();
      return filed;
    }

    testWidgets('files the stroke in board space, not in pixels',
        (tester) async {
      // The teacher writes in a 1440pt window and the student reads it in a
      // 390pt one. Pixels would put the letter somewhere else on every
      // screen; 0..1 of the board puts it in the same place on all of them.
      final points = await draw(
        tester,
        size: const Size(640, 400),
        from: const Offset(0.25, 0.25),
        to: const Offset(0.75, 0.75),
      );

      expect(points, isNotEmpty);
      expect(points.first.dx, closeTo(0.25, 0.01));
      expect(points.first.dy, closeTo(0.25, 0.01));
      expect(points.last.dx, closeTo(0.75, 0.01));
      expect(points.last.dy, closeTo(0.75, 0.01));
    });

    testWidgets('the same drag on a smaller board files the same stroke',
        (tester) async {
      final big = await draw(
        tester,
        size: const Size(640, 400),
        from: const Offset(0.25, 0.25),
        to: const Offset(0.75, 0.75),
      );
      final small = await draw(
        tester,
        size: const Size(320, 240),
        from: const Offset(0.25, 0.25),
        to: const Offset(0.75, 0.75),
      );

      expect(small.first.dx, closeTo(big.first.dx, 0.02));
      expect(small.first.dy, closeTo(big.first.dy, 0.02));
      expect(small.last.dx, closeTo(big.last.dx, 0.02));
      expect(small.last.dy, closeTo(big.last.dy, 0.02));
    });

    testWidgets('a point outside the board is pulled back onto it',
        (tester) async {
      // A pointer dragged off the edge keeps reporting; without the clamp the
      // stroke carries on past the board and lands somewhere else entirely on
      // a screen of another size.
      final points = await draw(
        tester,
        size: const Size(640, 400),
        from: const Offset(0.5, 0.5),
        to: const Offset(1.4, 1.4),
      );

      for (final p in points) {
        expect(p.dx, inInclusiveRange(0, 1));
        expect(p.dy, inInclusiveRange(0, 1));
      }
    });
  });

  group('what a student sees', () {
    testWidgets('an opened but empty board says so', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 360,
              child: HkBoardView(
                strokes: [],
                emptyMessage: 'O‘qituvchi doskani ochdi — hozircha bo‘sh.',
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('hozircha bo‘sh'), findsOneWidget);
    });

    testWidgets('and is silent once something is on it', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 360,
              child: HkBoardView(
                strokes: [_ink('a')],
                emptyMessage: 'bo‘sh',
              ),
            ),
          ),
        ),
      );

      expect(find.text('bo‘sh'), findsNothing);
    });
  });
}
