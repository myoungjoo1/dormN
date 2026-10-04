# DormN Project Guide

## 1. 프로젝트 개요

**DormN**은 기숙사 거주 학생들이 대용량 상품이나 배달음식 등을 함께 공동구매하고, 모집부터 참여·정산·주문·픽업까지 관리할 수 있도록 하는 모바일 앱이다.

이 프로젝트는 단순히 앱을 빠르게 완성하는 것뿐 아니라, 개발자가 직접 **백엔드와 데이터베이스 구조를 공부하면서 구현하는 것**을 중요한 목표로 한다.

핵심 흐름은 다음과 같다.

```text
공동구매 글 작성
→ 참여자 모집
→ 모집 마감
→ 개인별 금액 정산
→ 송금 확인
→ 모집자 주문
→ 상품 도착
→ 기숙사 내 픽업
→ 거래 완료
```

---

# 2. 현재 프로젝트 상태

현재는 개발 시작 단계이다.

완료된 것:

```text
- GitHub Repository 생성
- 로컬 프로젝트 폴더 생성
- git init 완료
```

아직 본격적인 코드 구현은 시작하지 않았다.

앞으로 아래 순서대로 개발한다.

```text
Supabase 프로젝트 생성 및 연결 설정
→ ERD 설계
→ PostgreSQL Schema 작성
→ FastAPI 서버 생성
→ FastAPI ↔ PostgreSQL 연결
→ 공동구매 핵심 API 구현
→ Flutter 연결
→ 인증 / 채팅 / 알림 / GPS 등 추가
```

---

# 3. 기술 스택

## Frontend

```text
Flutter
Dart
```

Android / iOS 앱을 하나의 코드베이스로 개발한다.

Flutter 개발은 백엔드 핵심 기능이 어느 정도 완성된 뒤 시작한다.

---

## Backend

```text
Python
FastAPI
```

FastAPI에서 직접 다음을 구현한다.

```text
REST API
Request / Response
Validation
Business Logic
Authentication 확인
Authorization
Error Handling
Transaction
State Management
```

---

## Database

```text
PostgreSQL
Supabase PostgreSQL
```

개발 중에는 Docker나 Supabase Local을 사용하지 않고, 별도로 생성한 Supabase 프로젝트의 PostgreSQL에 직접 연결한다.

운영 단계에서는 개발 환경과 분리된 Supabase PostgreSQL 프로젝트를 사용할 예정이다.

Supabase의 자동 API에 핵심 로직을 맡기지 않고 기본적으로 다음 구조를 사용한다.

```text
Flutter
↓ HTTP
FastAPI
↓ SQL
PostgreSQL
```

DB 구조와 SQL은 가능한 한 직접 설계하고 공부하면서 작성한다.

---

## 추가 기술

추후 필요할 때 추가한다.

```text
Supabase Auth
→ 인증

Kakao Login
→ 로그인

Supabase Storage
→ 상품 이미지

FastAPI WebSocket
→ 채팅

Firebase Cloud Messaging
→ Push 알림

GPS / Location
→ 기숙사 체류 인증
```

---

# 4. 핵심 MVP

첫 번째 목표는 모든 기능을 만드는 것이 아니다.

**공동구매 하나가 실제로 처음부터 끝까지 진행될 수 있는 최소 기능**을 먼저 만든다.

예:

```text
사용자 A

햇반 24개 공동구매 글 작성
↓
사용자 B가 4개 참여
↓
사용자 C가 6개 참여
↓
모집 마감
↓
각 사용자 금액 계산
↓
정산
↓
거래 진행
```

첫 번째 Vertical Slice의 목표는 다음이다.

> 공동구매 글을 만들고, 다른 사용자가 글을 조회한 뒤 원하는 수량으로 참여할 수 있다.

---

# 5. 초기 핵심 DB

처음부터 모든 테이블을 만들지 않는다.

우선 핵심 거래에 필요한 테이블만 설계한다.

```text
profiles
posts
participations
settlements
```

추후 추가할 예정:

