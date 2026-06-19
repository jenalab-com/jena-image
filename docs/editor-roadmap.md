# 이미지 에디터 확장 로드맵 (계획)

> **상태: 계획 단계 (미착수).** 뷰어 기능을 먼저 안정화한 뒤 착수한다.
> 이 문서는 "언젠가 편집기를 포토샵급으로 키운다면 어떤 순서로 가야 하는가"를
> 박제해 둔 것이다. 2026-06-19 브레인스토밍에서 도출.

## 목표

맥 기본 미리보기를 대체하는 뷰어에, **자주 쓰는 편집 기능만** 골라 비파괴로 얹는다.
포토샵 전체가 아니라: 레이어, 합성, 레벨, 콘트라스트, 커브, 색상 조정, 마스크,
조정(레이어) 보정.

## 핵심 결정 — 왜 단계가 필요한가

현재 에디터([Sources/viewer/ImageEditorWindowController.swift](../Sources/viewer/ImageEditorWindowController.swift),
[Sources/services/ImageEditingService.swift](../Sources/services/ImageEditingService.swift))는
단일 `NSImage`를 `lockFocus`로 즉석에서 덮어쓰는 **파괴적** 구조다. 편집할 때마다
원본 픽셀이 사라진다. 레이어·마스크·합성·조정 레이어는 모두 **비파괴 편집
파이프라인**이라는 토대 위에 선다. 토대 없이 레이어부터 만들면 나중에 전부
갈아엎어야 한다. 따라서 의존 순서를 지켜 단계적으로 간다.

밝기/대비/채도는 이미 `CIColorControls`(Core Image)를 쓰고 있어, 비파괴 전환의
씨앗은 이미 코드에 있다.

## 단계 분해

각 Phase는 **독립된 spec → 계획 → 구현 사이클**이다. 한 번에 다 하지 않는다.
Phase 1을 "끝났다" 확정하고 내놓은 뒤 다음으로 간다.

| 단계 | 내용 | 의존 |
|---|---|---|
| **Phase 1** | 비파괴 편집 기반 + 고급 색보정(레벨·커브·색상조정 HSL/색조) | 없음 (토대) |
| **Phase 2** | 레이어 시스템 + 합성 (이미지 레이어 추가·순서·불투명도·블렌드 모드) | Phase 1 |
| **Phase 3** | 마스크 (레이어별 부분 적용) | Phase 2 |
| **Phase 4** | 조정 레이어 (Phase 1 보정을 비파괴+마스크 가능한 레이어로 승격) | Phase 2,3 |

**Phase 1만으로도 단일 이미지 보정의 8할이 완성**되어, 기본 미리보기를 훌쩍 넘는
도구가 된다. 그 자체로 완결된 출시 단위다.

## 기술 메모 (착수 시 출발점)

- **편집 모델**: "파괴적 즉시 적용" → "원본 + 조정 레시피(필터 체인)". Phase 2부터
  "레이어 스택"으로 확장.
- **렌더링**: Core Image(`CIFilter` 체인) + `CIContext`. 큰 이미지에서 슬라이더
  실시간 미리보기가 버벅이면 Metal 백엔드(`MTKView` / Metal `CIContext`) 검토.
- **필터 매핑**:
  - 커브 → `CIToneCurve`
  - 밝기/대비/채도 → `CIColorControls` (이미 사용 중)
  - 색조 → `CIHueAdjust`
  - 하이라이트/섀도 → `CIHighlightShadowAdjust` (에디터에 슬라이더 이미 있음)
  - 레벨 → 커스텀(감마/입출력 레인지) 또는 `CIColorPolynomial`
  - 합성/블렌드 → `CISourceOverCompositing`, `CIMultiplyBlendMode` 등 블렌드 필터군
  - 마스크 → `CIBlendWithMask`
- **저장**: 비파괴 편집 결과를 최종 1회 렌더 후 기존 `ImageService.exportImage`로 출력.
  (편집 세션 자체의 저장 포맷은 Phase 2 레이어 도입 시 별도 설계)

## 착수 트리거

뷰어 기능이 안정화되고, "편집을 더 자주, 더 깊게 쓰고 싶다"는 실사용 신호가
쌓이면 Phase 1부터 별도 brainstorming으로 시작한다.
