import 'dart:io';
import 'dart:typed_data';

import 'package:cardiag_mobile/brands/registry.dart';
import 'package:cardiag_mobile/brands/scanner.dart';
import 'package:cardiag_mobile/brands/vag.dart';
import 'package:cardiag_mobile/core/coding/coder.dart';
import 'package:cardiag_mobile/core/coding/profile.dart';
import 'package:cardiag_mobile/core/errors.dart';
import 'package:cardiag_mobile/core/uds/uds_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

CodingProfile loadDemoProfile() =>
    CodingProfile.parse(File('assets/profiles/vag_09_demo.json').readAsStringSync(), source: 'demo');

void main() {
  group('coding profile', () {
    final profile = loadDemoProfile();
    final data = Uint8List(30)
      ..[0] = 0x15
      ..[1] = 0x03
      ..[2] = 0x1E;

    test('decodes options', () {
      final d = profile.decode(data);
      expect(d['drl'], 'on');
      expect(d['auto_lock'], '15 km/h');
      expect(d['comfort_blinks'], '3');
      expect(d['coming_home'], '30 s');
      expect(d['region'], 'Europe');
    });

    test('applies changes and keeps unmapped bits', () {
      final input = Uint8List.fromList(data)
        ..[0] = 0xC1
        ..[3] = 0xFC;
      final out = profile.apply(input, {'drl': 'off', 'auto_lock': '25 km/h', 'region': 'rest of world'});
      expect(out[0], 0xC6);
      expect(out[3], 0xFE);
      expect(out.sublist(4), input.sublist(4));
    });

    test('rejects invalid values', () {
      for (final change in [
        {'drl': 'maybe'},
        {'comfort_blinks': '0'},
        {'region': 'Mars'},
        {'nope': '1'},
      ]) {
        expect(() => profile.apply(data, change), throwsA(isA<CodingException>()), reason: '$change');
      }
      expect(() => profile.decode(Uint8List(4)), throwsA(isA<CodingException>()));
    });

    test('rejects invalid profiles', () {
      for (final option in [
        {'key': 'x', 'byte': 9},
        {'key': 'x', 'byte': 0, 'bit': 6, 'width': 3, 'type': 'int'},
        {'key': 'x', 'byte': 0, 'width': 2, 'type': 'bool'},
        {'key': 'x', 'byte': 0, 'type': 'enum'},
        {'key': 'x', 'byte': 0, 'type': 'float'},
      ]) {
        expect(
          () => CodingProfile.fromJson({
            'id': 't',
            'tx_id': '0x700',
            'did': '0x0100',
            'length': 2,
            'options': [option],
          }),
          throwsA(isA<CodingException>()),
          reason: '$option',
        );
      }
    });

    test('loads profiles written for the command-line tool', () {
      final p = CodingProfile.parse(File('../cardiag/coding/profiles/demo_bcm.json').readAsStringSync());
      expect(p.txId, 0x726);
      expect(p.securityLevel, 1);
    });

    test('matches by brand, module and part number', () {
      expect(profile.matches(brandId: 'vag', moduleAddress: '09', partNumber: '5Q0937DEMO'), isTrue);
      expect(profile.matches(brandId: 'vag', moduleAddress: '09', partNumber: '5Q0937084AB'), isFalse);
      expect(profile.matches(brandId: 'vag', moduleAddress: '17', partNumber: '5Q0937DEMO'), isFalse);
      expect(profile.matches(brandId: 'generic', moduleAddress: '09', partNumber: '5Q0937DEMO'), isFalse);
    });
  });

  test('brand detection from VIN', () {
    expect(brandForVin('WVWZZZAUZHW123456'), isA<VagBrand>());
    expect(brandForVin('WAUZZZ8V0JA000000').id, 'vag');
    expect(brandForVin('TMBJJ7NE0L0000000').id, 'vag');
    expect(brandForVin('1HGCM82633A004352').id, 'generic');
    expect(brandForVin(null).id, 'generic');
  });

  forEachTransport((name, setup) {
    test('VW module scan', () async {
      final (t, _) = await setup();
      final results = await ModuleScanner(t, const VagBrand()).scan().toList();
      final present = {for (final r in results.where((r) => r.present)) r.def.address: r};
      expect(present.keys.toSet(), {'01', '02', '03', '09', '15', '17', '19'});
      expect(present['09']!.partNumber, '5Q0937DEMO');
      expect(present['03']!.dtcs!.single.display, 'C0035-1F');
      expect(present['15']!.dtcs, isEmpty);
      final full = await ModuleScanner(t, const VagBrand()).probe(present['01']!.def, full: true);
      expect(full.text(0xF197), 'R4 1.4l TFSI');
    });

    test('long coding write: backup, write, verify, restore', () async {
      final (t, vehicle) = await setup();
      final store = MemoryBackupStore();
      final profile = loadDemoProfile();
      final coder = Coder(UdsClient(t, 0x70E, rxId: 0x778), did: 0x0600, store: store, moduleName: 'Central electrics');
      final old = await coder.read();
      final updated = profile.apply(old, {'drl': 'off', 'comfort_blinks': '5', 'tail_drl': 'on'});
      final backup = await coder.write(updated, vin: 'WVWZZZAUZHW123456', profileId: profile.id);
      expect(vehicle.ecu(0x70E)!.dids[0x0600], updated);
      expect(backup.data, old);
      expect((await store.list(txId: 0x70E)).single.vin, 'WVWZZZAUZHW123456');
      await coder.write(backup.data);
      expect(await coder.read(), old);
      expect(vehicle.ecu(0x70E)!.session, defaultSession);
    });

    test('SFD-locked module refuses coding with a helpful hint', () async {
      final (t, _) = await setup();
      final coder = Coder(
        UdsClient(t, 0x710, rxId: 0x77A),
        did: 0x0600,
        store: MemoryBackupStore(),
        moduleName: 'Gateway',
      );
      final old = await coder.read();
      try {
        await coder.write(Uint8List.fromList([...old.sublist(0, 7), old[7] ^ 1]));
        fail('write should have been refused');
      } on NegativeResponseException catch (e) {
        expect(const VagBrand().explainError(e, writing: true), contains('SFD'));
      }
    });
  });

  test('file backup store round trip', () async {
    final dir = await Directory.systemTemp.createTemp('cardiag');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileBackupStore(dir);
    final b = CodingBackup(
      moduleName: 'Gateway',
      txId: 0x710,
      did: 0x0600,
      data: Uint8List.fromList([1, 2, 3]),
      timestamp: DateTime.now(),
    );
    await store.save(b);
    final [loaded] = await store.list(txId: 0x710);
    expect(loaded.data, [1, 2, 3]);
    expect(loaded.moduleName, 'Gateway');
    expect(await store.list(txId: 0x711), isEmpty);
  });
}
