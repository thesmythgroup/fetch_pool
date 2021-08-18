# FetchPool

A library to help you easily asynchronously download lists of URLs in parallel, using a given
number of parallel connections. You could for example download a list of 100 images, while only
ever downloading four images concurrently.

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
  final results = await pool.fetch();

  results.forEach((url, result) {
    if (result.isSuccess) {
      print('SUCCESS: ${url} > ${result.localPath}');
    } else {
      print('FAILURE: ${url} > ${result.error}');
    }
  });
}
```
