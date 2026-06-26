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
  Map<String, dynamic> predict(List<double> rawInputData) {
    // PENTING: model dilatih dengan transformasi log1p pada seluruh fitur
    // (lihat metadata.feature_transform di model_data.json). Input mentah
    // dari aplikasi (screen_time dalam jam, unlocks, notif) HARUS
    // ditransformasi dengan rumus yang sama sebelum dihitung, supaya
    // konsisten dengan skala mean/variance yang disimpan dari training.
    final List<double> inputData =
        rawInputData.map((x) => math.log(1 + x)).toList();

    List<double> scores = [];
    int bestClass = classes[0];
    double bestScore = -double.infinity;

    // Hitung skor log-posterior untuk tiap kelas (0=Aman, 1=Bahaya)
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
      scores.add(score);
      if (score > bestScore) {
        bestScore = score;
        bestClass = classes[i];
      }
    }
    // Normalisasi skor jadi probabilitas asli (softmax dengan log-sum-exp
    // agar stabil secara numerik, karena exp(score) bisa overflow/underflow).
    final maxScore = scores.reduce(math.max);
    final expScores = scores.map((s) => math.exp(s - maxScore)).toList();
    final sumExp = expScores.reduce((a, b) => a + b);
    final probabilities = expScores.map((e) => e / sumExp).toList();
    final addictionProb = probabilities[classes.indexOf(1)];
    return {
      'prediction': bestClass,
      'probability': addictionProb,
    };
  }
}