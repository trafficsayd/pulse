import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/transport/ble/ble_adapter.dart';
import 'package:pulse/features/transport/ble/ble_client.dart';
import 'package:pulse/features/transport/ble/ble_transport_exception.dart';
import 'package:pulse/features/transport/ble/ble_uuids.dart';
import 'package:pulse/features/transport/ble/packet_codec.dart';
import 'package:pulse/features/transport/ble/real_ble_client.dart';
import 'package:pulse/features/transport/transport.dart';

import 'fake_flutter_blue_plus.dart';

void main() {
  group('RealBleClient', () {
    late FakeBleScanner scanner;
    late FakeBlePermissionGate permissions;
    late FakeBleCharacteristic tx;
    late FakeBleCharacteristic rx;
    late FakeBleDevice device;
    late RealBleClient client;

    setUp(() {
      tx = FakeBleCharacteristic(uuid: pulseTxCharacteristicUuid);
      rx = FakeBleCharacteristic(uuid: pulseRxCharacteristicUuid);
      final service = FakeBleService(
        uuid: pulseServiceUuid,
        characteristics: [tx, rx],
      );
      device = FakeBleDevice(
        remoteId: 'AA:BB:CC:DD:EE:FF',
        services: [service],
      );
      scanner = FakeBleScanner();
      permissions = FakeBlePermissionGate();
      client = RealBleClient(scanner: scanner, permissions: permissions);
    });

    tearDown(() async {
      await client.dispose();
      await scanner.dispose();
      await device.dispose();
      await tx.dispose();
      await rx.dispose();
    });

    Future<void> connectViaFakePeer({
      Duration scanTimeout = const Duration(seconds: 5),
    }) async {
      final adv = BleAdvertisement(
        device: device,
        rssi: -42,
        serviceUuids: [pulseServiceUuid],
      );
      final connectFuture = client.connect(scanTimeout: scanTimeout);
      // Yield so the client subscribes to scanResults before we emit.
      await Future<void>.delayed(Duration.zero);
      scanner.emit([adv]);
      await connectFuture;
    }

    test('happy path: scans, connects, subscribes, and emits decoded packets',
        () async {
      await connectViaFakePeer();

      expect(permissions.callCount, 1);
      expect(permissions.lastAdvertise, isFalse);
      expect(scanner.startCount, 1);
      expect(scanner.lastFilter, equals(const [pulseServiceUuid]));
      expect(scanner.stopCount, greaterThanOrEqualTo(1));
      expect(device.connectCount, 1);
      expect(tx.notifyEnabled, isTrue);
      expect(client.currentState, BleClientState.connected);

      final received = <Packet>[];
      final sub = client.incoming.listen(received.add);

      final inbound = TransportPacket(
        kind: 'mode_event',
        payload: Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]),
      );
      tx.emitNotification(packetEncoder(inbound));
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.kind, 'mode_event');
      expect(received.single.payload, equals(inbound.payload));

      await sub.cancel();
    });

    test('send() writes encoded packet to the RX characteristic', () async {
      await connectViaFakePeer();

      final outbound = TransportPacket(
        kind: 'sneak_signal',
        payload: Uint8List.fromList(const [1, 2, 3, 4]),
      );
      await client.send(outbound);

      expect(rx.writes, hasLength(1));
      final decoded = packetDecoder(rx.writes.single);
      expect(decoded.kind, outbound.kind);
      expect(decoded.payload, equals(outbound.payload));
    });

    test('permission denied throws BleTransportException.permissionDenied',
        () async {
      permissions.granted = false;
      await expectLater(
        client.connect(scanTimeout: const Duration(seconds: 1)),
        throwsA(
          isA<BleTransportException>().having(
            (e) => e.reason,
            'reason',
            BleTransportFailure.permissionDenied,
          ),
        ),
      );
      expect(scanner.startCount, 0);
      expect(client.currentState, BleClientState.idle);
    });

    test('scan timeout throws BleTransportException.scanTimeout', () async {
      await expectLater(
        client.connect(scanTimeout: const Duration(milliseconds: 50)),
        throwsA(
          isA<BleTransportException>().having(
            (e) => e.reason,
            'reason',
            BleTransportFailure.scanTimeout,
          ),
        ),
      );
      expect(scanner.stopCount, greaterThanOrEqualTo(1));
      expect(client.currentState, BleClientState.idle);
    });

    test('peer disconnect after connect surfaces a disconnected error',
        () async {
      await connectViaFakePeer();

      final errors = <Object>[];
      final sub = client.incoming.listen(
        (_) {},
        onError: errors.add,
      );

      device.simulatePeerDisconnect();
      await Future<void>.delayed(Duration.zero);

      expect(client.currentState, BleClientState.disconnected);
      expect(errors, hasLength(1));
      expect(errors.single, isA<BleTransportException>());
      expect(
        (errors.single as BleTransportException).reason,
        BleTransportFailure.disconnected,
      );

      await sub.cancel();
    });

    test('disconnect mid-send: send after disconnect throws writeFailed',
        () async {
      await connectViaFakePeer();
      await client.disconnect();

      await expectLater(
        client.send(
          TransportPacket(
            kind: 'mode_event',
            payload: Uint8List.fromList(const [0]),
          ),
        ),
        throwsA(
          isA<BleTransportException>().having(
            (e) => e.reason,
            'reason',
            BleTransportFailure.writeFailed,
          ),
        ),
      );
    });

    test('write failure raises BleTransportException.writeFailed', () async {
      await connectViaFakePeer();
      rx.failWrite = true;

      await expectLater(
        client.send(
          TransportPacket(
            kind: 'mode_event',
            payload: Uint8List.fromList(const [9]),
          ),
        ),
        throwsA(
          isA<BleTransportException>().having(
            (e) => e.reason,
            'reason',
            BleTransportFailure.writeFailed,
          ),
        ),
      );
    });

    test('disconnect is idempotent and stops scanning', () async {
      await connectViaFakePeer();
      await client.disconnect();
      await client.disconnect();

      expect(client.currentState, BleClientState.idle);
      expect(device.disconnectCount, greaterThanOrEqualTo(1));
    });

    test('state stream reflects scanning → connecting → connected', () async {
      final states = <BleClientState>[];
      final sub = client.state.listen(states.add);

      await connectViaFakePeer();
      await Future<void>.delayed(Duration.zero);

      expect(
        states,
        containsAllInOrder(<BleClientState>[
          BleClientState.scanning,
          BleClientState.connecting,
          BleClientState.connected,
        ]),
      );

      await sub.cancel();
    });
  });

  group('packetEncoder/packetDecoder', () {
    test('round-trips arbitrary payload kinds', () {
      final p = TransportPacket(
        kind: 'mode_event',
        payload: Uint8List.fromList(List<int>.generate(64, (i) => i & 0xFF)),
      );
      final bytes = packetEncoder(p);
      final back = packetDecoder(bytes);
      expect(back.kind, p.kind);
      expect(back.payload, equals(p.payload));
    });

    test('rejects malformed JSON with a FormatException', () {
      expect(() => packetDecoder(const [0xFF, 0xFF]), throwsFormatException);
      expect(() => packetDecoder(const [0x7B, 0x7D]), throwsFormatException);
    });
  });

  group('ble_uuids', () {
    test('Pulse service UUID is the canonical FEED service', () {
      expect(pulseServiceUuid, '0000feed-0000-1000-8000-00805f9b34fb');
    });

    test('TX and RX UUIDs are distinct', () {
      expect(
          pulseTxCharacteristicUuid, isNot(equals(pulseRxCharacteristicUuid)));
    });
  });
}
