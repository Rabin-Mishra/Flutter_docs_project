import 'dart:convert';
import 'package:universal_html/html.dart' as html;
import 'package:dart_quill_delta/dart_quill_delta.dart' as quill;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ExportService {
  // ─── PLAIN TEXT EXPORTER ───────────────────────────────────────────────────
  static void downloadAsTXT(String title, quill.Delta delta) {
    final buffer = StringBuffer();
    for (final op in delta.toJson()) {
      if (op.containsKey('insert')) {
        final insertVal = op['insert'];
        if (insertVal is String) {
          buffer.write(insertVal);
        }
      }
    }
    
    final text = buffer.toString();
    final bytes = utf8.encode(text);
    final blob = html.Blob([bytes], 'text/plain;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    
    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..style.display = 'none'
      ..download = '${title.isEmpty ? "Untitled" : title}.txt';
      
    html.document.body!.children.add(anchor);
    anchor.click();
    html.document.body!.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
  }

  // ─── HIGH-FIDELITY PDF EXPORTER ────────────────────────────────────────────
  static Future<void> downloadAsPDF(String title, quill.Delta delta) async {
    final pdf = pw.Document();

    // Parse Delta into lines / blocks with their styles
    final List<_DeltaLine> lines = _parseDeltaToLines(delta);

    // Build PDF pages
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return lines.map((line) {
            final pw.TextAlign align = _getPdfAlignment(line.align);

            // 1. Render Headers
            if (line.headerLevel != null) {
              final double fontSize = line.headerLevel == 1 
                  ? 24 
                  : (line.headerLevel == 2 ? 18 : 14);
              final pw.FontWeight weight = pw.FontWeight.bold;
              final double topMargin = line.headerLevel == 1 
                  ? 16 
                  : (line.headerLevel == 2 ? 12 : 8);

              return pw.Container(
                margin: pw.EdgeInsets.only(top: topMargin, bottom: 6),
                alignment: line.align == 'center' 
                    ? pw.Alignment.center 
                    : (line.align == 'right' ? pw.Alignment.centerRight : pw.Alignment.centerLeft),
                child: pw.RichText(
                  textAlign: align,
                  text: pw.TextSpan(
                    children: line.runs.map((run) => _buildPdfSpan(run, baseFontSize: fontSize, defaultWeight: weight)).toList(),
                  ),
                ),
              );
            }

            // 2. Render List Items
            if (line.listType != null) {
              final isBullet = line.listType == 'bullet';
              return pw.Container(
                margin: const pw.EdgeInsets.only(left: 18, top: 3, bottom: 3),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      isBullet ? '  •   ' : '  1.  ', 
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)
                    ),
                    pw.Expanded(
                      child: pw.RichText(
                        textAlign: align,
                        text: pw.TextSpan(
                          children: line.runs.map((run) => _buildPdfSpan(run)).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // 3. Render Normal Paragraphs
            return pw.Container(
              margin: const pw.EdgeInsets.only(top: 4, bottom: 4),
              child: pw.RichText(
                textAlign: align,
                text: pw.TextSpan(
                  children: line.runs.map((run) => _buildPdfSpan(run)).toList(),
                ),
              ),
            );
          }).toList();
        },
      ),
    );

    // Save and download the PDF
    final bytes = await pdf.save();
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..style.display = 'none'
      ..download = '${title.isEmpty ? "Untitled" : title}.pdf';

    html.document.body!.children.add(anchor);
    anchor.click();
    html.document.body!.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
  }

  // ─── HELPERS ───────────────────────────────────────────────────────────────
  static pw.TextSpan _buildPdfSpan(_TextRun run, {double baseFontSize = 11, pw.FontWeight? defaultWeight}) {
    final bool isBold = run.attributes['bold'] == true;
    final bool isItalic = run.attributes['italic'] == true;
    final bool isUnderline = run.attributes['underline'] == true;

    final pw.FontWeight weight = isBold 
        ? pw.FontWeight.bold 
        : (defaultWeight ?? pw.FontWeight.normal);

    final pw.FontStyle style = isItalic 
        ? pw.FontStyle.italic 
        : pw.FontStyle.normal;

    final pw.TextDecoration decoration = isUnderline 
        ? pw.TextDecoration.underline 
        : pw.TextDecoration.none;

    return pw.TextSpan(
      text: run.text,
      style: pw.TextStyle(
        fontSize: baseFontSize,
        fontWeight: weight,
        fontStyle: style,
        decoration: decoration,
        color: PdfColors.black,
      ),
    );
  }

  static pw.TextAlign _getPdfAlignment(String? align) {
    if (align == 'center') return pw.TextAlign.center;
    if (align == 'right') return pw.TextAlign.right;
    if (align == 'justify') return pw.TextAlign.justify;
    return pw.TextAlign.left;
  }

  // Parses Delta JSON operations array into logical lines with custom attributes
  static List<_DeltaLine> _parseDeltaToLines(quill.Delta delta) {
    final List<_DeltaLine> lines = [];
    List<_TextRun> currentRuns = [];

    for (final op in delta.toJson()) {
      if (!op.containsKey('insert')) continue;
      final insertVal = op['insert'];
      final attributes = Map<String, dynamic>.from(op['attributes'] ?? {});

      if (insertVal is String) {
        final List<String> segments = insertVal.split('\n');

        for (int i = 0; i < segments.length; i++) {
          final text = segments[i];

          if (text.isNotEmpty) {
            currentRuns.add(_TextRun(text, attributes));
          }

          // If we hit a newline segment boundary, compile the line
          if (i < segments.length - 1) {
            // Check if the current line ending has line attributes in this or subsequent inserts
            final String? listType = attributes['list'];
            final int? headerLevel = attributes['header'];
            final String? align = attributes['align'];

            lines.add(_DeltaLine(
              List.from(currentRuns),
              listType: listType,
              headerLevel: headerLevel,
              align: align,
            ));
            currentRuns.clear();
          }
        }
      }
    }

    // Add remaining runs if any
    if (currentRuns.isNotEmpty) {
      lines.add(_DeltaLine(List.from(currentRuns)));
    }

    return lines;
  }
}

class _TextRun {
  final String text;
  final Map<String, dynamic> attributes;
  _TextRun(this.text, this.attributes);
}

class _DeltaLine {
  final List<_TextRun> runs;
  final String? listType; // bullet, ordered
  final int? headerLevel; // 1, 2, 3
  final String? align;    // center, right, justify
  _DeltaLine(this.runs, {this.listType, this.headerLevel, this.align});
}
