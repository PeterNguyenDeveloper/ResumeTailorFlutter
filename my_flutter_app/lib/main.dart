import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mime/mime.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:htmltopdfwidgets/htmltopdfwidgets.dart' as html2pdf;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';

String GEMINI_API_KEY = "Insert your API key here";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resume Tailor AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(
            255,
            38,
            89,
            228,
          ), // Modern purple accent
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto', // Modern, clean font
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFF212121), // Dark grey for headings
          ),
          titleLarge: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Color(0xFF424242),
          ),
          bodyMedium: TextStyle(
            fontSize: 16,
            color: Color(0xFF757575), // Medium grey for body text
            height: 1.5,
          ),
          labelLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            backgroundColor: const Color(0xFF6750A4), // Primary purple
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontSize: 16),
            elevation: 3,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF6750A4)),
            ),
            foregroundColor: const Color(0xFF6750A4),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFBDBDBD)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6750A4), width: 2),
          ),
          labelStyle: const TextStyle(color: Color(0xFF757575)),
          hintStyle: const TextStyle(color: Color(0xFF9E9E9E)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFF212121),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: Color(0xFF424242)),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF6750A4),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF424242),
          contentTextStyle: TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE0E0E0),
          thickness: 1,
        ),
      ),
      home: const MyHomePage(title: 'Resume Tailor AI'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  PlatformFile? _selectedPDF;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _tailoredResume = '';
  bool _isLoading = false;
  bool _isCancelled = false;
  late final GenerativeModel _model;

  Future<void> _downloadAsPDF() async {
    final ByteData notoSansData = await rootBundle.load(
      'assets/fonts/NotoSans-Regular.ttf',
    );
    final pw.Font notoSans = pw.Font.ttf(notoSansData);

    final List<pw.Widget> markdownWidgets = await html2pdf.HTMLToPdf()
        .convertMarkdown(_tailoredResume);

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: notoSans, fontFallback: [notoSans]),
        build: (pw.Context context) => [...markdownWidgets],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  void initState() {
    super.initState();
    _model = GenerativeModel(model: 'gemini-2.0-flash', apiKey: GEMINI_API_KEY);
  }

  Future<void> pickPDF() async {
    setState(() {
      _selectedPDF = null;
      _tailoredResume = '';
    });
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() => _selectedPDF = result.files.single);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Selected: ${_selectedPDF!.name}')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No PDF file selected or file is empty.'),
          ),
        );
      }
    }
  }

  Future<void> _cancelStream() async {
    if (_isLoading) {
      print("Attempting to cancel stream...");
      setState(() {
        _isCancelled = true;
        _isLoading = false;
        _tailoredResume += "\n\n[Request Cancelled by User]";
      });
      print("Cancellation requested.");
    }
  }

  Future<void> streamTailorResume() async {
    if (_selectedPDF == null || _selectedPDF!.bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a PDF file first.')),
        );
      }
      return;
    }
    if (_textController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please paste the job description.')),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _isCancelled = false;
      _tailoredResume = '';
    });

    try {
      final pdfBytes = _selectedPDF!.bytes!;
      final mimeType = lookupMimeType(
        _selectedPDF!.name,
        headerBytes:
            pdfBytes.length > 1024 ? pdfBytes.sublist(0, 1024) : pdfBytes,
      );

      if (mimeType != 'application/pdf') {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _tailoredResume =
                'Error: Invalid file type detected ($mimeType). Only PDF is supported.';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Invalid file type: ${mimeType ?? 'unknown'}. Please select a PDF.',
              ),
            ),
          );
        }
        return;
      }

      final String prompt =
          "Respond in Markdown format. Output the finished resume. "
          "Each line should be between 15 to 30 words. Don't omit anything from original resume. "
          "Style the resume in a professional manner. "
          "Tailor the resume to the following Job Description: ${_textController.text}";

      final pdfPart = DataPart(mimeType!, pdfBytes);
      final textPart = TextPart(prompt);

      final content = [
        Content.multi([textPart, pdfPart]),
      ];

      final Stream<GenerateContentResponse> responseStream = _model
          .generateContentStream(content);

      await for (final chunk in responseStream) {
        if (_isCancelled) {
          print("Stream processing stopped due to cancellation.");
          break;
        }
        final textChunk = chunk.text;
        if (textChunk != null && mounted) {
          setState(() {
            _tailoredResume += textChunk;
            if (_tailoredResume.startsWith('```markdown')) {
              _tailoredResume =
                  _tailoredResume.substring('```markdown'.length).trim();
            }
            if (_tailoredResume.length > 5 && _tailoredResume.endsWith('```')) {
              _tailoredResume =
                  _tailoredResume
                      .substring(0, _tailoredResume.length - 3)
                      .trim();
            }
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients &&
                _scrollController.position.maxScrollExtent > 0) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });
        }
        final finishReason = chunk.candidates.firstOrNull?.finishReason;
        if (finishReason != null &&
            finishReason != FinishReason.stop &&
            finishReason != FinishReason.unspecified) {
          print("Stream stopped by API: $finishReason");
          if (mounted) {
            setState(() {
              _tailoredResume += '\n[API Stop Reason: $finishReason]';
            });
          }
          break;
        }
      }
      if (!_isCancelled && mounted) {
        print("Stream finished normally.");
      }
    } catch (e, stackTrace) {
      print('Error generating content: $e\n$stackTrace');
      if (mounted) {
        setState(() {
          _tailoredResume += '\n\n[Error: ${e.toString()}]';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An error occurred: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_isLoading)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Cancel',
              onPressed: _cancelStream,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ElevatedButton.icon(
              icon: const Icon(Icons.upload_file_outlined),
              onPressed: _isLoading ? null : pickPDF,
              label: const Text('Upload Resume (PDF)'),
            ),
            if (_selectedPDF != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Selected: ${_selectedPDF!.name}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            TextField(
              controller: _textController,
              maxLines: 6,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                labelText: 'Job Description / Context',
                hintText: 'Paste the target job description here...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.auto_awesome),
              onPressed:
                  (_selectedPDF == null || _isLoading)
                      ? null
                      : streamTailorResume,
              label: Text(
                _isLoading ? 'Tailoring Resume...' : 'Tailor My Resume',
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: LinearProgressIndicator(),
              ),
            const SizedBox(height: 24),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: MarkdownBody(
                    data:
                        _tailoredResume.isEmpty && !_isLoading && !_isCancelled
                            ? '*Tailored resume will appear here...*'
                            : _tailoredResume,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(
                      Theme.of(context),
                    ).copyWith(p: Theme.of(context).textTheme.bodyMedium),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download as PDF'),
              onPressed: _tailoredResume.trim().isEmpty ? null : _downloadAsPDF,
            ),
          ],
        ),
      ),
    );
  }
}
