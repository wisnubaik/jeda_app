import 'dart:math';
import 'dart:convert';
import 'package:flutter/services.dart';

class NaiveBayesModel {
  List<double> classPrior = [];
  List<List<double>> theta = [];
  List<List<double>> variance = [];
  List<String> features = [];

  static NaiveBayesModel? _instance;

  static Future<NaiveBayesModel> getInstance() async {
    if (_instance == null) {
      _instance = NaiveBayesModel();
      await _instance!._loadModel();
    }
    return _instance!;
  }

  Future<void> _loadModel() async {
    final String jsonString =
        await rootBundle.loadString('assets/model_jeda.json');
    final Map<String, dynamic> json = jsonDecode(jsonString);

    classPrior = List<double>.from(json['class_prior']);
    theta = (json['theta'] as List)
        .map((row) => List<double>.from(row))
        .toList();
    variance = (json['var'] as List)
        .map((row) => List<double>.from(row))
        .toList();
    features = List<String>.from(json['features']);
  }

  // 0 = aman, 1 = bahaya
  int predict(Map<String, double> input) {
    List<double> logProbs = [];

    for (int c = 0; c < 2; c++) {
      double logProb = log(classPrior[c]);

      for (int f = 0; f < features.length; f++) {
        double x = input[features[f]] ?? 0.0;
        double mean = theta[c][f];
        double varVal = variance[c][f];
        double logLikelihood =
            -0.5 * log(2 * pi * varVal) - pow(x - mean, 2) / (2 * varVal);
        logProb += logLikelihood;
      }

      logProbs.add(logProb);
    }

    return logProbs[1] > logProbs[0] ? 1 : 0;
  }

  double getAddictionProbability(Map<String, double> input) {
    List<double> logProbs = [];

    for (int c = 0; c < 2; c++) {
      double logProb = log(classPrior[c]);

      for (int f = 0; f < features.length; f++) {
        double x = input[features[f]] ?? 0.0;
        double mean = theta[c][f];
        double varVal = variance[c][f];
        double logLikelihood =
            -0.5 * log(2 * pi * varVal) - pow(x - mean, 2) / (2 * varVal);
        logProb += logLikelihood;
      }

      logProbs.add(logProb);
    }

    double maxLog = logProbs.reduce(max);
    List<double> expProbs =
        logProbs.map((lp) => exp(lp - maxLog)).toList();
    double sumExp = expProbs.reduce((a, b) => a + b);

    return expProbs[1] / sumExp; // probabilitas kecanduan
  }
}