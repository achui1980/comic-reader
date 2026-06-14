enum HttpMethod { get, post }

class FetchConfig {
  final String url;
  final HttpMethod method;
  final Map<String, String>? headers;
  final Map<String, dynamic>? queryParameters;
  final dynamic body;
  final Duration? timeout;

  const FetchConfig({
    required this.url,
    this.method = HttpMethod.get,
    this.headers,
    this.queryParameters,
    this.body,
    this.timeout,
  });
}
