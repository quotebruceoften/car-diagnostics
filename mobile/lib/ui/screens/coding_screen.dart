import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../brands/brand.dart';
import '../../core/coding/coder.dart';
import '../../core/coding/profile.dart';
import '../../core/errors.dart';
import '../../core/hex.dart';
import '../../core/uds/uds_client.dart';
import '../session.dart';
import '../widgets/common.dart';

/// Long coding editor: named options when a profile matches the module,
/// plus a byte/bit editor that works for any module.
class CodingScreen extends StatefulWidget {
  const CodingScreen({super.key, required this.module, required this.did, required this.partNumber});

  final ModuleDef module;
  final int did;
  final String partNumber;

  @override
  State<CodingScreen> createState() => _CodingScreenState();
}

class _CodingScreenState extends State<CodingScreen> {
  Uint8List? _original;
  Uint8List? _edited;
  CodingProfile? _profile;
  Object? _error;
  String? _hint;
  bool _writing = false;

  DiagSession get _session => SessionScope.read(context);

  bool get _changed => _original != null && !bytesEqual(_original!, _edited!);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_original == null && _error == null) _load();
  }

  Future<Coder> _coder() async => Coder(
    UdsClient(_session.transport, widget.module.txId, rxId: widget.module.rxId),
    did: widget.did,
    store: await _session.backupStore(),
    moduleName: widget.module.label,
    access: _session.brand.codingAccessFor(widget.module),
  );

  Future<void> _load() async {
    setState(() {
      _error = null;
      _hint = null;
    });
    try {
      final data = await (await _coder()).read();
      var profile = _session.profileFor(widget.module.address, widget.partNumber);
      if (profile != null && profile.length != data.length) profile = null; // wrong variant
      if (!mounted) return;
      setState(() {
        _original = data;
        _edited = Uint8List.fromList(data);
        _profile = profile;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _setOption(CodingOption o, int raw) {
    setState(() => o.apply(_edited!, raw));
  }

  Future<void> _write() async {
    final original = _original!, edited = Uint8List.fromList(_edited!);
    final profile = _profile;
    final optionChanges = [
      if (profile != null)
        for (final o in profile.options)
          if (o.raw(original) != o.raw(edited)) '${o.label}: ${o.display(original)} → ${o.display(edited)}',
    ];
    final byteChanges = [
      for (var i = 0; i < original.length; i++)
        if (original[i] != edited[i]) 'Byte $i: ${bytesToHex([original[i]])} → ${bytesToHex([edited[i]])}',
    ];
    final ok = await confirm(
      context,
      title: 'Write new coding?',
      action: 'Write',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.module.label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final c in optionChanges.isEmpty ? byteChanges : optionChanges) Text('• $c'),
          if (optionChanges.isNotEmpty && byteChanges.length > optionChanges.length)
            Text('• plus ${byteChanges.length} changed byte(s)'),
          const SizedBox(height: 12),
          const Text(
            'The current coding is backed up first. Keep the ignition on and do not disconnect the '
            'adapter while writing. A battery charger is recommended.',
          ),
        ],
      ),
    );
    if (!ok || !mounted) return;
    setState(() {
      _writing = true;
      _error = null;
      _hint = null;
    });
    try {
      await (await _coder()).write(
        edited,
        vin: _session.vin ?? '',
        partNumber: widget.partNumber,
        profileId: profile?.id,
      );
      if (!mounted) return;
      setState(() => _original = edited);
      showMessage(context, 'Coding written and verified. The previous coding was backed up.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _hint = e is CarDiagException ? _session.brand.explainError(e, writing: true) : null;
      });
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _showBackups() async {
    final store = await _session.backupStore();
    final backups = (await store.list(
      txId: widget.module.txId,
    )).where((b) => b.did == widget.did && b.data.length == _original!.length).toList();
    if (!mounted) return;
    final picked = await showModalBottomSheet<CodingBackup>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Coding backups'),
              subtitle: Text('Pick one to load it into the editor. Nothing is written until you press Write.'),
            ),
            if (backups.isEmpty) const ListTile(title: Text('No backups yet. One is saved before every write.')),
            for (final b in backups)
              ListTile(
                leading: const Icon(Icons.restore),
                title: Text(_formatTime(b.timestamp)),
                subtitle: Text(
                  '${b.vin.isEmpty ? '' : '${b.vin}\n'}${bytesToHex(b.data, separator: ' ')}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                onTap: () => Navigator.pop(context, b),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _edited = Uint8List.fromList(picked.data));
  }

  static String _formatTime(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _editByte(int index) async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ByteEditor(
        index: index,
        original: _original![index],
        value: _edited![index],
        options: _profile?.options.where((o) => o.byte == index).toList() ?? const [],
      ),
    );
    if (result != null) setState(() => _edited![index] = result);
  }

  Future<void> _editInt(CodingOption o) async {
    final controller = TextEditingController(text: '${o.raw(_edited!)}');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(o.label),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(helperText: 'Allowed: ${o.describeRange()}', suffixText: o.unit),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              if (n != null && n >= o.min && n <= o.max) Navigator.pop(context, n);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) _setOption(o, value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Coding · ${widget.module.address.isEmpty ? widget.module.name : widget.module.address}'),
        actions: [
          if (_original != null)
            IconButton(tooltip: 'Backups', icon: const Icon(Icons.history), onPressed: _writing ? null : _showBackups),
        ],
      ),
      body: _original == null
          ? (_error == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [ErrorPanel(error: _error!, onRetry: _load)],
                  ))
          : ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: ErrorPanel(error: _error!, hint: _hint),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    _profile == null
                        ? 'No option names are known for this module (part number ${widget.partNumber.isEmpty ? 'unknown' : widget.partNumber}). '
                              'You can still change individual bits if you know what they do.'
                        : _profile!.description,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                if (_profile != null) ...[
                  const SectionHeader('Options'),
                  for (final o in _profile!.options) _optionTile(o),
                ],
                SectionHeader('Bytes (${_original!.length})'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (var i = 0; i < _edited!.length; i++) _byteChip(i, scheme)],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _original == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _changed && !_writing
                            ? () => setState(() => _edited = Uint8List.fromList(_original!))
                            : null,
                        child: const Text('Undo changes'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        icon: _writing
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.upload),
                        label: Text(_writing ? 'Writing...' : 'Write'),
                        onPressed: _changed && !_writing ? _write : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _optionTile(CodingOption o) {
    final changed = o.raw(_original!) != o.raw(_edited!);
    final subtitle = changed ? Text('was ${o.display(_original!)}') : null;
    final title = Text(o.label, style: changed ? const TextStyle(fontWeight: FontWeight.w600) : null);
    switch (o.type) {
      case 'bool':
        return SwitchListTile(
          title: title,
          subtitle: subtitle,
          value: o.raw(_edited!) == 1,
          onChanged: _writing ? null : (v) => _setOption(o, v ? 1 : 0),
        );
      case 'enum':
        final current = o.raw(_edited!);
        return ListTile(
          title: title,
          subtitle: subtitle,
          trailing: DropdownButton<int>(
            value: o.values.containsKey(current) ? current : null,
            hint: Text('unknown ($current)'),
            items: [for (final (raw, label) in o.choices) DropdownMenuItem(value: raw, child: Text(label))],
            onChanged: _writing ? null : (v) => v == null ? null : _setOption(o, v),
          ),
        );
      default:
        return ListTile(
          title: title,
          subtitle: subtitle,
          trailing: Text(o.display(_edited!), style: Theme.of(context).textTheme.titleMedium),
          onTap: _writing ? null : () => _editInt(o),
        );
    }
  }

  Widget _byteChip(int i, ColorScheme scheme) {
    final changed = _original![i] != _edited![i];
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _writing ? null : () => _editByte(i),
      child: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: changed ? scheme.tertiaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text('$i', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            Text(
              bytesToHex([_edited![i]]),
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: changed ? scheme.onTertiaryContainer : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ByteEditor extends StatefulWidget {
  const _ByteEditor({required this.index, required this.original, required this.value, required this.options});
  final int index;
  final int original;
  final int value;
  final List<CodingOption> options;

  @override
  State<_ByteEditor> createState() => _ByteEditorState();
}

class _ByteEditorState extends State<_ByteEditor> {
  late int _value = widget.value;

  String? _labelFor(int bit) {
    for (final o in widget.options) {
      if (bit >= o.bit && bit < o.bit + o.width) return o.width == 1 ? o.label : '${o.label} (bit ${bit - o.bit})';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Byte ${widget.index}: ${bytesToHex([_value])}'),
            subtitle: Text('Was ${bytesToHex([widget.original])}'),
            trailing: FilledButton(onPressed: () => Navigator.pop(context, _value), child: const Text('Done')),
          ),
          for (var bit = 0; bit < 8; bit++)
            SwitchListTile(
              dense: true,
              title: Text('Bit $bit'),
              subtitle: Text(_labelFor(bit) ?? 'Unknown function'),
              secondary: (widget.original >> bit) & 1 != (_value >> bit) & 1
                  ? const Icon(Icons.edit, size: 18)
                  : const SizedBox(width: 18),
              value: (_value >> bit) & 1 == 1,
              onChanged: (v) => setState(() => _value = v ? _value | (1 << bit) : _value & ~(1 << bit)),
            ),
          TextButton(onPressed: () => setState(() => _value = widget.original), child: const Text('Reset this byte')),
        ],
      ),
    ),
  );
}
