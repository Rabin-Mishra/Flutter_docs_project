import 'dart:async';
import 'dart:convert';

import 'package:docs_clone_flutter/colors.dart';
import 'package:docs_clone_flutter/common/widgets/loader.dart';
import 'package:docs_clone_flutter/models/document_model.dart';
import 'package:docs_clone_flutter/models/error_model.dart';
import 'package:docs_clone_flutter/repository/auth_repository.dart';
import 'package:docs_clone_flutter/repository/document_repository.dart';
import 'package:docs_clone_flutter/repository/socket_repository.dart';
import 'package:docs_clone_flutter/services/export_service.dart';
import 'package:docs_clone_flutter/services/rich_embed_service.dart';
import 'package:docs_clone_flutter/services/dictionary_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:dart_quill_delta/dart_quill_delta.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:routemaster/routemaster.dart';
import 'package:universal_html/html.dart' as html;

class DocumentScreen extends ConsumerStatefulWidget {
  final String id;
  const DocumentScreen({
    Key? key,
    required this.id,
  }) : super(key: key);

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends ConsumerState<DocumentScreen> {
  TextEditingController titleController = TextEditingController(text: 'Untitled Document');
  quill.QuillController? _controller;
  ErrorModel? errorModel;
  SocketRepository socketRepository = SocketRepository();
  String userPermission = 'viewer';
  List<dynamic> activeCollaborators = [];

  // Stage 10 State Variables
  bool showSidebar = false;
  bool sidebarLoading = false;
  String sidebarWord = '';
  DictionaryResult? dictionaryResult;
  final TextEditingController sidebarSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final token = ref.read(userProvider)!.token;
    socketRepository.connect(token);

    socketRepository.onPresenceUpdate((data) {
      if (data != null && data['users'] != null) {
        if (!mounted) return;
        setState(() {
          activeCollaborators = List.from(data['users']);
          activeCollaborators.removeWhere((collab) => collab['userId'] == ref.read(userProvider)!.uid);
        });
      }
    });

    // Register load listener BEFORE joining room to ensure no event is missed
    socketRepository.onDocumentLoaded((data) {
      if (!mounted) return;
      if (_controller != null) return; // Prevent double initialization

      userPermission = data['permission'] ?? 'viewer';

      final rawContent = List.from(data['content']);
      if (rawContent.isNotEmpty) {
        // Safe check for trailing newline character to satisfy Quill's loadDocument constraints
        final lastOp = rawContent.last;
        if (lastOp is Map && lastOp.containsKey('insert')) {
          final insertData = lastOp['insert'];
          if (insertData is String && !insertData.endsWith('\n')) {
            rawContent[rawContent.length - 1] = {
              ...Map<String, dynamic>.from(lastOp),
              'insert': '$insertData\n',
            };
          }
        }
      }

      _controller = quill.QuillController(
        document: rawContent.isEmpty
            ? quill.Document()
            : quill.Document.fromDelta(
                quill.Delta.fromJson(rawContent),
              ),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: userPermission == 'viewer',
      );

      _controller!.document.changes.listen((event) {
        if (event.source == quill.ChangeSource.local) {
          socketRepository.submitOp(
            widget.id,
            event.change.toJson(),
            _controller!.document.toDelta().toJson(),
          );
        }
      });

      _controller!.addListener(() {
        final selection = _controller!.selection;
        socketRepository.emitCursorMove(
          widget.id,
          selection.baseOffset,
          selection.extentOffset - selection.baseOffset,
        );

        // Stage 10: Auto-lookup word on double-click selection
        if ((selection.end - selection.start) > 1) {
          final docText = _controller!.document.toPlainText();
          if (selection.start >= 0 && selection.end <= docText.length) {
            final selectedText = docText.substring(selection.start, selection.end).trim();
            if (selectedText.isNotEmpty &&
                !selectedText.contains(' ') &&
                selectedText.length < 25 &&
                RegExp(r'^[a-zA-Z]+$').hasMatch(selectedText)) {
              _lookupWordSilently(selectedText);
            }
          }
        }
      });

      setState(() {});
    });

    socketRepository.onReceiveOp((data) {
      _controller?.compose(
        quill.Delta.fromJson(data['delta']),
        _controller?.selection ?? const TextSelection.collapsed(offset: 0),
        quill.ChangeSource.remote,
      );
    });

    fetchDocumentData();
  }

