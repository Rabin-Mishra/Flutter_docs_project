import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

// ─── CUSTOM EMBED TYPES ──────────────────────────────────────────────────────

class CustomTableEmbed extends quill.CustomBlockEmbed {
  static const String embedType = 'custom-table';
  CustomTableEmbed(String data) : super(embedType, data);
}

class CustomChartEmbed extends quill.CustomBlockEmbed {
  static const String embedType = 'custom-chart';
  CustomChartEmbed(String data) : super(embedType, data);
}

// ─── EMBED BUILDERS ──────────────────────────────────────────────────────────

class CustomTableEmbedBuilder extends quill.EmbedBuilder {
  @override
  String get key => 'custom-table';

  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final controller = embedContext.controller;
    final node = embedContext.node;
    final readOnly = embedContext.readOnly;
    final String data = node.value.data as String;
    return CustomTableWidget(
      data: data,
      readOnly: readOnly,
      onChanged: (updatedData) {
        final offset = node.documentOffset;
        controller.replaceText(offset, 1, CustomTableEmbed(updatedData), null);
      },
    );
  }
}

class CustomChartEmbedBuilder extends quill.EmbedBuilder {
  @override
  String get key => 'custom-chart';

  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final controller = embedContext.controller;
    final node = embedContext.node;
    final readOnly = embedContext.readOnly;
    final String data = node.value.data as String;
    return CustomChartWidget(
      data: data,
      readOnly: readOnly,
      onChanged: (updatedData) {
        final offset = node.documentOffset;
        controller.replaceText(offset, 1, CustomChartEmbed(updatedData), null);
      },
    );
  }
}

// ─── COLLABORATIVE TABLE WIDGET ──────────────────────────────────────────────

class CustomTableWidget extends StatefulWidget {
  final String data;
  final bool readOnly;
  final Function(String) onChanged;

  const CustomTableWidget({
    Key? key,
    required this.data,
    required this.readOnly,
    required this.onChanged,
  }) : super(key: key);

  @override
  _CustomTableWidgetState createState() => _CustomTableWidgetState();
}

class _CustomTableWidgetState extends State<CustomTableWidget> {
  List<List<TextEditingController>> _controllers = [];
  List<List<FocusNode>> _focusNodes = [];
  List<List<String>> _matrix = [];

  @override
  void initState() {
    super.initState();
    _parseData();
  }

  void _parseData() {
    try {
      final List<dynamic> decoded = jsonDecode(widget.data);
      _matrix = decoded.map((row) => List<String>.from(row)).toList();
    } catch (_) {
      // Fallback 3x3 table
      _matrix = List.generate(3, (_) => List.generate(3, (_) => ''));
    }

    _disposeControllersAndNodes();

    _controllers = _matrix.map((row) {
      return row.map((cell) => TextEditingController(text: cell)).toList();
    }).toList();

    _focusNodes = _matrix.map((row) {
      return row.map((_) => FocusNode()).toList();
    }).toList();

    // Attach listeners to trigger database changes when the cell loses focus
    for (int r = 0; r < _focusNodes.length; r++) {
      for (int c = 0; c < _focusNodes[r].length; c++) {
        _focusNodes[r][c].addListener(() {
          if (!_focusNodes[r][c].hasFocus) {
            _commitChange();
          }
        });
      }
    }
  }

  void _disposeControllersAndNodes() {
    for (var row in _controllers) {
      for (var ctrl in row) {
        ctrl.dispose();
      }
    }
    for (var row in _focusNodes) {
      for (var fn in row) {
        fn.dispose();
      }
    }
    _controllers.clear();
    _focusNodes.clear();
  }