```text
dorm_verifications
chat_rooms
chat_room_members
messages
pickups
```

---

# 6. 사용자 구조

추후 Supabase Auth를 사용할 예정이므로 인증 사용자와 서비스 사용자 정보를 분리하는 방향을 우선 고려한다.

예:

```text
auth.users
    │
    │ 1 : 1
    ↓
profiles
```

`profiles`에는 DormN에서 필요한 사용자 정보를 저장한다.

예상 정보:

```text
id
room_number
dorm_verified
dorm_verified_at
bank_name
bank_account
created_at
```

정확한 컬럼은 ERD 설계 단계에서 확정한다.

---

# 7. 공동구매 Post

공동구매 글에는 대략 다음 정보가 필요하다.

```text
작성자
상품명
상품 URL
상품 이미지
총 가격
총 수량
모집자가 기본적으로 가져갈 수량
모집 마감시간
픽업 장소
모집 미달 정책
현재 거래 상태
```

정확한 컬럼과 타입은 DB 설계 단계에서 확정한다.

---

# 8. 참여 Participation

사용자는 공동구매 글에 원하는 수량으로 참여한다.

최소 참여 수량:

```text
1
```

참여 과정에서 서버는 최소한 다음을 검사해야 한다.

```text
1. Post가 존재하는가?
2. 현재 모집중인가?
3. deadline이 지나지 않았는가?
4. 남은 수량이 충분한가?
5. 요청한 수량이 올바른가?
6. 참여 금액은 얼마인가?
7. 참여 정보를 저장할 수 있는가?
```

참여 수량과 가격 계산은 반드시 서버에서 처리한다.

클라이언트가 보내는 계산 결과를 그대로 신뢰하지 않는다.

---

# 9. 동시 참여

중요한 백엔드 학습 포인트이다.

예:

```text
남은 수량: 2

사용자 A → 2개 참여 요청
사용자 B → 2개 참여 요청
```

두 요청이 거의 동시에 도착해도 둘 다 성공하면 안 된다.

다음 작업이 하나의 안전한 단위처럼 처리되어야 한다.

```text
남은 수량 확인
+
참여 정보 저장
+
수량 반영
```

이를 위해 PostgreSQL Transaction과 동시성 처리를 공부하면서 구현한다.

---

# 10. 가격 계산

## 묶음 상품

기본적으로 수량 비례 계산을 사용한다.

```text
개인 금액
=
총 가격 × 개인 수량 / 총 수량
```

원 단위 나머지가 발생하면 모집자가 부담하는 방향을 우선 고려한다.

---

## 배달음식

배달음식 등 같이 먹는 상품은 기본적으로 참여 인원 기준 균등 N빵을 고려한다.

세부 메뉴별 금액까지 DormN에서 복잡하게 계산하는 것은 MVP 범위에서 제외한다.

---

# 11. 모집 마감

각 Post는 반드시 `deadline`을 가진다.

마감 시 기본 상태 변화:

```text
RECRUITING
→
CLOSED
```

모집 조건을 만족하지 못한 경우:

```text
RECRUITING
→
CANCELLED
```

`deadline` 자체가 실제 모집 가능 여부를 판단하는 기준이다.

Scheduler는 상태를 자동 변경하는 보조 수단으로 사용한다.

---

# 12. 모집 미달 정책

글 작성 시 모집자가 두 가지 중 하나를 선택한다.

## KEEP_BY_HOST

남은 수량을 모집자가 가져간다.

예:

```text
총 수량 24

모집자 기본 수량 4
다른 참여자 총 수량 8

남은 수량 12

→ 모집자가 최종적으로 16개를 가져감
```

---

## CANCEL_IF_SHORT

전체 수량이 모집되지 않으면 거래를 취소한다.

```text
RECRUITING
→
CANCELLED
```

---

# 13. 정산

참여 직후 바로 송금하지 않는다.

기본 흐름:

```text
참여
↓
모집 진행
↓
모집 마감
↓
거래 성립 여부 확인
↓
최종 수량 확정
↓
최종 금액 확정
↓
송금
```

