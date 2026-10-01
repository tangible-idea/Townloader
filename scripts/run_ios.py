#!/usr/bin/env python3
"""Build, install, and launch a release app on a physical iOS device."""

import argparse
import json
from pathlib import Path
import subprocess
import sys


def select_device(devices, selector):
    physical = [
        device
        for device in devices
        if device.get("targetPlatform") == "ios"
        and device.get("emulator") is False
        and device.get("isSupported") is True
    ]
    if selector:
        # Prefer an exact ID/name; allow an unambiguous ID prefix like Flutter.
        exact = [
            device for device in physical
            if selector.casefold() in (
                device["id"].casefold(), device["name"].casefold()
            )
        ]
        physical = exact or [
            device for device in physical
            if device["id"].casefold().startswith(selector.casefold())
        ]
    if len(physical) == 1:
        return physical[0]
    if not physical:
        selected = f" ({selector})" if selector else ""
        raise ValueError(
            f"사용 가능한 iOS 실기기가 없습니다{selected}. "
            "iPhone/iPad를 연결하고 잠금을 해제한 뒤, 이 컴퓨터 신뢰와 "
            "개발자 모드를 확인하세요. 기기 목록: make devices"
        )
    choices = "\n".join(
        f"  {device['name']}: make ios DEVICE={device['id']}"
        for device in physical
    )
    raise ValueError(f"iOS 실기기가 여러 대입니다. 설치할 기기를 지정하세요:\n{choices}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="")
    parser.add_argument("--env-file", default=".env.json")
    args = parser.parse_args()
    # Resolve settings and Flutter project paths consistently, even from another cwd.
    project = Path(__file__).resolve().parent.parent
    try:
        result = subprocess.run(
            ["flutter", "devices", "--machine", "--device-timeout", "15"],
            cwd=project,
            text=True,
            stdout=subprocess.PIPE,
            check=True,
        )
        try:
            devices = json.loads(result.stdout)
            if not isinstance(devices, list):
                raise ValueError("expected a device list")
        except ValueError as error:
            raise ValueError("Flutter 기기 목록을 읽지 못했습니다. make devices로 확인하세요.") from error
        device = select_device(devices, args.device.strip())
        command = ["flutter", "run", "--release", "--no-resident", "-d", device["id"]]
        env_file = Path(args.env_file)
        if not env_file.is_absolute():
            env_file = project / env_file
        if env_file.is_file():
            command.append(f"--dart-define-from-file={env_file}")
        else:
            print(f"{args.env_file} 없음: Instagram 조회 키 없이 빌드합니다.", flush=True)
        print(f"{device['name']} ({device['id']})에 Release 앱을 빌드·설치·실행합니다.", flush=True)
        subprocess.run(command, cwd=project, check=True)
        print("완료: 앱을 기기에서 직접 실행할 수 있습니다.", flush=True)
        return 0
    except (ValueError, FileNotFoundError) as error:
        print(error, file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        return error.returncode
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
