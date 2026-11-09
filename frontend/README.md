# DormN Flutter

## Supabase 설정

Supabase Project URL과 Publishable Key는 소스에 저장하지 않고 Dart define으로 전달한다.

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

## Kakao 로그인 설정

1. Kakao Developers에서 앱을 만든다.
2. Kakao Login Redirect URI에 Supabase의 callback URL을 등록한다.
3. Supabase Dashboard의 Authentication > Providers > Kakao에서 Client ID와 Client Secret을 등록한다.
4. Supabase Authentication URL Configuration에 다음 redirect URL을 등록한다.

```text
io.dormn.app://login-callback
```

앱은 `OAuthProvider.kakao`로 Supabase Auth OAuth 흐름을 시작한다.
