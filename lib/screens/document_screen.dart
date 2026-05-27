import 'dart:async';

import 'package:docs_clone_flutter/colors.dart';
import 'package:docs_clone_flutter/common/widgets/loader.dart';
import 'package:docs_clone_flutter/models/document_model.dart';
import 'package:docs_clone_flutter/models/error_model.dart';
import 'package:docs_clone_flutter/repository/auth_repository.dart';
import 'package:docs_clone_flutter/repository/document_repository.dart';
import 'package:docs_clone_flutter/repository/socket_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:dart_quill_delta/dart_quill_delta.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:routemaster/routemaster.dart';

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
                      radius: 15,
                      child: avatarUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Image.network(
                                avatarUrl,
                                width: 30,
                                height: 30,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Text(
                                    name[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                },
                              ),
                            )
                          : Text(
                              name[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: ElevatedButton.icon(
              onPressed: () {
                if (isOwner) {
                  shareDocumentDialog();
                } else {
                  Clipboard.setData(ClipboardData(text: 'http://localhost:5000/#/document/${widget.id}')).then(
                    (value) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Link copied! (${userPermission.toUpperCase()})',
                          ),
                        ),
                      );
                    },
                  );
                }
              },
              icon: Icon(
                isOwner ? Icons.share : Icons.lock,
                size: 16,
              ),
              label: Text(isOwner ? 'Share' : 'Get Link'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kBlueColor,
              ),
            ),
          ),
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
          padding: const EdgeInsets.symmetric(vertical: 9.0),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  Routemaster.of(context).replace('/');
                },
                child: Image.asset(
                  'assets/images/docs-logo.png',
                  height: 40,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: titleController,
                  enabled: userPermission != 'viewer',
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: kBlueColor,
                      ),
                    ),
                    contentPadding: EdgeInsets.only(left: 10),
                  ),
                  onSubmitted: (value) => updateTitle(ref, value),
                ),
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
      body: Center(
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
                      config: const quill.QuillEditorConfig(),
                    ),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
