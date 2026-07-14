-- ============================================================
-- 03_feature_engineering.sql
-- 목적: 예측 모델용 뷰 2개를 생성하고, 그 뷰를 활용하는 예시 쿼리를 함께 둔다.
--   1) time_table    — 주문 로그를 30분 bin으로 피벗한 시간대별 소비량
--   2) model_feature — time_table 기반으로 lag·rolling·비율 피처를 추가한 모델링 테이블
--   3) (하단) model_feature 활용 예시 — 사후 시뮬레이션용 검증 데이터셋 추출
-- ============================================================

DROP VIEW IF EXISTS time_table;

CREATE VIEW time_table AS
WITH time_table AS (
    -- 주문 시각을 30분 단위 bin(hh:mm)으로 변환
    SELECT dcl_id,
        CONCAT(DATE_FORMAT(order_datetime, "%H:"), LPAD(FLOOR(MINUTE(order_datetime) / 30) * 30, 2, '0')) hh_mm,
        chicken_g, qty
    FROM order_detail_log
),
join_table AS (
    -- bin별 소비량(chicken_g)을 피벗 + 일별 총 소비량(sum_g)·주문건수(cnt) 집계
    SELECT dcl_id,
        SUM(CASE WHEN hh_mm = '16:00' THEN chicken_g ELSE 0 END) AS `16:00`,
        SUM(CASE WHEN hh_mm = '16:30' THEN chicken_g ELSE 0 END) AS `16:30`,
        SUM(CASE WHEN hh_mm = '17:00' THEN chicken_g ELSE 0 END) AS `17:00`,
        SUM(CASE WHEN hh_mm = '17:30' THEN chicken_g ELSE 0 END) AS `17:30`,
        SUM(CASE WHEN hh_mm = '18:00' THEN chicken_g ELSE 0 END) AS `18:00`,
        SUM(CASE WHEN hh_mm = '18:30' THEN chicken_g ELSE 0 END) AS `18:30`,
        SUM(CASE WHEN hh_mm = '19:00' THEN chicken_g ELSE 0 END) AS `19:00`,
        SUM(CASE WHEN hh_mm = '19:30' THEN chicken_g ELSE 0 END) AS `19:30`,
        SUM(CASE WHEN hh_mm = '20:00' THEN chicken_g ELSE 0 END) AS `20:00`,
        SUM(CASE WHEN hh_mm = '20:30' THEN chicken_g ELSE 0 END) AS `20:30`,
        SUM(CASE WHEN hh_mm = '21:00' THEN chicken_g ELSE 0 END) AS `21:00`,
        SUM(CASE WHEN hh_mm = '21:30' THEN chicken_g ELSE 0 END) AS `21:30`,
        SUM(CASE WHEN hh_mm = '22:00' THEN chicken_g ELSE 0 END) AS `22:00`,
        SUM(CASE WHEN hh_mm = '22:30' THEN chicken_g ELSE 0 END) AS `22:30`,
        SUM(chicken_g) sum_g, SUM(qty) cnt
    FROM time_table
    GROUP BY dcl_id
),
dcl_table AS (
    -- daily_chicken_log에서 모델링에 쓸 컬럼만 정제
    SELECT dcl_id, `날짜` AS `date`, `요일` AS `day_of_week`, `마감잔량_g` AS end_g,
        CASE WHEN `공휴일여부` = 1 OR `휴일전날여부` = 1 THEN 1 ELSE 0 END AS `before_rest`,
        `1차초벌량_완성kg` AS first_fried_kg, `재초벌량_완성kg` AS second_fried_kg,
        ROUND(`1차초벌량_완성kg` + `재초벌량_완성kg`, 2) AS total_fired_kg,
        COALESCE(`완벌조리kg`, 0) AS plus_kg
    FROM daily_chicken_log
)
SELECT dt.dcl_id, dt.date, dt.day_of_week,dt.before_rest ,dt.end_g,
    jt.`16:00`, jt.`16:30`, jt.`17:00`, jt.`17:30`,
    jt.`18:00`, jt.`18:30`, jt.`19:00`, jt.`19:30`,
    jt.`20:00`, jt.`20:30`, jt.`21:00`, jt.`21:30`,
    jt.`22:00`, jt.`22:30`,
    jt.sum_g, jt.cnt,
    jt.sum_g - dt.plus_kg * 1000 AS act_g  -- 완벌조리량을 뺀 순수 초벌 소모량 (완벌 도입 전후 비교용)
FROM join_table jt
JOIN dcl_table dt ON dt.dcl_id = jt.dcl_id;


-- ============================================================
-- model_feature: 예측 모델용 최종 피처 테이블
-- 현재 모델링 대상: Stage 1(16~19시, 첫 출근 시 예측) / Stage 2(20~22시, 재초벌 시점 예측)
-- ============================================================
DROP VIEW IF EXISTS model_feature;

