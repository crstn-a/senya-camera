import 'dart:async';
import 'dart:js' as js;
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SpellItScreen(),
    );
  }
}

class SpellItScreen extends StatefulWidget {
  const SpellItScreen({super.key});

  @override
  _SpellItScreenState createState() => _SpellItScreenState();
}

class _SpellItScreenState extends State<SpellItScreen> {
  late web.HTMLVideoElement _videoElement;
  bool isCameraInitialized = false;
  String predictedLabel = '';
  Timer? _predictionTimer;

  // Target Word for Fingerspelling
  String targetWord = "apple";
  int currentLetterIndex = 0;
  List<bool> correctLetters = [];

  @override
  void initState() {
    super.initState();
    correctLetters = List.filled(targetWord.length, false);
    _initializeCamera();
  }

  void _initializeCamera() {
    _videoElement = web.HTMLVideoElement()
      ..autoplay = true
      ..style.width = "100%"
      ..style.height = "100%";

    ui.platformViewRegistry.registerViewFactory(
      'webcamVideo',
      (int viewId) => _videoElement,
    );

    web.MediaStreamConstraints constraints = web.MediaStreamConstraints(video: true.toJS);
    web.window.navigator.mediaDevices.getUserMedia(constraints).toDart.then((stream) {
      _videoElement.srcObject = stream;
      setState(() {
        isCameraInitialized = true;
      });

      // Start automatic prediction every 500ms
      _startAutomaticPrediction();
    }).catchError((e) {
      debugPrint("Error accessing camera: $e");
    });
  }

  void _startAutomaticPrediction() {
  _predictionTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
    _captureFrameAndPredict();
  });
}


  void _captureFrameAndPredict() {
    final canvas = web.HTMLCanvasElement();
    canvas.width = 224;
    canvas.height = 224;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;

    ctx.drawImage(_videoElement, 0, 0);
    var imageData = ctx.getImageData(0, 0, 224, 224);
    var isModelReady = js.context['modelReady'];
    if (isModelReady == true) {
      var prediction = js.context.callMethod('predictFromImage', [imageData]);

    prediction.then((value) {
      if (value == null) return;

      String recognizedLetter = value.toString().toLowerCase();

      setState(() {
        predictedLabel = recognizedLetter;
        _checkUserInput(recognizedLetter);
      });
    }).catchError((e) {
      debugPrint("❌ Prediction Error: $e");
    });
  } else {
    debugPrint("⚠️ Waiting for model to load...");
  }
}

void _checkUserInput(String recognizedLetter) {
  if (recognizedLetter.isEmpty || currentLetterIndex >= targetWord.length) {
    return;
  }

  setState(() {
    if (recognizedLetter == targetWord[currentLetterIndex]) {
      correctLetters[currentLetterIndex] = true;
      currentLetterIndex++; // Move to next letter
    } else {
      correctLetters[currentLetterIndex] = false;
    }
  });
}


  Widget _buildWordDisplay() {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: targetWord.split('').asMap().entries.map((entry) {
      int index = entry.key;
      String letter = entry.value;

      Color color;
      if (index < currentLetterIndex) {
        color = correctLetters[index] ? Colors.green : Colors.red;
      } else if (index == currentLetterIndex) {
        color = Colors.blue; // Highlight the next letter to spell
      } else {
        color = Colors.grey;
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Text(
          letter.toUpperCase(),
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color),
        ),
      );
    }).toList(),
  );
}

  @override
  void dispose() {
    _predictionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.orange),
          onPressed: () {},
        ),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Text(
                  'Spell the word:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                _buildWordDisplay(),
                const SizedBox(height: 10),
                Text(
                  'Prediction: $predictedLabel',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: isCameraInitialized
                      ? const HtmlElementView(viewType: 'webcamVideo')
                      : const Center(child: CircularProgressIndicator()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}