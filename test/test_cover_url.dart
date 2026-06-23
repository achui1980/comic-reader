import 'package:comic_reader/data/sources/wu55comic_decoder.dart';

void main() {
  final urls = Wu55ComicDecoder.buildShardUrls('https://bmigmij-wuwu.sqxxov.com/break_2/static/upload/book/5312/cover_pc.jpg');
  print('shard0: ${urls[0]}');
  print('shard1: ${urls[1]}');
}
