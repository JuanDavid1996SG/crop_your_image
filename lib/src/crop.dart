part of crop_your_image;

const dotSize = 8.0; // visible dot size
const dotPadding = 16.0; // padding for touchable area
const dotTotalSize = dotSize + (dotPadding * 2);

/// Widget for the entry point of crop_your_image.
class Crop extends StatelessWidget {
  /// original image data
  final Uint8List image;

  /// callback when cropping completed
  final ValueChanged<Uint8List> onCropped;

  /// fixed aspect ratio of cropping area.
  /// null, by default, means no fixed aspect ratio.
  final double? aspectRatio;

  /// initial size of cropping area.
  /// Set double value less than 1.0.
  /// if initialSize is 1.0 (or null),
  /// cropping area would expand as much as possible.
  final double? initialSize;

  /// flag if cropping image with circle shape.
  /// if [true], [aspectRatio] is fixed to 1.
  final bool withCircleUi;

  /// conroller for control crop actions
  final CropController? controller;

  /// flag to show debug sheet
  final bool showDebugSheet;

  const Crop({
    Key? key,
    required this.image,
    required this.onCropped,
    this.aspectRatio,
    this.initialSize,
    this.withCircleUi = false,
    this.controller,
    this.showDebugSheet = false,
  })  : assert((initialSize ?? 1.0) <= 1.0,
            'initialSize must be less than 1.0, or null meaning not specified.'),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (c, constraints) {
        final newData = MediaQuery.of(c).copyWith(
          size: constraints.biggest,
        );
        return MediaQuery(
          data: newData,
          child: _CropEditor(
            image: image,
            onCropped: onCropped,
            aspectRatio: aspectRatio,
            initialSize: initialSize,
            withCircleUi: withCircleUi,
            controller: controller,
            showDebugSheet: showDebugSheet,
          ),
        );
      },
    );
  }
}

class _CropEditor extends StatefulWidget {
  final Uint8List image;
  final ValueChanged<Uint8List> onCropped;
  final double? aspectRatio;
  final double? initialSize;
  final bool withCircleUi;
  final CropController? controller;
  final bool showDebugSheet;

  const _CropEditor({
    Key? key,
    required this.image,
    required this.onCropped,
    this.aspectRatio,
    this.initialSize,
    this.withCircleUi = false,
    this.controller,
    this.showDebugSheet = false,
  }) : super(key: key);

  @override
  _CropEditorState createState() => _CropEditorState();
}

class _CropEditorState extends State<_CropEditor> {
  late CropController _cropController;
  late TransformationController _controller;
  late Rect _rect;
  image.Image? _targetImage;
  late Rect _imageRect;
  late double _centerX;
  late double _centerY;

  double? _aspectRatio;
  bool _withCircleUi = false;
  bool _isFitVertically = false;

  _Calculator get calculator => _isFitVertically
      ? const _VerticalCalculator()
      : const _HorizontalCalculator();

  @override
  void initState() {
    _cropController = widget.controller ?? CropController();
    _cropController.delegate = CropControllerDelegate()
      ..onCrop = _crop
      ..onChangeAspectRatio = _resizeWith
      ..onChangeWithCircleUi = (withCircleUi) {
        _withCircleUi = withCircleUi;
        _resizeWith(_aspectRatio);
      };

    final decodedImage = image.decodeImage(widget.image);
    setState(() {
      _targetImage = decodedImage;
    });

    _controller = TransformationController()
      ..addListener(() => setState(() {}));

    super.initState();
  }

  @override
  void didChangeDependencies() {
    final screenSize = MediaQuery.of(context).size;
    final imageRatio = _targetImage!.width / _targetImage!.height;
    _isFitVertically = imageRatio < (screenSize.width / screenSize.height);

    _imageRect = calculator.imageRect(screenSize, imageRatio);

    _centerX = screenSize.width / 2;
    _centerY = screenSize.height / 2;

    _withCircleUi = widget.withCircleUi;
    _resizeWith(widget.aspectRatio);

    super.didChangeDependencies();
  }

  /// resize cropping area with given aspect ratio.
  void _resizeWith(double? aspectRatio) {
    _aspectRatio = _withCircleUi ? 1 : aspectRatio;

    setState(() {
      _rect = calculator.initialCropRect(
        MediaQuery.of(context).size,
        _imageRect,
        _aspectRatio ?? 1,
        widget.initialSize ?? 1,
      );
    });
  }

