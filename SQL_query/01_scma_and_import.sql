-- ============================================================
-- 01_schema_and_import.sql
-- 목적: 원본 CSV(영수증 OCR 결과, 일별 운영 로그)를 MySQL로 적재하기 위한
--       테이블 스키마 정의 + LOAD DATA 적재
-- ============================================================

-- create database chicken_db;

SET GLOBAL local_infile = 1;  -- LOAD DATA LOCAL INFILE 사용을 위해 필요 (클라이언트/서버 양쪽 설정)
-- SHOW GLOBAL VARIABLES LIKE 'local_infile';  -- 설정 확인용

-- daily_chicken_log(부모) ← order_detail_log(자식, FK) 관계이므로
-- DROP은 반드시 자식 → 부모 순서로 (역순으로 하면 FK 제약 위반)
DROP TABLE IF EXISTS order_detail_log;
DROP TABLE IF EXISTS daily_chicken_log;

-- ────────────────────────────────────────────────────────────
-- ① daily_chicken_log: 일별 운영 로그 (1일 1행)
--    현장에서 수기로 기록하는 초벌량·마감잔량 등 운영 지표
-- ────────────────────────────────────────────────────────────
CREATE TABLE daily_chicken_log (
    dcl_id              VARCHAR(10)     NOT NULL,   -- 예: dcl_0511 (날짜 기반 ID)
    날짜                DATE            NOT NULL,
    요일                VARCHAR(1),                 -- 월/화/수...
    날씨_비여부         TINYINT(1),
    공휴일여부          TINYINT(1),
    연휴여부            VARCHAR(5),                 -- -/1 등
    연휴_상황           VARCHAR(20),
    휴일전날여부        TINYINT(1),
    특수일              VARCHAR(20),
    대타여부            TINYINT(1),
    1차초벌량_생닭kg    FLOAT,
    1차초벌량_완성kg    FLOAT,
    재초벌여부          TINYINT(1),
    재초벌전잔량_g      FLOAT,
    재초벌시각          TIME,
    재초벌량_생닭kg     FLOAT,
    재초벌량_완성kg     FLOAT,
    마감잔량_g          FLOAT,
    퇴근시각            TIME,
    특이사항            VARCHAR(100),
    완벌조리kg          FLOAT,                      -- 6월 조리 방식 변경(완벌 조리 병행) 이후 추가된 컬럼
    PRIMARY KEY (dcl_id),
    UNIQUE KEY uq_date (날짜)                       -- 날짜 중복 적재 방지
);

-- ────────────────────────────────────────────────────────────
-- ② order_detail_log: 상세 주문 로그 (1일 N행, OCR 파싱 결과)
--    daily_chicken_log와 1:N 관계
-- ────────────────────────────────────────────────────────────
CREATE TABLE order_detail_log (
    dcl_id              VARCHAR(10)     NOT NULL,   -- daily_chicken_log FK
    order_id            VARCHAR(10)     NOT NULL,   -- 예: ORD01 (일별로 0부터 재시작)
    recp_idf            VARCHAR(20),
    order_datetime      DATETIME,
    channel             VARCHAR(20),
    source_file         VARCHAR(50),
    menu_name           VARCHAR(150),
    size_category       VARCHAR(30),
    qty                 INT,
    chicken_g           FLOAT,
    -- 복합 PK: order_id는 매일 0부터 재시작하는 값이라 단독 PK로 쓰면
    -- 날짜가 다른 두 행이 같은 order_id를 가질 수 있어 JOIN/집계 시 중복 오염이 발생한다.
    -- dcl_id + order_id 조합으로 날짜 단위 유일성을 보장한다.
    PRIMARY KEY (dcl_id, order_id),
    CONSTRAINT fk_dcl FOREIGN KEY (dcl_id)
        REFERENCES daily_chicken_log(dcl_id)
);

-- ────────────────────────────────────────────────────────────
-- 데이터 적재
-- ────────────────────────────────────────────────────────────
LOAD DATA LOCAL INFILE 'file_path'
INTO TABLE daily_chicken_log
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(dcl_id, 날짜, 요일, 날씨_비여부, 공휴일여부, 연휴여부, 연휴_상황, 휴일전날여부, 특수일, 대타여부,
 `1차초벌량_생닭kg`, `1차초벌량_완성kg`, 재초벌여부, 재초벌전잔량_g, 재초벌시각, `재초벌량_생닭kg`,
 `재초벌량_완성kg`, 마감잔량_g, 퇴근시각, 특이사항, `완벌조리kg`);

LOAD DATA LOCAL INFILE 'file_path'
INTO TABLE order_detail_log
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(dcl_id, order_id, recp_idf, order_datetime, channel, source_file, menu_name, size_category, qty, chicken_g);