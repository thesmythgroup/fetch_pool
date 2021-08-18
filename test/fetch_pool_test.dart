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

    setUp(() {
      
    });

    tearDown(() async {
      // Clean up files
      Directory(destinationDir).delete(recursive: true);
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
          return Response("Not found", 404); 
        } else if (filename == 'image40.png') {
          return Response("Internal Server Error", 500); 
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

    test('Ensure maxConcurrent is greater than 0', () async {
      expect(() => FetchPool(maxConcurrent: 0, urls: [], destinationDirectory: "."), throwsArgumentError);
      expect(() => FetchPool(maxConcurrent: -1, urls: [], destinationDirectory: "."), throwsArgumentError);
    });

    test('Ensure destinationDirectory is not empty', () async {
      expect(() => FetchPool(maxConcurrent: 1, urls: [], destinationDirectory: ""), throwsArgumentError);
      expect(() => FetchPool(maxConcurrent: 1, urls: [], destinationDirectory: "       "), throwsArgumentError);
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