  void fetchDocumentData() async {
    errorModel = await ref.read(documentRepositoryProvider).getDocumentById(
          ref.read(userProvider)!.token,
          widget.id,
        );

    if (errorModel!.data != null) {
      if (!mounted) return;
      titleController.text = (errorModel!.data as DocumentModel).title;
      // Now that we have metadata loaded, join the socket room to trigger load-document event
      socketRepository.joinRoom(widget.id);
    } else {
      // Allow screen to render/exit error if document couldn't be retrieved
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  void dispose() {
    socketRepository.disconnect();
    titleController.dispose();
    sidebarSearchController.dispose();
    super.dispose();
  }

  void updateTitle(WidgetRef ref, String title) {
    ref.read(documentRepositoryProvider).updateTitle(
          token: ref.read(userProvider)!.token,
          id: widget.id,
          title: title,
        );
  }

  void shareDocumentDialog() {
    final emailController = TextEditingController();
    String selectedPermission = 'viewer';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.share, color: kBlueColor),
                  SizedBox(width: 10),
                  Text('Share Document', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Invite collaborators by email address:',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      hintText: 'user@example.com',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Role / Permission:', style: TextStyle(fontWeight: FontWeight.bold)),
                      DropdownButton<String>(
                        value: selectedPermission,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                          DropdownMenuItem(value: 'editor', child: Text('Editor')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setStateDialog(() {
                              selectedPermission = val;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: 'http://localhost:5000/#/document/${widget.id}')).then(
                      (_) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Link copied to clipboard!')),
                        );
                      },
                    );
                  },
                  child: const Text('Copy Link'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBlueColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final email = emailController.text.trim();
                    if (email.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter an email address.')),
                      );
                      return;
                    }
                    Navigator.of(context).pop();
                    
                    final res = await ref.read(documentRepositoryProvider).shareDocument(
                          token: ref.read(userProvider)!.token,
                          id: widget.id,
                          email: email,
                          permission: selectedPermission,
                        );
                    
                    if (res.data != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Document successfully shared with $email as a $selectedPermission!')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(res.error ?? 'Failed to share document.')),
                      );
                    }
                  },
                  child: const Text('Share', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _lookupWordSilently(String word) async {
    final cleanWord = word.trim().replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (cleanWord.isEmpty || cleanWord.toLowerCase() == sidebarWord.toLowerCase()) return;
    
    final res = await DictionaryService.lookupWord(cleanWord);
    if (res != null) {
      if (!mounted) return;
      setState(() {
        sidebarWord = cleanWord;
        dictionaryResult = res;
        sidebarSearchController.text = cleanWord;
      });
    }
  }

  void _lookupWord(String word) async {
    final cleanWord = word.trim().replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (cleanWord.isEmpty) return;

    if (!mounted) return;
    setState(() {
      sidebarLoading = true;
      sidebarWord = cleanWord;
      dictionaryResult = null;
    });

    final res = await DictionaryService.lookupWord(cleanWord);
    
    if (!mounted) return;
    setState(() {
      sidebarLoading = false;
      dictionaryResult = res;
    });
  }

  Widget _buildDictionarySidebar() {
    return Container(
      width: 290,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: Colors.grey.shade200, width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            spreadRadius: 1,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                const Icon(Icons.book, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Dictionary Helper',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: () {
                    setState(() {
                      showSidebar = false;
                    });
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Search Field
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: sidebarSearchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => _lookupWord(value),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search any word...',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                suffixIcon: sidebarSearchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                        onPressed: () {
                          sidebarSearchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Colors.blue, width: 1.5),
                ),
              ),
              onChanged: (value) {
                setState(() {});
              },
            ),
          ),
          const Divider(height: 1),

          // Body
          Expanded(
            child: sidebarLoading
                ? const Center(child: CircularProgressIndicator())
                : dictionaryResult == null
                    ? _buildSidebarEmptyState()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Word Title
                            Text(
                              dictionaryResult!.word.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (dictionaryResult!.phonetic != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                dictionaryResult!.phonetic!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),

                            // Meanings
                            ...dictionaryResult!.meanings.map((meaning) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Part of Speech Tag
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.blue.shade100, width: 0.5),
                                          ),
                                          child: Text(
                                            meaning.partOfSpeech.toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    // Definitions
                                    ...meaning.definitions.asMap().entries.map((entry) {
                                      final idx = entry.key + 1;
                                      final def = entry.value;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Text(
                                              '$idx. ${def.definition}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black87,
                                                height: 1.4,
                                              ),
                                            ),
                                            if (def.example != null) ...[
                                              const SizedBox(height: 2),
                                              Padding(
                                                padding: const EdgeInsets.only(left: 14.0),
                                                child: Text(
                                                  '“${def.example}”',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontStyle: FontStyle.italic,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    }).toList(),

                                    // Synonyms
                                    if (meaning.synonyms.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Synonyms:',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black45),
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: meaning.synonyms.take(4).map((syn) {
                                          return ActionChip(
                                            label: Text(syn, style: const TextStyle(fontSize: 10)),
                                            padding: EdgeInsets.zero,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            backgroundColor: Colors.grey.shade100,
                                            onPressed: () {
                                              _lookupWord(syn);
                                            },
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text(
              'No Word Loaded',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            const Text(
              'Type a word in search, or double-click any word in the document to lookup definitions.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  void _showWordCountDialog() {
    final text = _controller!.document.toPlainText();
    
    final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final charsWithSpaces = text.length;
    final charsWithoutSpaces = text.replaceAll(RegExp(r'\s'), '').length;
    
    final lines = text.split('\n');
    final paragraphs = lines.where((line) => line.trim().isNotEmpty).length;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 8),
              Text('Word Count', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCountRow('Words', words.toString()),
              const Divider(),
              _buildCountRow('Characters (with spaces)', charsWithSpaces.toString()),
              const Divider(),
              _buildCountRow('Characters (no spaces)', charsWithoutSpaces.toString()),
              const Divider(),
              _buildCountRow('Paragraphs', paragraphs.toString()),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCountRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  void _insertLink(BuildContext context) {
    final textController = TextEditingController();
    final urlController = TextEditingController();
    
    final selection = _controller!.selection;
    if ((selection.end - selection.start) > 0) {
      final docText = _controller!.document.toPlainText();
      textController.text = docText.substring(selection.start, selection.end);
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Insert Hyperlink', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                decoration: const InputDecoration(
                  labelText: 'Text to Display',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Link URL (https://...)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                textController.dispose();
                urlController.dispose();
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final linkText = textController.text.trim();
                final url = urlController.text.trim();
                if (url.isNotEmpty) {
                  final index = _controller!.selection.baseOffset;
                  final length = _controller!.selection.extentOffset - index;
                  
                  if (length > 0) {
                    _controller!.formatSelection(quill.LinkAttribute(url));
                  } else {
                    final display = linkText.isEmpty ? url : linkText;
                    _controller!.replaceText(index, 0, display, null);
                    _controller!.updateSelection(TextSelection(baseOffset: index, extentOffset: index + display.length), quill.ChangeSource.local);
                    _controller!.formatSelection(quill.LinkAttribute(url));
                    _controller!.updateSelection(TextSelection.collapsed(offset: index + display.length), quill.ChangeSource.local);
                  }
                }
                textController.dispose();
                urlController.dispose();
                Navigator.pop(context);
              },
              child: const Text('Insert'),
            ),
          ],
        );
      },
    );
  }

  void _insertImage(BuildContext context) {
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Insert Image', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Image Web URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text('OR', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload Local Image'),
                onPressed: () {
                  Navigator.pop(context);
                  _uploadLocalImage();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                urlController.dispose();
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final url = urlController.text.trim();
                if (url.isNotEmpty) {
                  final index = _controller!.selection.baseOffset;
                  _controller!.replaceText(index, 0, quill.BlockEmbed.image(url), null);
                }
                urlController.dispose();
                Navigator.pop(context);
              },
              child: const Text('Insert'),
            ),
          ],
        );
      },
    );
  }

  void _uploadLocalImage() {
    final uploadInput = html.FileUploadInputElement()..accept = 'image/*';
    uploadInput.click();
    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        final reader = html.FileReader();
        reader.readAsDataUrl(file);
        reader.onLoadEnd.listen((e) {
          final base64String = reader.result as String;
          final index = _controller!.selection.baseOffset;
          _controller!.replaceText(index, 0, quill.BlockEmbed.image(base64String), null);
        });
      }
    });
  }

  void _insertTable() {
    final index = _controller!.selection.baseOffset;
    final initialTableData = json.encode([
      ['Header 1', 'Header 2', 'Header 3'],
      ['Cell A2', 'Cell B2', 'Cell C2'],
      ['Cell A3', 'Cell B3', 'Cell C3']
    ]);
    _controller!.replaceText(index, 0, CustomTableEmbed(initialTableData), null);
  }

  void _insertChart() {
    final index = _controller!.selection.baseOffset;
    final initialChartData = json.encode({
      'type': 'bar',
      'title': 'Sales Overview',
      'labels': ['Q1', 'Q2', 'Q3', 'Q4'],
      'values': [100.0, 180.0, 140.0, 220.0]
    });
    _controller!.replaceText(index, 0, CustomChartEmbed(initialChartData), null);
  }

  void _exportToDocx(BuildContext context, WidgetRef ref) async {
    final token = ref.read(userProvider)!.token;
    final snackbar = ScaffoldMessenger.of(context);
    
    snackbar.showSnackBar(
      const SnackBar(content: Text('Preparing Word document export...')),
    );
    
    try {
      final res = await ref.read(documentRepositoryProvider).exportToDocx(token, widget.id);
      
      if (res.data != null) {
        final bytes = res.data as List<int>;
        final blob = html.Blob([bytes], 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
        final url = html.Url.createObjectUrlFromBlob(blob);
        
        final safeTitle = titleController.text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = '${safeTitle.isEmpty ? "Untitled" : safeTitle}.docx';
          
        html.document.body!.children.add(anchor);
        anchor.click();
        html.document.body!.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
      } else {
        snackbar.showSnackBar(
          SnackBar(content: Text(res.error ?? 'Export failed.')),
        );
      }
    } catch (e) {
      snackbar.showSnackBar(
        SnackBar(content: Text('Error during export: $e')),
      );
    }
  }

  Widget _buildFileMenu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'File Options',
      offset: const Offset(0, 20),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Text(
          'File',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      onSelected: (value) async {
        final title = titleController.text;
        final docDelta = _controller!.document.toDelta();

        if (value == 'txt') {
          ExportService.downloadAsTXT(title, docDelta);
        } else if (value == 'pdf') {
          await ExportService.downloadAsPDF(title, docDelta);
        } else if (value == 'docx') {
          _exportToDocx(context, ref);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          enabled: false,
          child: Text(
            'Download As',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'pdf',
          child: Row(
            children: const [
              Icon(Icons.picture_as_pdf, color: Colors.red, size: 18),
              SizedBox(width: 8),
              Text('PDF Document (.pdf)', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'docx',
          child: Row(
            children: const [
              Icon(Icons.description, color: Colors.blue, size: 18),
              SizedBox(width: 8),
              Text('Word Document (.docx)', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'txt',
          child: Row(
            children: const [
              Icon(Icons.text_snippet, color: Colors.grey, size: 18),
              SizedBox(width: 8),
              Text('Plain Text (.txt)', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInsertMenu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Insert Elements',
      offset: const Offset(0, 20),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Text(
          'Insert',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      onSelected: (value) async {
        if (value == 'link') {
          _insertLink(context);
        } else if (value == 'image') {
          _insertImage(context);
        } else if (value == 'table') {
          _insertTable();
        } else if (value == 'chart') {
          _insertChart();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          enabled: false,
          child: Text(
            'Insert Component',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'link',
          child: Row(
            children: const [
              Icon(Icons.link, color: Colors.blue, size: 18),
              SizedBox(width: 8),
              Text('Link', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'image',
          child: Row(
            children: const [
              Icon(Icons.image, color: Colors.green, size: 18),
              SizedBox(width: 8),
              Text('Image URL / Upload', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'table',
          child: Row(
            children: const [
              Icon(Icons.table_chart, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Text('Collaborative Table (3x3)', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'chart',
          child: Row(
            children: const [
              Icon(Icons.bar_chart, color: Colors.purple, size: 18),
              SizedBox(width: 8),
              Text('Interactive Chart', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToolsMenu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Tools',
      offset: const Offset(0, 20),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Text(
          'Tools',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      onSelected: (value) {
        if (value == 'wordcount') {
          _showWordCountDialog();
        } else if (value == 'dictionary') {
          setState(() {
            showSidebar = !showSidebar;
          });
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          enabled: false,
          child: Text(
            'Document Tools',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'wordcount',
          child: Row(
            children: const [
              Icon(Icons.info_outline, color: Colors.blue, size: 18),
              SizedBox(width: 8),
              Text('Word Count', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'dictionary',
          child: Row(
            children: const [
              Icon(Icons.book, color: Colors.purple, size: 18),
              SizedBox(width: 8),
              Text('Dictionary Sidebar', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return const Scaffold(body: Loader());
    }
    final isOwner = userPermission == 'owner';
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kWhiteColor,
        elevation: 0,
        actions: [
          if (activeCollaborators.isNotEmpty)
            Row(
              children: activeCollaborators.map((collab) {
                final String name = collab['name'] ?? 'Anonymous';
                final String email = collab['email'] ?? '';
                final String avatarUrl = collab['avatarUrl'] ?? '';
                final String colorHex = collab['color'] ?? '#E53935';
                final color = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));

                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: Tooltip(
                    message: '$name ($email)',
                    child: CircleAvatar(
                      backgroundColor: color,
                      radius: 14,
                      backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl.isEmpty
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'A',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
            child: ElevatedButton.icon(
              onPressed: isOwner ? shareDocumentDialog : null,
              icon: const Icon(Icons.share, size: 15, color: Colors.white),
              label: const Text('Share', style: TextStyle(fontSize: 12, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isOwner ? kBlueColor : Colors.grey.shade400,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: CircleAvatar(
              backgroundColor: getUserColor(ref.watch(userProvider)!.email),
              radius: 18,
              child: ref.watch(userProvider)!.profilePic.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.network(
                        ref.watch(userProvider)!.profilePic,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Text(
                            ref.watch(userProvider)!.name[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          );
                        },
                      ),
                    )
                  : Text(
                      ref.watch(userProvider)!.name[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Routemaster.of(context).replace('/');
                    },
                    child: Image.asset(
                      'assets/images/docs-logo.png',
                      height: 30,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 180,
                    height: 28,
                    child: TextField(
                      controller: titleController,
                      enabled: userPermission != 'viewer',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.only(left: 4),
                      ),
                      onSubmitted: (value) => updateTitle(ref, value),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 38),
                  _buildFileMenu(context, ref),
                  const SizedBox(width: 12),
                  _buildInsertMenu(context, ref),
                  const SizedBox(width: 12),
                  _buildToolsMenu(context, ref),
                ],
              ),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: kGreyColor,
                width: 0.1,
              ),
            ),
          ),
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              children: [
                if (userPermission != 'viewer') ...[
                  const SizedBox(height: 10),
                  quill.QuillSimpleToolbar(
                    controller: _controller!,
                    config: const quill.QuillSimpleToolbarConfig(),
                  ),
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: SizedBox(
                    width: 750,
                    child: Card(
                      color: kWhiteColor,
                      elevation: 5,
                      child: Padding(
                        padding: const EdgeInsets.all(30.0),
                        child: quill.QuillEditor.basic(
                          controller: _controller!,
                          config: quill.QuillEditorConfig(
                            embedBuilders: [
                              CustomTableEmbedBuilder(),
                              CustomChartEmbedBuilder(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
          if (showSidebar)
            _buildDictionarySidebar(),
        ],
      ),
    );
  }
}
