import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const CropPredictionApp());
}

class CropPredictionApp extends StatelessWidget {
  const CropPredictionApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crop Prediction',
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const CropPredictionScreen(),
    );
  }
}

class SensorData {
  final DateTime timestamp;
  final double temperature;
  final double humidity;

  SensorData({
    required this.timestamp,
    required this.temperature,
    required this.humidity,
  });

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      timestamp: DateTime.parse(json['timestamp']),
      temperature: json['temperature'].toDouble(),
      humidity: json['humidity'].toDouble(),
    );
  }
}

class PredictionResult {
  final String crop;
  final double confidence;

  PredictionResult({
    required this.crop,
    required this.confidence,
  });

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    return PredictionResult(
      crop: json['predicted_crop'],
      confidence: json['confidence'].toDouble(),
    );
  }
}

class CropPredictionScreen extends StatefulWidget {
  const CropPredictionScreen({Key? key}) : super(key: key);

  @override
  _CropPredictionScreenState createState() => _CropPredictionScreenState();
}

class _CropPredictionScreenState extends State<CropPredictionScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _temperatureController = TextEditingController();
  final TextEditingController _humidityController = TextEditingController();
  
  Timer? _timer;
  SensorData? _latestSensorData;
  PredictionResult? _prediction;
  bool _isLoading = false;
  bool _isAutoMode = false;

  @override
  void initState() {
    super.initState();
    _startAutoUpdate();
  }

  void _startAutoUpdate() {
    _timer?.cancel();
    if (_isAutoMode) {
      _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
        _fetchSensorData();
      });
      _fetchSensorData(); // Fetch immediately when switching to auto mode
    }
  }

  Future<void> _fetchSensorData() async {
    try {
      setState(() => _isLoading = true);
      
      final response = await http.get(
        Uri.parse('http://localhost:8000/sensor-data'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _latestSensorData = SensorData.fromJson(data['latest_reading']);
          _prediction = PredictionResult.fromJson(data['predictions']);
        });
      } else {
        throw Exception('Failed to fetch sensor data');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _predictCrop() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('http://localhost:8000/predict'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'temperature': double.parse(_temperatureController.text),
          'humidity': double.parse(_humidityController.text),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _prediction = PredictionResult.fromJson(data);
        });
      } else {
        throw Exception('Failed to predict crop');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crop Prediction'),
        actions: [
          Switch(
            value: _isAutoMode,
            onChanged: (value) {
              setState(() {
                _isAutoMode = value;
                _startAutoUpdate();
              });
            },
          ),
          const Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Text('Auto Mode'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isAutoMode) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sensor Data',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (_latestSensorData != null) ...[
                        Text('Temperature: ${_latestSensorData!.temperature.toStringAsFixed(1)}°C'),
                        Text('Humidity: ${_latestSensorData!.humidity.toStringAsFixed(1)}%'),
                        Text('Last Updated: ${_latestSensorData!.timestamp.toString()}'),
                      ] else
                        const Text('No sensor data available'),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _temperatureController,
                      decoration: const InputDecoration(
                        labelText: 'Temperature (°C)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter temperature';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Please enter a valid number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _humidityController,
                      decoration: const InputDecoration(
                        labelText: 'Humidity (%)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter humidity';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Please enter a valid number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _predictCrop,
                      child: _isLoading
                          ? const CircularProgressIndicator()
                          : const Text('Predict Crop'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (_prediction != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        'Recommended Crop:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _prediction!.crop,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Confidence: ${_prediction!.confidence.toStringAsFixed(2)}%',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _temperatureController.dispose();
    _humidityController.dispose();
    super.dispose();
  }
}