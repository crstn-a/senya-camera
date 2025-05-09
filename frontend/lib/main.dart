import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui;
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          margin: const EdgeInsets.all(10),
        ),
      ),
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
  bool isModelReady = false;
  bool isConnectingToAPI = false;
  bool _showInstructions = false;

  final String apiEndpoint = 'http://127.0.0.1:8000';

  List<String> targetWords = ["apple", "banana", "cherry", "pineapple", "papaya"];
  int currentWordIndex = 0;
  int currentLetterIndex = 0;
  List<bool> correctLetters = [];
  String? lastIncorrectPrediction;
  bool isWordCompleted = false;
  
  String errorMessage = '';
  int connectionRetries = 0;
  final int maxRetries = 3;

  @override
  void initState() {
    super.initState();
    correctLetters = List.filled(targetWords[currentWordIndex].length, false);
    currentLetterIndex = 0;
    _checkModelStatus();
    _initializeCamera();
  }

  Future<void> _checkModelStatus() async {
    setState(() {
      isConnectingToAPI = true;
      errorMessage = '';
    });
    
    try {
      final response = await http.get(Uri.parse('$apiEndpoint/model-status'))
          .timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          isModelReady = data['model_loaded'] == true;
          isConnectingToAPI = false;
          connectionRetries = 0;
        });
      } else {
        _handleConnectionError("Server error: ${response.statusCode}");
      }
    } on TimeoutException {
      _handleConnectionError("Connection timeout");
    } catch (e) {
      _handleConnectionError("Error checking model status: $e");
    }
  }
  
  void _handleConnectionError(String message) {
    connectionRetries++;
    setState(() {
      isConnectingToAPI = false;
      isModelReady = false;
      errorMessage = message;
    });
    
    if (connectionRetries < maxRetries) {
      Future.delayed(const Duration(seconds: 3), _checkModelStatus);
    }
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
      _startAutomaticPrediction();
    }).catchError((e) {
      debugPrint("Error accessing camera: $e");
      setState(() {
        errorMessage = "Camera access denied. Please enable camera permissions.";
      });
    });
  }

  void _startAutomaticPrediction() {
    _predictionTimer?.cancel();
    _predictionTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!isWordCompleted) {
        _captureFrameAndPredict();
      }
    });
  }

  Future<void> _captureFrameAndPredict() async {
    if (!isModelReady || isWordCompleted) {
      if (!isConnectingToAPI) await _checkModelStatus();
      return;
    }

    final canvas = web.HTMLCanvasElement();
    canvas.width = 224;
    canvas.height = 224;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;

    try {
      ctx.drawImage(_videoElement, 0, 0, canvas.width, canvas.height);
    } catch (e) {
      debugPrint("Error capturing video frame: $e");
      return;
    }
    
    final base64Image = canvas.toDataURL('image/jpeg').split(',')[1];
    
    setState(() {
      predictedLabel = 'Processing...';
    });
    
    try {
      final response = await http.post(
        Uri.parse('$apiEndpoint/predict-base64'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          predictedLabel = '${data['letter']} (${(data['confidence'] * 100).toStringAsFixed(2)}%)';
          errorMessage = '';
          if (!isWordCompleted) {
            _checkUserInput(data['letter']);
          }
        });
      } else {
        setState(() {
          predictedLabel = 'Error';
          errorMessage = "API Error: ${response.statusCode}";
        });
      }
    } on TimeoutException {
      setState(() {
        predictedLabel = 'Timeout';
        errorMessage = "API request timed out";
      });
    } catch (e) {
      setState(() {
        predictedLabel = 'Error';
        errorMessage = "Connection error";
      });
    }
  }

  void _checkUserInput(String recognizedLetter) {
    if (recognizedLetter.isEmpty || isWordCompleted || currentLetterIndex >= targetWords[currentWordIndex].length) {
      return;
    }

    setState(() {
      final currentLetter = targetWords[currentWordIndex][currentLetterIndex].toLowerCase();
      final predictedLetter = recognizedLetter.toLowerCase();
      
      if (predictedLetter == currentLetter) {
        correctLetters[currentLetterIndex] = true;
        currentLetterIndex++;
        lastIncorrectPrediction = null;

        if (currentLetterIndex >= targetWords[currentWordIndex].length) {
          isWordCompleted = true;
          _predictionTimer?.cancel();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Excellent! You spelled "${targetWords[currentWordIndex]}" correctly!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );

          Future.delayed(const Duration(seconds: 3), () {
            if (currentWordIndex < targetWords.length - 1) {
              setState(() {
                currentWordIndex++;
                currentLetterIndex = 0;
                correctLetters = List.filled(targetWords[currentWordIndex].length, false);
                lastIncorrectPrediction = null;
                isWordCompleted = false;
                predictedLabel = '';
              });
              _startAutomaticPrediction();
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Next word: "${targetWords[currentWordIndex]}"'),
                  backgroundColor: Colors.blue,
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Congratulations! You completed all words!'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }
          });
        }
      } else {
        lastIncorrectPrediction = predictedLetter;
      }
    });
  }

  Widget _buildWordDisplay() {
    int totalLetters = targetWords.fold(0, (sum, word) => sum + word.length);
    int completedLetters = 0;
    for (int wordIndex = 0; wordIndex < currentWordIndex; wordIndex++) {
      completedLetters += targetWords[wordIndex].length;
    }
    completedLetters += correctLetters.where((e) => e).length;

    double overallProgress = completedLetters / totalLetters;

    final displayIndex = currentLetterIndex < targetWords[currentWordIndex].length
        ? currentLetterIndex
        : targetWords[currentWordIndex].length - 1;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Word ${currentWordIndex + 1} of ${targetWords.length}',
          style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: overallProgress,
              minHeight: 10,
              backgroundColor: Colors.orange.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
            ),
          ),
        ),

        const SizedBox(height: 10),

        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: targetWords[currentWordIndex].split('').asMap().entries.map((entry) {
            int index = entry.key;
            String letter = entry.value;
            String currentLetter = targetWords[currentWordIndex][displayIndex].toLowerCase();

            Color color;
            if (index < displayIndex) {
              color = Colors.green;
            } else if (index == displayIndex) {
              color = (lastIncorrectPrediction != null &&
                      lastIncorrectPrediction!.isNotEmpty &&
                      lastIncorrectPrediction != currentLetter)
                  ? Colors.red
                  : Colors.blue;
            } else {
              color = Colors.grey;
            }

            return Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                letter.toUpperCase(),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildInstructionCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade50,
              Colors.white,
            ],
          ),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How to Play',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 16),
              _buildInstructionStep(
                '1',
                'Position Your Hand',
                'Make sure your hand is clearly visible in the camera view',
                Icons.videocam,
              ),
              _buildInstructionStep(
                '2',
                'Form the ASL Sign',
                'Show the sign for the highlighted letter in the word',
                Icons.fingerprint,
              ),
              _buildInstructionStep(
                '3',
                'Hold Steady',
                'Maintain the sign for a moment to allow recognition',
                Icons.timer,
              ),
              _buildInstructionStep(
                '4',
                'Continue Spelling',
                'Repeat for each letter until the word is complete',
                Icons.spellcheck,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionStep(String number, String title, String description, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorDisplay() {
    if (errorMessage.isEmpty) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorMessage,
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
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
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(
          'Senya Spelling Game',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.orange,
          ),
        ),
        centerTitle: true,
        // In your app bar actions:
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => Center(
                  child: SizedBox(
                    width: 600, // Square width
                    height: 400, // Square height
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: _buildInstructionCard(),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_showInstructions) ...[
                  _buildInstructionCard(),
                  const SizedBox(height: 20),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column - Camera View
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Container(
                                height: 400,
                                width: 500,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isModelReady ? Colors.green : Colors.grey,
                                    width: 2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: isCameraInitialized
                                      ? const HtmlElementView(viewType: 'webcamVideo')
                                      : const Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircularProgressIndicator(),
                                              SizedBox(height: 16),
                                              Text(
                                                "Initializing camera...",
                                                style: TextStyle(color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lightbulb_outline,
                                    color: Colors.blue.shade700,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Current prediction: $predictedLabel',
                                    style: TextStyle(
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _buildErrorDisplay(),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 40),
                    
                    // Right Column - Word Display
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Container(  // Added Container with fixed dimensions
                                height: 400,    // Matches camera height
                                width: 500,     // Matches camera width
                                padding: const EdgeInsets.all(20.0),
                                child: _buildWordDisplay(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}