모집 실패 시 환불 문제를 만들지 않기 위한 구조이다.

---

# 14. Settlement 상태

기본 정산 상태:

```text
UNPAID
→
SENT
→
CONFIRMED
```

의미:

```text
UNPAID
아직 송금하지 않음

SENT
참여자가 "송금했어요" 버튼을 누름

CONFIRMED
모집자가 실제 계좌를 확인한 뒤 입금을 확인함
```

DormN 자체에서 실제 송금을 처리하지 않는다.

사용자에게 다음 기능만 제공한다.

```text
계좌번호 표시
계좌번호 복사
본인 결제금액 표시
외부 은행 앱 연결
송금 상태 관리
```

---

# 15. 거래 상태

Post의 기본 상태 흐름:

```text
RECRUITING
↓
CLOSED
↓
ORDERED
↓
ARRIVED
↓
PICKUP
↓
COMPLETED
```

예외:

```text
CANCELLED
```

잘못된 상태 변경은 허용하지 않는다.

예:

```text
RECRUITING
→
ARRIVED
```

직접 변경 불가.

상태 변경 가능 여부는 서버에서 검사한다.

---

# 16. 권한

모집자와 참여자의 권한을 구분한다.

예:

```text
모집자만 가능

CLOSED → ORDERED
ORDERED → ARRIVED
ARRIVED → PICKUP
```

사용자는 본인의 정산 정보만 조회할 수 있어야 한다.

다른 참여자의 개인 결제금액은 일반 참여자가 볼 수 없다.

---

# 17. 참여 취소 정책

MVP에서는 참여자가 앱에서 바로 참여를 취소하는 기능을 제공하지 않는다.

참여 전 확인창을 제공한다.

예:

```text
4개
예상 금액 3,817원

참여 이후 앱에서 직접 취소할 수 없습니다.
변경이 필요한 경우 모집자와 협의해주세요.
```

추후 채팅에서 모집자와 협의한 뒤 수정하는 방식은 고려할 수 있다.

---

# 18. 기숙사 사용자 이름

서비스 내부 공개 이름은 실명이 아니라 **호실 기반 이름**을 사용한다.

예:

```text
717-1
717-2
709-1
709-2
```

한 호실 슬롯에는 하나의 계정만 등록할 수 있도록 한다.

실명은 다른 사용자에게 공개하지 않는다.

---

# 19. 기숙사 인증

DormN은 기숙사 거주자를 대상으로 한다.

최종적으로는 GPS를 이용하여 특정 시간대에 사용자가 실제 기숙사 범위에 일정 시간 존재했는지를 확인하는 방식을 고려한다.

예:

```text
00:15 기숙사 범위 내부
01:20 기숙사 범위 내부
02:45 기숙사 범위 내부

→ 인증 성공
```

GPS 원본 위치 데이터를 장기간 저장하지 않는 방향을 우선 고려한다.

DB에는 가능한 경우 다음과 같이 최소한의 결과만 저장한다.

```text
dorm_verified = true
dorm_verified_at = timestamp
```

GPS 기능은 MVP 핵심 거래 기능이 완성된 이후 구현한다.

---

# 20. 채팅

추후 두 종류의 채팅을 구현한다.

```text
1:1 채팅
공동구매 단체 채팅
```

각 공동구매에는 하나의 단체 채팅방이 연결된다.

예:

```text
햇반 24개 공동구매
└── Group Chat Room
```

채팅은 초기 핵심 개발 범위에 포함하지 않는다.

---

# 21. Push 알림

Firebase Cloud Messaging을 사용할 예정이다.

예상 알림:

```text
모집 마감
송금 요청
입금 확인
상품 주문
상품 도착
픽업 요청
미수령자 알림
```

Push 역시 핵심 거래 기능 이후 구현한다.

---

# 22. 초기 API 예상

확정된 API 명세는 아니며 구현하면서 구체화한다.

```text
GET    /posts
POST   /posts
GET    /posts/{post_id}

POST   /posts/{post_id}/join

GET    /posts/{post_id}/settlement/me

POST   /settlements/{id}/sent
POST   /settlements/{id}/confirm

PATCH  /posts/{post_id}/status
```

