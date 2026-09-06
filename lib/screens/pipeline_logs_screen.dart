import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/musly_backend_service.dart';
import '../services/subsonic_service.dart';
import '../theme/app_theme.dart';

class PipelineLogsScreen extends StatefulWidget {
  final String? bridgeUrl;

  const PipelineLogsScreen({super.key, this.bridgeUrl});

  @override
  State<PipelineLogsScreen> createState() => _PipelineLogsScreenState();
}

class _PipelineLogsScreenState extends State<PipelineLogsScreen> {
  String? _logs;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final bridgeUrl = widget.bridgeUrl?.isNotEmpty == true
        ? widget.bridgeUrl!
        : (Provider.of<SubsonicService>(context, listen: false).bridgeUrl ?? '');

    if (bridgeUrl.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Music Pipeline bridge URL is not available.';
      });
      return;
    }

    try {
      final logs = await MuslyBackendService().getLogs(bridgeUrl, minutes: 10);
      if (mounted) setState(() { _logs = logs; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Failed to fetch logs: $e'; _isLoading = false; });
    }
  }

  Future<void> _copyLogs() async {
    final text = _logs?.trim() ?? '';
    if (text.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(CupertinoIcons.checkmark_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Logs copied to clipboard'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final hasLogs = _logs != null && _logs!.trim().isNotEmpty;

    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.exclamationmark_triangle, size: 40, color: Colors.orange),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchLogs,
                icon: const Icon(CupertinoIcons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else if (!hasLogs) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.doc_text, size: 40, color: isDark ? Colors.white38 : Colors.black38),
            const SizedBox(height: 12),
            const Text('No logs recorded in the last 10 minutes.'),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _fetchLogs,
              icon: const Icon(CupertinoIcons.refresh, size: 16),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    } else {
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _copyLogs,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141414) : const Color(0xFFF6F8FA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFD0D7DE)),
          ),
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                _logs!,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                  color: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF24292F),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Pipeline Logs'),
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (hasLogs)
            IconButton(
              icon: const Icon(CupertinoIcons.doc_on_doc),
              tooltip: 'Copy Logs',
              onPressed: _copyLogs,
            ),
          IconButton(
            icon: const Icon(CupertinoIcons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _fetchLogs,
          ),
        ],
      ),
      body: body,
    );
  }
}
