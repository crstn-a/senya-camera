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

  // API endpoint
  final String apiEndpoint = 'http://127.0.0.1:8000'; // Change to your actual API endpoint

  // Target Word for Fingerspelling
  String targetWord = "apple";
  int currentLetterIndex = 0;
  List<bool> correctLetters = [];
  
  // Error tracking
  String errorMessage = '';
  int connectionRetries = 0;
  final int maxRetries = 3;

  @override
  void initState() {
    super.initState();
    correctLetters = List.filled(targetWord.length, false);
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
      final responseBody = response.body;
      debugPrint("Raw response: $responseBody");
      
      final data = jsonDecode(responseBody);
      debugPrint("Decoded data: $data");
      debugPrint("model_loaded value: ${data['model_loaded']}");
      
      setState(() {
        isModelReady = data['model_loaded'] == true; // Explicit comparison
        isConnectingToAPI = false;
        connectionRetries = 0;
        
        // Debug message
        debugPrint("isModelReady set to: $isModelReady");
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
    
    debugPrint("❌ $message (Attempt $connectionRetries of $maxRetries)");
    
    // Try again if under max retries
    if (connectionRetries < maxRetries) {
      debugPrint("Retrying connection in 3 seconds...");
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

      // Start automatic prediction every 3 seconds
      _startAutomaticPrediction();
    }).catchError((e) {
      debugPrint("Error accessing camera: $e");
      setState(() {
        errorMessage = "Camera access denied. Please enable camera permissions.";
      });
    });
  }

  void _startAutomaticPrediction() {
    _predictionTimer?.cancel(); // Cancel existing timer if any
    _predictionTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _captureFrameAndPredict();
    });
  }

  Future<void> _captureFrameAndPredict() async {
    if (!isModelReady) {
      // Only check model status if we're not already connecting
      if (!isConnectingToAPI) {
        await _checkModelStatus();
      }
      if (!isModelReady) {
        debugPrint("⚠️ Waiting for model to load...");
        return;
      }
    }

    final canvas = web.HTMLCanvasElement();
    canvas.width = 224;
    canvas.height = 224;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;

    // Attempt to draw the video frame to the canvas
    try {
      ctx.drawImage(_videoElement, 0, 0, canvas.width, canvas.height);
    } catch (e) {
      debugPrint("Error capturing video frame: $e");
      return;
    }
    
    // Convert canvas to base64
    final base64Image = canvas.toDataURL('image/jpeg').split(',')[1];
    
    setState(() {
      predictedLabel = 'Processing...';
    });
    
    try {
      // Send the image to the FastAPI backend
      final response = await http.post(
        Uri.parse('$apiEndpoint/predict-base64'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final letter = data['letter'];
        final confidence = data['confidence'];

        setState(() {
          predictedLabel = '$letter (${(confidence * 100).toStringAsFixed(2)}%)';
          errorMessage = '';
          _checkUserInput(letter);
        });
      } else {
        setState(() {
          predictedLabel = 'Error';
          errorMessage = "API Error: ${response.statusCode}";
        });
        debugPrint("❌ API Error: ${response.statusCode} - ${response.body}");
      }
    } on TimeoutException {
      setState(() {
        predictedLabel = 'Timeout';
        errorMessage = "API request timed out";
      });
      debugPrint("❌ API request timed out");
    } catch (e) {
      setState(() {
        predictedLabel = 'Error';
        errorMessage = "Connection error";
      });
      debugPrint("❌ API Connection Error: $e");
    }
  }

  void _checkUserInput(String recognizedLetter) {
    if (recognizedLetter.isEmpty || currentLetterIndex >= targetWord.length) {
      return;
    }

    setState(() {
      if (recognizedLetter.toLowerCase() == targetWord[currentLetterIndex]) {
        correctLetters[currentLetterIndex] = true;
        currentLetterIndex++; // Move to next letter
        
        // Check if the word is complete
        if (currentLetterIndex >= targetWord.length) {
          _predictionTimer?.cancel(); // Stop predictions when word is complete
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Congratulations! You spelled the word correctly!'),
              backgroundColor: Colors.green,
            ),
          );
        }
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
          color = Colors.green; // Correctly spelled letters
        } else if (index == currentLetterIndex) {
          color = Colors.blue; // Current letter to spell
        } else {
          color = Colors.grey; // Upcoming letters
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

  Widget _buildInstructionCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Instructions:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '1. Position your hand in the camera view',
              style: TextStyle(fontSize: 16),
            ),
            Text(
              '2. Form the ASL sign for the highlighted letter',
              style: TextStyle(fontSize: 16),
            ),
            Text(
              '3. Hold the sign steady for a moment',
              style: TextStyle(fontSize: 16),
            ),
            Text(
              '4. Continue until you spell the entire word',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildErrorDisplay() {
    if (errorMessage.isEmpty) return SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('ASL Spelling Game'),
        actions: [
          // Model status indicator
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isModelReady ? Colors.green.withOpacity(0.2) : 
                    isConnectingToAPI ? Colors.orange.withOpacity(0.2) : 
                    Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                if (isConnectingToAPI) 
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                  )
                else
                  Icon(
                    isModelReady ? Icons.check_circle : Icons.warning,
                    size: 16,
                    color: isModelReady ? Colors.green : Colors.red,
                  ),
                SizedBox(width: 4),
                Text(
                  isModelReady ? "Model Ready" : 
                  isConnectingToAPI ? "Connecting..." : 
                  "Not Connected",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isModelReady ? Colors.green[800] : 
                          isConnectingToAPI ? Colors.orange[800] : 
                          Colors.red[800],
                  ),
                ),
              ],
            ),
          ),
          // Refresh button
          IconButton(
            icon: Icon(Icons.refresh),
            color: Colors.blue,
            onPressed: _checkModelStatus,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(
              'Spell the word:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildWordDisplay(),
            const SizedBox(height: 20),
            
            // Camera View
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isModelReady ? Colors.green : Colors.grey,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
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
                            Text("Initializing camera..."),
                          ],
                        ),
                      ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Prediction display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(
                'Current prediction: $predictedLabel',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ),
            
            // Error message if any
            _buildErrorDisplay(),
            
            // Instructions
            _buildInstructionCard(),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _captureFrameAndPredict,
        tooltip: 'Capture and Predict',
        child: Icon(Icons.camera),
      ),
    );
  }
}