import 'dart:convert';

import 'package:dio/dio.dart';

class GeminiException implements Exception {
  const GeminiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class GeminiModels {
  GeminiModels._();

  static const String hydrogen = 'gemini-4-hydrogen';
  static const String flashLite = 'gemini-3.5-flash-lite';

  static const List<({String id, String label, String subtitle})> available = [
    (
      id: hydrogen,
      label: 'Gemini 4 Hydrogen — GRATIS (Free Tier)',
      subtitle:
          'Gratis di Google AI Studio tanpa kartu kredit. Akurat untuk scan struk, chat transaksi, & evaluasi laporan.',
    ),
    (
      id: flashLite,
      label: 'Gemini 3.5 Flash-Lite — GRATIS (Hemat Kuota)',
      subtitle:
          'Gratis & super cepat untuk pemakaian harian frekuensi tinggi.',
    ),
  ];
}

/// Minimal, spec-compliant REST client for Gemini Interactions API (`v1/interactions`).
/// Uses `store: false` by default so family financial prompts are not retained server-side.
class GeminiInteractionsClient {
  GeminiInteractionsClient({
    Dio? dio,
    this.endpoint = 'https://generativelanguage.googleapis.com/v1/interactions',
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 120),
                sendTimeout: const Duration(seconds: 45),
              ),
            );

  final Dio _dio;
  final String endpoint;

  /// Calls `POST /v1/interactions` and returns the extracted text output.
  Future<String> createInteraction({
    required String apiKey,
    required String model,
    required Object input, // String or List<Map<String, dynamic>>
    String? systemInstruction,
    Map<String, dynamic>? jsonSchema,
    int? maxOutputTokens,
    bool store = false,
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw const GeminiException(
        'Gemini API Key belum diatur. Buka Pengaturan AI untuk memasukkan API Key dari Google AI Studio.',
      );
    }

    final body = <String, dynamic>{
      'model': model,
      'input': input,
      'store': store,
      if (systemInstruction != null && systemInstruction.trim().isNotEmpty)
        'system_instruction': systemInstruction,
      if (jsonSchema != null)
        'response_format': {
          'type': 'text',
          'mime_type': 'application/json',
          'schema': jsonSchema,
        },
      if (maxOutputTokens != null)
        'generation_config': {
          'max_output_tokens': maxOutputTokens,
        },
    };

    try {
      final response = await _dio.post<dynamic>(
        endpoint,
        data: jsonEncode(body),
        options: Options(
          headers: {
            'x-goog-api-key': trimmedKey,
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data;
      final Map<String, dynamic> map;
      if (data is Map<String, dynamic>) {
        map = data;
      } else if (data is String) {
        map = jsonDecode(data) as Map<String, dynamic>;
      } else {
        throw const GeminiException('Format respons Gemini API tidak dikenali.');
      }

      final text = extractOutputText(map);
      if (text == null || text.trim().isEmpty) {
        throw const GeminiException(
          'Gemini tidak mengembalikan teks jawaban. Coba ulangi permintaan Anda.',
        );
      }
      return text;
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Extracts trailing text output from Interactions API `steps` array,
  /// matching the official SDK's `interaction.output_text` semantics.
  static String? extractOutputText(Map<String, dynamic> json) {
    final directOutput = json['output_text'];
    if (directOutput is String && directOutput.isNotEmpty) {
      return directOutput;
    }

    final steps = json['steps'];
    if (steps is List) {
      final trailingTexts = <String>[];
      for (var i = steps.length - 1; i >= 0; i--) {
        final step = steps[i];
        if (step is! Map) continue;
        if (step['type'] != 'model_output') {
          if (trailingTexts.isNotEmpty) break;
          continue;
        }
        final content = step['content'];
        if (content is List) {
          final stepTexts = <String>[];
          for (final part in content) {
            if (part is Map &&
                part['type'] == 'text' &&
                part['text'] is String) {
              stepTexts.add(part['text'] as String);
            }
          }
          if (stepTexts.isNotEmpty) {
            trailingTexts.insert(0, stepTexts.join(''));
          }
        }
      }
      if (trailingTexts.isNotEmpty) {
        return trailingTexts.join('\n');
      }
    }

    return null;
  }

  Future<String> testConnection({
    required String apiKey,
    required String model,
  }) {
    return createInteraction(
      apiKey: apiKey,
      model: model,
      input: 'Balas singkat tepat 2 kata: Koneksi berhasil.',
      maxOutputTokens: 32,
      store: false,
    );
  }

  GeminiException _mapDioError(DioException e) {
    final code = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const GeminiException(
        'Tidak dapat terhubung ke internet. Fitur manual, laporan, dan sync Wi-Fi tetap bisa digunakan offline.',
      );
    }
    if (e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return const GeminiException(
        'Permintaan ke Gemini memakan waktu terlalu lama. Silakan coba lagi.',
      );
    }
    if (code == 400) {
      return GeminiException(
        'Permintaan ditolak Gemini (400). Periksa format API Key atau pilihan model.',
        statusCode: code,
      );
    }
    if (code == 401 || code == 403) {
      return GeminiException(
        'Gemini API Key tidak valid atau tidak memiliki izin (HTTP $code). Periksa kembali di Google AI Studio.',
        statusCode: code,
      );
    }
    if (code == 429) {
      return const GeminiException(
        'Kuota request Gemini API sedang penuh (429). Tunggu beberapa saat atau ganti ke model Gemini 3.5 Flash-Lite di Pengaturan AI.',
        statusCode: 429,
      );
    }
    return GeminiException(
      'Terjadi kesalahan saat menghubungi Gemini API${code != null ? ' (HTTP $code)' : ''}.',
      statusCode: code,
    );
  }
}
