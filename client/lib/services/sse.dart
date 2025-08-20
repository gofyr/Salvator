import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SseClient {
  final String url;
  final String? accessToken;
  final String? clientKey;
  final HttpClient Function() httpClientFactory;

  SseClient({
    required this.url,
    required this.httpClientFactory,
    this.accessToken,
    this.clientKey,
  });

  Stream<Map<String, dynamic>> connect() async* {
    final client = httpClientFactory();
    final uri = Uri.parse(url);
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    if (clientKey != null) req.headers.set('X-Client-Key', clientKey!);
    if (accessToken != null)
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw HttpException('SSE failed ${resp.statusCode}');
    }
    final controller = StreamController<Map<String, dynamic>>();
    final lines = resp.transform(utf8.decoder).transform(const LineSplitter());
    String? dataBuffer;
    late final StreamSubscription sub;
    sub = lines.listen(
      (line) {
        if (line.startsWith('data:')) {
          dataBuffer = (dataBuffer ?? '') + line.substring(5).trim();
        } else if (line.isEmpty) {
          if (dataBuffer != null) {
            try {
              final map = jsonDecode(dataBuffer!) as Map<String, dynamic>;
              controller.add(map);
            } catch (e) {
              // ignore parse errors silently in release
            }
            dataBuffer = null;
          }
        }
      },
      onDone: () => controller.close(),
      onError: (e, st) {
        controller.addError(e, st);
        controller.close();
      },
    );
    controller.onCancel = () async {
      await sub.cancel();
    };
    yield* controller.stream;
  }
}
