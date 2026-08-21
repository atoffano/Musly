class ServerConfig {
  final String serverUrl;
  final String username;
  final String password;
  final bool useLegacyAuth;
  final bool allowSelfSignedCertificates;
  final List<String> selectedMusicFolderIds;
  final String? serverType;
  final String? serverVersion;
  final String?
  customCertificatePath; 
  final String?
  clientCertificatePath; 
  final String?
  clientCertificatePassword;
  final String? name;

  ServerConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.useLegacyAuth = false,
    this.allowSelfSignedCertificates = false,
    this.selectedMusicFolderIds = const [],
    this.serverType,
    this.serverVersion,
    this.customCertificatePath,
    this.clientCertificatePath,
    this.clientCertificatePassword,
    this.name,
  });

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      serverUrl: json['serverUrl'] ?? '',
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      useLegacyAuth: json['useLegacyAuth'] ?? false,
      allowSelfSignedCertificates: json['allowSelfSignedCertificates'] ?? false,
      selectedMusicFolderIds:
          (json['selectedMusicFolderIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      serverType: json['serverType'],
      serverVersion: json['serverVersion'],
      customCertificatePath: json['customCertificatePath'],
      clientCertificatePath: json['clientCertificatePath'],
      clientCertificatePassword: json['clientCertificatePassword'],
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serverUrl': serverUrl,
      'username': username,
      'password': password,
      'useLegacyAuth': useLegacyAuth,
      'allowSelfSignedCertificates': allowSelfSignedCertificates,
      'selectedMusicFolderIds': selectedMusicFolderIds,
      'serverType': serverType,
      'serverVersion': serverVersion,
      'customCertificatePath': customCertificatePath,
      'clientCertificatePath': clientCertificatePath,
      'clientCertificatePassword': clientCertificatePassword,
      'name': name,
    };
  }

  ServerConfig copyWith({
    String? serverUrl,
    String? username,
    String? password,
    bool? useLegacyAuth,
    bool? allowSelfSignedCertificates,
    List<String>? selectedMusicFolderIds,
    String? serverType,
    String? serverVersion,
    String? customCertificatePath,
    String? clientCertificatePath,
    String? clientCertificatePassword,
    String? name,
  }) {
    return ServerConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      useLegacyAuth: useLegacyAuth ?? this.useLegacyAuth,
      allowSelfSignedCertificates:
          allowSelfSignedCertificates ?? this.allowSelfSignedCertificates,
      selectedMusicFolderIds:
          selectedMusicFolderIds ?? this.selectedMusicFolderIds,
      serverType: serverType ?? this.serverType,
      serverVersion: serverVersion ?? this.serverVersion,
      customCertificatePath:
          customCertificatePath ?? this.customCertificatePath,
      clientCertificatePath:
          clientCertificatePath ?? this.clientCertificatePath,
      clientCertificatePassword:
          clientCertificatePassword ?? this.clientCertificatePassword,
      name: name ?? this.name,
    );
  }

  String get normalizedUrl {
    String url = serverUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  String? get bridgeUrl {
    if (serverUrl.isEmpty) return null;
    try {
      final uri = Uri.parse(normalizedUrl);
      if (uri.host.isEmpty) return null;
      return '${uri.scheme}://${uri.host}:8788';
    } catch (_) {
      return null;
    }
  }

  bool get isValid {
    return serverUrl.isNotEmpty && username.isNotEmpty && password.isNotEmpty;
  }
}
