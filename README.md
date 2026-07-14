# 치킨집 초벌 닭 산정

경험 기반 의사결정을 데이터로 전환하는 수요 예측 프로젝트

> "오늘 몇 (kg) 초벌해야 하는가"를 데이터로 예측할 수 있는가?

---

## 개요

닭강정 배달·포장 매장(shop&shop)에서, 치킨 사업 경험이 없는 사장님이 감각으로 결정해온
**초벌 닭 준비량**을 데이터 기반으로 예측하는 프로젝트입니다. 배달 플랫폼 주문 영수증을
OCR로 자동 파싱해 MySQL에 적재하고, 통계적 가설검증과 회귀모델을 거쳐 Tableau
대시보드로 전달하는 전체 파이프라인을 혼자 설계·구현했습니다.

| 항목 | 내용 |
|---|---|
| 기간 | 2026.05 ~ (진행 중) |
| 데이터 | 배달 플랫폼 주문 영수증 (일 30~40건) |
| 기술 스택 | Python · MySQL · Tableau · Claude Agent(OCR) · Google Drive |

## 파이프라인

```
영수증 촬영 → Google Drive → Claude Agent OCR → MySQL 적재 → Python 분석 → Tableau 전달
수기 (외부)데이터 → Python(coldab) 데이터 변환 스크립트 → Google Drive 보관  → MySQL 적재 → Python 분석 → Tableau 전달 
```

- **수집**: 배달 영수증을 촬영해 Google Drive에 업로드하면 OCR로 메뉴·수량·시간을 자동 파싱
- **적재**: `daily_chicken_log`(1일 1행, 운영 로그) : `order_detail_log`(1일 N행, 상세 주문) = 1:N 구조
- **분석**: 가설검증 → 요일별 모델링 시도 → 소표본 과적합 확인 → 통합 데이터 재설계 → 사후 검증
- **전달**: Tableau 대시보드 (월-주간 리포트 + 일별 상세 로그)

## 핵심 발견

- **H3 채택**: 오후(16-19시) 소비가 저녁(20-22시)보다 유의하게 많음 (t=2.68, p=0.0135, Cohen's d=0.56)
- **요일별 분리 모델의 함정**: 화요일 단독 스텝와이즈 OLS는 Adj R²=0.942로 매우 높게 나왔지만,
  관측치 5개·잔차 자유도 2에 불과해 통계적으로 신뢰 불가능함을 직접 실증. 인접 시간대(T2)에
  같은 방법론을 적용하자 F검정이 기각 실패(p=0.171)로 정반대 결과가 나와, 소표본 분리의
  위험성을 재확인함
- **통합 모델 채택**: baseline(단순 평균) 대비, T1은 유의미한 피처가 없어 baseline 유지,
  T2는 `금`(요일) + `roll_prev_3days_mean_t2`로 LOOCV RMSE를 약 20% 개선 (F=7.138, p=0.0073)
- **이상치의 잔차→레버리지 전이**: 특정 이상치가 발생 시점에는 잔차(Y) 문제로, lag 피처
  구조상 정확히 7일 뒤에는 레버리지(X) 문제로 형태를 바꿔 전이됨을 Cook's D로 확인
  (0.133→0.391, 임계값 0.2→0.167 초과)
- **사후 시뮬레이션**: 학습에 쓰지 않은 신규 데이터(n=4)에 모델을 적용해 사장님의 감각(A),
  모델 예측(B), 단순 일평균(C)을 비교. 전체 MAE는 세 방식이 비슷했으나, 예측 성공/실패
  조건에 따라 오차가 크게 갈리는 패턴을 확인 (표본 확대 후 재검증 필요)

## 폴더 구조

```
notebooks/
├── 01_eda_hypothesis_test.ipynb        # EDA + H1~H3 가설검증
├── 02_feature_correlation_dilution.ipynb  # 상관계수 희석 진단
├── 03_tuesday_solo_model.ipynb          # 화요일 단독 스텝와이즈 OLS (과적합 실증)
├── 04_integrated_model_loocv.ipynb      # 통합 데이터 baseline + LOOCV 모델
├── 05_posthoc_simulation.ipynb          # 사후 검증 시뮬레이션
└── 06_outlier_leverage_analysis.ipynb   # 이상치 잔차→레버리지 전이 검증

sql/
├── 01_schema_and_import.sql             # 테이블 스키마 + CSV 적재
├── 02_base_table_preprocessing.sql      # 베이스 테이블 전처리
├── 03_feature_engineering.sql           # lag·rolling 피처 뷰
├── 04_hypothesis_test_prep.sql          # 가설검증용 전처리
├── 05_dashboard_peak_time.sql           # 피크타임 대시보드 쿼리
├── 06_dashboard_kpi_using_rate.sql       # 소진율(U-rate) 대시보드 쿼리
└── 99_archive_feature_query_draft.sql   # 초기 draft (아카이브)
```

## 한계와 다음 단계

- T1(1차 피크) 회귀모델 미구축 — 표본(n=17)에 아직 예측 신호가 축적되지 않은 상태로 판단,
  데이터 추가 수집 후 재검증 예정
- T2 모델은 `금 vs 월+화` 2분법에 그침 — 표본 확대 후 3분법 확장 검토
- 외부요인(날씨·공휴일) 변수는 발생 빈도가 낮아 아직 통계적으로 다루기 어려움
- 이상치 민감도 검증은 `lag_same_day_t1` 단일 피처 기준의 보수적 하한 검증이며,
  실제 채택 모델(T2)에 대한 동일 진단은 별도로 진행 예정

## 개발 방식 (Methodology Note)

가설·분석 방향(어떤 통계 기법을 쓸지, 결과를 어떻게 해석 방법론)은 직접 설계했으며, 통계 기법의
python 코드 구현은 AI 코드 어시스턴트(Claude)와 논의하며 기초 골격을 빠르게 잡은 뒤, 프로젝트
데이터의 소표본·요일별 구조에 맞게 직접 발전시켰습니다. 이후 코드 리펙토링 작업을 AI 코드 어시스턴트를 활용하여 가독성을 증진했습니다.
## 작성자

조승훈 — 데이터 분석가(주니어) 지망 ·
E-MAIL : nextbus1245@gmail.com 
Tel. : 010-3975-3130

해당 프로젝트 노션 기록 : https://app.notion.com/p/36522de4a40981c1b1a0c2e6177e8c9a?source=copy_link
