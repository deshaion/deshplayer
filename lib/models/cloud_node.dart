class CloudNode {
  final String path;
  final String name;
  final bool isDir;
  final String? mimeType;
  final int? size;
  final String? downloadUrl; // some providers give this upfront
  final String? md5;
  final String? sha1;
  final String? sha256;

  CloudNode({
    required this.path,
    required this.name,
    required this.isDir,
    this.mimeType,
    this.size,
    this.downloadUrl,
    this.md5,
    this.sha1,
    this.sha256,
  });
}
