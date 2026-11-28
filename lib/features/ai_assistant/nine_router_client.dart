import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:si_hemat/features/ai_assistant/gemini_client.dart';

/// OpenAI-compatible REST client for **9Router** (and compatible local/remote
/// OpenAI-format gateways), supporting text chat, JSON structured parsing,
/// multimodal receipt vision (`image_url` data URI), and live `/models` listing.
class NineRouterClient {
  NineRouterClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 120),
                sendTimeout: const Duration(seconds: 45),
              ),
            );

  final Dio _dio;

  static const String defaultBaseUrl = 'http://192.168.1.10:20128/v1';

  /// Normalizes user-entered base URLs such as:
  /// - `http://192.168.1.5:20128` -> `http://192.168.1.5:20128/v1`
  /// - `http://192.168.1.5:20128/v1/` -> `http://192.168.1.5:20128/v1`
  /// - `https://router.example.com/v1/chat/completions` -> `https://router.example.com/v1`
  static String normalizeBaseUrl(String raw) {
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return '';
    if (!cleaned.startsWith('http://') && !cleaned.startsWith('https://')) {
      cleaned = 'http://$cleaned';
    }
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    if (cleaned.endsWith('/chat/completions')) {
      cleaned = cleaned.substring(0, cleaned.length - '/chat/completions'.length);
    } else if (cleaned.endsWith('/models')) {
      cleaned = cleaned.substring(0, cleaned.length - '/models'.length);
    }
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    if (!cleaned.endsWith('/v1')) {
      cleaned = '$cleaned/v1';
    }
    return cleaned;
  }

  /// Calls `POST <baseUrl>/chat/completions` and returns extracted assistant text.
  Future<String> createChatCompletion({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String userText,
    String? systemInstruction,
    Uint8List? imageBytes,
    String imageMimeType = 'image/jpeg',
    Map<String, dynamic>? jsonSchema,
    int? maxTokens,
  }) async {
    final normalizedBase = normalizeBaseUrl(baseUrl);
    if (normalizedBase.isEmpty) {
      throw const GeminiException(
        'Base URL 9Router belum diisi. Buka Pengaturan AI untuk memasukkan alamat server 9Router Anda (contoh: http://192.168.1.10:20128/v1).',
      );
    }
    final trimmedModel = model.trim();
    if (trimmedModel.isEmpty) {
      throw const GeminiException(
        'Nama model atau Combo 9Router belum diisi. Pilih atau ketik nama model di Pengaturan AI.',
      );
    }

    var effectiveSystem = systemInstruction?.trim() ?? '';
    if (jsonSchema != null) {
      final schemaHint =
          'PENTING: Balas HANYA dengan 1 objek JSON valid (tanpa markdown, tanpa teks tambahan di luar JSON) yang mengikuti skema ini: ${jsonEncode(jsonSchema)}';
      effectiveSystem =
          effectiveSystem.isEmpty ? schemaHint : '$effectiveSystem\n\n$schemaHint';
    }

    final Object userContent;
    if (imageBytes != null) {
      final b64 = base64Encode(imageBytes);
      userContent = [
        {'type': 'text', 'text': userText},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:$imageMimeType;base64,$b64'},
        },
      ];
    } else {
      userContent = userText;
    }

    final messages = <Map<String, dynamic>>[
      if (effectiveSystem.isNotEmpty)
        {'role': 'system', 'content': effectiveSystem},
      {'role': 'user', 'content': userContent},
    ];

    final endpoint = '$normalizedBase/chat/completions';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
    };

    Future<String> send({required bool includeJsonResponseFormat}) async {
      final body = <String, dynamic>{
        'model': trimmedModel,
        'messages': messages,
        'stream': false,
        if (includeJsonResponseFormat)
          'response_format': {'type': 'json_object'},
        'max_tokens': ?maxTokens,
      };

      final response = await _dio.post<dynamic>(
        endpoint,
        data: jsonEncode(body),
        options: Options(headers: headers),
      );

      final map = _decodeResponseMap(response.data);
      final text = extractCompletionText(map);
      if (text == null || text.trim().isEmpty) {
        throw const GeminiException(
          '9Router tidak mengembalikan teks jawaban. Pastikan model/combo aktif dan coba lagi.',
        );
      }
      return text;
    }

    try {
      return await send(includeJsonResponseFormat: jsonSchema != null);
    } on DioException catch (e) {
      // Some upstream models behind 9Router reject `response_format: json_object`
      // with HTTP 400; retry cleanly relying on our strict JSON system prompt.
      if (jsonSchema != null && e.response?.statusCode == 400) {
        try {
          return await send(includeJsonResponseFormat: false);
        } on DioException catch (retryErr) {
          throw _mapDioError(retryErr, normalizedBase);
        }
      }
      throw _mapDioError(e, normalizedBase);
    }
  }

  /// Calls `GET <baseUrl>/models` to fetch active model & combo IDs from 9Router.
  Future<List<String>> listModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final normalizedBase = normalizeBaseUrl(baseUrl);
    if (normalizedBase.isEmpty) {
      throw const GeminiException('Masukkan Base URL 9Router terlebih dahulu.');
    }
    final endpoint = '$normalizedBase/models';
    final headers = <String, String>{
      if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
    };

    try {
      final response = await _dio.get<dynamic>(
        endpoint,
        options: Options(headers: headers),
      );
      final map = _decodeResponseMap(response.data);
      final rawData = map['data'];
      if (rawData is! List) return const [];
      final ids = <String>[];
      for (final item in rawData) {
        if (item is Map && item['id'] is String) {
          final id = (item['id'] as String).trim();
          if (id.isNotEmpty) ids.add(id);
        }
      }
      ids.sort();
      return ids;
    } on DioException catch (e) {
      throw _mapDioError(e, normalizedBase);
    }
  }

  Future<String> testConnection({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) {
    return createChatCompletion(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      userText: 'Balas singkat tepat 2 kata: Koneksi berhasil.',
      maxTokens: 32,
    );
  }

  /// Extracts assistant text from OpenAI-compatible `choices[0].message.content`,
  /// stripping optional `<think>...</think>` blocks emitted by reasoning models.
  static String? extractCompletionText(Map<String, dynamic> json) {
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map) {
          final content = message['content'];
          if (content is String) {
            return stripThinkBlocks(content);
          }
          if (content is List) {
            final parts = <String>[];
            for (final part in content) {
              if (part is Map && part['text'] is String) {
                parts.add(part['text'] as String);
              }
            }
            if (parts.isNotEmpty) {
              return stripThinkBlocks(parts.join('\n'));
            }
          }
        }
        if (first['text'] is String) {
          return stripThinkBlocks(first['text'] as String);
        }
      }
    }
    return null;
  }

  static String stripThinkBlocks(String raw) {
    return raw
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        .trim();
  }

  Map<String, dynamic> _decodeResponseMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    throw const GeminiException('Format respons server 9Router tidak dikenali.');
  }

  GeminiException _mapDioError(DioException e, String baseUrl) {
    final code = e.response?.statusCode;
    final usesLocalhost = baseUrl.contains('localhost') ||
        baseUrl.contains('127.0.0.1');

    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      if (usesLocalhost) {
        return const GeminiException(
          'Tidak dapat terhubung ke localhost dari HP. Ganti localhost dengan IP LAN PC/server Anda (mis. http://192.168.1.10:20128/v1) atau http://10.0.2.2:20128/v1 di emulator.',
        );
      }
      return GeminiException(
        'Tidak dapat terhubung ke server 9Router ($baseUrl). Pastikan 9Router menyala dan HP berada di jaringan yang bisa mengaksesnya.',
      );
    }
    if (e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return const GeminiException(
        'Permintaan ke 9Router memakan waktu terlalu lama. Coba model yang lebih cepat atau ulangi lagi.',
      );
    }
    if (code == 401 || code == 403) {
      return GeminiException(
        'API Key 9Router tidak valid atau ditolak (HTTP $code). Periksa kunci di dashboard 9Router Anda.',
        statusCode: code,
      );
    }
    if (code == 404) {
      return GeminiException(
        'Endpoint atau model tidak ditemukan di 9Router (HTTP 404). Cek Base URL (/v1) dan nama model/combo Anda.',
        statusCode: code,
      );
    }
    if (code == 429) {
      return const GeminiException(
        'Batas request provider di 9Router sedang penuh (HTTP 429). Coba gunakan Combo fallback di dashboard 9Router.',
        statusCode: 429,
      );
    }

    String detail = '';
    final respData = e.response?.data;
    if (respData is Map && respData['error'] is Map) {
      final msg = (respData['error'] as Map)['message'];
      if (msg is String && msg.isNotEmpty) {
        detail = ' — $msg';
      }
    }
    return GeminiException(
      'Gagal menghubungi 9Router${code != null ? ' (HTTP $code)' : ''}$detail',
      statusCode: code,
    );
  }
}