CREATE VIEW model_feature AS
WITH base AS (
    SELECT dcl_id, `date`, day_of_week,before_rest, end_g, sum_g,
        (`16:00` + `16:30` + `17:00` + `17:30`
         + `18:00` + `18:30` + `19:00` + `19:30`) AS cumul_16_19,  -- Stage 1 타겟
        (`20:00` + `20:30` + `21:00` + `21:30`
         + `22:00` + `22:30`) AS cumul_20_22                       -- Stage 2 타겟
    FROM time_table
    WHERE day_of_week != '목'  -- 목요일은 고정 근로일이 아니라 표본에서 제외
)
SELECT *,
    -- ── LAG 피처 ──────────────────────────────────────────
    -- 근무 요일이 월·화·금으로 고정돼 있어 날짜 간 텀이 요일마다 다르다.
    -- 화요일은 월요일 바로 다음 날이라 "직전 영업일"과 "직전 동요일"이 사실상 같지만,
    -- 월·금요일은 그 사이에 3일의 공백이 있어 의미가 달라진다.
    -- 이 차이를 모델이 구분할 수 있도록 lag_prev_day(직전 영업일 값)와
    -- lag_same_day(직전 동요일 값)를 분리해서 만든다.
    LAG(cumul_16_19) OVER (ORDER BY date) lag_prev_day_t1,
    LAG(cumul_16_19) OVER (PARTITION BY day_of_week ORDER BY date) AS lag_same_day_t1,
    LAG(cumul_20_22) OVER (ORDER BY date) lag_prev_day_t2,
    LAG(cumul_20_22) OVER (PARTITION BY day_of_week ORDER BY date) AS lag_same_day_t2,
    -- 동요일 2회 전 값 (격주 패턴 확인용)
    LAG(cumul_16_19, 2) OVER (PARTITION BY day_of_week ORDER BY date) AS lag_biweekly_t1,
    LAG(cumul_20_22, 2) OVER (PARTITION BY day_of_week ORDER BY date) AS lag_biweekly_t2,

    -- ── ROLLING 피처 (이동평균) ───────────────────────────
    -- 수집일이 아직 적어 동요일만으로 이동평균을 구하면 표본이 더 줄어들므로,
    -- "직전 N일 전체 평균"과 "직전 N회 동요일 평균" 두 가지 형태로 나눠서 만든다.
    -- 주의: 당일 값을 포함하면 예측 시점에 알 수 없는 당일 수요가 섞여 누출(leakage)이
    -- 발생하므로, 반드시 "1 PRECEDING"부터 시작해 당일을 제외한다.
    -- 직전 3일 평균 (표본 3개 미만이면 NULL)
    CASE WHEN COUNT(cumul_16_19) OVER (ORDER BY date ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) < 3 THEN NULL
         ELSE ROUND(AVG(cumul_16_19) OVER (ORDER BY date ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING), 2) END roll_prev_3days_mean_t1,
    CASE WHEN COUNT(cumul_16_19) OVER (PARTITION BY day_of_week ORDER BY date ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) < 3 THEN NULL
         ELSE ROUND(AVG(cumul_16_19) OVER (PARTITION BY day_of_week ORDER BY date ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING), 2) END roll_same_3days_mean_t1,
    CASE WHEN COUNT(cumul_20_22) OVER (ORDER BY date ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) < 3 THEN NULL
         ELSE ROUND(AVG(cumul_20_22) OVER (ORDER BY date ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING), 2) END roll_prev_3days_mean_t2,
    CASE WHEN COUNT(cumul_20_22) OVER (PARTITION BY day_of_week ORDER BY date ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) < 3 THEN NULL
         ELSE ROUND(AVG(cumul_20_22) OVER (PARTITION BY day_of_week ORDER BY date ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING), 2) END roll_same_3days_mean_t2,
    -- 직전 5일 평균 (표본이 더 쌓인 뒤 사용할 장기 버전)
    CASE WHEN COUNT(cumul_16_19) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING) < 5 THEN NULL
         ELSE ROUND(AVG(cumul_16_19) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING), 2) END roll_prev_5days_mean_t1,
    CASE WHEN COUNT(cumul_20_22) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING) < 5 THEN NULL
         ELSE ROUND(AVG(cumul_20_22) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING), 2) END roll_prev_5days_mean_t2,

    -- ── 비율 피처 ─────────────────────────────────────────
    -- 절대량(lag)만으로는 "그날 전체 주문이 원래 많았는지"를 구분 못 하므로,
    -- 직전 값 대비 해당 시간대가 차지하는 비중(ratio)도 함께 만든다.
    ROUND(LAG(cumul_16_19) OVER (ORDER BY date) / LAG(sum_g) OVER (ORDER BY date), 2) AS lag_prev_t1_ratio,
    ROUND(LAG(cumul_16_19) OVER (PARTITION BY day_of_week ORDER BY date) / LAG(sum_g) OVER (PARTITION BY day_of_week ORDER BY date), 2) AS lag_same_t1_ratio,
    ROUND(LAG(cumul_20_22) OVER (ORDER BY date) / LAG(sum_g) OVER (ORDER BY date), 2) AS lag_prev_t2_ratio,
    ROUND(LAG(cumul_20_22) OVER (PARTITION BY day_of_week ORDER BY date) / LAG(sum_g) OVER (PARTITION BY day_of_week ORDER BY date), 2) AS lag_same_t2_ratio,
    LAG(sum_g) OVER (ORDER BY date) AS prev_sum_g,
    LAG(sum_g) OVER (PARTITION BY day_of_week ORDER BY date) AS same_prev_sum_g
FROM base;


-- ============================================================
-- 활용 예시: model_feature 뷰를 이용한 사후 시뮬레이션용 검증 데이터셋 추출
-- (구 vail_data_set.sql — model_feature와 강하게 결합돼 있어 같은 파일로 병합)
-- 목적: 모델 학습 범위(~06/30, n=23)에는 없던 7월 신규 날짜만 뽑는다.
--       T2 모델(cumul_20_22 ~ 금 + roll_prev_3days_mean_t2) 검증용
--       (사후_검증_시뮬레이션.ipynb 참고)
-- ============================================================
SELECT dcl_id, `date`, day_of_week, cumul_20_22, roll_prev_3days_mean_t2
FROM model_feature
WHERE `date` LIKE "2026-07%"
ORDER BY `date`;