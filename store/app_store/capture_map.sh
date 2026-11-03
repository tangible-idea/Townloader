#!/bin/zsh
# 실제 지도 화면을 시뮬레이터에서 찍어 screenshots/raw/ 에 둔다. 저장소 루트에서 실행한다.
set -u
SIM=04B461C5-ADBB-4BD4-B57B-484C325E4414  # iPhone 16 Pro (1206×2622)
RAW=store/app_store/screenshots/raw
LOG=$(mktemp)
mkdir -p $RAW
xcrun simctl boot $SIM 2>/dev/null
xcrun simctl bootstatus $SIM -b >/dev/null
xcrun simctl status_bar $SIM override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
python3 -m http.server 8765 --bind 127.0.0.1 -d test/store/images >/dev/null 2>&1 &
SERVER=$!
trap "kill $SERVER 2>/dev/null" EXIT
for locale in ${@:-ko en-US}; do
  : > $LOG
  flutter test integration_test/store_map_shot_test.dart -d $SIM \
    --dart-define-from-file=.env.json --dart-define=STORE_LOCALE=${locale%%-*} > $LOG 2>&1 &
  RUN=$!
  until grep -q STORE_MAP_READY $LOG; do
    kill -0 $RUN 2>/dev/null || { tail -30 $LOG; exit 1; }
    sleep 2
  done
  xcrun simctl io $SIM screenshot $RAW/map_$locale.png
  wait $RUN
  tail -2 $LOG
done
xcrun simctl status_bar $SIM clear
