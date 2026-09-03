import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'sand_models.dart';

class SandWorld {
  SandWorld({this.columns = 64, this.rows = 96})
      : assert(columns > 4 && rows > 4),
        cells = Uint8List(columns * rows);

  final int columns;
  final int rows;
  final Uint8List cells;
  int tick = 0;

  int get capacity => cells.length;
  int get filledCells => cells.where((value) => value != 0).length;

  int at(int x, int y) => cells[y * columns + x];

  void apply(SandCommand command) {
    final radius = switch (command.tool) {
      SandTool.paint => 1 + (command.intensity * 2).round(),
      SandTool.pour => 2 + (command.intensity * 2).round(),
      SandTool.erase => 3 + (command.intensity * 3).round(),
    };
    SandPoint? previous;
    for (final point in command.points) {
      if (previous == null) {
        _stamp(point, command, radius);
      } else {
        final dx = (point.x - previous.x) * columns;
        final dy = (point.y - previous.y) * rows;
        final samples = math.max(1, math.sqrt(dx * dx + dy * dy).ceil());
        for (var sample = 1; sample <= samples; sample++) {
          final t = sample / samples;
          _stamp(
            SandPoint(
              previous.x + (point.x - previous.x) * t,
              previous.y + (point.y - previous.y) * t,
            ),
            command,
            radius,
          );
        }
      }
      previous = point;
    }
  }

  void _stamp(SandPoint point, SandCommand command, int radius) {
    final centerX = (point.x * (columns - 1)).round();
    final centerY = (point.y * (rows - 1)).round();
    for (var y = centerY - radius; y <= centerY + radius; y++) {
      if (y < 0 || y >= rows) continue;
      for (var x = centerX - radius; x <= centerX + radius; x++) {
        if (x < 0 || x >= columns) continue;
        final distanceSquared =
            (x - centerX) * (x - centerX) + (y - centerY) * (y - centerY);
        if (distanceSquared > radius * radius) continue;
        final index = y * columns + x;
        if (command.tool == SandTool.erase) {
          cells[index] = 0;
        } else {
          cells[index] = command.material.index + 1;
        }
      }
    }
  }

  int step({required int seed, int maxMoves = 640}) {
    var moves = 0;
    final leftFirst = ((seed + tick) & 1) == 0;
    for (var y = rows - 2; y >= 0 && moves < maxMoves; y--) {
      final offset = (seed + tick * 17 + y * 13) % columns;
      for (var scan = 0; scan < columns && moves < maxMoves; scan++) {
        final x = (scan + offset) % columns;
        final index = y * columns + x;
        final material = cells[index];
        if (material == 0) continue;
        final below = index + columns;
        if (cells[below] == 0) {
          cells[below] = material;
          cells[index] = 0;
          moves++;
          continue;
        }
        final firstDx = leftFirst ? -1 : 1;
        if (_fallDiagonal(x, y, index, material, firstDx) ||
            _fallDiagonal(x, y, index, material, -firstDx)) {
          moves++;
        }
      }
    }
    tick++;
    return moves;
  }

  bool _fallDiagonal(int x, int y, int index, int material, int dx) {
    final targetX = x + dx;
    if (targetX < 0 || targetX >= columns || y + 1 >= rows) return false;
    final target = (y + 1) * columns + targetX;
    if (cells[target] != 0) return false;
    cells[target] = material;
    cells[index] = 0;
    return true;
  }

  int digest() {
    var hash = 0x811c9dc5;
    for (final value in cells) {
      hash ^= value;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}

class SandSimulation {
  SandSimulation({SandWorld? world, this.maxQueue = 64})
      : world = world ?? SandWorld();

  final SandWorld world;
  final int maxQueue;
  final Queue<SandCommand> _queue = Queue<SandCommand>();
  SandCommand? _active;
  int _stepsRemaining = 0;

  int get queuedCommands => _queue.length + (_active == null ? 0 : 1);
  bool get isIdle => _active == null && _queue.isEmpty;

  bool enqueue(SandCommand command) {
    if (queuedCommands >= maxQueue) return false;
    _queue.add(command);
    return true;
  }

  bool tick({int maxMoves = 640}) {
    if (_active == null) {
      if (_queue.isEmpty) return false;
      _active = _queue.removeFirst();
      world.apply(_active!);
      _stepsRemaining = _active!.settleSteps;
    }
    final command = _active!;
    if (_stepsRemaining > 0) {
      world.step(seed: command.seed, maxMoves: maxMoves);
      _stepsRemaining--;
    }
    if (_stepsRemaining <= 0) _active = null;
    return true;
  }

  void drain({int maxTicks = 4096}) {
    var ticks = 0;
    while (!isIdle && ticks < maxTicks) {
      tick();
      ticks++;
    }
  }
}
