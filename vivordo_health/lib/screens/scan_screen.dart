import 'dart:async';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../src/utils/ppg_algorithm.dart';

enum ScanState { initializing, idle, scanning, processing, success, error }

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _cameraController;
  ScanState _scanState = ScanState.initializing;
  
  final List<double> _redValues = [];
  bool _isProcessingFrame = false;
  
  DateTime? _scanStartTime;
  Timer? _scanTimer;
  final int _scanDurationSeconds = 15;
  double _progress = 0.0;
  double _finalBpm = 0.0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();

      // Filter to rear-facing cameras only.
      final backCameras = cameras
          .where((c) => c.lensDirection == CameraLensDirection.back)
          .toList();

      if (backCameras.isEmpty) {
        setState(() => _scanState = ScanState.error);
        return;
      }

      // Debug: logs each back camera's index and name to the console.
      // Remove this once the correct camera is confirmed.
      for (int i = 0; i < backCameras.length; i++) {
        debugPrint('[PPG] backCameras[$i] name: ${backCameras[i].name}');
      }

      // Always use the first back camera (wide-angle lens, index 0).
      // The wide-angle lens is the only rear camera that supports torch
      // mode on iOS. The ultrawide and telephoto lenses will crash with
      // an AVFoundation abort if you try to enable the torch on them.
      final selectedCamera = backCameras.first;

      // Low resolution for faster processing
      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888, // Standard iOS format
      );

      await _cameraController!.initialize();
      try {
        await _cameraController!.setFlashMode(FlashMode.torch);
      } catch (e) {
        debugPrint('[PPG] Could not enable torch: $e');
      }
      
      setState(() => _scanState = ScanState.idle);
      _startImageStream();
    } catch (e) {
      setState(() => _scanState = ScanState.error);
    }
  }

  void _startImageStream() {
    _cameraController?.startImageStream((CameraImage image) {
      if (_isProcessingFrame) return;
      _isProcessingFrame = true;

      try {
        double redMean = _extractAverageRed(image);
        
        if (redMean > 120) {
          if (_scanState == ScanState.idle) {
             _startScan();
          }
          if (_scanState == ScanState.scanning) {
            _redValues.add(redMean);
          }
        } else {
          if (_scanState == ScanState.scanning) {
            _pauseScan();
          }
        }
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  double _extractAverageRed(CameraImage image) {
    if (image.planes.isEmpty) return 0.0;
    
    // For iOS BGRA8888, red is at index 2 of 4-byte chunk
    final bytes = image.planes[0].bytes;
    int redThresholdIndex = 2;

    double redSum = 0;
    int pixelCount = 0;
    
    for (int i = redThresholdIndex; i < bytes.length; i += 400) {
      redSum += bytes[i];
      pixelCount++;
    }
    
    return pixelCount == 0 ? 0 : redSum / pixelCount;
  }

  void _startScan() {
    if (!mounted) return;
    setState(() {
      _scanState = ScanState.scanning;
      _redValues.clear();
      _scanStartTime = DateTime.now();
      _progress = 0.0;
    });

    _scanTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _scanState != ScanState.scanning) {
        timer.cancel();
        return;
      }
      
      final elapsed = DateTime.now().difference(_scanStartTime!).inMilliseconds;
      setState(() {
        _progress = elapsed / (_scanDurationSeconds * 1000);
      });

      if (elapsed >= _scanDurationSeconds * 1000) {
        timer.cancel();
        _completeScan();
      }
    });
  }

  void _pauseScan() {
    if (!mounted) return;
    _scanTimer?.cancel();
    setState(() {
      _scanState = ScanState.idle;
      _progress = 0.0;
    });
  }

  Future<void> _completeScan() async {
    if (!mounted) return;
    setState(() => _scanState = ScanState.processing);
    await _cameraController?.stopImageStream();
    await _cameraController?.setFlashMode(FlashMode.off);

    final durationSecs = DateTime.now().difference(_scanStartTime!).inMilliseconds / 1000.0;
    
    final bpmResult = PpgAlgorithm.calculateBPM(_redValues, durationSecs);
    
    if (bpmResult > 0) {
      await _saveToFirestore(bpmResult.round());
      if (mounted) {
        setState(() {
          _finalBpm = bpmResult;
          _scanState = ScanState.success;
        });
      }
    } else {
      if (mounted) {
        setState(() => _scanState = ScanState.error);
      }
    }
  }

  Future<void> _saveToFirestore(int bpm) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('heart_rate_scans').add({
          'userId': user.uid,
          'bpm': bpm,
          'timestamp': FieldValue.serverTimestamp(),
          'durationSeconds': _scanDurationSeconds,
          'source': 'camera_ppg',
        });
      }
    } catch (e) {
      debugPrint('Failed to save to Firestore: $e');
    }
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _cameraController?.setFlashMode(FlashMode.off);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isScanningActive = _scanState == ScanState.scanning;
    bool isSuccess = _scanState == ScanState.success;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFAFF),
      appBar: AppBar(
        title: const Text('Heart Rate Scan', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: const Color(0xFF7B6EF6),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            Text(
              isSuccess ? 'Scan Complete!' : 'Place your finger over the rear camera lens & flash.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: Color(0xFF2D3142), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 40),
            
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black12,
                  border: Border.all(
                    color: isScanningActive ? const Color(0xFF4ADE80) : const Color(0xFF9CA3AF),
                    width: 6,
                  ),
                  boxShadow: isScanningActive ? [
                    BoxShadow(color: const Color(0xFF4ADE80).withOpacity(0.4), blurRadius: 40, spreadRadius: 10)
                  ] : [],
                ),
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_cameraController != null && _cameraController!.value.isInitialized)
                        Transform.scale(
                          scale: 1.5,
                          child: Center(
                            child: CameraPreview(_cameraController!),
                          ),
                        ),
                      if (isSuccess)
                        Container(color: const Color(0xFF7B6EF6)),
                      
                      if (isScanningActive)
                         Align(
                           alignment: Alignment.bottomCenter,
                           child: Container(
                             color: Colors.red.withOpacity(0.3),
                             height: 250 * (1 - _progress),
                           ),
                         ),
                         
                       if (_scanState == ScanState.processing)
                         const Center(child: CircularProgressIndicator(color: Colors.white)),
                         
                       if (isSuccess)
                         Center(
                           child: Column(
                             mainAxisSize: MainAxisSize.min,
                             children: [
                               const Text("BPM", style: TextStyle(color: Colors.white70, fontSize: 16)),
                               Text(
                                 _finalBpm.round().toString(), 
                                 style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w800)
                               ),
                             ],
                           )
                         )
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 40),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey.shade200,
                color: const Color(0xFF7B6EF6),
                minHeight: 12,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            
            const Spacer(),
            
            if (_scanState == ScanState.idle)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  "Waiting for finger...",
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 16),
                ),
              ),
              
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
