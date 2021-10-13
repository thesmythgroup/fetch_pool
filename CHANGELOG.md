# FetchPool Changelog

## 1.0.1

- Add `fileOverwritingStrategy` option of either `overwrite` (default) or `skip`. This enables a basic way to deal with the case that the destination file already exists on disk. The `FetchPoolResult` class has a new corresponding `persistenceResult` property of either `saved`, `overwritten`, or `skipped`.

## 1.0.0

- Initial version.
