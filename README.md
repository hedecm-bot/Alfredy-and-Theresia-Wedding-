# Alfred & Theresia Wedding Invitation and Admission System

A mobile-first starter application for the 5 December 2026 wedding at Ngome Hall, Africa Sana, Mwenge, Dar es Salaam.

## Included
- `index.html`: mobile web app with staff sign-in, QR camera scanning, physical-card name lookup, electronic invitation lookup, individual admission recording, admin guest registration, CSV import/export, and electronic invitation preview.
- `schema.sql`: Supabase database schema, row-level security policies, and atomic duplicate-safe admission function.
- `guest-list-template.csv`: sample import format.

## Important operating model
- Physical cards: one common QR printed on all cards; names are handwritten. Gate staff scan the QR, search/select the registered individual, then tap Admit.
- Electronic cards: each invitation has its own QR and digitally printed guest name(s). Couple members have separate person-level admission records and can arrive separately.
- Public verification does not consume an invitation. Only signed-in gate staff can record admission.
- A unique constraint plus a database function ensures the same individual cannot be admitted twice, including when two gate phones scan at nearly the same time.

## Setup required before live use
1. Create a Supabase project.
2. Open Supabase SQL Editor and run `schema.sql`.
3. In Supabase Authentication, create one admin user and one or more gate users.
4. Copy each user's Auth UUID. As project owner, run the example `INSERT INTO public.staff_profiles...` statements at the bottom of `schema.sql`, replacing UUID, name, and role. Use `admin` for the administrator and `gate` for entrance staff.
5. Host `index.html` on an HTTPS static host (camera scanning requires HTTPS, except localhost).
6. Open the hosted app, enter the Supabase project URL and anon/public key, and sign in.
7. Add/import the invitee list. Use one invitation record per single person or couple. For couples, add two invitee rows under the same invitation.
8. Print the common physical QR by encoding the physical QR URL described below; the event's `physical_qr_code` is in `wedding_events` and must be used as the `physical` query value. Example: `https://YOUR-HOST/?physical=PHYSICAL_QR_CODE`.
9. For electronic invitations, create invitations with delivery type `electronic`, then use Admin > Electronic invitation preview to generate each personalised card. The QR is unique to that invitation.

## CSV import
Use the columns in `guest-list-template.csv`:
`type,delivery,guest1,guest2`

Allowed values: `single` or `couple`; `physical` or `electronic`. For a single guest leave guest2 empty. Keep names comma-free, or quote fields carefully (the simple importer expects comma-separated fields).

## Critical production checks
- Test with at least 20 dummy invitees before importing the real list.
- Test first admission, repeat admission, unknown name, couple arriving separately, and two phones attempting the same admission simultaneously.
- Test camera permissions and mobile data at the actual venue.
- Keep a charged backup phone and a written emergency register. Do not run multiple independent offline admission lists; they cannot guarantee cross-device duplicate prevention.
- Keep the Supabase service-role key private. The browser app must use only the anon/public key. Never place service-role credentials in `index.html`.
- The common physical QR is not a unique security credential; handwritten names must be matched against the registered guest list by gate staff.

## Current status
This is a prepared application package, not a deployed live service. It needs a Supabase project, staff accounts, and HTTPS hosting configuration before it can admit real guests. The SQL and HTML have not been connected to the user's accounts or tested against a live database in this environment.
