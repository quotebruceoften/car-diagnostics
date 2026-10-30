import 'dart:io';
import 'dart:typed_data';

import 'package:cardiag_mobile/brands/registry.dart';
import 'package:cardiag_mobile/brands/vag.dart';
import 'package:cardiag_mobile/core/coding/coder.dart';
import 'package:cardiag_mobile/core/vin.dart';
import 'package:cardiag_mobile/main.dart';
import 'package:cardiag_mobile/ui/car_media.dart';
import 'package:cardiag_mobile/ui/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A 1x1 PNG.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  test('model year from the VIN', () {
    expect(modelYear('WVWZZZAUZDW123456'), 2013);
    expect(modelYear('WVWZZZAUZHW123456'), 2017);
    expect(modelYear('WVWZZZ1KZ8W123456'), 2008);
    expect(modelYear('WVWZZZ1KZYW123456'), 2000);
    // The code repeats every 30 years: Y is 2000 until 2029, then 2030.
    expect(modelYear('WVWZZZ1KZYW123456', currentYear: 2031), 2030);
    expect(modelYear('short'), isNull);
  });

  test('VW Group VINs identify the model', () {
    const vag = VagBrand();
    expect(vag.identify('WVWZZZAUZDW123456').title, 'Volkswagen Golf 7 · 2013');
    expect(vag.identify('WAUZZZ8K0BA000000').name, 'Audi A4');
    expect(vag.identify('TMBZZZ5E0FB000000').name, 'Škoda Octavia');
    expect(vag.identify('WVWZZZZZZJW000000').name, 'Volkswagen'); // unknown model code
    expect(genericBrand.identify('1HGCM82633A004352').name, 'Your car');
  });

  group('media store', () {
    late Directory dir;
    late File source;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('media');
      source = File('${dir.path}/picked.jpg')..writeAsBytesSync(_png);
    });
    tearDown(() => dir.delete(recursive: true));

    test('keeps one picture per car', () async {
      final store = CarMediaStore(Directory('${dir.path}/store'));
      expect(await store.get('VIN1'), isNull);
      final saved = await store.save('VIN1', CarMediaType.photo, source.path);
      expect(saved.file.path, endsWith('.jpg'));
      expect(saved.file.readAsBytesSync(), _png);

      // A fresh store (app restart) finds it again.
      final reopened = await CarMediaStore(Directory('${dir.path}/store')).get('VIN1');
      expect(reopened!.type, CarMediaType.photo);
      expect(await store.get('VIN2'), isNull);

      // Replacing removes the old file.
      final video = await store.save('VIN1', CarMediaType.video, source.path);
      expect(saved.file.existsSync(), isFalse);
      expect((await store.get('VIN1'))!.type, CarMediaType.video);

      await store.remove('VIN1');
      expect(video.file.existsSync(), isFalse);
      expect(await store.get('VIN1'), isNull);
    });
  });

  group('car card', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('card'));
    tearDown(() => dir.delete(recursive: true));

    Future<DiagSession> connect(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final session = DiagSession(
        backupStore: MemoryBackupStore(),
        mediaStore: CarMediaStore(Directory('${dir.path}/store')),
        demoLatency: Duration.zero,
      );
      await tester.pumpWidget(CarDiagApp(session: session));
      await tester.tap(find.text('Demo car'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      return session;
    }

    testWidgets('shows the car name and invites a picture', (tester) async {
      await connect(tester);
      expect(find.text('Volkswagen Golf 7'), findsOneWidget);
      expect(find.text('Model year 2017'), findsOneWidget);
      expect(find.text('Add a photo or video of your car'), findsOneWidget);
      await tester.tap(find.byTooltip('Add a picture'));
      await tester.pumpAndSettle();
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose a video'), findsOneWidget);
      expect(find.text('Remove picture'), findsNothing);
    });

    testWidgets('shows the saved photo', (tester) async {
      final session = await connect(tester);
      final source = File('${dir.path}/car.jpg')..writeAsBytesSync(_png);
      await tester.runAsync(() => session.setCarMedia(CarMediaType.photo, source.path));
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as FileImage).file.path, startsWith('${dir.path}/store/'));
      expect(find.text('Add a photo or video of your car'), findsNothing);
      expect(find.byTooltip('Change picture'), findsOneWidget);
    });

    testWidgets('area chips show module health after a scan', (tester) async {
      await connect(tester);
      expect(find.text('Engine'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Scan'));
      await tester.pumpAndSettle();
      // The scan runs on its own screen; the card updates behind it.
      expect(find.text('Scan again'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Engine · 4'), findsOneWidget);
      expect(find.text('Chassis · 1'), findsOneWidget);
      expect(find.text('Lights · 1'), findsOneWidget);
      expect(find.text('Interior'), findsOneWidget);

      await tester.tap(find.text('Engine · 4'));
      await tester.pumpAndSettle();
      expect(find.text('Engine & gearbox'), findsOneWidget);
      expect(find.text('3 faults'), findsOneWidget);
      await tester.tap(find.text('Transmission'));
      await tester.pumpAndSettle();
      expect(find.text('0CW300040H'), findsOneWidget);
    });
  });
}
