# FetchPool

A library to easily and asynchronously download a list of URLs in parallel, using a given
maximum number of concurrent connections. This lets you download a list of hundreds of files,
while only ever downloading a few at the same time.

[![Pub](https://img.shields.io/pub/v/fetch_pool.svg)](https://pub.dartlang.org/packages/fetch_pool)
[![Tests](https://github.com/thesmythgroup/fetch_pool/actions/workflows/dart.yml/badge.svg)](https://github.com/thesmythgroup/fetch_pool/actions/workflows/dart.yml)

## Usage

A simple usage example:

```dart
import 'package:fetch_pool/fetch_pool.dart';

main() {
  const urls = [
    "https://picsum.photos/id/0/5616/3744",
    "https://picsum.photos/id/1/5616/3744",
    "https://some.invalid.url/to/simulate/an/error", // intentional
    "https://picsum.photos/id/1001/5616/3744",
    "https://picsum.photos/id/1002/4312/2868",
    "https://picsum.photos/id/1003/1181/1772",
    "https://picsum.photos/id/1004/5616/3744",
    "https://picsum.photos/id/1005/5760/3840",
  ];

  final pool = FetchPool(maxConcurrent: 2, urls: urls, destinationDirectory: "./deep/path/to/images");
  final results = await pool.fetch(progressCallback: (progress) {
    print('Total progress: $progress');
  });

  results.forEach((url, result) {
    if (result.isSuccess) {
      print('SUCCESS: ${url} > ${result.localPath}');
    } else {
      print('FAILURE: ${url} > ${result.error}');
    }
  });
}
```

The above code will try to download the list of URLs to the given `destinationDirectory`. It will use a
maximum of two concurrent connections and report on the total progress using the given `progressCallback`.

By default, the downloaded files will be named using the `FetchPoolFileNamingStrategy.basename` strategy.
That means that a URL like `https://test.com/img.png?a=123&b=456` will result in a local filename of `img.png`.
Using `basenameWithQueryParams` would result in `img_a_123_b_456.png`.
Using `base64EncodedUrl` base64 encodes the whole URL and would result in a local filename of `aHR0cHM6Ly90ZXN0LmNvbS9pbWcucG5nP2E9MTIzJmI9NDU2`.

By default, the `FetchPoolFileOverwritingStrategy.overwrite` strategy is used. That means that any existing files of the same name in the `destinationDirectory` will be overwritten. Using the `FetchPoolFileOverwritingStrategy.skip` strategy will skip existing files and not even attempt to download them. The `FetchPoolResult` object for each requested URL has a `persistenceResult` property that indicates if/how the file was persisted (`saved`, `overwritten`, or `skipped`).

## Credits

FetchPool is a project by [TSG](https://thesmythgroup.com/), a full-service digital agency taking software from concept to launch.
Our powerhouse team of designers and engineers build iOS, Android, and web apps across many industries.
