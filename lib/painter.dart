library painter;

import 'dart:convert';

import 'package:flutter/widgets.dart' hide Image;
import 'dart:ui';
import 'dart:async';
import 'dart:typed_data';

class Painter extends StatefulWidget {
  final PainterController painterController;

  Painter(PainterController painterController):
        this.painterController=painterController,
        super(key:new ValueKey<PainterController>(painterController));

  @override
  _PainterState createState() => new _PainterState();
}

class _PainterState extends State<Painter> {

  bool _eraseMode;
  bool _finished;

  @override
  void initState() {
    super.initState();
    _finished=false;
    _eraseMode=false;
    widget.painterController._widgetFinish=_finish;
  }

  Size _finish(){
    setState((){
      _finished=true;
    });
    return context.size;
  }

  @override
  Widget build(BuildContext context) {
    Widget child=new CustomPaint(
      willChange: true,
      painter: new _PainterPainter(
          widget.painterController._pathHistory,
          repaint: widget.painterController
      ),
    );
    child=new ClipRect(child:child);
    if(!_finished){
      child=new GestureDetector(
        child:child,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
      );
    }
    return new Container(
      child: child,
      width: double.infinity,
      height: double.infinity,
    );
  }

  void _onPanStart(DragStartDetails start){
    Offset pos=(context.findRenderObject() as RenderBox)
        .globalToLocal(start.globalPosition);
    widget.painterController._pathHistory.add(pos);
    widget.painterController._notifyListeners();
  }

  void _onPanUpdate(DragUpdateDetails update){
    Offset pos=(context.findRenderObject() as RenderBox)
        .globalToLocal(update.globalPosition);
    widget.painterController._pathHistory.updateCurrent(pos);
    widget.painterController._notifyListeners();
  }

  void _onPanEnd(DragEndDetails end){
    widget.painterController._pathHistory.endCurrent();
    widget.painterController._notifyListeners();
  }

}

class _PainterPainter extends CustomPainter{
  final _PathHistory _path;

  _PainterPainter(this._path,{Listenable repaint}):super(repaint:repaint);

  @override
  void paint(Canvas canvas, Size size) {
    _path.draw(canvas, size);
  }

  @override
  bool shouldRepaint(_PainterPainter oldDelegate) {
    return true;
  }

}

class _PathHistory{

  List<MapEntry<Path,Paint>> _paths;
  Paint currentPaint;
  Paint _backgroundPaint;
  bool _inDrag;
  Function _onDrawStepListener;

  int historySize() {
    return _paths.length;
  }


  _PathHistory(List<MapEntry<Path,Paint>> paths){
    if (paths != null) {
      _paths = paths;
    } else {
      _paths=new List<MapEntry<Path,Paint>>();
    }
    _inDrag=false;
    _backgroundPaint=new Paint();

  }

  void setOnDrawStepListener(Function onDrawListener) {
    _onDrawStepListener = onDrawListener;
  }

  void setBackgroundColor(Color backgroundColor){
    _backgroundPaint.color=backgroundColor;
  }

  void undo() {
    if (!_inDrag) {
      _paths.removeLast();
    }
  }

  void clear(){
    if(!_inDrag){
      _paths.clear();
    }
  }

  void _triggerOnDrawStepListener() {
    _onDrawStepListener?.call();
  }

  void add(Offset startPoint){
    if(!_inDrag) {
      _inDrag=true;
      Path path = new Path();
      path.moveTo(startPoint.dx, startPoint.dy);
      _paths.add(new MapEntry<Path, Paint>(path, currentPaint));
      _triggerOnDrawStepListener();
    }
  }

  void updateCurrent(Offset nextPoint) {
    if (_inDrag) {
      Path path=_paths.last.key;
      path.lineTo(nextPoint.dx, nextPoint.dy);
    }
  }

  void endCurrent() {
    _inDrag=false;
  }

  void draw(Canvas canvas,Size size){
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(new Rect.fromLTWH(0.0, 0.0, size.width, size.height), _backgroundPaint);
    for(MapEntry<Path,Paint> path in _paths){
      canvas.drawPath(path.key,path.value);
    }
    canvas.restore();
  }
}

typedef PictureDetails PictureCallback();

class PictureDetails{
  final Picture picture;
  final int width;
  final int height;

  const PictureDetails(this.picture,this.width,this.height);

  Future<Image> toImage(){
    return picture.toImage(width, height);
  }

  Future<Uint8List> toPNG() async{
    final image = await toImage();
    return (await image.toByteData(format: ImageByteFormat.png)).buffer.asUint8List();
  }
}

class PainterController extends ChangeNotifier{
  Color _drawColor=new Color.fromARGB(255, 0, 0, 0);
  Color _backgroundColor=new Color.fromARGB(255, 255, 255, 255);
  bool _eraseMode=false;

  double _thickness=1.0;
  PictureDetails _cached;
  _PathHistory _pathHistory;
  ValueGetter<Size> _widgetFinish;

  PainterController({this.history}){
    _pathHistory=new _PathHistory(_derializeHistory(history));
  }

  String history;

  String serializeHistory(List<MapEntry<Path,Paint>> deserializedHistory) {
    return jsonEncode(deserializedHistory);
  }

  List<MapEntry<Path,Paint>> _derializeHistory(String serializedHistory) {
    if (serializedHistory != null) {
      return json.decode(serializedHistory) as List<MapEntry<Path,Paint>>;
    } else {
      return null;
    }
  }

  void setOnDrawStepListener(Function onDrawStepListener) {
    _pathHistory.setOnDrawStepListener(onDrawStepListener);
  }

  bool hasHistory() {
    return _pathHistory.historySize() != 0;
  }

  // setter for erase mode.
  // Note: Works only for transparent background
  bool get eraseMode => _eraseMode;
  set eraseMode(bool enabled) {
    _eraseMode = enabled;
    _updatePaint();
  }

  Color get drawColor => _drawColor;
  set drawColor(Color color){
    _drawColor=color;
    _updatePaint();
  }

  Color get backgroundColor => _backgroundColor;
  set backgroundColor(Color color){
    _backgroundColor=color;
    _updatePaint();
  }

  double get thickness => _thickness;
  set thickness(double t){
    _thickness=t;
    _updatePaint();
  }

  void _updatePaint(){
    Paint paint=new Paint();
    if (_eraseMode) {
      paint.color=Color.fromARGB(0, 255, 0, 0);
      paint.blendMode = BlendMode.clear;
    } else {
      paint.color=drawColor;
    }
    paint.style=PaintingStyle.stroke;
    paint.strokeWidth=thickness;
    _pathHistory.currentPaint=paint;
    _pathHistory.setBackgroundColor(backgroundColor);
    notifyListeners();
  }

  void undo(){
    if(!isFinished()) {
      _pathHistory.undo();
      notifyListeners();
    }
  }

  void _notifyListeners(){
    notifyListeners();
  }

  void clear(){
    if(!isFinished()) {
      _pathHistory.clear();
      notifyListeners();
    }
  }

  PictureDetails finish(){
    if(!isFinished()){
      _cached=_render(_widgetFinish());
    }
    return _cached;
  }

  PictureDetails _render(Size size){
    PictureRecorder recorder =new PictureRecorder();
    Canvas canvas=new Canvas(recorder);
    _pathHistory.draw(canvas, size);
    return new PictureDetails(recorder.endRecording(),size.width.floor(),size.height.floor());
  }

  bool isFinished(){
    return _cached!=null;
  }

}