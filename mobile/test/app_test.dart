import 'package:cardiag_mobile/brands/registry.dart';
import 'package:cardiag_mobile/core/coding/coder.dart';
import 'package:cardiag_mobile/main.dart';
import 'package:cardiag_mobile/ui/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DiagSession session;
  late MemoryBackupStore backups;

  setUp(() {
    backups = MemoryBackupStore();
    session = DiagSession(backupStore: backups, demoLatency: Duration.zero);
  });

  Future<void> connectDemo(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(CarDiagApp(session: session));
    expect(find.text('Demo car'), findsOneWidget);
    await tester.tap(find.text('Demo car'));
    await tester.pumpAndSettle();
  }

  testWidgets('connects to the demo car and shows the overview', (tester) async {
    await connectDemo(tester);
    expect(find.text('Volkswagen Group'), findsWidgets);
    expect(find.text('WVWZZZAUZHW123456'), findsWidgets);
    expect(find.text('Check engine light on'), findsOneWidget);
    expect(find.text('2 emissions fault codes stored'), findsOneWidget);
  });

  testWidgets('shows OBD fault codes with descriptions', (tester) async {
    await connectDemo(tester);
    await tester.tap(find.text('Faults'));
    await tester.pumpAndSettle();
    expect(find.text('P0301'), findsOneWidget);
    expect(find.textContaining('Cylinder 1 misfire'), findsOneWidget);
    expect(find.text('P0730'), findsOneWidget);
  });

  testWidgets('scans VW modules, edits long coding and writes it', (tester) async {
    await connectDemo(tester);
    await tester.tap(find.text('Modules'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan all modules'));
    await tester.pumpAndSettle();
    expect(find.text('7 modules · 6 faults'), findsOneWidget);

    await tester.tap(find.text('Central electrics'));
    await tester.pumpAndSettle();
    expect(find.text('5Q0937DEMO'), findsOneWidget);
    await tester.tap(find.text('Long coding'));
    await tester.pumpAndSettle();

    // Named options from the matching profile.
    final drl = find.widgetWithText(SwitchListTile, 'Daytime running lights');
    expect(tester.widget<SwitchListTile>(drl).value, isTrue);
    await tester.tap(drl);
    await tester.pumpAndSettle();
    expect(find.text('was on'), findsOneWidget);

    await tester.tap(find.text('Write'));
    await tester.pumpAndSettle();
    expect(find.text('• Daytime running lights: on → off'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Write').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('written and verified'), findsOneWidget);
    expect(session.demoVehicle!.ecu(0x70E)!.dids[0x0600]![0], 0x14);
    expect(backups.backups.single.data[0], 0x15);
  });

  testWidgets('explains why the gateway refuses coding', (tester) async {
    await connectDemo(tester);
    await tester.tap(find.text('Modules'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan all modules'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Gateway'), 200);
    await tester.tap(find.text('Gateway'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Long coding'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No option names are known'), findsOneWidget);

    await tester.tap(find.text('01').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Bit 0'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Write').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('security access denied'), findsOneWidget);
    expect(find.textContaining('SFD'), findsOneWidget);
  });

  testWidgets('coding tab lists codable modules and keeps backups', (tester) async {
    await connectDemo(tester);
    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Find codable modules'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Scan modules'));
    await tester.pumpAndSettle();

    expect(find.text('CODABLE MODULES (3)'), findsOneWidget);
    expect(find.text('Named options'), findsOneWidget); // only the central electrics have a profile
    expect(find.text('Bit editor'), findsNWidgets(2));

    await tester.tap(find.text('Central electrics'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Fold mirrors on lock'));
    await tester.pumpAndSettle();
    expect(find.text('1 byte changed'), findsOneWidget);
    await tester.tap(find.text('Write'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Write').last);
    await tester.pumpAndSettle();
    expect(session.demoVehicle!.ecu(0x70E)!.dids[0x0600]![0], 0x35);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('RECENT BACKUPS'), findsOneWidget);
    expect(find.text('1 backup'), findsOneWidget);
  });

  testWidgets('coding tab explains when the make has no coding', (tester) async {
    await connectDemo(tester);
    await session.setBrand(genericBrand);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Coding not available for Generic OBD-II'), findsOneWidget);
  });
}
