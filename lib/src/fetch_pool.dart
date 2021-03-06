import 'dart:convert';
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

  /// Local persistence result
  /// Was the file simply saved, overwritten, or skipped?
  final FetchPoolFilePersistenceResult? persistenceResult;

  /// Error in case of failure
  final Object? error;

  /// Indicates whether fetching was successful
  bool get isSuccess {
    return error == null;
  }

  /// Create a new instance
  FetchPoolResult(
      {required this.url, this.localPath, this.persistenceResult, this.error});
}

/// Enum describing the different file naming strategies.
enum FetchPoolFileNamingStrategy {
  /// Given a URL of https://test.com/img.png?a=123&b=456,
  /// results in a local filename of "img.png".
  basename,

  /// Given a URL of https://test.com/img.png?a=123&b=456,
  /// results in a local filename of "img_a_123_b_456.png".
  basenameWithQueryParams,

  /// Given a URL of https://test.com/img.png?a=123&b=456,
  /// results in a local filename of "aHR0cHM6Ly90ZXN0LmNvbS9pbWcucG5nP2E9MTIzJmI9NDU2".
  base64EncodedUrl
}

/// Enum describing the different file persistence results.
enum FetchPoolFilePersistenceResult {
  /// If the file didn't already exist in the target directory and was saved
  saved,

  /// If the file already existed in the target directory and was overwritten
  overwritten,

  /// If the file already existed in the target directory and was skipped
  skipped
}

/// Enum describing the different file overwriting strategies.
enum FetchPoolFileOverwritingStrategy {
  /// If the file already exists in the target directory, overwrite it
  overwrite,

  /// If the file already exists in the target directory, don't download it
  skip
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

  /// Indicates how the local filename should be named. Defaults to [basename].
  final FetchPoolFileNamingStrategy fileNamingStrategy;

  /// Indicates how to handle files of the same name that already exist in the
  /// target directory. Defaults to [overwrite].
  final FetchPoolFileOverwritingStrategy fileOverwritingStrategy;

  /// Used to prevent `fetch` from being called twice
  var _hasFetchBeenRun = false;

  /// The HTTP client to use
  ///
  /// This should usually only need to be changed for unit testing.
  http.Client client = http.Client();

  /// Creates a new instance allowing [maxConcurrent] parallel downloads
  ///
  /// If [destinationDirectory] doesn't exist, it will be created.
  FetchPool(
      {required this.maxConcurrent,
      required this.urls,
      required this.destinationDirectory,
      this.fileNamingStrategy = FetchPoolFileNamingStrategy.basename,
      this.fileOverwritingStrategy =
          FetchPoolFileOverwritingStrategy.overwrite}) {
    if (maxConcurrent < 1) {
      throw ArgumentError.value(maxConcurrent, 'maxConcurrent',
          'The maxConcurrent value must be greater than 0.');
    }

    if (destinationDirectory.trim().isEmpty) {
      throw ArgumentError.value(destinationDirectory, 'destinationDirectory',
          'The destinationDirectory must not be empty.');
    }
  }

  /// Convert the given Url string to a local filename, applying the given naming strategy
  ///
  /// See [FetchPoolFileNamingStrategy] for details.
  static String filenameFromUrl(String urlString,
      [FetchPoolFileNamingStrategy fileNamingStrategy =
          FetchPoolFileNamingStrategy.basename]) {
    final url = Uri.parse(urlString);
    switch (fileNamingStrategy) {
      case FetchPoolFileNamingStrategy.basename:
        return p.basename(url.path);
      case FetchPoolFileNamingStrategy.basenameWithQueryParams:
        final basenameWithoutExt = p.basenameWithoutExtension(url.path);
        final extension = p.extension(url.path);
        final convertedQueryString =
            '${url.hasQuery ? '_' : ''}${url.query.replaceAll(RegExp('&|=|\\?'), '_')}';
        return '$basenameWithoutExt$convertedQueryString$extension';
      case FetchPoolFileNamingStrategy.base64EncodedUrl:
        final bytes = utf8.encode(urlString);
        return base64Url.encode(bytes);
    }
  }

