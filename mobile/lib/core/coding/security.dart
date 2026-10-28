/// Seed/key algorithms for UDS SecurityAccess (service 0x27).
///
/// Real algorithms are manufacturer and module specific and are not shipped
/// with the app. Brands register theirs here by name; coding profiles refer
/// to them with `"security": {"level": 3, "algorithm": "<name>"}`.
library;

import 'dart:typed_data';

import '../errors.dart';
import '../uds/uds_client.dart';

final Map<String, KeyFunction> _registry = {'demo_xor': demoXor};

void registerSecurityAlgorithm(String name, KeyFunction fn) => _registry[name] = fn;

KeyFunction securityAlgorithm(String name) =>
    _registry[name] ??
    (throw CodingException('Unknown security algorithm "$name" (known: ${_registry.keys.join(', ')})'));

/// Toy algorithm used by the built-in simulator. Not used by any real car.
Uint8List demoXor(Uint8List seed, int level) =>
    Uint8List.fromList([for (var i = 0; i < seed.length; i++) seed[i] ^ 0xA5 ^ ((i * 0x3B + level) & 0xFF)]);
