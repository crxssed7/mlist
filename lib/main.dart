import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

const anilistUsername = 'crxssed';
const apiEndpoint =
    'https://albert.crxssed.dev/api/anilist/reading-list/$anilistUsername?only_unread=true';
const cacheKey = 'readingListCache'; // Updated cache key

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Manga Updates',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF8BA798),
        brightness: Brightness.dark,
      ),
      home: const MangaListPage(),
    );
  }
}

class MangaListPage extends StatefulWidget {
  const MangaListPage({super.key});

  @override
  State<MangaListPage> createState() => _MangaListPageState();
}

class _MangaListPageState extends State<MangaListPage> {
  List<Map<String, dynamic>> _outdatedManga = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initializeAndFetch();
  }

  Future<void> _initializeAndFetch() async {
    await _loadCache();
    // If cache is empty or old, refresh.
    // A more sophisticated cache validation could be implemented here.
    if (_outdatedManga.isEmpty) {
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
      setState(() {
        _outdatedManga = List<Map<String, dynamic>>.from(decoded);
        _loading = false;
      });
    }
  }

  Future<void> _saveCache(String data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cacheKey, data);
  }

  Future<void> _refreshData({bool forceRefresh = false}) async {
    setState(() => _loading = true);
    if (forceRefresh) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cacheKey);
      setState(() {
        _outdatedManga = [];
      });
    }

    //
    final response = await http.get(Uri.parse(apiEndpoint));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);

      final result = data
          .map((item) {
            final media = item['media'];
            if (media == null) return null;

            final title =
                media['title']?['english'] ??
                media['title']?['romaji'] ??
                'No Title';
            final imageUrl = media['coverImage']?['large'] ?? '';
            final colorHex = media['coverImage']?['color'] ?? '#77DD77';
            final chaptersRead = item['progress'] ?? 0;

            double? totalChapters;
            if (media['inferredChapterCount'] != null) {
              totalChapters = media['inferredChapterCount'].toDouble();
            } else if (media['comickMatch'] != null &&
                media['comickMatch']['lastChapter'] != null) {
              totalChapters = media['comickMatch']['lastChapter'].toDouble();
            } else {
              totalChapters = chaptersRead.toDouble();
            }

            if (totalChapters == null ||
                totalChapters <= chaptersRead.toDouble()) {
              return null;
            }

            final chaptersLeft = totalChapters - chaptersRead;

            return {
              'title': title,
              'imageUrl': imageUrl,
              'color': colorHex,
              'chaptersRead': chaptersRead,
              'totalChapters': totalChapters,
              'chaptersLeft': chaptersLeft,
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      result.sort(
        (a, b) => (a['chaptersLeft'] as double).compareTo(
          b['chaptersLeft'] as double,
        ),
      );

      print('Sorted result: $result');

      await _saveCache(jsonEncode(result));

      setState(() {
        _outdatedManga = result;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
    try {} catch (e) {
      print('Error fetching data: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Up Next')),
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
              child: _outdatedManga.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 100),
                        Center(child: Text("You're up to date! 🎉")),
                      ],
                    )
                  : ListView.builder(
                      itemCount: _outdatedManga.length,
                      itemBuilder: (context, index) {
                        final manga = _outdatedManga[index];
                        final title = manga['title'] as String? ?? 'No Title';
                        final imageUrl = manga['imageUrl'] as String? ?? '';
                        final chaptersRead = manga['chaptersRead'] ?? 0.0;
                        final totalChapters = manga['totalChapters'] ?? 1.0;
                        final chaptersLeft = manga['chaptersLeft'] ?? 0.0;
                        final colorHex = manga['color'];

                        final double progressValue = (totalChapters > 0)
                            ? chaptersRead.toDouble() / totalChapters.toDouble()
                            : 0.0;

                        return MangaListItem(
                          title: title,
                          imageUrl: imageUrl,
                          chaptersRead: chaptersRead.toDouble(),
                          totalChapters: totalChapters.toDouble(),
                          chaptersLeft: chaptersLeft.toDouble(),
                          colorHex: colorHex,
                          progressValue: progressValue,
                          cleanNumber: _cleanNumber,
                        );
                      },
                    ),
            ),
    );
  }
}

class MangaListItem extends StatelessWidget {
  final String title;
  final String imageUrl;
  final double chaptersRead;
  final double totalChapters;
  final double chaptersLeft;
  final String colorHex;
  final double progressValue;
  final String Function(double, {int precision}) cleanNumber;

  const MangaListItem({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.chaptersRead,
    required this.totalChapters,
    required this.chaptersLeft,
    required this.colorHex,
    required this.progressValue,
    required this.cleanNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Color(
            int.parse(colorHex.substring(1), radix: 16) + 0xFF000000,
          ),
          width: 0.5,
        ),
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
                child: Image.network(imageUrl, fit: BoxFit.cover),
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
                          '${cleanNumber(chaptersRead)} / ${cleanNumber(totalChapters)} (${cleanNumber(chaptersLeft)} behind)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: progressValue,
                          backgroundColor: Colors.grey.shade300,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(
                              int.parse(colorHex.substring(1), radix: 16) +
                                  0xFF000000,
                            ),
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
