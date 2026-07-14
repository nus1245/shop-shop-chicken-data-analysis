-- ============================================================
-- 05_dashboard_peak_time.sql
-- 목적: "피크타임"을 절대 시각이 아니라, 일자별 상대적 소비 밀집도로 정의해
--       Tableau 대시보드용 데이터를 만든다.
-- 정의: 일별 30분 bin 소비 비중(pct)의 평균 + 1표준편차를 넘는 구간 = 피크타임
--       (상위 약 15.87%, 정규분포 기준 평균+1SD 초과 구간의 비율)
-- ============================================================

USE chicken_db;

-- ── 탐색: 공휴일/휴일전날 통합 플래그 + 일자별 총 소비량 ────────
SELECT dcl.dcl_id, `요일`, `공휴일여부`, `휴일전날여부`,
    CASE WHEN `공휴일여부` = 1 OR `휴일전날여부` = 1 THEN 1 ELSE 0 END AS `휴일 및 전일`,
    t.sum_kg
FROM daily_chicken_log dcl
JOIN (
    SELECT dcl_id, ROUND(SUM(chicken_g) / 1000, 2) sum_kg
    FROM order_detail_log
    GROUP BY dcl_id
) t ON dcl.dcl_id = t.dcl_id;

-- ── 탐색: 30분 bin별 소비량 + 일자별 누적합 확인용 ──────────────
SELECT dcl_id, chicken_g, order_datetime,
    CONCAT(DATE_FORMAT(order_datetime, "%H:"), LPAD(FLOOR(MINUTE(order_datetime) / 30) * 30, 2, '0')) AS hh_mm,
    SUM(chicken_g) OVER (PARTITION BY dcl_id)
FROM order_detail_log;

-- ── 최종: 30분 bin 기준 피크타임 판정 ──────────────────────────
WITH bin_table AS (
    -- 주문 시각을 30분 단위 bin으로 변환 (하루 14개 구간)
    SELECT dcl_id, chicken_g, order_datetime,
        CONCAT(DATE_FORMAT(order_datetime, "%H:"), LPAD(FLOOR(MINUTE(order_datetime) / 30) * 30, 2, '0')) AS hh_mm
    FROM order_detail_log
),
cum_bin AS (
    -- bin별 소비량 합산
    SELECT dcl_id, hh_mm, SUM(chicken_g) AS cum_bin
    FROM bin_table
    GROUP BY dcl_id, hh_mm
),
cum_bin_pct AS (
    -- 일자 내 각 bin이 차지하는 비중(pct)과 누적 비중(cum_pct) 계산
    SELECT dcl_id, hh_mm, cum_bin,
        SUM(cum_bin) OVER (PARTITION BY dcl_id) AS total,
        ROUND(cum_bin / SUM(cum_bin) OVER (PARTITION BY dcl_id) * 100, 2) AS pct,
        ROUND(SUM(cum_bin) OVER (PARTITION BY dcl_id ORDER BY hh_mm)
              / SUM(cum_bin) OVER (PARTITION BY dcl_id) * 100, 2) AS cum_pct
    FROM cum_bin
),
peek_table AS (
    -- 일자별 평균 비중(daily_avg)과 표준편차(daily_std)로 임계치 산출
    SELECT dcl_id,
        AVG(pct) AS daily_avg,
        STDDEV(pct) AS daily_std,
        ROUND(AVG(pct) + 2 * STDDEV(pct), 2) AS daily_2peek_pct,  -- 상위 약 2.28% (평균+2SD)
        ROUND(AVG(pct) + STDDEV(pct), 2) AS daily_peek_pct        -- 상위 약 15.87% (평균+1SD) — 채택 기준
    FROM cum_bin_pct
    GROUP BY dcl_id
)
SELECT cm.dcl_id, cm.hh_mm, cm.pct, pt.daily_peek_pct, pt.daily_2peek_pct
FROM cum_bin_pct cm
JOIN peek_table pt ON cm.dcl_id = pt.dcl_id
WHERE cm.pct > pt.daily_peek_pct  -- 평균+1SD를 넘는 bin만 피크타임으로 판정
ORDER BY cm.dcl_id, cm.hh_mm;

-- ── 참고용: 1시간 bin 기준 동일 로직 (세부 대시보드용 대안 granularity) ──
WITH bin_hour AS (
    SELECT dcl_id, order_datetime, DATE_FORMAT(order_datetime, "%H:00") bin_hour, chicken_g
    FROM order_detail_log
),
sum_table AS (
    SELECT dcl_id, bin_hour, SUM(chicken_g) / 1000 AS sum_kg
    FROM bin_hour
    GROUP BY dcl_id, bin_hour
),
cum_table AS (
    SELECT dcl_id, bin_hour,
        SUM(sum_kg) OVER (PARTITION BY dcl_id ORDER BY bin_hour) cum_sum,
        ROUND(sum_kg / SUM(sum_kg) OVER (PARTITION BY dcl_id) * 100, 2) pct,
        ROUND(SUM(sum_kg) OVER (PARTITION BY dcl_id ORDER BY bin_hour)
              / SUM(sum_kg) OVER (PARTITION BY dcl_id) * 100, 2) AS cum_pct
    FROM sum_table
),
peek_time AS (
    SELECT dcl_id,
        ROUND(AVG(pct), 2) avg_pct,
        STDDEV(pct) std_pct,
        AVG(pct) + STDDEV(pct) peek_time,
        AVG(pct) + 2 * STDDEV(pct) peek_time_2
    FROM cum_table
    GROUP BY dcl_id
)
SELECT ct.dcl_id, ct.bin_hour, ct.pct, pt.peek_time, pt.peek_time_2
FROM cum_table ct
JOIN peek_time pt ON ct.dcl_id = pt.dcl_id
WHERE ct.pct > pt.peek_time
ORDER BY ct.dcl_id, ct.bin_hour;