추후:

```text
POST /auth/kakao

GET /users/me

POST /dorm/verify

POST /pickups/{id}/complete

GET /chatrooms
POST /chatrooms/{id}/messages
```

---

# 23. 개발 순서

반드시 대략 다음 순서를 따른다.

## Phase 1 — 프로젝트 환경

```text
Repository
↓
프로젝트 기본 구조
↓
Supabase 프로젝트 생성 및 연결 설정
↓
Supabase PostgreSQL 연결 확인
```

---

## Phase 2 — DB

```text
핵심 ERD 설계

profiles
posts
participations
settlements

↓

PK / FK / Constraint 결정

↓

SQL Schema 작성

↓

Migration 작성

↓

Supabase PostgreSQL에 적용
```

---

## Phase 3 — FastAPI

가장 작은 서버부터 만든다.

```text
GET /hello
```

정상 실행을 먼저 확인한다.

그 후 PostgreSQL 연결.

```text
FastAPI
↓
DATABASE_URL
↓
PostgreSQL
```

---

## Phase 4 — 핵심 거래 API

순서:

```text
POST /posts
↓
GET /posts
↓
GET /posts/{post_id}
↓
POST /posts/{post_id}/join
```

여기까지 Flutter 없이 API 테스트 도구를 사용해서 먼저 검증한다.

---

## Phase 5 — 거래 로직

```text
동시 참여
Transaction
모집 마감
미달 정책
Settlement
거래 상태
권한 검사
```

---

## Phase 6 — Flutter

백엔드 핵심 기능이 작동한 뒤 Flutter를 연결한다.

처음에는:

```text
홈
↓
GET /posts
↓
공동구매 목록 표시
```

그다음:

```text
글 작성
상세 페이지
수량 선택
참여
정산
```

순으로 구현한다.

---

## Phase 7 — 부가 기능

핵심 거래가 정상 작동한 이후 추가한다.

```text
Kakao Login
Supabase Auth
사용자 / 호실 등록
상품 이미지
Supabase Storage
1:1 채팅
공동구매 단체 채팅
WebSocket
FCM Push
픽업
GPS 인증
상품 URL 정보 추출
UI/UX 개선
실제 서버 배포
```

---

# 24. 초반에 하지 않을 것

아래 기능을 초반부터 구현하지 않는다.

```text
카카오 로그인
GPS
실시간 채팅
Push 알림
AWS
상품 크롤링
복잡한 UI
완벽한 예외처리
과도한 아키텍처 설계
```

핵심 데이터 구조와 거래 로직을 먼저 완성한다.

---

# 25. 개발 원칙

기능 하나를 구현할 때 항상 다음 순서로 생각한다.

```text
1. DB에 어떤 데이터가 필요한가?

↓

2. FastAPI는 어떤 요청을 받아야 하는가?

↓

3. 서버에서 어떤 검증과 로직을 처리해야 하는가?

↓

4. 어떤 Response를 반환해야 하는가?

↓

5. Flutter에서는 이 결과를 어떻게 보여줄 것인가?
```

---

# 26. 학습 목적

이 프로젝트의 중요한 목적 중 하나는 개발자가 백엔드와 DB를 직접 이해하는 것이다.

따라서 가능한 경우 바로 복잡한 라이브러리나 추상화에 의존하기보다 먼저 기본 동작을 이해한다.

특히 다음을 직접 공부하면서 구현한다.

```text
HTTP Request / Response

REST API

GET
POST
PATCH
DELETE

HTTP Status Code

PostgreSQL

CREATE TABLE
SELECT
INSERT
UPDATE
DELETE

WHERE
ORDER BY
JOIN
GROUP BY

PRIMARY KEY
FOREIGN KEY
UNIQUE
NOT NULL
CHECK

INDEX

TRANSACTION
```

SQL 기본 구조를 이해한 뒤 필요하면 SQLAlchemy 같은 ORM을 도입한다.

---

# 27. Codex 작업 원칙

