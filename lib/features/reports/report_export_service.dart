import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';

class ReportExportService {
  const ReportExportService();

  /// Generates RFC-4180 compliant CSV text for the given month's transactions.
  String buildCsvContent(
    List<TransactionWithDetails> items, {
    required String familyName,
    required DateTime month,
  }) {
    final buf = StringBuffer();
    buf.writeln(
      'Tanggal,Jenis,Kategori,Toko/Merchant,Dompet,Dompet Tujuan,Anggota,Visibilitas,Nominal (Rp),Catatan',
    );

    for (final item in items) {
      final tx = item.transaction;
      final dt =
          DateTime.fromMillisecondsSinceEpoch(tx.date, isUtc: true).toLocal();
      final row = [
        DateFormatter.formatShortDate(dt),
        _typeLabel(tx.type),
        item.category?.name ?? (tx.type == TransactionType.transfer ? 'Transfer' : ''),
        tx.merchant ?? '',
        item.wallet?.name ?? '',
        item.toWallet?.name ?? '',
        item.member?.name ?? '',
        tx.visibility == VisibilityScope.shared ? 'Keluarga' : 'Pribadi',
        tx.amount.toString(),
        tx.note ?? '',
      ].map(_escapeCsv).join(',');
      buf.writeln(row);
    }
    return buf.toString();
  }

  /// Generates a clean printable Indonesian monthly financial report PDF.
  Future<Uint8List> buildPdfBytes({
    required String familyName,
    required MonthlyReportData report,
    required List<TransactionWithDetails> transactions,
  }) async {
    final doc = pw.Document();
    final monthTitle = DateFormatter.formatMonthYear(report.month);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'SI-HEMAT',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#0E7C66'),
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Laporan Keuangan $familyName',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Text(
                monthTitle,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 12),

          // Summary Row
          pw.Row(
            children: [
              _pdfStatBox(
                'Total Pemasukan',
                CurrencyFormatter.formatIdr(report.summary.totalIncome),
                PdfColor.fromHex('#15803D'),
              ),
              pw.SizedBox(width: 8),
              _pdfStatBox(
                'Total Pengeluaran',
                CurrencyFormatter.formatIdr(report.summary.totalExpense),
                PdfColor.fromHex('#DC2626'),
              ),
              pw.SizedBox(width: 8),
              _pdfStatBox(
                'Selisih / Tabungan',
                CurrencyFormatter.formatIdr(report.summary.netCashflow),
                PdfColor.fromHex('#0E7C66'),
              ),
              pw.SizedBox(width: 8),
              _pdfStatBox(
                'Saving Rate',
                '${report.summary.savingRatePercent.toStringAsFixed(1)}%',
                PdfColors.blueGrey800,
              ),
            ],
          ),
          pw.SizedBox(height: 18),

          // Expense Breakdown by Category
          pw.Text(
            'Pengeluaran per Kategori',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (report.expenseByCategory.isEmpty)
            pw.Text(
              'Belum ada data pengeluaran pada periode ini.',
              style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 10),
            )
          else
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#0E7C66'),
              ),
              cellStyle: const pw.TextStyle(fontSize: 9.5),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 5,
              ),
              headers: ['Kategori', 'Jumlah Transaksi', 'Porsi', 'Total'],
              data: report.expenseByCategory
                  .map(
                    (c) => [
                      c.categoryName,
                      '${c.transactionCount}x',
                      '${c.percentage.toStringAsFixed(1)}%',
                      CurrencyFormatter.formatIdr(c.amount),
                    ],
                  )
                  .toList(),
            ),
          pw.SizedBox(height: 18),

          // Transaction List
          pw.Text(
            'Rincian Transaksi (${transactions.length})',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (transactions.isEmpty)
            pw.Text(
              'Belum ada transaksi pada periode ini.',
              style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 10),
            )
          else
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey800,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 4,
              ),
              headers: ['Tanggal', 'Jenis', 'Keterangan', 'Dompet', 'Nominal'],
              data: transactions.map((item) {
                final tx = item.transaction;
                final dt = DateTime.fromMillisecondsSinceEpoch(
                  tx.date,
                  isUtc: true,
                ).toLocal();
                final desc = tx.type == TransactionType.transfer
                    ? '${item.wallet?.name ?? ''} -> ${item.toWallet?.name ?? ''}'
                    : [
                        item.category?.name ?? '',
                        if (tx.merchant != null) tx.merchant!,
                      ].where((s) => s.isNotEmpty).join(' - ');
                return [
                  DateFormatter.formatShortDate(dt),
                  _typeLabel(tx.type),
                  desc,
                  item.wallet?.name ?? '-',
                  CurrencyFormatter.formatIdr(tx.amount),
                ];
              }).toList(),
            ),
        ],
      ),
    );

    return doc.save();
  }

  Future<File> exportCsvAndShare({
    required String familyName,
    required DateTime month,
    required List<TransactionWithDetails> transactions,
  }) async {
    final csv = buildCsvContent(
      transactions,
      familyName: familyName,
      month: month,
    );
    final dir = await getTemporaryDirectory();
    final key = DateFormatter.monthKey(month);
    final file = File(p.join(dir.path, 'si_hemat_laporan_$key.csv'));
    await file.writeAsString(csv);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Laporan Keuangan $familyName ($key)',
      ),
    );
    return file;
  }

  Future<File> exportPdfAndShare({
    required String familyName,
    required MonthlyReportData report,
    required List<TransactionWithDetails> transactions,
  }) async {
    final bytes = await buildPdfBytes(
      familyName: familyName,
      report: report,
      transactions: transactions,
    );
    final dir = await getTemporaryDirectory();
    final key = DateFormatter.monthKey(report.month);
    final file = File(p.join(dir.path, 'si_hemat_laporan_$key.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Laporan Keuangan PDF $familyName ($key)',
      ),
    );
    return file;
  }

  pw.Widget _pdfStatBox(String label, String value, PdfColor accent) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case TransactionType.income:
        return 'Pemasukan';
      case TransactionType.expense:
        return 'Pengeluaran';
      case TransactionType.transfer:
        return 'Transfer';
      default:
        return type;
    }
  }

  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
