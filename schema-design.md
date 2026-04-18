# Tzu Chi University — Community Platform Schema Design

## Overview

Production-grade Supabase schema for Second-hand Trading, Lost & Found, Student Verification, and AI Assistant logging.

---

## Table: `profiles`

Linked to `auth.users` via `id` (UUID). Auto-created on sign-up via trigger.

| Column               | Type                | Constraints                               | Notes                                 |
|----------------------|---------------------|-------------------------------------------|---------------------------------------|
| id                   | uuid                | PK, FK → auth.users(id) ON DELETE CASCADE | Mirrors Supabase Auth UID             |
| full_name            | text                | NOT NULL                                  | Student's real name                   |
| student_id           | text                | UNIQUE, NOT NULL                          | University student number             |
| department           | text                |                                           | e.g., "Medical Sciences"              |
| avatar_url           | text                |                                           | Profile picture URL                   |
| phone_number         | text                |                                           | Contact phone (optional)              |
| line_id              | text                |                                           | LINE messenger handle                 |
| instagram_handle     | text                |                                           | Instagram username (no @)             |
| is_verified          | boolean             | NOT NULL, DEFAULT false                   | Set true when admin approves          |
| student_id_image_url | text                |                                           | URL of uploaded student ID photo      |
| verification_status  | verification_status | NOT NULL, DEFAULT 'pending'               | pending → approved → is_verified=true |
| created_at           | timestamptz         | DEFAULT now()                             |                                       |
| updated_at           | timestamptz         | DEFAULT now()                             |                                       |

---

## Table: `items`

Central table for all listings (Marketplace + Lost & Found).

| Column                   | Type           | Constraints                    | Notes                                          |
|--------------------------|----------------|--------------------------------|------------------------------------------------|
| id                       | uuid           | PK, DEFAULT gen_random_uuid()  |                                                |
| owner_id                 | uuid           | NOT NULL, FK → profiles(id)    | The student who posted the item                |
| title                    | text           | NOT NULL, length 3–120         | Short title                                    |
| description              | text           | NOT NULL, length ≥ 20          | Detailed description                           |
| category                 | item_category  | NOT NULL                       | 'exchange', 'lost', 'found'                    |
| unique_identifier        | text           | NOT NULL, length ≥ 5           | Serial no., brand, distinguishing mark         |
| verification_hint        | text           |                                | Public hint (e.g., "scratch on battery cover") |
| price                    | numeric(10,2)  |                                | NULL for Lost/Found items                      |
| image_urls               | text[]         | DEFAULT '{}'                   | Array of image URLs                            |
| status                   | item_status    | NOT NULL, DEFAULT 'available'  | 'available', 'sold', 'returned'                |
| preferred_contact_method | contact_method | NOT NULL, DEFAULT 'line'       | 'line', 'instagram', 'phone', 'chat'           |
| location_hint            | text           |                                | "Near Library", "Dorm B3", etc.                |
| last_confirmed_at        | timestamptz    | NOT NULL, DEFAULT now()        | Reset by owner via confirm_item() RPC          |
| expires_at               | timestamptz    | GENERATED ALWAYS AS (last_confirmed_at + '7 days') STORED | Auto-computed expiry |
| is_active                | boolean        | NOT NULL, DEFAULT true         | Set false by expire_old_items() after expiry   |
| created_at               | timestamptz    | DEFAULT now()                  |                                                |
| updated_at               | timestamptz    | DEFAULT now()                  |                                                |

---

## Table: `ai_logs`

Stores AI assistant conversations per user.

| Column     | Type        | Constraints                          | Notes              |
|------------|-------------|--------------------------------------|--------------------|
| id         | uuid        | PK, DEFAULT gen_random_uuid()        |                    |
| user_id    | uuid        | FK → profiles(id) ON DELETE SET NULL |                    |
| message    | text        | NOT NULL                             | User's message     |
| response   | text        | NOT NULL                             | AI response        |
| created_at | timestamptz | DEFAULT now()                        |                    |

---

## Relationships

```text
auth.users  (1) ──── (1) profiles
profiles    (1) ──── (N) items
profiles    (1) ──── (N) ai_logs
```

---

## Enums

| Type                  | Values                                    |
|-----------------------|-------------------------------------------|
| `item_category`       | `exchange`, `lost`, `found`               |
| `item_status`         | `available`, `sold`, `returned`           |
| `verification_status` | `pending`, `approved`, `rejected`         |
| `contact_method`      | `line`, `instagram`, `phone`, `chat`      |

---

## RLS Policy Summary

| Table    | Operation | Who Can Perform                                 |
|----------|-----------|-------------------------------------------------|
| profiles | SELECT    | Public (anyone)                                 |
| profiles | INSERT    | Authenticated user (own row only)               |
| profiles | UPDATE    | Authenticated user (own row only)               |
| items    | SELECT    | Public (is_active = true only)                  |
| items    | INSERT    | **Verified** students only (is_verified = true) |
| items    | UPDATE    | Owner only (`auth.uid() = owner_id`)            |
| items    | DELETE    | Owner only (`auth.uid() = owner_id`)            |
| ai_logs  | SELECT    | Owner only (`auth.uid() = user_id`)             |
| ai_logs  | INSERT    | Authenticated user (own row only)               |

---

## RPC Functions

| Function                     | Description                                                          |
|------------------------------|----------------------------------------------------------------------|
| `expire_old_items()`         | Sets `is_active = false` where `expires_at < now()`. Run via pg_cron.|
| `confirm_item(item_id uuid)` | Resets `last_confirmed_at = now()` for the caller's own item.        |
| `search_items(keyword text)` | Returns active items matching keyword in title/description/location. |

---

## Triggers

| Trigger                   | Table      | Action                                       |
|---------------------------|------------|----------------------------------------------|
| `set_profiles_updated_at` | profiles   | Updates `updated_at` on every row update     |
| `set_items_updated_at`    | items      | Updates `updated_at` on every row update     |
| `on_auth_user_created`    | auth.users | Auto-creates a `profiles` row on sign-up     |

---

## Verification Flow

```text
Student signs up
  → profile created (is_verified=false, verification_status='pending')
  → student uploads student ID image URL via My Profile
  → admin sets verification_status='approved', is_verified=true
  → student can now post items
```

## Item Lifecycle

```text
Posted (is_active=true, status='available')
  → owner clicks ✓ Confirm every 7 days → last_confirmed_at resets
  → if not confirmed → expire_old_items() sets is_active=false (hidden)
  → owner marks Sold/Returned → status updated, remains visible to owner
```

---

## Design Decisions

1. **`unique_identifier` is mandatory** — prevents fraud; partially masked on public cards.
2. **`verification_hint`** — a safe public hint so finders know what to look for without revealing the secret detail.
3. **`is_active` + `expires_at`** — keeps the feed fresh; owners must confirm every 7 days.
4. **`is_verified` RLS guard on INSERT** — only verified students can create listings.
5. **`ai_logs` table** — enables conversation history and future personalisation.
6. **`preferred_contact_method`** — surfaces the poster's preference directly on the card.
