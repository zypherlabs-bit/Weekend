"""Seed 5 synthetic demo profiles next to the probe account (development-only).

Purpose: give the redesigned discovery feed real cards to render so layout
screenshots can be captured from the v2.8.1 APK. This mirrors the existing
synthetic-account pattern in tool/setup_live_test_users.ps1 and
tool/create_probe_account.py - it writes ONLY to the dev project and uses
obviously-fake @example.com identities.

Flow per profile:
  1. Insert an auth user through the Management API (service role). The
     on_auth_user_created trigger (handle_new_user) creates the profiles /
     user_settings / preferences rows, so we UPDATE rather than INSERT.
  2. UPDATE profiles with an adult date_of_birth, display name, bio, gender,
     and coordinates a couple of kilometres from the probe so the row clears
     every get_nearby_profiles filter (is_active, dating_profile_activated,
     non-empty name, adult age, not snoozed/incognito).
  3. Generate a distinct synthetic portrait JPEG (Pillow, no real people),
     upload it to the private profile-photos bucket, and insert an APPROVED
     profile_photos row so primary_photo_path resolves for the photo-first card.
  4. Link a few interests from the existing catalogue.

Idempotent: reuses an existing wknd.demo.N user if present. Prints only uids
and e-mails (all @example.com fakes); never prints keys or tokens.

Usage: python tool/seed_demo_profiles.py
"""
from __future__ import annotations

import io
import json
import os
import pathlib
import random
import urllib.error
import urllib.request
import uuid

TEMP = pathlib.Path(os.environ.get("TEMP", "."))
TOKEN = (TEMP / "sbp_token.txt").read_text(encoding="utf-8").strip()
REF = "ocypgybqfushqfzisnvs"
ROOT = pathlib.Path(__file__).resolve().parents[1]

# Probe account location (Bangalore). Demo profiles sit 0.5-4 km away so they
# are inside the app's default 50 km discovery radius and order by distance.
PROBE_LAT = 12.9716
PROBE_LON = 77.5946

PROFILES = [
    {
        "name": "Aisha N", "gender": "Woman", "dob": "1997-04-12",
        "intent": "Long-term relationship", "city": "Bengaluru",
        "bio": "Product designer who sketches in cafÃ©s. Will always say yes to filter coffee and a long walk.",
        "occupation": "Product Designer", "offset": (0.011, 0.014),
        "interests": ["Live Music", "Travel", "Movies"],
        "colors": ((255, 111, 97), (108, 47, 216)),
    },
    {
        "name": "Rohan M", "gender": "Man", "dob": "1995-09-03",
        "intent": "Long-term relationship", "city": "Bengaluru",
        "bio": "Backend engineer, weekend trekker. Ask me about the worst bug I've ever shipped.",
        "occupation": "Software Engineer", "offset": (-0.016, 0.021),
        "interests": ["Hiking", "Camping", "Travel"],
        "colors": ((52, 120, 246), (18, 26, 66)),
    },
    {
        "name": "Meera K", "gender": "Woman", "dob": "1999-01-27",
        "intent": "Dating", "city": "Bengaluru",
        "bio": "Half marathoner, full-time plant mom. Sunday farmers market is non-negotiable.",
        "occupation": "Marketing Associate", "offset": (0.027, -0.012),
        "interests": ["Nature walks", "Beach days", "Theatre"],
        "colors": ((240, 147, 51), (122, 66, 12)),
    },
    {
        "name": "Arjun S", "gender": "Man", "dob": "1993-06-18",
        "intent": "Long-term relationship", "city": "Bengaluru",
        "bio": "Photographer chasing golden hour. I'll cook if you handle the playlist.",
        "occupation": "Photographer", "offset": (-0.008, -0.025),
        "interests": ["Movies", "Live music", "Road trips"],
        "colors": ((214, 64, 132), (62, 16, 60)),
    },
    {
        "name": "Leela P", "gender": "Woman", "dob": "2000-11-09",
        "intent": "New people & Friendships", "city": "Bengaluru",
        "bio": "Architecture student, amateur baker. Currently accepting recommendations for live comedy.",
        "occupation": "Architecture Student", "offset": (0.019, 0.031),
        "interests": ["Stand-up comedy", "Travel", "Movies"],
        "colors": ((16, 185, 129), (10, 60, 70)),
    },
]


def env() -> dict:
    out = {}
    for line in (ROOT / ".env").read_text(encoding="utf-8-sig").splitlines():
        s = line.strip()
        if s and not s.startswith("#") and "=" in s:
            k, v = s.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def mgt(method: str, url: str, payload=None, bearer=None, apikey=None,
        raw=None, ctype=None):
    data = raw if raw is not None else (
        json.dumps(payload).encode() if payload is not None else None)
    headers = {"Authorization": "Bearer " + (bearer or TOKEN)}
    if apikey:
        headers["apikey"] = apikey
    headers["Content-Type"] = (ctype or "application/octet-stream") \
        if raw is not None else "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            body = r.read().decode()
            return r.status, (json.loads(body) if body else {})
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(body)
        except json.JSONDecodeError:
            return e.code, body


