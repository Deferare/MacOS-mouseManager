# Mouse Manager (starter)

Mac Mouse Fix 같은 스타일의 설정 UI(General / Buttons / Scrolling / About)와, 최소한의 마우스/스크롤 이벤트 후킹(Event Tap) 골격을 포함한 macOS SwiftUI 앱 스타터입니다.

## 실행/빌드

```bash
mkdir -p /tmp/clang-module-cache /tmp/swiftpm-cache
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_CACHE_DIR=/tmp/swiftpm-cache swift build -c debug
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_CACHE_DIR=/tmp/swiftpm-cache swift run MouseManager
```

## 권한(중요)

스크롤/버튼 이벤트를 수정하려면 **손쉬운 사용(Accessibility)** 권한이 필요합니다.

- 앱 실행 후 `General > Permissions > Request…` 버튼을 누르거나
- macOS 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 허용해 주세요.

## 현재 포함된 기능(초안)

- 탭 UI + 설정 저장(`@AppStorage`)
- 스크롤 이벤트: 방향 반전, 속도 배율, 간단한 정밀(양자화)
- 버튼 리매핑 UI는 있지만 실제 리매핑 로직은 아직 비활성(안전하게 통과)

