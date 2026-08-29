import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/lockscreen/application/lockscreen_ray_bridge.dart';
import 'package:pulse/features/session/application/mode_event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.pulse.lockscreen/ray');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'notificationsEnabled' => true,
        'requestNotifications' => true,
        _ => null,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('forwards complete Ray payload to the native lock-screen canvas',
      () async {
    const event = ModeEvent(
      type: 'ray_card',
      data: {
        'canvas': 0xFF120D1D,
        'strokes': [
          {
            'color': 0xFF9747FF,
            'width': 10.0,
            'effect': 1,
            'points': [
              [0.2, 0.3],
              [0.7, 0.8],
            ],
          },
        ],
      },
    );

    await LockscreenRayBridge.handleIncoming(event, languageCode: 'ru');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'rayEvent');
    final arguments = calls.single.arguments as Map<Object?, Object?>;
    expect(arguments['type'], 'ray_card');
    expect(arguments['data'], event.data);
    expect(arguments['languageCode'], 'ru');
  });

  test('does not forward unrelated sensory modes', () async {
    await LockscreenRayBridge.handleIncoming(
      const ModeEvent(type: 'candle_blow', data: {'strength': 0.8}),
    );

    expect(calls, isEmpty);
  });

  test('reports and requests native notification permission', () async {
    expect(await LockscreenRayBridge.notificationsEnabled(), isTrue);
    expect(await LockscreenRayBridge.requestNotifications(), isTrue);
    await LockscreenRayBridge.setConnectionKeepAlive(true);
    expect(
      calls.map((call) => call.method),
      [
        'notificationsEnabled',
        'requestNotifications',
        'setConnectionKeepAlive',
      ],
    );
    expect(calls.last.arguments, isTrue);
  });
}
