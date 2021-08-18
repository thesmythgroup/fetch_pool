import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pool/pool.dart';
import 'package:path/path.dart' as p;

/// Result of fetching a single URL
class FetchPoolResult {
  /// URL that was (attempted to be) fetched
  final String url;
  /// Local path the URL was downloaded to
  final String? localPath;
  /// Error in case of failure
  final Object? error;

  /// Indicates whether fetching was successful
  bool get isSuccess {
    return error == null;
  }
  
  /// Create a new instance
  FetchPoolResult({ required this.url, this.localPath, this.error });
}

/// Class used to fetch a list of URLs in parallel, only using a set number
/// of operations in parallel.
class FetchPool {
  /// Max number of concurrent operations (downloads)
  final int maxConcurrent;
  /// Destination download directory
  final String destinationDirectory;
  /// List of URLs to download
  final List<String> urls;
  /// Results keyed by the URL string
  final Map<String, FetchPoolResult> resultsByUrl = {};
  var _hasFetchBeenRun = false;
  /// The HTTP client to use
  /// 
  /// This should usually only need to be changed for unit testing.
  http.Client client = http.Client();

  /// Creates a new instance allowing [maxConcurrent] parallel downloads
  /// 
  /// If [destinationDirectory] doesn't exist, it will be created.
  FetchPool({required this.maxConcurrent, required this.urls, required this.destinationDirectory}) {
    if (maxConcurrent < 1) {
      throw ArgumentError.value(maxConcurrent, 'maxConcurrent', 'The maxConcurrent value must be greater than 0.');
    }

    if (destinationDirectory.trim().isEmpty) {
      throw ArgumentError.value(destinationDirectory, 'destinationDirectory', 'The destinationDirectory must not be empty.');
    }
  }

  /// Starts fetching the list of URLs
  /// 
  /// Returns a [Future] with the map of results, keyed by each URL.
  /// This method is only allowed to be called once on a [FetchPool] instance.
  /// If you need to repeat a fetch, you need to create a fresh instance.
  Future<Map<String, FetchPoolResult>> fetch() async {
    if (_hasFetchBeenRun) {
      throw StateError('It is illegal to run fetch more than once on the same instance.');
    }

    _hasFetchBeenRun = true;

    var pool = Pool(maxConcurrent);
    final uniqueUrls = urls.toSet().toList();

    var poolStream = pool.forEach<String, FetchPoolResult>(uniqueUrls, (urlString) async {
      final url = Uri.parse(urlString);
      String filename = p.basename(url.path);
      String destinationPath = p.join(destinationDirectory, filename);

      final request = http.Request('GET', url);
      final http.StreamedResponse response = await client.send(request);

      if (response.statusCode == HttpStatus.ok) {
        File destinationFile = await File(destinationPath).create(recursive: true);
        await response.stream.pipe(destinationFile.openWrite());

        return FetchPoolResult(url: urlString, localPath: destinationPath);
      } else {
        return FetchPoolResult(url: urlString, error: 'Status ${response.statusCode}');
      }
    }, onError: (urlString, error, stackTrace) {
      resultsByUrl[urlString] = FetchPoolResult(url: urlString, error: error);

      /// Do not return the error to the output stream
      return false;
    });

    await for (var result in poolStream) {
      resultsByUrl[result.url] = result;
    }

    return resultsByUrl;
  }
}
