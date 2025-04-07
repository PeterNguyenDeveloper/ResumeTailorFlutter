import 'dart:async'; // Keep for WidgetsBinding if needed, but not StreamSubscription
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart'; // Import the package
import 'package:mime/mime.dart';
import 'package:flutter_markdown/flutter_markdown.dart'; // Keep for Markdown if needed
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
      title: 'Resume Tailor (SDK Streaming)', // Updated title
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const MyHomePage(
        title: 'Gemini AI Resume Tailor (SDK Stream)',
      ), // Updated title
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
  bool _isCancelled = false; // Flag to signal cancellation

  // --- Initialize the Generative Model ---
  late final GenerativeModel _model;

  Future<void> _downloadAsPDF() async {
    // Load fonts
    final ByteData notoSansData = await rootBundle.load(
      'assets/fonts/NotoSans-Regular.ttf',
    );
    final pw.Font notoSans = pw.Font.ttf(notoSansData);

    // Convert Markdown string to PDF widgets
    final List<pw.Widget> markdownWidgets = await html2pdf.HTMLToPdf()
        .convertMarkdown(_tailoredResume);

    // Create a new PDF document
    final pdf = pw.Document();

    // Add content to the PDF with font and fallback
    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(
          base: notoSans,
          fontFallback: [
            notoSans,
          ], // Fallback for unsupported characters like bullets
        ),
        build:
            (pw.Context context) => [
              pw.Header(level: 0, child: pw.Text('Tailored Resume')),
              ...markdownWidgets,
            ],
      ),
    );

    // Let user print or download
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  void initState() {
    super.initState();
    // --- Initialize the Model ---
    _model = GenerativeModel(
      // Use the specific model supporting function calling
      model: 'gemini-2.0-flash', // Or your preferred model
      apiKey: GEMINI_API_KEY,
      // Optional: Add safety settings, generation config if needed
      // safetySettings: [ SafetySetting(...) ],
      // generationConfig: GenerationConfig( temperature: 0.7 ),
    );
  }

  // --- Pick PDF (Unchanged from original) ---
  Future<void> pickPDF() async {
    // No need to cancel stream here, cancellation logic is now simpler
    setState(() {
      _selectedPDF = null;
      _tailoredResume = '';
    });

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true, // Ensure bytes are loaded
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

  // --- Cancel Stream (Simplified) ---
  Future<void> _cancelStream() async {
    if (_isLoading) {
      print("Attempting to cancel stream...");
      setState(() {
        _isCancelled = true; // Signal the stream loop to stop
        _isLoading = false; // Update UI immediately
        _tailoredResume += "\n\n[Request Cancelled by User]";
      });
      print("Cancellation requested.");
    }
  }

  // --- ** Refactored streamTailorResume using google_generative_ai SDK ** ---
  Future<void> streamTailorResume() async {
    // --- Input Validation (Mostly Unchanged) ---
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

    // --- Reset state for new request ---
    setState(() {
      _isLoading = true;
      _isCancelled = false; // Reset cancellation flag
      _tailoredResume = ''; // Clear previous output
    });

    // --- Prepare Request Content using SDK Parts ---
    try {
      final pdfBytes = _selectedPDF!.bytes!;
      final mimeType = lookupMimeType(
        _selectedPDF!.name,
        headerBytes:
            pdfBytes.length > 1024
                ? pdfBytes.sublist(0, 1024)
                : pdfBytes, // Use header bytes for lookup
      );

      // Validate MIME type (important for the API)
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

      // Create DataPart for the PDF
      final pdfPart = DataPart(mimeType!, pdfBytes);
      // Create TextPart for the prompt
      final textPart = TextPart(prompt);

      // Combine parts into a Content object (for multimodal input)
      // The API expects a List<Content>
      final content = [
        Content.multi([textPart, pdfPart]),
      ];

      // --- Call the SDK's stream API ---
      final Stream<GenerateContentResponse> responseStream = _model
          .generateContentStream(content);

      // --- Process the stream ---
      await for (final chunk in responseStream) {
        // Check if cancellation was requested during the stream processing
        if (_isCancelled) {
          print("Stream processing stopped due to cancellation.");
          break; // Exit the loop
        }

        // Extract text from the chunk
        final textChunk = chunk.text;
        if (textChunk != null && mounted) {
          setState(() {
            _tailoredResume += textChunk; // Append text chunk
            // Remove ```markdown at the start
            if (_tailoredResume.startsWith('```markdown')) {
              _tailoredResume =
                  _tailoredResume.substring('```markdown'.length).trim();
            }
            // Remove ``` at the end if the length is greater than 20
            if (_tailoredResume.length > 5 && _tailoredResume.endsWith('```')) {
              _tailoredResume =
                  _tailoredResume
                      .substring(0, _tailoredResume.length - 3)
                      .trim();
            }
          });

          // Auto-scroll (simplified)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients &&
                _scrollController.position.maxScrollExtent > 0) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200), // Smooth scroll
                curve: Curves.easeOut,
              );
            }
          });
        }

        // Optional: Check for finish reason if needed
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
          break; // Stop processing if API signals an issue
        }
      }

      // If the loop finishes without being cancelled, mark loading as done
      if (!_isCancelled && mounted) {
        print("Stream finished normally.");
      }
    } catch (e, stackTrace) {
      // --- Handle SDK Errors ---
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
      // --- Ensure loading state is reset ---
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
    // No need to manually cancel SDK stream subscription or close http client here
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // --- BUILD METHOD REMAINS THE SAME ---
    // No changes needed in the UI structure itself.
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          if (_isLoading)
            IconButton(
              icon: const Icon(Icons.cancel),
              tooltip: 'Cancel Request', // Updated tooltip
              onPressed: _cancelStream, // Calls the simplified cancel logic
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: _isLoading ? null : pickPDF,
              label: const Text('1. Pick Resume PDF'),
            ),
            if (_selectedPDF != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Selected: ${_selectedPDF!.name}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              maxLines: 6,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '2. Paste Job Description / Context',
                hintText: 'Paste the target job description here...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.auto_awesome),
              onPressed:
                  (_selectedPDF == null || _isLoading)
                      ? null
                      : streamTailorResume, // Calls the refactored function
              label: Text(
                _isLoading ? 'Tailoring...' : '3. Tailor Resume (Stream)',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isLoading
                        ? Colors.grey
                        : Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: LinearProgressIndicator(),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                padding: const EdgeInsets.all(12.0),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: MarkdownBody(
                    data:
                        _tailoredResume.isEmpty && !_isLoading && !_isCancelled
                            ? '*Tailored resume will appear here...*' // Placeholder text (as Markdown italic)
                            : _tailoredResume, // The actual Markdown content from Gemini
                    selectable:
                        true, // Allows text selection like SelectableText
                    styleSheet: MarkdownStyleSheet.fromTheme(
                      Theme.of(context),
                    ).copyWith(
                      // Apply base text style similar to the previous SelectableText
                      p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 15,
                        height: 1.4,
                      ),
                      // You can customize other Markdown elements here if needed:
                      // h1: Theme.of(context).textTheme.headlineLarge,
                      // code: TextStyle(backgroundColor: Colors.grey[200], fontFamily: 'monospace'),
                      // blockquoteDecoration: BoxDecoration(...)
                    ),
                  ),
                ),
              ),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Download as PDF'),
              onPressed: _tailoredResume.trim().isEmpty ? null : _downloadAsPDF,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
