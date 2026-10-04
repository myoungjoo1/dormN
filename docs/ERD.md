# DormN ERD

## 1. profiles

DormN 사용자의 서비스 내 정보를 저장한다.

| 컬럼 | 타입 | 제약조건 | 역할 |
|---|---|---|---|
| id | UUID | PK | DormN 사용자 고유 ID |
| auth_user_id | UUID | UNIQUE, NULL 가능 | 추후 Supabase Auth 사용자와 연결 |
| room_number | VARCHAR | UNIQUE | 사용자 호실명 (예: 717-1) |
| dorm_verified | BOOLEAN | NOT NULL, DEFAULT false | 수경재 인증 여부 |
| dorm_verified_at | TIMESTAMP | NULL 가능 | 마지막 수경재 인증 시간 |
| bank_name | VARCHAR | NULL 가능 | 정산용 은행명 |
| bank_account | VARCHAR | NULL 가능 | 정산용 계좌번호 |
| created_at | TIMESTAMP | NOT NULL | 가입 시각 |

## 2. posts

공동구매 글의 정보를 저장한다.

| 컬럼 | 타입 | 제약조건 | 역할 |
|---|---|---|---|
| id | UUID | PK | 공동구매 글 고유 ID |
| author_id | UUID | FK → profiles.id, NOT NULL | 글을 만든 모집자 |
| product_name | VARCHAR | NOT NULL | 상품명 |
| product_url | TEXT | NULL 가능 | 상품 구매 링크 |
| image_url | TEXT | NULL 가능 | 상품 이미지 주소 |
| total_price | INTEGER | NOT NULL | 상품 총 가격 |
| total_quantity | INTEGER | NOT NULL | 상품 총 수량 |
| host_quantity | INTEGER | NOT NULL | 모집자가 기본적으로 가져갈 수량 |
| deadline | TIMESTAMPTZ | NOT NULL | 모집 마감 시간 |
| pickup_location | VARCHAR | NOT NULL | 픽업 장소 |
| shortfall_policy | VARCHAR | NOT NULL | 모집 미달 시 처리 방식 |
| status | VARCHAR | NOT NULL | 현재 거래 상태 |
| created_at | TIMESTAMPTZ | NOT NULL | 글 생성 시간 |

## 3. participations

사용자가 특정 공동구매 글에 참여한 정보를 저장한다.

| 컬럼 | 타입 | 제약조건 | 역할 |
|---|---|---|---|
| id | UUID | PK | 참여 정보 고유 ID |
| post_id | UUID | FK → posts.id, NOT NULL | 어떤 공동구매에 참여했는지 |
| user_id | UUID | FK → profiles.id, NOT NULL | 누가 참여했는지 |
| quantity | INTEGER | NOT NULL | 참여 수량 |
| created_at | TIMESTAMPTZ | NOT NULL | 참여한 시간 |

추가 제약조건:

- `quantity >= 1`
- `(post_id, user_id)` 조합은 UNIQUE

## 4. settlements

모집 마감 후 참여자의 최종 정산 정보를 저장한다.

| 컬럼 | 타입 | 제약조건 | 역할 |
|---|---|---|---|
| id | UUID | PK | 정산 정보 고유 ID |
| participation_id | UUID | FK → participations.id, UNIQUE, NOT NULL | 어떤 참여에 대한 정산인지 |
| amount | INTEGER | NOT NULL | 최종 결제 금액 |
| payment_status | VARCHAR | NOT NULL, DEFAULT 'UNPAID' | 송금 상태 |
| sent_at | TIMESTAMPTZ | NULL 가능 | 참여자가 '송금했어요'를 누른 시간 |
| confirmed_at | TIMESTAMPTZ | NULL 가능 | 모집자가 입금 확인한 시간 |
| created_at | TIMESTAMPTZ | NOT NULL | 정산 정보 생성 시간 |

payment_status 값:

- UNPAID
- SENT
- CONFIRMED
