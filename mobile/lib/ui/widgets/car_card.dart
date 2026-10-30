import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../brands/brand.dart';
import '../../brands/scanner.dart';
import '../car_media.dart';
import '../screens/module_screen.dart';
import '../screens/scan_screen.dart';
import '../session.dart';
import 'common.dart';

/// The connected car: the user's own photo or video, its name, and the health
/// of each area of the car from the module scan.
class CarCard extends StatelessWidget {
  const CarCard({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return Card(
      child: ListenableBuilder(
        listenable: session.scan,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Hero(session: session),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Wrap(spacing: 8, runSpacing: 8, children: _zoneChips(context, session)),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 16), child: _footer(context, session)),
          ],
        ),
      ),
    );
  }

  List<Widget> _zoneChips(BuildContext context, DiagSession session) {
    final scan = session.scan;
    final chips = <Widget>[];
    for (final zone in CarZone.values) {
      final defs = session.brand.modules.where((m) => m.zone == zone).toList();
      if (defs.isEmpty) continue;
      final results = [for (final d in defs) ?scan.find(d.txId)];
      final present = results.where((r) => r.present);
      final faults = present.fold(0, (n, r) => n + (r.dtcs?.length ?? 0));
      final scanned = results.length == defs.length && present.isNotEmpty;
      final Color color;
      final String label;
      IconData? icon;
      if (!scanned) {
        color = Theme.of(context).colorScheme.outline;
        label = zone.short;
      } else if (faults > 0) {
        color = toneColor(context, Tone.bad);
        label = '${zone.short} · $faults';
      } else {
        color = toneColor(context, Tone.ok);
        label = zone.short;
        icon = Icons.check_rounded;
      }
      chips.add(_ZoneChip(label: label, color: color, icon: icon, onTap: () => _openZone(context, session, zone)));
    }
    return chips;
  }

  Widget _footer(BuildContext context, DiagSession session) {
    final scan = session.scan;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    if (scan.scanning) {
      return Row(
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text('Checking modules ${scan.results.length} of ${scan.total}...', style: muted),
        ],
      );
    }
    if (!scan.hasResults) {
      return Row(
        children: [
          Expanded(child: Text('Scan the modules to see the health of each area.', style: muted)),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: () => openScan(context), child: const Text('Scan')),
        ],
      );
    }
    return Text('Tap an area to see its modules.', style: muted);
  }

  Future<void> _openZone(BuildContext context, DiagSession session, CarZone zone) async {
    final def = await showModalBottomSheet<ModuleDef>(
      context: context,
      builder: (_) => _ZoneSheet(zone: zone),
    );
    if (def == null || !context.mounted) return;
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ModuleScreen(module: def)));
    if (!session.connected) return;
    try {
      await session.scan.refresh(session.transport, session.brand, def);
    } catch (_) {
      // The card keeps the previous status; a rescan fixes it.
    }
  }
}

/// The picture area: the user's photo or video with the car's name over it.
class _Hero extends StatelessWidget {
  const _Hero({required this.session});
  final DiagSession session;

  Future<void> _change(BuildContext context) async {
    final hasMedia = session.carMedia != null;
    final choice = await showModalBottomSheet<_MediaAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Picture of your car', style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final a in _MediaAction.values)
              if (a != _MediaAction.remove || hasMedia)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: Icon(a.icon),
                  title: Text(a.label),
                  onTap: () => Navigator.pop(context, a),
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    try {
      if (choice == _MediaAction.remove) {
        await session.removeCarMedia();
        return;
      }
      final picker = ImagePicker();
      final XFile? picked = switch (choice) {
        _MediaAction.takePhoto => await picker.pickImage(source: ImageSource.camera, maxWidth: 2560, imageQuality: 90),
        _MediaAction.choosePhoto => await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 2560,
          imageQuality: 90,
        ),
        _MediaAction.recordVideo => await picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(seconds: 20),
        ),
        _MediaAction.chooseVideo => await picker.pickVideo(source: ImageSource.gallery),
        _MediaAction.remove => null,
      };
      if (picked == null) return; // cancelled
      final type = choice == _MediaAction.recordVideo || choice == _MediaAction.chooseVideo
          ? CarMediaType.video
          : CarMediaType.photo;
      await session.setCarMedia(type, picked.path);
    } catch (e) {
      if (context.mounted) showMessage(context, 'Could not use that picture: ${errorText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = session.identity;
    final media = session.carMedia;
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Stack(
        fit: StackFit.expand,
        children: [
          switch (media?.type) {
            CarMediaType.photo => Image.file(
              media!.file,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _Placeholder(onAdd: () => _change(context)),
            ),
            CarMediaType.video => _LoopingVideo(key: ValueKey(media!.file.path), media: media),
            null => _Placeholder(onAdd: () => _change(context)),
          },
          // Shade the bottom so the name stays readable on any picture.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.45, 1],
                colors: [Colors.transparent, Color(0xB3000000)],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 72,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  identity.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
                if (identity.year != null)
                  Text(
                    'Model year ${identity.year}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                  ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: IconButton.filledTonal(
              tooltip: media == null ? 'Add a picture' : 'Change picture',
              icon: Icon(media == null ? Icons.add_a_photo_outlined : Icons.edit_outlined),
              onPressed: () => _change(context),
            ),
          ),
        ],
      ),
    );
  }
}

