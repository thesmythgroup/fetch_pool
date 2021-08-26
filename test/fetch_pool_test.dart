import 'dart:convert';
import 'dart:io';

import 'package:fetch_pool/fetch_pool.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Fetch Pool', () {

    final imageGifBytes = base64Decode('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7');
    String destinationDir = './__fetch_pool_test_images';

    tearDown(() async {
      // Clean up files
      final dir = Directory(destinationDir);
      if (dir.existsSync()) {
        dir.delete(recursive: true);
      }
    });

    test('filenameFromUrl', () {
      final url = 'https://test.com/img.png';
      final urlWithQuery = 'https://test.com/img.png?a=123&b=456';
      final urlWithoutExtension = 'https://test.com/img';
      final urlWithoutExtensionWithQuery = 'https://test.com/img?a=123&b=456';

      // basename (default)
      expect(FetchPool.filenameFromUrl(url), 'img.png');
      expect(FetchPool.filenameFromUrl(urlWithQuery), 'img.png');
      expect(FetchPool.filenameFromUrl(urlWithoutExtension), 'img');
      expect(FetchPool.filenameFromUrl(urlWithoutExtensionWithQuery), 'img');

      // basenameWithQueryParams
      expect(FetchPool.filenameFromUrl(url, FetchPoolFileNamingStrategy.basenameWithQueryParams), 'img.png');
      expect(FetchPool.filenameFromUrl(urlWithQuery, FetchPoolFileNamingStrategy.basenameWithQueryParams), 'img_a_123_b_456.png');
      expect(FetchPool.filenameFromUrl(urlWithoutExtension, FetchPoolFileNamingStrategy.basenameWithQueryParams), 'img');
      expect(FetchPool.filenameFromUrl(urlWithoutExtensionWithQuery, FetchPoolFileNamingStrategy.basenameWithQueryParams), 'img_a_123_b_456');

      // base64EncodedUrl
      expect(FetchPool.filenameFromUrl(url, FetchPoolFileNamingStrategy.base64EncodedUrl), 'aHR0cHM6Ly90ZXN0LmNvbS9pbWcucG5n');
      expect(FetchPool.filenameFromUrl(urlWithQuery, FetchPoolFileNamingStrategy.base64EncodedUrl), 'aHR0cHM6Ly90ZXN0LmNvbS9pbWcucG5nP2E9MTIzJmI9NDU2');
      expect(FetchPool.filenameFromUrl(urlWithoutExtension, FetchPoolFileNamingStrategy.base64EncodedUrl), 'aHR0cHM6Ly90ZXN0LmNvbS9pbWc=');
      expect(FetchPool.filenameFromUrl(urlWithoutExtensionWithQuery, FetchPoolFileNamingStrategy.base64EncodedUrl), 'aHR0cHM6Ly90ZXN0LmNvbS9pbWc_YT0xMjMmYj00NTY=');
    });

    test('Single Image', () async {
      final expectedDestinationPath = p.join(destinationDir, 'image.png');
      final fetchPool = FetchPool(maxConcurrent: 2, urls: ['http://example.com/image.png'], destinationDirectory: destinationDir);
      fetchPool.client = MockClient((request) async {
        return Response.bytes(imageGifBytes, 200);
      });

      final results = await fetchPool.fetch();
      expect(results.length, 1);
      expect(results.keys.first, 'http://example.com/image.png');
      final firstResult = results.values.first;
      expect(firstResult.url, 'http://example.com/image.png');
      expect(firstResult.error, null);
      expect(firstResult.localPath, expectedDestinationPath);

      List<FileSystemEntity> entries = Directory(destinationDir).listSync(recursive: false).toList();
      expect(entries.length, 1);
      expect(entries.first.path, expectedDestinationPath);
    });

    test('Multiple Images', () async {
      final urls = List.generate(50, (index) => 'http://example.com/image$index.png');
      final fetchPool = FetchPool(maxConcurrent: 5, urls: urls, destinationDirectory: destinationDir);
      fetchPool.client = MockClient((request) async {
        return Response.bytes(imageGifBytes, 200);
      });

      final results = await fetchPool.fetch();
      expect(results.length, urls.length);
      for (var url in urls) {
        final expectedDestinationPath = p.join(destinationDir, p.basename(url));
        final result = results[url];

        expect(result != null, true);
        expect(result!.url, url);
        expect(result.localPath, expectedDestinationPath);
      }

      List<FileSystemEntity> entries = Directory(destinationDir).listSync(recursive: false).toList();
      expect(entries.length, urls.length);
    });

    test('Multiple Images With Some Errors', () async {
      final urls = List.generate(50, (index) => 'http://example.com/image$index.png');
      final fetchPool = FetchPool(maxConcurrent: 5, urls: urls, destinationDirectory: destinationDir);
      fetchPool.client = MockClient((request) async {
        final filename = p.basename(request.url.path);

        if (filename == 'image10.png' || filename == 'image30.png') {
          return Response('Not found', 404); 
        } else if (filename == 'image40.png') {
          return Response('Internal Server Error', 500); 
        } else {
          return Response.bytes(imageGifBytes, 200); 
        }
      });

      final results = await fetchPool.fetch();
      expect(results.length, urls.length);
      for (var url in urls) {
        final filename = p.basename(url);
        final expectedDestinationPath = p.join(destinationDir, filename);
        final result = results[url];

        expect(result != null, true);
        expect(result!.url, url);

        if (filename == 'image10.png' || filename == 'image30.png') {
          expect(result.localPath, null);
          expect(result.error, 'Status 404');
          expect(result.isSuccess, false);
        } else if (filename == 'image40.png') {
          expect(result.localPath, null);
          expect(result.error, 'Status 500');
          expect(result.isSuccess, false);
        } else {
          expect(result.localPath, expectedDestinationPath);
          expect(result.error, null);
          expect(result.isSuccess, true);
        }
      }

      List<FileSystemEntity> entries = Directory(destinationDir).listSync(recursive: false).toList();
      expect(entries.length, urls.length - 3);
    });

    test('Local filenames with basename fileNamingStrategy (default)', () async {
      final urls = List.generate(10, (index) => 'http://example.com/image$index.png?v=123&p=456');
      final fetchPool = FetchPool(
        maxConcurrent: 5,
        urls: urls,
        destinationDirectory: destinationDir
      );
      fetchPool.client = MockClient((request) async {
        return Response.bytes(imageGifBytes, 200);
      });

      final results = await fetchPool.fetch();
      final List<String> destinationPaths = [];
      expect(results.length, urls.length);

      for (var urlString in urls) {
        final url = Uri.parse(urlString);
        final expectedDestinationPath = p.join(destinationDir, p.basename(url.path));
        final result = results[urlString];

        destinationPaths.add(expectedDestinationPath);

        expect(result != null, true);
        expect(result!.url, urlString);
        expect(result.localPath, expectedDestinationPath);
      }

      List<FileSystemEntity> entries = Directory(destinationDir).listSync(recursive: false).toList();
      expect(entries.length, urls.length);

      for (var element in entries) {
        expect(destinationPaths.contains(element.path), true);
      }
    });

    test('Local filenames with basenameWithQueryParams fileNamingStrategy', () async {
      final urls = List.generate(10, (index) => 'http://example.com/image$index.png?v=123&p=456');
      final fetchPool = FetchPool(
        maxConcurrent: 5,
        urls: urls,
        destinationDirectory: destinationDir,
        fileNamingStrategy: FetchPoolFileNamingStrategy.basenameWithQueryParams
      );
      fetchPool.client = MockClient((request) async {
        return Response.bytes(imageGifBytes, 200);
      });

      final results = await fetchPool.fetch();
      final List<String> destinationPaths = [];
      expect(results.length, urls.length);

      for (var urlString in urls) {
        final url = Uri.parse(urlString);
        final basenameWithoutExt = p.basenameWithoutExtension(url.path);
        final extension = p.extension(url.path);
        final expectedDestinationPath = p.join(destinationDir, '${basenameWithoutExt}_v_123_p_456$extension');
        final result = results[urlString];

        destinationPaths.add(expectedDestinationPath);

        expect(result != null, true);
        expect(result!.url, urlString);
        expect(result.localPath, expectedDestinationPath);
      }

      List<FileSystemEntity> entries = Directory(destinationDir).listSync(recursive: false).toList();
      expect(entries.length, urls.length);

      for (var element in entries) {
        expect(destinationPaths.contains(element.path), true);
      }
    });

    test('Local filenames with base64EncodedUrl fileNamingStrategy', () async {
      final urls = List.generate(10, (index) => 'http://example.com/image$index.png?v=123&p=456');
      final fetchPool = FetchPool(
        maxConcurrent: 5,
        urls: urls,
        destinationDirectory: destinationDir,
        fileNamingStrategy: FetchPoolFileNamingStrategy.base64EncodedUrl
      );
      fetchPool.client = MockClient((request) async {
        return Response.bytes(imageGifBytes, 200);
      });

      final results = await fetchPool.fetch();
      final List<String> destinationPaths = [];
      expect(results.length, urls.length);

      for (var urlString in urls) {
        final base64EncodedUrl = base64Url.encode(utf8.encode(urlString));
        final expectedDestinationPath = p.join(destinationDir, base64EncodedUrl);
        final result = results[urlString];

        destinationPaths.add(expectedDestinationPath);

        expect(result != null, true);
        expect(result!.url, urlString);
        expect(result.localPath, expectedDestinationPath);
      }

      List<FileSystemEntity> entries = Directory(destinationDir).listSync(recursive: false).toList();
      expect(entries.length, urls.length);

      for (var element in entries) {
        expect(destinationPaths.contains(element.path), true);
      }
    });

    test('Total Progress Callback', () async {
      final urls = List.generate(50, (index) => 'http://example.com/image$index.png');
      final fetchPool = FetchPool(maxConcurrent: 5, urls: urls, destinationDirectory: destinationDir);
      fetchPool.client = MockClient((request) async {
        final filename = p.basename(request.url.path);

        if (filename == 'image10.png' || filename == 'image30.png') {
          return Response('Not found', 404); 
        } else if (filename == 'image40.png') {
          return Response('Internal Server Error', 500); 
        } else {
          return Response.bytes(imageGifBytes, 200); 
        }
      });

      var progressInvocationCount = 0;
      double lastProgress = -1;
      await fetchPool.fetch(progressCallback: (progress) {
        expect(progress >= 0, true);
        expect(progress <= 100, true);
        expect(progress > lastProgress, true);
        lastProgress = progress;
        progressInvocationCount += 1;
      });

      expect(lastProgress, 100);
      expect(progressInvocationCount >= urls.length, true);
    });

    test('Ensure maxConcurrent is greater than 0', () async {
      expect(() => FetchPool(maxConcurrent: 0, urls: [], destinationDirectory: '.'), throwsArgumentError);
      expect(() => FetchPool(maxConcurrent: -1, urls: [], destinationDirectory: '.'), throwsArgumentError);
    });

    test('Ensure destinationDirectory is not empty', () async {
      expect(() => FetchPool(maxConcurrent: 1, urls: [], destinationDirectory: ''), throwsArgumentError);
      expect(() => FetchPool(maxConcurrent: 1, urls: [], destinationDirectory: '       '), throwsArgumentError);
    });

    test('Ensure the fetch method cannot be called twice', () async {
      final fetchPool = FetchPool(maxConcurrent: 2, urls: ['http://example.com/image.png'], destinationDirectory: destinationDir);
      fetchPool.client = MockClient((request) async {
        return Response.bytes(imageGifBytes, 200);
      });

      await fetchPool.fetch();
      
      // Calling fetch a second time should fail
      expect(() async => await fetchPool.fetch(), throwsStateError);
    });


    
  });
}
