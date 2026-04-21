import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';

class NaiveBayesModel {
  final List<dynamic> classes;
  final List<dynamic> priors;
  final List<dynamic> means;
  final List<dynamic> variances;
  final List<dynamic> features;

  NaiveBayesModel({
    required this.classes,
    required this.priors,
    required this.means,
    required this.variances,
    required this.features,
  });

  // Load model dari file JSON assets
  static Future<NaiveBayesModel> getInstance() async {
    final String response = await rootBundle.loadString('assets/model/model_data.json');
    final data = json.decode(response);
    return NaiveBayesModel(
      classes: data['classes'],
      priors: data['priors'],
      means: data['means'],
      variances: data['variances'],
      features: data['features'],
    );
  }

  // Fungsi Prediksi Inti (Menerima List, Mengembalikan Map)
  Map<String, dynamic> predict(List<double> inputData) {
    double bestScore = -double.infinity;
    int bestClass = classes[0];
    
    // Hitung peluang untuk tiap kelas (0=Aman, 1=Bahaya)
    for (int i = 0; i < classes.length; i++) {
      double score = math.log(priors[i]);

      for (int j = 0; j < inputData.length; j++) {
        double x = inputData[j];
        double mean = means[i][j];
        double variance = variances[i][j] + 1e-9; 

        // Rumus Gaussian Naive Bayes Log-Likelihood
        double exponent = -math.pow(x - mean, 2) / (2 * variance);
        double logLikelihood = exponent - 0.5 * math.log(2 * math.pi * variance);
        score += logLikelihood;
      }

      if (score > bestScore) {
        bestScore = score;
        bestClass = classes[i];
      }
    }

    // Mengubah skor menjadi probabilitas sederhana (0.0 - 1.0) untuk UI
    double addictionProb = (bestClass == 1) ? 0.85 : 0.15; 

    return {
      'prediction': bestClass,
      'probability': addictionProb,
    };
  }
}