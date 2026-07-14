-- ============================================================
-- 04_hypothesis_test_prep.sql
-- 목적: 가설검증(H1~H3)용 데이터 전처리. 각 쿼리 결과를 Python으로 내보내
--       scipy로 통계 검정을 수행한다 (평균_가설_검증.ipynb 참고).
-- ============================================================

-- ── H1. 요일별 주문 소비량 차이 (ANOVA) ──────────────────────
-- 귀무가설: 월/화/금 세 요일 그룹의 평균 소비량은 같다
SELECT dcl.dcl_id, dcl.`요일` AS day_of_week, SUM(chicken_g) AS sum_g
FROM daily_chicken_log dcl
JOIN order_detail_log odl ON dcl.dcl_id = odl.dcl_id
WHERE dcl.`요일` != '목'  -- 표본 제외
GROUP BY dcl.dcl_id;

-- ── H2. 평일(월,화) vs 휴일전날(금,공휴일 전날) 평균 소비량 차이 (독립표본 t검정) ──
SELECT dcl.dcl_id, dcl.`휴일전날여부` AS day_status, SUM(chicken_g) AS sum_g
FROM daily_chicken_log dcl
JOIN order_detail_log odl ON dcl.dcl_id = odl.dcl_id
WHERE dcl.`요일` != '목'
GROUP BY dcl.dcl_id;

-- ── H3. 오후(16~19시, 4시간) vs 저녁(20~22:45시, 3시간45분) 평균 주문량 차이 (대응표본 t검정) ──
-- 같은 날짜 내에서 두 시간대를 짝지어 비교하므로 대응표본으로 검정 (날짜 변수 통제)
SELECT dcl_id,
    (`16:00` + `16:30` + `17:00` + `17:30`
     + `18:00` + `18:30` + `19:00` + `19:30`) AS cumul_16_19,  -- Stage 1
    (`20:00` + `20:30` + `21:00` + `21:30`
     + `22:00` + `22:30`) AS cumul_20_22                       -- Stage 2
FROM time_table;