import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef PdfPasswordPrompt = Future<String?> Function();

class PdfStatementException implements Exception {
  const PdfStatementException(this.message, {this.isCancelled = false});

  final String message;
  final bool isCancelled;

  @override
  String toString() => message;
}

/// Renders PDF bank statements (including password-protected e-Statements)
/// 100% locally on Android via native PDFBox-Android (`MethodChannel`), so passwords
/// never leave the phone and both Gemini and 9Router can process them identically.
class PdfStatementRenderer {
  const PdfStatementRenderer._();

  static const MethodChannel _channel = MethodChannel('id.sihemat/pdf_renderer');
  static const int maxSupportedPages = 25;
  static const int targetWidthPx = 1440;

  static Future<List<Uint8List>> renderPdfToJpegs({
    required Uint8List pdfBytes,
    required String fileName,
    PdfPasswordPrompt? passwordProvider,
    void Function(int rendered, int total)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final safeName =
        'stmt_${DateTime.now().millisecondsSinceEpoch}_${p.basename(fileName).replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
    final tempFile = File(p.join(tempDir.path, safeName));
    await tempFile.writeAsBytes(pdfBytes, flush: true);

    try {
      var password = '';
      late int totalPages;

      // Try opening without password first; prompt user locally ONLY if PDF is encrypted.
      while (true) {
        try {
          final info = await _channel.invokeMapMethod<String, dynamic>(
            'inspectPdf',
            {'path': tempFile.path, 'password': password},
          );
          totalPages = (info?['pageCount'] as num?)?.toInt() ?? 0;
          break;
        } on PlatformException catch (e) {
          if (e.code == 'INVALID_PASSWORD') {
            if (passwordProvider == null) {
              throw const PdfStatementException(
                'File PDF dilindungi password.',
              );
            }
            final entered = await passwordProvider();
            if (entered == null) {
              throw const PdfStatementException(
                'Pembukaan PDF berpassword dibatalkan.',
                isCancelled: true,
              );
            }
            password = entered;
            continue;
          }
          throw PdfStatementException(
            e.message ?? 'File PDF tidak dapat dibuka.',
          );
        } on MissingPluginException {
          throw const PdfStatementException(
            'Pembaca PDF hanya didukung di perangkat Android.',
          );
        }
      }

      if (totalPages <= 0) {
        throw const PdfStatementException(
          'File PDF tidak memiliki halaman yang dapat dibaca.',
        );
      }

      final pageCount =
          totalPages > maxSupportedPages ? maxSupportedPages : totalPages;
      final jpegs = <Uint8List>[];

      for (var i = 0; i < pageCount; i++) {
        onProgress?.call(i + 1, pageCount);
        final rendered = await _channel.invokeMethod<Uint8List>(
          'renderPage',
          {
            'path': tempFile.path,
            'password': password,
            'pageIndex': i,
            'dpi': 155,
          },
        );
        if (rendered == null || rendered.isEmpty) continue;
        final compressed = await compressStatementImage(rendered);
        jpegs.add(compressed);
      }

      if (jpegs.isEmpty) {
        throw const PdfStatementException(
          'Gagal merender halaman PDF menjadi gambar.',
        );
      }
      return jpegs;
    } on PdfStatementException {
      rethrow;
    } on PlatformException catch (e) {
      throw PdfStatementException(
        e.message ?? 'Gagal memproses file PDF.',
      );
    } catch (e) {
      throw PdfStatementException('File PDF tidak dapat dibuka: $e');
    } finally {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Compresses mobile-banking screenshots or rendered PDF pages into crisp JPEGs
  /// preserving small table digits cleanly for AI Vision.
  static Future<Uint8List> compressStatementImage(Uint8List rawBytes) async {
    try {
      return await FlutterImageCompress.compressWithList(
        rawBytes,
        minWidth: targetWidthPx,
        minHeight: targetWidthPx,
        quality: 85,
        format: CompressFormat.jpeg,
      );
    } catch (_) {
      return rawBytes;
    }
  }
}
