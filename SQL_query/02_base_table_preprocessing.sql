-- ============================================================
-- 02_base_table_preprocessing.sql
-- 목적: MySQL DB(chicken_db)에서 모델링/EDA용 분석 베이스 테이블 생성
--
-- 데이터 소스
--   - daily_chicken_log (19행): 일별 초벌 운영 로그
--   - order_detail_log  (N행) : 일별 상세 주문 로그
--
-- CTE 구조
--   1) time_table : order_detail_log에서 주문시각 → 30분 bin 변환
--   2) join_table : 30분 bin별 chicken_g 피벗 + sum_g, cnt 집계
--   3) dcl_table  : daily_chicken_log에서 피처 정제
--        - holiday_status : 공휴일 + 주말연휴 + 휴일전날 → 1, 평일 → 0
--        - total_fired_kg : 1차 + 2차 초벌 합산(완성kg)
--
-- 최종 SELECT 컬럼
--   - 식별자   : dcl_id, date, day_of_week, holiday_status
--   - 초벌 관련: first_fried_kg, second_fried_kg, total_fired_kg
--   - 보정 변수: plus_kg(완벌조리량), end_g(마감잔량)
--   - 시간대 bin: 16:00 ~ 22:30 (30분 단위, 14개)
--   - 집계     : sum_g(전체주문소모량), cnt(주문건수)
--   - 파생     : act_g = sum_g - plus_kg * 1000 (순수 초벌 소모량)
--
-- 설계 결정 사항
--   - 타겟변수: sum_g (완벌조리는 임시방편, 궁극적으로 초벌로 전량 커버가 목표)
--   - act_g   : 타겟이 아니라 EDA 비교용 (완벌조리 도입 전후 분석)
--   - 날씨_비여부: 19일치 중 2일만 해당돼 표본 부족으로 피처에서 제외
--   - holiday_status: 소표본 특성상 공휴일/연휴/전날을 하나로 통합
--   - 시간대 bin: 출근 전 시점엔 미래 데이터지만, 과거 패턴 학습용으로는 유효
-- ============================================================

WITH time_table AS (
    -- 주문 시각을 30분 단위 bin으로 변환
    SELECT dcl_id,
        CONCAT(DATE_FORMAT(order_datetime, "%H:"), LPAD(FLOOR(MINUTE(order_datetime) / 30) * 30, 2, '0')) hh_mm,
        chicken_g, qty
    FROM order_detail_log
),
join_table AS (
    -- bin별 소비량 피벗 + 일별 총 소비량(sum_g)·주문건수(cnt) 집계
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
    -- daily_chicken_log에서 분석용 컬럼 정제 + holiday_status 통합
    SELECT dcl_id, `날짜` AS `date`, `요일` AS `day_of_week`,
        CASE WHEN `공휴일여부` = 1 OR `휴일전날여부` = 1 THEN 1 ELSE 0 END AS `holiday_status`,
        `1차초벌량_완성kg` AS first_fried_kg, `재초벌량_완성kg` AS second_fried_kg,
        ROUND(`1차초벌량_완성kg` + `재초벌량_완성kg`, 2) AS total_fired_kg,
        `완벌조리kg` AS plus_kg, `마감잔량_g` AS end_g
    FROM daily_chicken_log
)
SELECT dt.dcl_id, dt.date, dt.day_of_week, dt.holiday_status,
    dt.first_fried_kg, dt.second_fried_kg, dt.total_fired_kg,
    dt.plus_kg, dt.end_g,
    jt.`16:00`, jt.`16:30`, jt.`17:00`, jt.`17:30`,
    jt.`18:00`, jt.`18:30`, jt.`19:00`, jt.`19:30`,
    jt.`20:00`, jt.`20:30`, jt.`21:00`, jt.`21:30`,
    jt.`22:00`, jt.`22:30`,
    jt.sum_g, jt.cnt,
    jt.sum_g - dt.plus_kg * 1000 AS act_g  -- 완벌조리량 제외한 순수 초벌 소모량
FROM join_table jt
JOIN dcl_table dt ON dt.dcl_id = jt.dcl_id;