import 'parse.dart';

/// `POST /dev/login` response. The token is kept in memory only (SPEC §9).
class AuthToken {
  const AuthToken({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
  });

  final String accessToken;
  final String tokenType;
  final int expiresIn;

  factory AuthToken.fromJson(Map<String, Object?> json) => AuthToken(
    accessToken: asString(json['access_token']),
    tokenType: asString(json['token_type'], 'bearer'),
    expiresIn: asInt(json['expires_in'], 86400),
  );
}
