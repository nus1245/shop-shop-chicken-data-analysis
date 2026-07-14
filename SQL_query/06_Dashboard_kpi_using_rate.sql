-- ============================================================
-- 06_dashboard_kpi_using_rate.sql
-- 목적: 소진율(U-rate) KPI 계산. 소진율 = 실질 소비량 / 준비된 총 재고량
--
-- 이월 재고(출근 전 남아있던 초벌량)를 직접 기록하지 않기 때문에, 역산으로
-- 추정해야 한다. 아래 3-case 로직으로 처리한다:
--   case 1) 초벌량 < 소비량  → 이월 재고가 있었다는 뜻 → 역산으로 추정 가능
--   case 2) 초벌량 > 소비량  → 이월 재고 없이도 소진 설명 가능 → 추정 불가(당일 초벌량 그대로 사용)
--   case 3) 완벌조리 발생(6월 중순~) → 완벌조리량은 초벌 재고에서 제외하고 계산
-- ============================================================

USE chicken_db;

-- 일자별 실질 소비량(kg) — 이후 쿼리들의 재료로 재사용
SELECT dcl_id, ROUND(SUM(chicken_g) / 1000, 2) AS amount_kg
FROM order_detail_log
GROUP BY dcl_id;

-- ── 탐색용: case 판별에 쓸 중간 계산값 확인 ──────────────────
SELECT dcl.dcl_id, `1차초벌량_완성kg`, `재초벌량_완성kg`,
    ROUND(`1차초벌량_완성kg` + `재초벌량_완성kg`, 2) AS total_fried,
    `완벌조리kg`,
    ROUND(`마감잔량_g` / 1000, 2) AS end_amount,
    ROUND((SUM(odl.chicken_g) / 1000) - coalesce(`완벌조리kg`,0), 2) AS ft_amount,        -- 완벌조리량 제외한 순수 소비량
    ROUND(SUM(odl.chicken_g) / 1000, 2) AS amount_kg,
    ROUND((`1차초벌량_완성kg` + `재초벌량_완성kg`)
          - ((`마감잔량_g` + SUM(odl.chicken_g)) / 1000 - `완벌조리kg`), 1) AS rka,
    -- ex_fried_kg: 음수면 "당일 초벌량으로 소비량+마감잔량을 못 채운다" → 이월 재고 존재 신호
    ROUND(((`1차초벌량_완성kg` + `재초벌량_완성kg`) - (`마감잔량_g` / 1000))
          - (SUM(odl.chicken_g) / 1000), 1) AS ex_fried_kg
FROM daily_chicken_log dcl
LEFT JOIN order_detail_log odl ON dcl.dcl_id = odl.dcl_id
GROUP BY dcl.dcl_id;

-- ── 최종: 3-case 로직으로 소진율(using_rate) 산출 ────────────
WITH ex_table AS (
    -- case 판별에 필요한 원재료 계산 (완벌조리량은 소비량에서 제외)
    SELECT dcl.dcl_id, `1차초벌량_완성kg`, `재초벌량_완성kg`,
        ROUND(`1차초벌량_완성kg` + `재초벌량_완성kg`, 2) AS total_fried,
        ROUND(`마감잔량_g` / 1000, 2) AS end_amount,
        ROUND((SUM(odl.chicken_g) / 1000) - coalesce(`완벌조리kg`,0), 2) AS amount_kg,
        ROUND((`1차초벌량_완성kg` + `재초벌량_완성kg`)
              - ((`마감잔량_g` + SUM(odl.chicken_g)) / 1000 - coalesce(`완벌조리kg`,0)), 1) AS ex_fried_kg
    FROM daily_chicken_log dcl
    JOIN order_detail_log odl ON dcl.dcl_id = odl.dcl_id
    GROUP BY dcl.dcl_id
),
pre_table AS (
    -- ex_fried_kg가 음수인 날(case 1) → 이월 재고량을 절댓값으로 추정
    SELECT dcl_id, total_fried, end_amount, amount_kg, ex_fried_kg,
        CASE WHEN ex_fried_kg < 0 THEN ABS(ex_fried_kg) ELSE NULL END AS pre_fried_kg,
        CASE WHEN ex_fried_kg < 0 THEN "추정 가능" ELSE "추정 불가" END label
    FROM ex_table
),
kpi_table AS (
    -- case 1이면 (당일 초벌량 + 추정 이월재고), case 2면 당일 초벌량 그대로를 총 재고량으로 사용
    SELECT dcl_id,
        CASE label WHEN "추정 가능" THEN ROUND(total_fried + pre_fried_kg, 1)
                   ELSE total_fried END AS total_pre_kg,
        total_fried, end_amount, amount_kg, ex_fried_kg, pre_fried_kg
    FROM pre_table
)
SELECT dcl_id, total_fried, end_amount, amount_kg, pre_fried_kg, total_pre_kg,
    ROUND(amount_kg / total_pre_kg, 2) AS using_rate  -- 소진율 = 실질 소비량 / 총 재고량(추정 포함)
FROM kpi_table;
