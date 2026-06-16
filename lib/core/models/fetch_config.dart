enum HttpMethod { get, post }

class FetchConfig {
  final String url;
  final HttpMethod method;
  final Map<String, String>? headers;
  final Map<String, dynamic>? queryParameters;
  final dynamic body;
  final Duration? timeout;
  final Map<String, dynamic>? extra;

  const FetchConfig({
    required this.url,
    this.method = HttpMethod.get,
    this.headers,
    this.queryParameters,
    this.body,
    this.timeout,
    this.extra,
  });

  FetchConfig copyWith({
    String? url,
    HttpMethod? method,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    dynamic body,
    Duration? timeout,
    Map<String, dynamic>? extra,
  }) {
    return FetchConfig(
      url: url ?? this.url,
      method: method ?? this.method,
      headers: headers ?? this.headers,
      queryParameters: queryParameters ?? this.queryParameters,
      body: body ?? this.body,
      timeout: timeout ?? this.timeout,
      extra: extra ?? this.extra,
    );
  }
}