def service_role() -> str:
    st, body = mgt("GET",
                   f"https://api.supabase.com/v1/projects/{REF}/api-keys?reveal=true")
    if st != 200 or not isinstance(body, list):
        raise SystemExit(f"cannot read api keys: HTTP {st}: {str(body)[:200]}")
    for k in body:
        if k.get("name") == "service_role":
            return k["api_key"]
    raise SystemExit("service_role key not found")


def sql(svc: str, q: str):
    # The Management `database/query` endpoint authenticates with the personal
    # access token (sbp_...), not the service_role JWT - hence no bearer/apikey
    # override here; mgt() defaults bearer to TOKEN.
    st, body = mgt(
        "POST",
        f"https://api.supabase.com/v1/projects/{REF}/database/query",
        {"query": q},
    )
    # The Management database/query endpoint reports success as 201 (and may
    # return 200/202), so anything outside 2xx is the real failure.
    if st not in (200, 201, 202):
        raise SystemExit(f"SQL HTTP {st}: {str(body)[:400]}")
    return body


def portrait(colors, initials: str, size=(900, 1200)) -> bytes:
    """Synthetic gradient 'portrait' with a large monogram. No real person.

    Draws an abstract head-and-shoulders silhouette plus the initials so the
    card gallery is visually distinguishable per profile and per photo.
    """
    from PIL import Image, ImageDraw, ImageFilter, ImageFont

    w, h = size
    (r1, g1, b1), (r2, g2, b2) = colors
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(h):
        t = y / h
        row = (int(r1 + (r2 - r1) * t), int(g1 + (g2 - g1) * t),
               int(b1 + (b2 - b1) * t))
        for x in range(w):
            px[x, y] = row

    # Soft radial highlight behind the head for depth.
    glow = Image.new("L", size, 0)
    gdraw = ImageDraw.Draw(glow)
    cx, cy = w // 2, int(h * 0.42)
    for i in range(18, 0, -1):
        r = int(w * 0.055 * i)
        gdraw.ellipse((cx - r, cy - r, cx + r, cy + r),
                      fill=int(200 - (18 - i) * 9))
    glow = glow.filter(ImageFilter.GaussianBlur(w // 14))
    img = Image.composite(Image.new("RGB", size, (255, 255, 255)), img, glow)

    # Abstract person silhouette (head + shoulders) in a translucent ink.
    ink = Image.new("RGBA", size, (0, 0, 0, 0))
    idraw = ImageDraw.Draw(ink)
    head_r = int(w * 0.16)
    head_cy = int(h * 0.40)
    idraw.ellipse((cx - head_r, head_cy - head_r, cx + head_r, head_cy + head_r),
                  fill=(255, 255, 255, 62))
    body = Image.new("L", size, 0)
    bdraw = ImageDraw.Draw(body)
    bw = int(w * 0.42)
    bdraw.ellipse((cx - bw, head_cy + int(head_r * 0.6),
                   cx + bw, head_cy + int(head_r * 0.6) + int(h * 0.72)),
                  fill=255)
    body = body.filter(ImageFilter.GaussianBlur(w // 40))
    ink.paste((255, 255, 255, 58), (0, 0), body)
    img = Image.alpha_composite(img.convert("RGBA"), ink).convert("RGB")

    # Monogram in a light weight, centred over the silhouette.
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("arialbd.ttf", int(w * 0.30))
    except OSError:
        font = ImageFont.load_default()
    box = d.textbbox((0, 0), initials, font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    d.text(((w - tw) / 2 - box[0], (h * 0.60) - th / 2 - box[1]),
           initials, font=font, fill=(255, 255, 255, 235))

    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=88)
    return buf.getvalue()


def main() -> int:
    e = env()
    base = e["SUPABASE_URL"].rstrip("/")
    svc = service_role()
    admin = base + "/auth/v1/admin/users"
    random.seed(20261019)

    # Interest catalogue: name -> id (first match wins on duplicate names).
    cat = sql(svc, "select id, name from public.interests")
    interest_ids: dict = {}
    for row in (cat if isinstance(cat, list) else []):
        d = row.get("data", row)
        interest_ids.setdefault(d["name"], d["id"])

    st, body = mgt("GET", admin + "?page=1&per_page=200", bearer=svc, apikey=svc)
    users = body.get("users", []) if isinstance(body, dict) else []

    for i, p in enumerate(PROFILES, start=1):
        email = f"wknd.demo.{i}@example.com"

        # 1. Find-or-create the auth user; the trigger builds the profile row.
        existing = next((u for u in users if u.get("email") == email), None)
        if existing:
            uid = existing["id"]
            print(f"demo{i}: reusing uid={uid}")
        else:
            st, body = mgt("POST", admin, {
                "email": email,
                "password": "Demo!234" + uuid.uuid4().hex[:10] + "aA1",
                "email_confirm": True,
                "raw_user_meta_data": {"display_name": p["name"],
                                       "date_of_birth": p["dob"],
                                       "gender": p["gender"]},
            }, bearer=svc, apikey=svc)
            if st not in (200, 201) or not isinstance(body, dict) \
                    or not body.get("id"):
                print(f"demo{i}: create FAILED HTTP {st} {str(body)[:200]}")
                return 1
            uid = body["id"]
            print(f"demo{i}: created uid={uid}")

        lat = PROBE_LAT + p["offset"][0]
        lon = PROBE_LON + p["offset"][1]
        q = lambda s: s.replace("'", "''")  # noqa: E731 - literal escaping
        sql(svc, f"""
            update public.profiles set
              display_name = '{q(p['name'])}',
              date_of_birth = '{p['dob']}',
              gender = '{q(p['gender'])}',
              bio = '{q(p['bio'])}',
              city = '{q(p['city'])}',
              locality = '{q(p['city'])}',
              country = 'IN',
              latitude = {lat},
              longitude = {lon},
              occupation = '{q(p['occupation'])}',
              relationship_intent = '{q(p['intent'])}',
              verification_status = 'verified',
              is_photo_verified = true,
              trust_score = {random.choice([72, 80, 85, 90])},
              profile_completion = 100,
              has_minimum_photos = true,
              is_active = true,
              dating_profile_activated = true,
              deleted_at = null,
              last_active_at = now() - interval '{random.randint(0, 40)} minutes',
              updated_at = now()
            where id = '{uid}';
        """)

        # 2. Synthetic portraits -> private bucket -> APPROVED photo rows so the
        #    photo-first card resolves primary_photo_path. The database requires
        #    a minimum of 4 approved photos (public.minimum_profile_photos());
        #    the on_photo_count_change trigger recomputes
        #    dating_profile_activated from that count, so fewer than 4 leaves
        #    the profile out of get_nearby_profiles entirely.
        initials = "".join(w[0] for w in p["name"].split()[:2]).upper()
        # Storage rows cannot be deleted via SQL (storage.protect_delete()); use
        # the Storage API for each existing object, then clear the photo rows.
        old = sql(svc, f"select storage_path from public.profile_photos "
                       f"where user_id = '{uid}'")
        for row in (old if isinstance(old, list) else []):
            d = row.get("data", row)
            sp = d.get("storage_path")
            if sp:
                mgt("DELETE", f"{base}/storage/v1/object/profile-photos/{sp}",
                    bearer=svc, apikey=svc)
        sql(svc, f"delete from public.profile_photos where user_id = '{uid}';")
        for k in range(4):
            # Vary each portrait slightly (hue shift) so the gallery is not
            # four identical tiles; card 1 stays the primary.
            (r1, g1, b1), (r2, g2, b2) = p["colors"]
            shift = (k * 26) % 90
            colors = (((r1 + shift) % 256, g1, (b1 + shift) % 256),
                      ((r2 + shift) % 256, g2, (b2 + shift) % 256))
            jpg = portrait(colors, initials)
            path = f"{uid}/{uuid.uuid4().hex}.jpg"
            st, _ = mgt("POST", f"{base}/storage/v1/object/profile-photos/{path}",
                        raw=jpg, ctype="image/jpeg", bearer=svc, apikey=svc)
            if st != 200:
                print(f"demo{i}: storage upload FAILED HTTP {st}")
                return 1
            sql(svc, f"""
                insert into public.profile_photos
                  (id, user_id, photo_url, thumbnail_url, is_primary,
                   storage_path, width, height, file_size_bytes, mime_type,
                   moderation_status, sort_order)
                values
                  ('{uuid.uuid4()}', '{uid}', '{path}', '{path}',
                   {str(k == 0).lower()}, '{path}',
                   900, 1200, {len(jpg)}, 'image/jpeg', 'approved', {k});
            """)

        # 3. Interests (skip any missing from the catalogue).
        sql(svc, f"delete from public.user_interests where user_id = '{uid}';")
        for nm in p["interests"]:
            iid = interest_ids.get(nm)
            if not iid:
                continue
            sql(svc, f"""
                insert into public.user_interests (id, user_id, interest_id)
                values ('{uuid.uuid4()}', '{uid}', '{iid}')
                on conflict do nothing;
            """)

        print(f"demo{i}: seeded {p['name']} at ({lat:.4f},{lon:.4f}) photo={path}")

    print("\nSeeded 5 demo profiles near the probe account.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