  @override
  void didUpdateWidget(CustomTableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      try {
        final List<dynamic> decoded = jsonDecode(widget.data);
        final newMatrix = decoded.map((row) => List<String>.from(row)).toList();

        // If structure changed, rebuild focus nodes and text controllers
        if (newMatrix.length != _matrix.length || 
            (newMatrix.isNotEmpty && newMatrix[0].length != _matrix[0].length)) {
          setState(() {
            _parseData();
          });
        } else {
          // If structure is same, only update cell text fields that aren't focused
          for (int r = 0; r < newMatrix.length; r++) {
            for (int c = 0; c < newMatrix[r].length; c++) {
              if (!_focusNodes[r][c].hasFocus && _controllers[r][c].text != newMatrix[r][c]) {
                _controllers[r][c].text = newMatrix[r][c];
              }
              _matrix[r][c] = newMatrix[r][c];
            }
          }
        }
      } catch (_) {}
    }
  }

  void _commitChange() {
    final currentMatrix = _controllers.map((row) {
      return row.map((ctrl) => ctrl.text).toList();
    }).toList();

    final jsonStr = jsonEncode(currentMatrix);
    if (jsonStr != widget.data) {
      widget.onChanged(jsonStr);
    }
  }

  @override
  void dispose() {
    _disposeControllersAndNodes();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int rows = _matrix.length;
    final int cols = rows > 0 ? _matrix[0].length : 0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.readOnly)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  const Icon(Icons.grid_on, size: 16, color: Colors.blue),
                  const SizedBox(width: 6),
                  const Text(
                    'Table Controls',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.green),
                    tooltip: 'Add Row',
                    onPressed: () {
                      _matrix.add(List.generate(cols, (_) => ''));
                      _commitChange();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.red),
                    tooltip: 'Delete Row',
                    onPressed: rows > 1 ? () {
                      _matrix.removeLast();
                      _commitChange();
                    } : null,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.playlist_add_circle_outlined, size: 18, color: Colors.blue),
                    tooltip: 'Add Column',
                    onPressed: () {
                      for (var row in _matrix) {
                        row.add('');
                      }
                      _commitChange();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.playlist_remove_outlined, size: 18, color: Colors.red),
                    tooltip: 'Delete Column',
                    onPressed: cols > 1 ? () {
                      for (var row in _matrix) {
                        row.removeLast();
                      }
                      _commitChange();
                    } : null,
                  ),
                ],
              ),
            ),
          Table(
            border: TableBorder.all(
              color: Colors.grey.shade300, 
              width: 1, 
              borderRadius: BorderRadius.circular(4)
            ),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: List.generate(rows, (r) {
              return TableRow(
                children: List.generate(cols, (c) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    color: r == 0 ? Colors.blue.shade50.withOpacity(0.5) : Colors.white,
                    child: TextFormField(
                      controller: _controllers[r][c],
                      focusNode: _focusNodes[r][c],
                      enabled: !widget.readOnly,
                      maxLines: null,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: r == 0 ? FontWeight.bold : FontWeight.normal,
                        color: Colors.black87,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  );
                }),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─── COLLABORATIVE CHART WIDGET ──────────────────────────────────────────────

class CustomChartWidget extends StatefulWidget {
  final String data;
  final bool readOnly;
  final Function(String) onChanged;

  const CustomChartWidget({
    Key? key,
    required this.data,
    required this.readOnly,
    required this.onChanged,
  }) : super(key: key);

  @override
  _CustomChartWidgetState createState() => _CustomChartWidgetState();
}

class _CustomChartWidgetState extends State<CustomChartWidget> {
  String _type = 'bar';
  String _title = 'Chart Embed';
  List<String> _labels = [];
  List<double> _values = [];

  @override
  void initState() {
    super.initState();
    _parseData();
  }

  void _parseData() {
    try {
      final Map<String, dynamic> map = jsonDecode(widget.data);
      _type = map['type'] ?? 'bar';
      _title = map['title'] ?? 'Chart Embed';
      _labels = List<String>.from(map['labels'] ?? []);
      _values = List<double>.from((map['values'] ?? []).map((v) => (v as num).toDouble()));
    } catch (_) {
      // Fallback default chart
      _type = 'bar';
      _title = 'Sales Report';
      _labels = ['Q1', 'Q2', 'Q3', 'Q4'];
      _values = [150.0, 220.0, 180.0, 270.0];
    }
  }

  @override
  void didUpdateWidget(CustomChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      setState(() {
        _parseData();
      });
    }
  }

  void _showEditDialog() {
    final titleController = TextEditingController(text: _title);
    String selectedType = _type;

    // Build data lists controllers
    final List<TextEditingController> labelControllers = 
        _labels.map((l) => TextEditingController(text: l)).toList();
    final List<TextEditingController> valueControllers = 
        _values.map((v) => TextEditingController(text: v.toStringAsFixed(0))).toList();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Chart Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Chart Title',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        decoration: const InputDecoration(
                          labelText: 'Chart Type',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'bar', child: Text('Bar Chart')),
                          DropdownMenuItem(value: 'line', child: Text('Line Chart')),
                          DropdownMenuItem(value: 'pie', child: Text('Pie Chart')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedType = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text('Dataset Entries', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const Spacer(),
                          TextButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Point', style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              setDialogState(() {
                                labelControllers.add(TextEditingController(text: 'Label ${labelControllers.length + 1}'));
                                valueControllers.add(TextEditingController(text: '100'));
                              });
                            },
                          ),
                        ],
                      ),
                      const Divider(),
                      ...List.generate(labelControllers.length, (idx) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: labelControllers[idx],
                                  decoration: const InputDecoration(
                                    labelText: 'Label',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: valueControllers[idx],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Value',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                onPressed: () {
                                  setDialogState(() {
                                    labelControllers[idx].dispose();
                                    valueControllers[idx].dispose();
                                    labelControllers.removeAt(idx);
                                    valueControllers.removeAt(idx);
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    for (var c in labelControllers) {
                      c.dispose();
                    }
                    for (var c in valueControllers) {
                      c.dispose();
                    }
                    titleController.dispose();
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final List<String> updatedLabels = [];
                    final List<double> updatedValues = [];

                    for (int i = 0; i < labelControllers.length; i++) {
                      final l = labelControllers[i].text;
                      final v = double.tryParse(valueControllers[i].text) ?? 0.0;
                      updatedLabels.add(l.isEmpty ? 'Item ${i + 1}' : l);
                      updatedValues.add(v);
                    }

                    final updatedMap = {
                      'type': selectedType,
                      'title': titleController.text.isEmpty ? 'Chart' : titleController.text,
                      'labels': updatedLabels,
                      'values': updatedValues,
                    };

                    widget.onChanged(jsonEncode(updatedMap));

                    for (var c in labelControllers) {
                      c.dispose();
                    }
                    for (var c in valueControllers) {
                      c.dispose();
                    }
                    titleController.dispose();
                    Navigator.pop(context);
                  },
                  child: const Text('Save Details'),
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
    return GestureDetector(
      onTap: widget.readOnly ? null : _showEditDialog,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart, color: Colors.purple, size: 20),
                const SizedBox(width: 8),
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                if (!widget.readOnly)
                  const Text(
                    'Click to Edit',
                    style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: CustomPaint(
                painter: _ChartPainter(
                  type: _type,
                  labels: _labels,
                  values: _values,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ─── CHART CUSTOM PAINTER ────────────────────────────────────────────────────

class _ChartPainter extends CustomPainter {
  final String type;
  final List<String> labels;
  final List<double> values;

  _ChartPainter({
    required this.type,
    required this.labels,
    required this.values,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final double maxVal = values.reduce((curr, next) => curr > next ? curr : next);
    final double divisor = maxVal == 0 ? 1.0 : maxVal;
    
    if (type == 'pie') {
      _paintPie(canvas, size, divisor);
    } else if (type == 'line') {
      _paintLine(canvas, size, divisor);
    } else {
      _paintBar(canvas, size, divisor);
    }
  }

  void _paintBar(Canvas canvas, Size size, double maxVal) {
    final int count = values.length;
    final double width = size.width;
    final double height = size.height - 30; // Leave space for labels
    
    final double colWidth = (width / count) * 0.6;
    final double gap = (width / count) * 0.4;
    
    for (int i = 0; i < count; i++) {
      final double val = values[i];
      final double colHeight = (val / maxVal) * height;
      
      final double left = (i * (colWidth + gap)) + (gap / 2);
      final double top = height - colHeight + 10;
      final double right = left + colWidth;
      final double bottom = height + 10;
      
      // Paint with a beautiful blue-purple gradient
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [Colors.blue.shade400, Colors.purple.shade400],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTRB(left, top, right, bottom))
        ..style = PaintingStyle.fill;
        
      // Round top corners of the bar
      final rrect = RRect.fromRectAndCorners(
        Rect.fromLTRB(left, top, right, bottom),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      
      canvas.drawRRect(rrect, paint);
      
      // Draw label
      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: const TextStyle(fontSize: 10, color: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: colWidth + gap);
      
      textPainter.paint(
        canvas,
        Offset(left + (colWidth - textPainter.width) / 2, height + 14),
      );
      
      // Draw value text on top of the bar
      final valPainter = TextPainter(
        text: TextSpan(
          text: val.toStringAsFixed(0),
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      
      valPainter.paint(
        canvas,
        Offset(left + (colWidth - valPainter.width) / 2, top - 12),
      );
    }
  }

  void _paintLine(Canvas canvas, Size size, double maxVal) {
    final int count = values.length;
    final double width = size.width;
    final double height = size.height - 30;
    
    final double stepX = width / (count > 1 ? count - 1 : 1);
    
    final path = Path();
    final fillPath = Path();
    
    final linePaint = Paint()
      ..color = Colors.blue.shade600
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
      
    final pointPaint = Paint()
      ..color = Colors.purple.shade500
      ..style = PaintingStyle.fill;

    for (int i = 0; i < count; i++) {
      final double val = values[i];
      final double x = i * stepX;
      final double y = height - (val / maxVal) * height + 10;
      
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, height + 10);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
      
      if (i == count - 1) {
        fillPath.lineTo(x, height + 10);
        fillPath.close();
      }
    }
    
    // Draw soft area gradient
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.blue.shade200.withOpacity(0.4), Colors.blue.shade50.withOpacity(0.0)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTRB(0, 10, width, height + 10));
      
    if (count > 1) {
      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(path, linePaint);
    }
    
    // Draw points & labels
    for (int i = 0; i < count; i++) {
      final double val = values[i];
      final double x = i * stepX;
      final double y = height - (val / maxVal) * height + 10;
      
      canvas.drawCircle(Offset(x, y), 5, pointPaint);
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = Colors.white);
      
      // Label
      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: const TextStyle(fontSize: 10, color: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      
      textPainter.paint(
        canvas,
        Offset(x - (textPainter.width / 2), height + 14),
      );
      
      // Value
      final valPainter = TextPainter(
        text: TextSpan(
          text: val.toStringAsFixed(0),
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      
      valPainter.paint(
        canvas,
        Offset(x - (valPainter.width / 2), y - 14),
      );
    }
  }

  void _paintPie(Canvas canvas, Size size, double divisor) {
    final double total = values.fold(0, (sum, val) => sum + val);
    if (total == 0) return;

    final double width = size.width;
    final double height = size.height;
    
    final double radius = (height < width ? height : width) * 0.4;
    final center = Offset(width * 0.35, height * 0.5);
    
    final List<Color> colors = [
      Colors.blue.shade400,
      Colors.purple.shade400,
      Colors.orange.shade400,
      Colors.green.shade400,
      Colors.red.shade400,
      Colors.yellow.shade600,
    ];
    
    double startAngle = -3.14159 / 2; // Start from top
    
    for (int i = 0; i < values.length; i++) {
      final double val = values[i];
      final double sweepAngle = (val / total) * 2 * 3.14159;
      
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;
        
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );
      
      // Draw slice border for clean separation
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
      
      startAngle += sweepAngle;
    }
    
    // Draw beautiful Legend on the right side
    final double legendLeft = width * 0.65;
    double legendTop = height * 0.15;
    
    for (int i = 0; i < values.length; i++) {
      final color = colors[i % colors.length];
      final double val = values[i];
      final double pct = (val / total) * 100;
      
      // Color block
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legendLeft, legendTop + 2, 10, 10),
          const Radius.circular(2),
        ),
        Paint()..color = color,
      );
      
      // Legend Label
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${labels[i]} (${pct.toStringAsFixed(0)}%)',
          style: const TextStyle(fontSize: 10, color: Colors.black87),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      
      textPainter.paint(canvas, Offset(legendLeft + 16, legendTop));
      legendTop += 18;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
