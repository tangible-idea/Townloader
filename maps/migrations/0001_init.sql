-- 로그인한 사람. 같은 사람이라도 구글과 Apple 은 다른 계정으로 본다.
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  provider TEXT NOT NULL,
  subject TEXT NOT NULL,
  email TEXT,
  created_at INTEGER NOT NULL,
  UNIQUE (provider, subject)
);

-- 앱이 들고 있는 세션 토큰의 SHA-256. 토큰 원문은 저장하지 않는다.
CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX sessions_user ON sessions (user_id);

-- 앱의 links.json 과 같은 모양({categories, links})을 통째로 둔다.
CREATE TABLE user_data (
  user_id TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  data TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- 공개한 카테고리. 여기 있으면 public, 지우면 다시 비공개다.
CREATE TABLE shares (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (user_id, category)
);