enum _MediaAction {
  takePhoto('Take a photo', Icons.photo_camera_outlined),
  choosePhoto('Choose a photo', Icons.photo_library_outlined),
  recordVideo('Record a short video', Icons.videocam_outlined),
  chooseVideo('Choose a video', Icons.video_library_outlined),
  remove('Remove picture', Icons.delete_outline_rounded);

  const _MediaAction(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, Color.lerp(scheme.primary, const Color(0xFF0B1B33), 0.55)!],
        ),
      ),
      child: Align(
        alignment: const Alignment(0, -0.35),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_car_filled_rounded, size: 56, color: scheme.onPrimary.withValues(alpha: 0.9)),
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: scheme.onPrimary),
              onPressed: onAdd,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('Add a photo or video of your car'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plays the user's video muted and on repeat, paused while off screen.
class _LoopingVideo extends StatefulWidget {
  const _LoopingVideo({super.key, required this.media});
  final CarMedia media;

  @override
  State<_LoopingVideo> createState() => _LoopingVideoState();
}

class _LoopingVideoState extends State<_LoopingVideo> {
  late final VideoPlayerController _controller = VideoPlayerController.file(widget.media.file);
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller
        .initialize()
        .then((_) async {
          await _controller.setLooping(true);
          await _controller.setVolume(0);
          if (!mounted) return;
          setState(() => _ready = true);
          _syncPlayback();
        })
        .catchError((Object _) {
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPlayback();
  }

  /// Hidden tabs disable tickers; use that to stop playing when not visible.
  void _syncPlayback() {
    if (!_ready) return;
    TickerMode.valuesOf(context).enabled ? _controller.play() : _controller.pause();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text('This video could not be played', style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
        ),
      );
    }
    if (!_ready) return const ColoredBox(color: Colors.black);
    final size = _controller.value.size;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(_controller)),
      ),
    );
  }
}

class _ZoneChip extends StatelessWidget {
  const _ZoneChip({required this.label, required this.color, required this.onTap, this.icon});
  final String label;
  final Color color;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: 0.12),
    shape: StadiumBorder(side: BorderSide(color: color.withValues(alpha: 0.6))),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: icon == null ? null : Icon(icon, size: 11, color: Colors.white),
            ),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    ),
  );
}

/// The modules in one area of the car and their status.
class _ZoneSheet extends StatelessWidget {
  const _ZoneSheet({required this.zone});
  final CarZone zone;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final defs = session.brand.modules.where((m) => m.zone == zone);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(zone.label, style: Theme.of(context).textTheme.titleLarge),
          ),
          for (final def in defs) _row(context, def, session.scan.find(def.txId)),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ModuleDef def, ModuleInfo? info) {
    final dtcs = info?.dtcs;
    final outline = Theme.of(context).colorScheme.outline;
    final Widget status;
    if (info == null) {
      status = Pill('not scanned', color: outline);
    } else if (!info.present) {
      status = Pill('not found', color: outline);
    } else if (dtcs == null) {
      status = Pill('?', color: outline);
    } else if (dtcs.isEmpty) {
      status = Pill('OK', color: toneColor(context, Tone.ok), icon: Icons.check_rounded);
    } else {
      status = Pill('${dtcs.length} fault${dtcs.length == 1 ? '' : 's'}', color: toneColor(context, Tone.bad));
    }
    final enabled = info == null || info.present;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      enabled: enabled,
      leading: ModuleBadge(def.address.isEmpty ? def.name[0] : def.address, dimmed: !enabled),
      title: Text(def.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: info?.partNumber.isNotEmpty == true ? Text(info!.partNumber) : null,
      trailing: status,
      onTap: enabled ? () => Navigator.pop(context, def) : null,
    );
  }
}