  /// crop given image with given area.
  Future<void> _crop(bool withCircleShape) async {
    assert(_targetImage != null);

    final screenSizeRatio = calculator.screenSizeRatio(
      _targetImage!,
      MediaQuery.of(context).size,
    );

    // use compute() not to block UI update
    final cropResult = await compute(
      withCircleShape ? _doCropCircle : _doCrop,
      [
        _targetImage!,
        Rect.fromLTWH(
          (_rect.left - _imageRect.left) * screenSizeRatio,
          (_rect.top - _imageRect.top) * screenSizeRatio,
          _rect.width * screenSizeRatio,
          _rect.height * screenSizeRatio,
        ),
      ],
    );
    widget.onCropped(cropResult);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InteractiveViewer(
          scaleEnabled: false,
          transformationController: _controller,
          child: Container(
            color: Colors.blue.shade50,
            width: double.infinity,
            height: double.infinity,
            child: Image.memory(widget.image),
          ),
        ),
        IgnorePointer(
          child: ClipPath(
            clipper: _withCircleUi
                ? _CircleCropAreaClipper(_rect)
                : _CropAreaClipper(_rect),
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black.withAlpha(100),
            ),
          ),
        ),
        Positioned(
          left: _rect.left,
          top: _rect.top,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _rect = calculator.moveRect(
                  _rect,
                  details.delta.dx,
                  details.delta.dy,
                  _imageRect,
                );
              });
            },
            child: Container(
              width: _rect.width,
              height: _rect.height,
              color: Colors.transparent,
            ),
          ),
        ),
        Positioned(
          left: _rect.left - (dotTotalSize / 2),
          top: _rect.top - (dotTotalSize / 2),
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _rect = calculator.moveTopLeft(
                  _rect,
                  details.delta.dx,
                  details.delta.dy,
                  _imageRect,
                  _aspectRatio,
                );
              });
            },
            child: _DotControl(),
          ),
        ),
        Positioned(
          left: _rect.right - (dotTotalSize / 2),
          top: _rect.top - (dotTotalSize / 2),
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _rect = calculator.moveTopRight(
                  _rect,
                  details.delta.dx,
                  details.delta.dy,
                  _imageRect,
                  _aspectRatio,
                );
              });
            },
            child: _DotControl(),
          ),
        ),
        Positioned(
          left: _rect.left - (dotTotalSize / 2),
          top: _rect.bottom - (dotTotalSize / 2),
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _rect = calculator.moveBottomLeft(
                  _rect,
                  details.delta.dx,
                  details.delta.dy,
                  _imageRect,
                  _aspectRatio,
                );
              });
            },
            child: _DotControl(),
          ),
        ),
        Positioned(
          left: _rect.right - (dotTotalSize / 2),
          top: _rect.bottom - (dotTotalSize / 2),
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _rect = calculator.moveBottomRight(
                  _rect,
                  details.delta.dx,
                  details.delta.dy,
                  _imageRect,
                  _aspectRatio,
                );
              });
            },
            child: _DotControl(),
          ),
        ),
        Visibility(
          visible: widget.showDebugSheet,
          child: _buildDebugSheet(context),
        ),
      ],
    );
  }

  /// build debug sheet containing current scale, position, image size, etc.
  Widget _buildDebugSheet(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Container(
      color: Colors.green.withAlpha(200),
      width: MediaQuery.of(context).size.width,
      padding: const EdgeInsets.all(16),
      child: Positioned(
        bottom: 0,
        left: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SCREEN: height ${screenSize.height} / width ${screenSize.width}',
              style: TextStyle(color: Colors.white),
            ),
            if (_targetImage != null)
              Text(
                'IMAGE: height ${_targetImage!.height} / width ${_targetImage!.width}',
                style: TextStyle(color: Colors.white),
              ),
            Text(
              '$_rect',
              style: TextStyle(color: Colors.white),
            ),
            Text(
              'CONTROLLER: ${_controller.value.getMaxScaleOnAxis()}\n${_controller.value}',
              style: TextStyle(color: Colors.white),
            ),
            if (_targetImage != null)
              Text(
                '${_targetImage!.width * _controller.value.getMaxScaleOnAxis()}\n${_controller.value.entry(0, 3).abs() + screenSize.width}',
                style: TextStyle(color: Colors.white),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _CropAreaClipper extends CustomClipper<Path> {
  final Rect rect;

  _CropAreaClipper(this.rect);

  @override
  Path getClip(Size size) {
    return Path()
      ..addPath(
        Path()
          ..moveTo(rect.left, rect.top)
          ..lineTo(rect.right, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close(),
        Offset.zero,
      )
      ..addRect(Rect.fromLTWH(0.0, 0.0, size.width, size.height))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => true;
}

class _CircleCropAreaClipper extends CustomClipper<Path> {
  final Rect rect;

  _CircleCropAreaClipper(this.rect);

  @override
  Path getClip(Size size) {
    return Path()
      ..addOval(Rect.fromCircle(center: rect.center, radius: rect.width / 2))
      ..addRect(Rect.fromLTWH(0.0, 0.0, size.width, size.height))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => true;
}

class _DotControl extends StatelessWidget {
  const _DotControl({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      width: dotTotalSize,
      height: dotTotalSize,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(dotSize),
          child: Container(
            width: dotSize,
            height: dotSize,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// process cropping image.
/// this method is supposed to be called only via compute()
Uint8List _doCrop(List<dynamic> cropData) {
  final originalImage = cropData[0] as image.Image;
  final rect = cropData[1] as Rect;
  return Uint8List.fromList(
    image.encodePng(
      image.copyCrop(
        originalImage,
        rect.left.toInt(),
        rect.top.toInt(),
        rect.width.toInt(),
        rect.height.toInt(),
      ),
    ),
  );
}

/// process cropping image with circle shape.
/// this method is supposed to be called only via compute()
Uint8List _doCropCircle(List<dynamic> cropData) {
  final originalImage = cropData[0] as image.Image;
  final rect = cropData[1] as Rect;
  return Uint8List.fromList(
    image.encodePng(
      image.copyCropCircle(
        originalImage,
        center:
            image.Point(rect.left + rect.width / 2, rect.top + rect.height / 2),
        radius: min(rect.width, rect.height) ~/ 2,
      ),
    ),
  );
}
