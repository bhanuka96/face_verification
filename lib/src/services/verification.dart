// lib/src/services/verification.dart
import 'dart:math';

double cosineSimilarity(List<double> a, List<double> b) {
  double dot = 0.0, na = 0.0, nb = 0.0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return dot / (sqrt(na) * sqrt(nb) + 1e-10);
}
