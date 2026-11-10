import 'package:flutter/material.dart';

/// Opens the same image source at its full aspect ratio, with pinch zoom.
class ExpandablePhoto extends StatelessWidget {
  final ImageProvider image;
  final String label;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? thumbnail;
  final bool enabled;
  const ExpandablePhoto(
      {super.key,
      required this.image,
      this.label = 'Tree photo',
      this.width,
      this.height,
      this.thumbnail,
      this.enabled = true,
      this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) => Semantics(
        button: enabled,
        label: 'Open full photo: $label',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: !enabled
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      backgroundColor: Colors.black,
                      appBar: AppBar(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        title: Text(label),
                        leading: IconButton(
                            tooltip: 'Close photo',
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop()),
                      ),
                      body: SafeArea(
                          child: SizedBox.expand(
                              child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 6,
                        child: Center(
                            child: Image(
                                image: image,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Text(
                                    'Photo unavailable',
                                    style: TextStyle(color: Colors.white)))),
                      ))),
                    ),
                  )),
          child: thumbnail ??
              Image(
                  image: image,
                  width: width,
                  height: height,
                  fit: fit,
                  errorBuilder: (_, __, ___) => SizedBox(
                      width: width,
                      height: height,
                      child: const Center(child: Text('Photo unavailable')))),
        ),
      );
}