  /// Starts fetching the list of URLs
  ///
  /// Returns a [Future] with the map of results, keyed by each URL.
  /// This method is only allowed to be called once on a [FetchPool] instance.
  /// If you need to repeat a fetch, you need to create a fresh instance.
  ///
  /// A [progressCallback] function can optionally be passed in. It will
  /// be called repeatedly to report on the overall estimated progress. The progress
  /// is not calculated by the overall combined download size of all URLs (since
  /// that would require a roundtrip to the server for each URL before even beginning
  /// the download). Instead, the progress mainly reports the percentage of completed
  /// downloads plus the download percentage of active downloads.
  Future<Map<String, FetchPoolResult>> fetch(
      {Function(double)? progressCallback}) async {
    if (_hasFetchBeenRun) {
      throw StateError(
          'It is illegal to run fetch more than once on the same instance.');
    }

    _hasFetchBeenRun = true;

    var pool = Pool(maxConcurrent);
    final uniqueUrls = urls.toSet().toList();
    final Map<String, double> activeJobs = {};
    var completedJobCount = 0;
    double lastTotalProgress = 0;

    void notifyProgressCallback() {
      if (progressCallback != null) {
        final combinedActivePercentage =
            activeJobs.values.fold<double>(0, (sum, percent) => sum + percent);
        final activeJobFraction = activeJobs.isNotEmpty
            ? (activeJobs.length *
                (combinedActivePercentage / (activeJobs.length * 100)))
            : 0;
        final completedJobFraction = completedJobCount + activeJobFraction;
        final totalProgress = (completedJobFraction / uniqueUrls.length) * 100;

        if (totalProgress != lastTotalProgress) {
          progressCallback(totalProgress);
          lastTotalProgress = totalProgress;
        }
      }
    }

    var poolStream =
        pool.forEach<String, FetchPoolResult>(uniqueUrls, (urlString) async {
      final url = Uri.parse(urlString);
      final String filename = filenameFromUrl(urlString, fileNamingStrategy);
      final String destinationPath = p.join(destinationDirectory, filename);
      final File destinationFile = File(destinationPath);
      final bool destinationFileExists = await destinationFile.exists();
      FetchPoolResult result;

      double calculateProgress(int downloadedByteCount, int? contentLength) {
        if (contentLength != null && contentLength > 0) {
          return (downloadedByteCount / contentLength) * 100;
        }

        return 0;
      }

      activeJobs[urlString] = 0;

      if (fileOverwritingStrategy == FetchPoolFileOverwritingStrategy.skip &&
          destinationFileExists) {
        result = FetchPoolResult(
            url: urlString,
            localPath: destinationPath,
            persistenceResult: FetchPoolFilePersistenceResult.skipped);
      } else {
        final request = http.Request('GET', url);
        final http.StreamedResponse response = await client.send(request);

        if (response.statusCode == HttpStatus.ok) {
          await destinationFile.create(recursive: true);

          IOSink destinationFileWriteStream = destinationFile.openWrite();
          int downloadedByteCount = 0;

          await response.stream.listen((List<int> chunk) {
            // Display percentage of completion
            final percentage =
                calculateProgress(downloadedByteCount, response.contentLength);
            activeJobs[urlString] = percentage;
            notifyProgressCallback();

            destinationFileWriteStream.add(chunk);
            downloadedByteCount += chunk.length;
          }).asFuture();

          // Display percentage of completion
          final percentage =
              calculateProgress(downloadedByteCount, response.contentLength);
          activeJobs[urlString] = percentage;
          notifyProgressCallback();

          // Close the stream
          await destinationFileWriteStream.close();

          result = FetchPoolResult(
              url: urlString,
              localPath: destinationPath,
              persistenceResult: destinationFileExists
                  ? FetchPoolFilePersistenceResult.overwritten
                  : FetchPoolFilePersistenceResult.saved);
        } else {
          result = FetchPoolResult(
              url: urlString, error: 'Status ${response.statusCode}');
        }
      }

      activeJobs.remove(urlString);
      completedJobCount += 1;

      notifyProgressCallback();

      return result;
    }, onError: (urlString, error, stackTrace) {
      resultsByUrl[urlString] = FetchPoolResult(url: urlString, error: error);

      activeJobs.remove(urlString);
      completedJobCount += 1;

      notifyProgressCallback();

      /// Do not return the error to the output stream
      return false;
    });

    await for (var result in poolStream) {
      resultsByUrl[result.url] = result;
    }

    return resultsByUrl;
  }
}
