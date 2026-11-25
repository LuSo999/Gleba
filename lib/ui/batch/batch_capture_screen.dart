import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/batch.dart';
import '../../domain/shelf_life.dart';
import '../labels.dart';
import 'batch_job.dart';

/// Photographing a shopping trip in a row: the camera stays open, every
/// product gets a barcode photo and a date photo, everything is read in the
/// background. "Done" opens the review.
class BatchCaptureScreen extends ConsumerStatefulWidget {
  const BatchCaptureScreen({super.key});

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  ConsumerState<BatchCaptureScreen> createState() => _BatchCaptureScreenState();
}

class _BatchCaptureScreenState extends ConsumerState<BatchCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  String? _error;
  bool _shooting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final c = _camera;
    if (s == AppLifecycleState.inactive && c != null) {
      _camera = null;
      c.dispose();
      if (mounted) setState(() {});
    } else if (s == AppLifecycleState.resumed && _camera == null) {
      _open();
    }
  }

  Future<void> _open() async {
    try {
      final cams = await availableCameras();
      final back =
          cams
              .where((c) => c.lensDirection == CameraLensDirection.back)
              .firstOrNull ??
          cams.first;
      final c = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _camera = c;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _shoot() async {
    final c = _camera;
    if (c == null || _shooting || !c.value.isInitialized) return;
    setState(() => _shooting = true);
    try {
      final shot = await c.takePicture();
      final job = ref.read(batchJobProvider.notifier);
      if (job.retake != null) {
        job.replacePhoto(shot.path);
      } else {
        job.awaitingDateFor == null
            ? job.addBarcodePhoto(shot.path)
            : job.addDatePhoto(shot.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  /// A taken product: both photos, retake either, or delete it.
  Future<void> _showProduct(BatchProduct p) async {
    final l = context.l;
    final job = ref.read(batchJobProvider.notifier);
    Widget photo(String? path, String label) => Expanded(
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: path == null
                  ? Container(
                      color: Colors.black12,
                      alignment: Alignment.center,
                      child: Text(l.batchNoPhoto),
                    )
                  : Image.file(File(path), fit: BoxFit.cover, cacheWidth: 500),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                p.name.isEmpty ? l.batchUnknownProduct : p.name,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  photo(p.barcodePath, l.batchStepBarcode),
                  const SizedBox(width: 12),
                  photo(
                    p.datePath,
                    p.skipDate ? l.batchNoDate : l.batchStepDate,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      job.setRetake(p.id, date: false);
                    },
                    icon: const Icon(Icons.qr_code_2),
                    label: Text(l.batchRetakeBarcode),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      job.setRetake(p.id, date: true);
                    },
                    icon: const Icon(Icons.event),
                    label: Text(l.batchRetakeDate),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      job.removeProduct(p.id);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l.deleteItem),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addReceipt() async {
    final l = context.l;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(l.receiptTake),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l.receiptGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    // The system camera needs ours released.
    final c = _camera;
    _camera = null;
    await c?.dispose();
    if (mounted) setState(() {});
    final photo = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (photo != null) {
      ref.read(batchJobProvider.notifier).addReceipt(await photo.readAsBytes());
    }
    if (mounted) _open();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    ref.watch(batchJobProvider);
    final job = ref.read(batchJobProvider.notifier);
    final retake = job.retake;
    final retakeName = retake == null
        ? null
        : (job.products.where((p) => p.id == retake.id).firstOrNull?.name ??
              '');
    final dateStep = retake?.date ?? (job.awaitingDateFor != null);
    final c = _camera;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            Center(child: CameraPreview(c))
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _error == null
                      ? l.batchCameraStarting
                      : l.batchCameraError(_error!),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          // Aim frame
          IgnorePointer(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.78,
                heightFactor: 0.3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white70, width: 2),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => context.pop(),
                      ),
                      const Spacer(),
                      _Pill(
                        text:
                            '📷 ${l.batchCount(job.photoCount, job.products.length)}',
                      ),
                      const Spacer(),
                      _Pill(
                        text: switch (job.receiptState) {
                          ReceiptState.none => '🧾 ${l.batchAddReceipt}',
                          ReceiptState.reading => '🧾 …',
                          ReceiptState.done => '🧾 ✓',
                          ReceiptState.failed => '🧾 ⚠️',
                        },
                        onTap: job.receiptState == ReceiptState.reading
                            ? null
                            : _addReceipt,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  retake != null
                      ? l.batchRetakeAim(
                          dateStep ? l.batchStepDate : l.batchStepBarcode,
                          retakeName ?? '',
                        )
                      : (dateStep ? l.batchAimDate : l.batchAimBarcode),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Step(text: '1 · ${l.batchStepBarcode}', on: !dateStep),
                    const SizedBox(width: 8),
                    _Step(text: '2 · ${l.batchStepDate}', on: dateStep),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                      for (final p in job.products.reversed)
                        _Thumb(product: p, onTap: () => _showProduct(p)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: retake != null
                              ? OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  onPressed: job.cancelRetake,
                                  child: Text(l.cancel),
                                )
                              : dateStep
                              ? OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  onPressed: job.skipDate,
                                  child: Text(l.batchNoDate),
                                )
                              : const SizedBox(),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: dateStep ? l.batchStepDate : l.batchStepBarcode,
                        child: GestureDetector(
                          onTap: _shoot,
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 5),
                              color: Colors.white.withValues(
                                alpha: _shooting ? 0.6 : 0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: job.isEmpty
                                ? null
                                : () => context.push('/batch/review'),
                            child: Text(l.batchDone),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.16),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.text, required this.on});

  final String text;
  final bool on;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: on ? Colors.white : Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: on ? Colors.black : Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

/// A taken product with its state: ✓ read, AI, … working, ! not recognised.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.product, required this.onTap});

  final BatchProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final (badge, color) = p.busy
        ? ('…', const Color(0xFFE08A00))
        : p.productState == ShotState.failed
        ? ('!', const Color(0xFFC62828))
        : p.productSource == ProductSource.ai || p.dateSource == DateSource.ai
        ? ('AI', const Color(0xFF8A70C2))
        : ('✓', const Color(0xFF2E9D5B));
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: p.barcodePath == null
                    ? Container(color: Colors.white24)
                    : Image.file(
                        File(p.barcodePath!),
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        cacheWidth: 120,
                      ),
              ),
              if (p.name.isNotEmpty)
                Positioned(
                  left: 2,
                  top: 0,
                  child: Text(
                    categoryById(p.categoryId).emoji,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              Positioned(
                right: -4,
                bottom: -4,
                child: CircleAvatar(
                  radius: 9,
                  backgroundColor: color,
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