이 프로젝트에서 코드를 작성하거나 수정할 때 다음 원칙을 따른다.

### 1. 과도하게 복잡하게 만들지 않는다.

현재는 학습용 MVP 단계다.

필요하지 않은 Design Pattern, 추상화 계층, Microservice 구조 등을 임의로 추가하지 않는다.

---

### 2. 요청하지 않은 기능을 미리 구현하지 않는다.

예:

```text
현재 Post API를 만드는 중인데

채팅
Push
GPS
Kakao Login
AWS
```

등을 미리 추가하지 않는다.

---

### 3. 기존 구조를 우선 이해한 뒤 수정한다.

파일을 수정하기 전에 관련 파일과 현재 구현 방식을 먼저 확인한다.

기존 코드를 불필요하게 전면 재작성하지 않는다.

---

### 4. DB 로직은 특히 명확하게 작성한다.

다음이 코드에서 분명하게 드러나야 한다.

```text
어떤 SQL이 실행되는지

Transaction 범위가 어디인지

어떤 Constraint가 있는지

왜 해당 FK가 필요한지
```

---

### 5. 보안과 권한 검사는 서버에서 처리한다.

Flutter에서 버튼을 숨기는 것만으로 권한을 제한했다고 판단하지 않는다.

예:

```text
모집자만 가능한 API
→ FastAPI에서 실제 작성자인지 검사
```

---

### 6. 클라이언트 값을 그대로 신뢰하지 않는다.

예:

```text
사용자가 보낸 금액
남은 수량
거래 상태
권한 정보
```

등은 가능한 경우 DB와 서버 상태를 기준으로 다시 계산하거나 검증한다.

---

### 7. 중요한 로직에는 이유를 설명한다.

특히 개발자가 아직 백엔드/DB를 학습하고 있으므로 다음과 같은 코드에는 간단한 설명을 제공한다.

```text
Transaction
JOIN
Foreign Key
Constraint
async / await
Dependency Injection
Authentication
Authorization
```

단순 문법마다 과도한 주석을 달 필요는 없다.

---

### 8. 한 번에 작은 단위로 구현한다.

예:

```text
GET /hello 성공

↓

DB 연결 성공

↓

POST /posts 성공

↓

GET /posts 성공
```

각 단계가 작동하는 것을 확인한 뒤 다음 단계로 이동한다.

---

### 9. 변경 후 검증한다.

가능한 경우 변경한 기능에 대해 다음을 확인한다.

```text
서버 실행 가능 여부
Syntax Error 여부
API Response
DB 저장 결과
예외 상황
```

---

# 28. 현재 최우선 작업

현재 프로젝트는 막 시작한 상태이다.

따라서 지금 당장 집중할 것은 다음이다.

```text
1. 프로젝트 기본 폴더 구조 생성

2. Supabase 프로젝트 생성 및 연결 설정

3. Supabase PostgreSQL 연결 확인

4. 핵심 ERD 설계

5. SQL Schema 작성

6. FastAPI 최소 서버 생성

7. FastAPI와 PostgreSQL 연결
```

이 단계가 완료되기 전에는 Flutter UI 구현이나 인증, 채팅, GPS 등의 기능으로 넘어가지 않는다.

---

# 29. 최종 방향

DormN의 핵심 구조는 다음과 같다.

```text
┌─────────────────┐
│     Flutter     │
│    DormN App    │
└────────┬────────┘
         │
         │ HTTP
         ▼
┌─────────────────┐
│     FastAPI     │
│                 │
│ API             │
│ Validation      │
│ Permission      │
│ Business Logic  │
│ Transaction     │
│ Settlement      │
│ State Machine   │
└────────┬────────┘
         │
         │ SQL
         ▼
┌─────────────────┐
│   PostgreSQL    │
│    Supabase     │
└─────────────────┘
```

핵심 원칙:

> **DB → FastAPI → Flutter 순서로 핵심 거래 기능을 먼저 만들고, 인증·채팅·Push·GPS 등의 기능은 이후 단계적으로 추가한다.**
