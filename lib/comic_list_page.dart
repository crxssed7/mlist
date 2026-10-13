import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const username = 'crxssed';
const apiEndpoint = 'https://kaboom.rocks/users/$username/upnext.json';
const cacheKey = 'comicsListCache';

Future<void> refreshData() async {
  try {
    final response = await http.get(Uri.parse(apiEndpoint));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      final result = data
          .map((item) {
            if (item is! Map<String, dynamic>) return null;

            final nextIssue = item['next_issue'];
            if (nextIssue == null) return null;

            final title =
                "${item['name']} - ${nextIssue['name'] ?? '#${nextIssue['absolute_number']}'}";
            final rereading = item['reread_active'] as bool? ?? false;
            final colorHex = (item['color'] ?? '#8BA798') as String;
            final imageUrl = (nextIssue['image']) as String;

            final nextIssueNum =
                (nextIssue['absolute_number'] as num?)?.toDouble() ??
                double.tryParse(nextIssue['issue_number']?.toString() ?? '');
            if (nextIssueNum == null) return null;

            final issuesRead = nextIssueNum > 1 ? nextIssueNum - 1 : 0.0;
            double totalIssues =
                (item['count_of_issues'] as num?)?.toDouble() ?? 0.0;
            if (totalIssues < nextIssueNum) {
              totalIssues = nextIssueNum;
            }

            if (totalIssues <= issuesRead) {
              return null;
            }

            final issuesLeft = totalIssues - issuesRead;

            return {
              'title': title,
              'rereading': rereading,
              'imageUrl': imageUrl,
              'color': colorHex,
              'issuesRead': issuesRead,
              'totalIssues': totalIssues,
              'issuesLeft': issuesLeft,
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(result));
    }
  } catch (e) {
    debugPrint('Error fetching data: $e');
  }
}

class ComicsListPage extends StatefulWidget {
  const ComicsListPage({super.key});

  @override
  State<ComicsListPage> createState() => _ComicsListPageState();
}

class _ComicsListPageState extends State<ComicsListPage> {
  List<Map<String, dynamic>> _outdatedComics = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initializeAndFetch();
  }

  Future<void> _initializeAndFetch() async {
    await _loadCache();
    // If cache is empty or old, refresh.
    if (_outdatedComics.isEmpty) {
      await _refreshData();
    }
  }

  String _cleanNumber(double value, {int precision = 2}) {
    // Round to avoid floating point noise
    double rounded = double.parse(value.toStringAsFixed(precision));

    // Remove trailing .0 or .00 if unnecessary
    if (rounded == rounded.toInt()) {
      return rounded.toInt().toString(); // Show as int if it's a whole number
    } else {
      return rounded.toString(); // Otherwise show decimal (e.g. 0.2)
    }
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedString = prefs.getString(cacheKey);
    if (cachedString != null) {
      final List<dynamic> decoded = jsonDecode(cachedString);
      if (mounted) {
        setState(() {
          _outdatedComics = List<Map<String, dynamic>>.from(decoded);
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshData({bool forceRefresh = false}) async {
    setState(() => _loading = true);
    if (forceRefresh) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cacheKey);
      if (mounted) {
        setState(() {
          _outdatedComics = [];
        });
      }
    }

    await refreshData();
    await _loadCache();

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Volumes')),
      floatingActionButton: Platform.isAndroid || Platform.isIOS
          ? null
          : FloatingActionButton(
              onPressed: () => _refreshData(forceRefresh: true),
              child: const Icon(Icons.refresh),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _refreshData(forceRefresh: true),
              child: _outdatedComics.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 100),
                        Center(child: Text("You're up to date! 🎉")),
                      ],
                    )
                  : ListView.builder(
                      itemCount: _outdatedComics.length,
                      itemBuilder: (context, index) {
                        final comic = _outdatedComics[index];
                        final title = comic['title'] as String? ?? 'No Title';
                        final imageUrl = comic['imageUrl'] as String? ?? '';
                        final rereading = comic['rereading'] as bool? ?? false;
                        final issuesRead =
                            ((comic['issuesRead'] ?? comic['chaptersRead'])
                                    as num?)
                                ?.toDouble() ??
                            0.0;
                        final totalIssues =
                            ((comic['totalIssues'] ?? comic['totalChapters'])
                                    as num?)
                                ?.toDouble() ??
                            1.0;
                        final issuesLeft =
                            ((comic['issuesLeft'] ?? comic['chaptersLeft'])
                                    as num?)
                                ?.toDouble() ??
                            0.0;
                        final colorHex = comic['color'] as String? ?? '#8BA798';

                        final double progressValue = (totalIssues > 0)
                            ? issuesRead / totalIssues
                            : 0.0;

                        return ComicsListItem(
                          title: title,
                          imageUrl: imageUrl,
                          issuesRead: issuesRead,
                          totalIssues: totalIssues,
                          issuesLeft: issuesLeft,
                          colorHex: colorHex,
                          progressValue: progressValue,
                          cleanNumber: _cleanNumber,
                          rereading: rereading,
                        );
                      },
                    ),
            ),
    );
  }
}

class ComicsListItem extends StatelessWidget {
  final String title;
  final String imageUrl;
  final double issuesRead;
  final double totalIssues;
  final double issuesLeft;
  final String colorHex;
  final double progressValue;
  final String Function(double, {int precision}) cleanNumber;
  final bool rereading;

  const ComicsListItem({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.issuesRead,
    required this.totalIssues,
    required this.issuesLeft,
    required this.colorHex,
    required this.progressValue,
    required this.cleanNumber,
    required this.rereading,
  });

  Color _parseColor(
    String hexString, {
    Color fallback = const Color(0xFF8BA798),
  }) {
    try {
      String hex = hexString.replaceFirst('#', '');
      if (hex.length == 6) {
        hex = 'FF$hex';
      }
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _parseColor(colorHex);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor, width: 0.5),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 80,
              height: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(child: Icon(Icons.broken_image)),
                      )
                    : const Center(child: Icon(Icons.book)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 120,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${rereading ? '⏪ ' : ''}${cleanNumber(issuesRead)} / ${cleanNumber(totalIssues)} (${cleanNumber(issuesLeft)} behind)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: progressValue,
                          backgroundColor: Colors.grey.shade300,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            borderColor,
                          ),
                          minHeight: 3,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
