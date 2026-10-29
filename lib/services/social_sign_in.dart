import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../config/app_config.dart';

/// 구글·Apple 로그인 창을 띄워 ID 토큰을 받는다. 사용자가 취소하면 null.
///
/// 받은 토큰은 그대로 지도 Worker 로 보내 검증받고, 앱에는 Worker 세션만 남긴다.
class SocialSignIn {
  bool _googleReady = false;

  /// 빌드에 구글 클라이언트 ID 가 있고 이 플랫폼에서 로그인 창을 띄울 수 있는지.
  bool get googleAvailable =>
      AppConfig.hasGoogleSignIn &&
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS);

  /// Apple 로그인은 iOS 에서만 둔다. iOS 에서 구글 로그인을 넣으면 함께 있어야 한다(4.8).
  bool get appleAvailable => !kIsWeb && Platform.isIOS;

  Future<String?> google() async {
    final signIn = GoogleSignIn.instance;
    if (!_googleReady) {
      await signIn.initialize(
        clientId:
            Platform.isIOS && AppConfig.googleIosClientId.isNotEmpty
                ? AppConfig.googleIosClientId
                : null,
        serverClientId: AppConfig.googleServerClientId,
      );
      _googleReady = true;
    }
    try {
      final account = await signIn.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  Future<String?> apple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email],
      );
      return credential.identityToken;
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
  }

  /// 다음에 로그인할 때 계정을 다시 고를 수 있게 구글 쪽 로그인도 끝낸다.
  Future<void> signOut() async {
    if (_googleReady) await GoogleSignIn.instance.signOut();
  }
}
