# 자주 쓰는 Flutter 명령 모음.
#
# 키를 빌드에 심는 `--dart-define-from-file` 을 매번 타이핑하지 않으려고 둔다.
# .env.json 이 없으면 플래그 없이 실행하므로, 키 없이 클론한 사람도 그대로 쓸 수 있다.
#
#   make run                 연결된 기기 중 하나로 실행
#   make run DEVICE=macos    기기 지정
#   make ios                 실제 iPhone/iPad에 Release 빌드·설치·실행
#   make ios DEVICE=<ID>     여러 실기기 중 하나 지정
#   make macos               macOS에서 실행
#   make devices             기기 목록과 ID 확인
#   make test / make analyze
#   make ipa / make apk / make aab   릴리스 빌드

ENV_FILE ?= .env.json
DEFINES  := $(if $(wildcard $(ENV_FILE)),--dart-define-from-file=$(ENV_FILE),)

DEVICE     ?=
DEVICE_ARG := $(if $(DEVICE),-d $(DEVICE),)

.PHONY: run ios macos devices test analyze ipa apk aab ipa-internal apk-internal env-check

run:
	flutter run $(DEFINES) $(DEVICE_ARG)

ios:
	python3 scripts/run_ios.py --device "$(DEVICE)" --env-file "$(ENV_FILE)"

macos:
	$(MAKE) run DEVICE=macos

devices:
	flutter devices

test:
	flutter test $(DEFINES)

analyze:
	flutter analyze

# 스토어 배포용은 키를 심지 않는다. 배포본에 심은 키는 바이너리에서 추출할 수
# 있고 HikerAPI 는 호출 건수로 과금하므로, 공개 배포본에 키가 들어가면 크레딧이
# 그대로 소진된다. 사용자는 설정 화면에서 자기 키를 넣는다.
ipa:
	flutter build ipa

apk:
	flutter build apk

# Play 업로드용. android/key.properties 의 업로드 키로 서명한다.
aab:
	flutter build appbundle $(DEFINES)

# 키를 심은 빌드. 내부 테스터에게만 돌릴 때 쓴다.
# 받은 사람이 IPA 를 뜯으면 키를 꺼낼 수 있다는 점을 알고 쓸 것.
ipa-internal:
	flutter build ipa $(DEFINES)

apk-internal:
	flutter build apk $(DEFINES)

# 키가 심긴 채로 빌드되는지 확인만 한다. 값 자체는 출력하지 않는다.
env-check:
	@if [ -f $(ENV_FILE) ]; then \
		echo "$(ENV_FILE) 있음 → 빌드에 키를 심습니다"; \
	else \
		echo "$(ENV_FILE) 없음 → 설정 화면에서 받은 키만 씁니다"; \
	fi
