# DormN ERD

DormN MVP의 핵심 데이터 구조를 정리한다.

현재 우선 구현하는 핵심 테이블은 다음 4개이다.

```text
users
posts
participations
settlements

추후 채팅, 픽업, 알림, 수경재 인증 기록 등의 기능이 추가되면
관련 테이블을 별도로 확장한다.
1. users
DormN 사용자의 서비스 내 정보를 저장한다.
비로그인 사용자는 users 테이블에 생성하지 않는다.
카카오 로그인을 완료한 사용자가 DormN 계정을 가지게 되며,
수경재 인증을 완료하기 전까지는 일부 기능만 사용할 수 있다.
컬럼
컬럼	타입	제약조건	역할
id	BIGINT	PRIMARY KEY, 자동 생성	DormN 내부 사용자 고유 ID
kakao_id	TEXT	UNIQUE, NOT NULL	카카오 계정 식별값
room_number	VARCHAR(20)	UNIQUE, NULL 가능	DormN에서 사용하는 호실명
dorm_verified	BOOLEAN	NOT NULL, DEFAULT FALSE	수경재 인증 완료 여부
dorm_verified_at	TIMESTAMPTZ	NULL 가능	수경재 인증 완료 시각
created_at	TIMESTAMPTZ	NOT NULL, DEFAULT NOW()	DormN 계정 생성 시각


예시
카카오 로그인만 완료한 상태:
id = 1
kakao_id = "kakao_user_123"
room_number = NULL
dorm_verified = false
dorm_verified_at = NULL

수경재 인증까지 완료한 상태:
id = 1
kakao_id = "kakao_user_123"
room_number = "717-1"
dorm_verified = true
dorm_verified_at = 인증 완료 시각

room_number
DormN에서는 일반 닉네임을 사용하지 않는다.
사용자가 다른 사용자에게 표시되는 이름은 호실명이다.
예:
717-1
717-2
709-1

한 호실명은 한 사용자만 사용할 수 있다.
따라서 room_number에는 UNIQUE 제약조건을 적용한다.
카카오 로그인 직후에는 아직 호실 인증을 하지 않았기 때문에
room_number는 NULL일 수 있다.
수경재 인증
최종 가입 흐름은 다음과 같다.
카카오 로그인
↓
수경재 위치 + 시간 기반 인증
↓
호실명 설정
↓
관생증 촬영
↓
기기 내 OCR
↓
수경재 / 현재 학기 / 호실 확인
↓
인증 성공

인증이 완료되면:
dorm_verified = true
dorm_verified_at = 인증 시각

으로 변경한다.
개인정보 저장 원칙
users 테이블에는 서비스 운영에 필요한 최소한의 정보만 저장한다.
다음 정보는 저장하지 않는다.
실명
학번
학생증 정보
관생증 원본 사진
OCR 전체 결과
GPS 원본 위치 기록
은행명
계좌번호

관생증 인증에서는 필요한 정보만 확인한다.
수경재 관생증 여부
현재 학기
호실 번호

2. posts
공동구매 모집글 정보를 저장한다.
한 사용자는 여러 개의 공동구매 글을 작성할 수 있다.
컬럼
컬럼	타입	제약조건	역할
id	BIGINT	PRIMARY KEY, 자동 생성	공동구매 글 고유 ID
author_id	BIGINT	FK → users.id, NOT NULL	모집자
product_name	VARCHAR(200)	NOT NULL	상품명
product_url	TEXT	NULL 가능	상품 판매 페이지 URL
image_url	TEXT	NULL 가능	상품 이미지 URL
total_price	INTEGER	NOT NULL, 0보다 큼	전체 상품 가격
total_quantity	INTEGER	NOT NULL, 0보다 큼	전체 상품 수량
host_quantity	INTEGER	NOT NULL, 1 이상	모집자가 기본적으로 가져갈 수량
deadline	TIMESTAMPTZ	NOT NULL	모집 마감 시각
pickup_location	VARCHAR(200)	NOT NULL	상품 픽업 장소
shortfall_policy	VARCHAR(30)	NOT NULL	모집 미달 처리 방식
status	VARCHAR(30)	NOT NULL, DEFAULT RECRUITING	현재 거래 상태
created_at	TIMESTAMPTZ	NOT NULL, DEFAULT NOW()	글 작성 시각


작성자
author_id는 글을 작성한 사용자의 users.id를 저장한다.
예:
users

id = 1
room_number = "717-1"

해당 사용자가 글을 작성했다면:
posts

id = 10
author_id = 1
product_name = "햇반 24개"

이 된다.
모집 미달 처리
shortfall_policy는 두 가지 값을 사용한다.
KEEP_BY_HOST
남은 수량을 모집자가 가져간다.

예:
총 수량: 24개

모집자 기본 수량: 4개
참여자 모집 수량: 8개

남은 수량: 12개

→ 모집자가 남은 12개를 추가로 가져감

CANCEL_IF_SHORT
전량 모집되지 않으면 거래를 취소한다.

마감 시점에 전체 수량이 모집되지 않았다면
해당 공동구매의 상태를 CANCELLED로 변경한다.
거래 상태
status는 다음 값을 사용한다.
RECRUITING
모집중

↓

CLOSED
모집마감

↓

ORDERED
주문완료

↓

ARRIVED
배송도착

↓

PICKUP
픽업중

↓

COMPLETED
거래완료

예외 상태:
CANCELLED
거래취소

잘못된 상태 변경은 서버에서 차단한다.
예:
RECRUITING
→ ARRIVED

불가능

3. participations
사용자가 특정 공동구매에 몇 개 참여했는지 저장한다.
users와 posts를 연결하는 역할을 한다.
컬럼
컬럼	타입	제약조건	역할
id	BIGINT	PRIMARY KEY, 자동 생성	참여 고유 ID
post_id	BIGINT	FK → posts.id, NOT NULL	참여한 공동구매
user_id	BIGINT	FK → users.id, NOT NULL	참여 사용자
quantity	INTEGER	NOT NULL, 1 이상	참여 수량
created_at	TIMESTAMPTZ	NOT NULL, DEFAULT NOW()	참여 시각


예시
사용자

users.id = 2
room_number = "709-2"

이 사용자가:
posts.id = 10
햇반 24개 공동구매

에 4개 참여한다면:
participations

id = 1
post_id = 10
user_id = 2
quantity = 4

가 된다.
중복 참여
한 사용자가 같은 공동구매에 참여 레코드를 여러 개 만들지 않도록 한다.
UNIQUE(post_id, user_id)

예:
post_id = 10
user_id = 2

인 데이터가 이미 존재한다면
같은 조합을 한 번 더 생성할 수 없다.
수량 변경이 필요하다면 새로운 참여 데이터를 만드는 것이 아니라
기존 참여 정보의 quantity를 변경하는 방식으로 처리한다.
참여 시 확인해야 할 내용
참여 API에서는 다음 내용을 확인한다.
Post가 존재하는가?

↓

현재 RECRUITING 상태인가?

↓

deadline이 지나지 않았는가?

↓

요청한 수량이 1개 이상인가?

↓

남은 수량이 충분한가?

↓

정상이라면 Participation 생성

동시에 여러 사용자가 참여하는 경우
수량 초과가 발생하지 않도록 Transaction을 사용한다.
4. settlements
공동구매 모집이 끝난 뒤
각 참여자의 정산 정보를 저장한다.
하나의 Participation에는 하나의 Settlement만 존재한다.
모집 상태가 CLOSED가 될 때만 정산을 생성하며,
CANCELLED 상태에서는 생성하지 않는다.
모집 마감 시점의 참여 수량으로 금액을 확정하고 이후 자동 재계산하지 않는다.
컬럼
컬럼	타입	제약조건	역할
id	BIGINT	PRIMARY KEY, 자동 생성	정산 고유 ID
participation_id	BIGINT	FK → participations.id, UNIQUE, NOT NULL	해당 정산의 참여 정보
amount	INTEGER	NOT NULL, 0 이상	최종 송금 금액
payment_status	VARCHAR(20)	NOT NULL, DEFAULT UNPAID	송금 상태
sent_at	TIMESTAMPTZ	NULL 가능	참여자가 송금했다고 표시한 시각
confirmed_at	TIMESTAMPTZ	NULL 가능	모집자가 입금을 확인한 시각
created_at	TIMESTAMPTZ	NOT NULL, DEFAULT NOW()	정산 생성 시각


정산 금액
묶음 상품은 기본적으로 참여 수량에 비례하여 계산한다.
개인 금액
=
총 가격 × 개인 수량 // 총 수량

실수 계산이나 반올림을 사용하지 않고 정수 나눗셈으로 내림 처리한다.
예를 들어 총 가격이 22,900원이고 총 수량이 24개일 때
4개 참여자의 금액은 22,900 × 4 // 24 = 3,816원이다.

정확히 나누어지지 않아 발생하는 원 단위 차이는
모집자가 부담하는 방향으로 처리한다.
모집자 부담액은 총 가격에서 참여자 정산 금액 합계를 뺀 금액으로 계산한다.
따라서 참여자 정산금액 합계와 모집자 부담액의 합은 항상 총 가격이 된다.
송금 상태
payment_status는 다음 세 가지 값을 사용한다.
UNPAID
아직 송금하지 않은 상태

SENT
참여자가 [송금했어요] 버튼을 누른 상태

이때:
sent_at = 현재 시각

을 기록한다.
CONFIRMED
모집자가 실제 계좌를 확인하고
[입금 확인] 버튼을 누른 상태

이때:
confirmed_at = 현재 시각

을 기록한다.
5. 핵심 테이블 관계
전체 관계는 다음과 같다.
users
│
├── 1 : N ───── posts
│                │
│                │
│                └── 1 : N ───── participations
│                                   │
│                                   │
│                                   └── 1 : 1 ───── settlements
│
└── 1 : N ───── participations

쉽게 보면:
User
├── 여러 Post 작성 가능
└── 여러 Post 참여 가능

Post
├── 작성자 1명
└── 참여자 여러 명

Participation
├── User 1명
├── Post 1개
└── Settlement 1개

Settlement
└── Participation 하나의 정산 정보

6. 실제 데이터 관계 예시
사용자
users

id = 1
room_number = "717-1"

id = 2
room_number = "709-2"

공동구매
717-1이 햇반 공동구매를 작성한다.
posts

id = 10
author_id = 1
product_name = "햇반 24개"
total_price = 22900
total_quantity = 24
host_quantity = 4
status = "RECRUITING"

참여
709-2가 4개 참여한다.
participations

id = 20
post_id = 10
user_id = 2
quantity = 4

정산
모집이 마감되면 해당 참여자의 정산 정보가 생성된다.
settlements

id = 30
participation_id = 20
amount = 3816
payment_status = "UNPAID"

전체 연결:
717-1
users.id = 1

↓ 작성

햇반 공동구매
posts.id = 10

↑ 참여

709-2
users.id = 2

↓

participations.id = 20
quantity = 4

↓

settlements.id = 30
amount = 3816
UNPAID

7. 계좌정보
모집자의 은행명과 계좌번호는
users 테이블에 저장하지 않는다.
계좌정보는 사용자 프로필에 영구적으로 귀속되는 정보가 아니라
특정 공동구매 거래에 사용되는 정보로 취급한다.
기본 방향:
모집자가 공동구매 건별로 계좌정보 입력

↓

모집 진행 중에는 참여자에게 공개하지 않음

↓

모집 마감 후 해당 공동구매 참여자에게만 공개

↓

거래 종료 후 삭제 가능

정확한 저장 방식과 별도 테이블 구조는
정산 기능 구현 단계에서 결정한다.
8. 비로그인 사용자
비로그인 사용자는 users 테이블에 저장하지 않는다.
비로그인 상태에서도 다음 기능은 사용할 수 있다.
공동구매 목록 조회
공동구매 상세 조회

다음 기능은 수경재 인증까지 완료한 사용자만 사용할 수 있다.
공동구매 작성
공동구매 참여
채팅
정산

9. 추후 추가할 테이블
현재 MVP의 핵심 거래 구조가 완성된 이후 다음 기능을 추가한다.
chat_rooms
chat_room_members
messages

pickups

dorm_verifications

필요에 따라 계좌정보 관리용 테이블도
정산 기능 구현 단계에서 추가한다.
10. 현재 핵심 구조
users
│
├── posts
│     │
│     └── participations
│             │
│             └── settlements
│
└── participations

현재 개발에서는 우선 이 네 테이블을 기준으로
공동구매 작성
↓
공동구매 조회
↓
공동구매 참여
↓
모집 마감
↓
정산

흐름을 완성하는 것을 목표로 한다.
