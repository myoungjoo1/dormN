-- =========================================
-- DormN Database Schema
-- =========================================


-- 1. profiles
CREATE TABLE profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    room_number VARCHAR(20) NOT NULL UNIQUE,

    dorm_verified BOOLEAN NOT NULL DEFAULT FALSE,
    dorm_verified_at TIMESTAMPTZ,

    bank_name VARCHAR(50),
    bank_account VARCHAR(100),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- 2. posts
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    author_id UUID NOT NULL
        REFERENCES profiles(id),

    product_name VARCHAR(200) NOT NULL,

    product_url TEXT,
    image_url TEXT,

    total_price INTEGER NOT NULL
        CHECK (total_price > 0),

    total_quantity INTEGER NOT NULL
        CHECK (total_quantity > 0),

    host_quantity INTEGER NOT NULL
        CHECK (host_quantity >= 1),

    deadline TIMESTAMPTZ NOT NULL,

    pickup_location VARCHAR(200) NOT NULL,

    shortfall_policy VARCHAR(30) NOT NULL
        CHECK (
            shortfall_policy IN (
                'KEEP_BY_HOST',
                'CANCEL_IF_SHORT'
            )
        ),

    status VARCHAR(30) NOT NULL DEFAULT 'RECRUITING'
        CHECK (
            status IN (
                'RECRUITING',
                'CLOSED',
                'ORDERED',
                'ARRIVED',
                'PICKUP',
                'COMPLETED',
                'CANCELLED'
            )
        ),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK (host_quantity <= total_quantity)
);


-- 3. participations
CREATE TABLE participations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    post_id UUID NOT NULL
        REFERENCES posts(id),

    user_id UUID NOT NULL
        REFERENCES profiles(id),

    quantity INTEGER NOT NULL
        CHECK (quantity >= 1),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (post_id, user_id)
);


-- 4. settlements
CREATE TABLE settlements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    participation_id UUID NOT NULL UNIQUE
        REFERENCES participations(id),

    amount INTEGER NOT NULL
        CHECK (amount >= 0),

    payment_status VARCHAR(20) NOT NULL DEFAULT 'UNPAID'
        CHECK (
            payment_status IN (
                'UNPAID',
                'SENT',
                'CONFIRMED'
            )
        ),

    sent_at TIMESTAMPTZ,
    confirmed_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);