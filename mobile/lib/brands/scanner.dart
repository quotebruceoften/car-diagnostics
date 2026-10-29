import 'dart:typed_data';

import '../core/errors.dart';
import '../core/hex.dart';
import '../core/obd/dtc.dart';
import '../core/transport/transport.dart';
import '../core/uds/uds_client.dart';
import 'brand.dart';

class ModuleInfo {
  ModuleInfo(this.def, {required this.present, this.identification = const {}, this.dtcs, this.coding, this.error});

  final ModuleDef def;
  final bool present;
  final Map<int, Uint8List> identification;

  /// null when fault codes could not be read.
  final List<Dtc>? dtcs;

  /// The module's current coding; null when the make has no coding or the module doesn't report it.
  final Uint8List? coding;
  final String? error;

  bool get codable => coding != null && coding!.isNotEmpty;

  String? text(int did) {
    final v = identification[did];
    return v == null ? null : formatDidValue(v);
  }

  String get partNumber => text(0xF187) ?? '';
  String get systemName => text(0xF197) ?? '';
}

/// Finds which of a brand's modules are fitted and reads their fault codes.
class ModuleScanner {
  ModuleScanner(this.transport, this.brand);

  final Transport transport;
  final Brand brand;

  UdsClient client(ModuleDef m) => UdsClient(transport, m.txId, rxId: m.rxId);

  /// Probes one module. With [full], reads every identification DID.
  Future<ModuleInfo> probe(ModuleDef m, {bool full = false}) async {
    final uds = client(m);
    final ident = <int, Uint8List>{};
    try {
      ident[brand.partNumberDid] = await uds.readDataByIdentifier(brand.partNumberDid);
    } on NoResponseException {
      return ModuleInfo(m, present: false);
    } on NegativeResponseException {
      // It answered, so it's there; it just doesn't report a part number.
    } on CarDiagException catch (e) {
      return ModuleInfo(m, present: false, error: e.message);
    }
    final dids = full ? brand.identificationDids.keys : const [0xF197];
    ident.addAll(await uds.readMany(dids.where((d) => !ident.containsKey(d))));
    List<Dtc>? dtcs;
    String? error;
    try {
      dtcs = await uds.readDtcs();
    } on CarDiagException catch (e) {
      error = e.message;
    }
    Uint8List? coding;
    final codingDid = brand.codingDidFor(m);
    if (codingDid != null) {
      try {
        coding = await uds.readDataByIdentifier(codingDid);
      } on CarDiagException {
        coding = null; // not codable this way
      }
    }
    return ModuleInfo(m, present: true, identification: ident, dtcs: dtcs, coding: coding, error: error);
  }

  /// Probes every module of the brand, yielding results as they arrive.
  Stream<ModuleInfo> scan() async* {
    for (final m in brand.modules) {
      yield await probe(m);
    }
  }
}
