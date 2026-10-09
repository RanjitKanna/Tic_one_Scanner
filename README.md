# TicOne Scanner

Gate and boarding app for verifying TicOne **movie** and **bus** tickets. Staff
sign in with their TicOne **admin** account (same login as the Admin console),
scan the QR on the customer's ticket, and admit it with one tap.

## How a scan works

1. The camera reads the QR. Every format the TicOne app issues is understood
   (server `qrCodeData`, the text passes in My Bookings / booking success, a
   typed booking code or PNR). See `lib/features/scan/ticket_code_parser.dart`.
2. `GET /api/admin/tickets/:code` looks the booking up.
3. The result is shown as **green** (valid), **amber** (wrong day / too early —
   staff may "Admit anyway") or **red** (already used, cancelled, unpaid,
   expired, not found).
4. **Admit** calls `POST /api/admin/tickets/:code/check-in`. The server admits a
   ticket only once, so a screenshot shared with a friend is rejected at the
   second gate.

Entry windows: movies open 1 h before the show until 3 h after it starts; buses
open 2 h before departure until arrival (`lib/features/scan/ticket_verdict.dart`).

## Backend requirement

The ticket endpoints live in `tic_one_middleware`
(`lib/services/admin/admin_ticket_scan_service.dart`). Deploy the middleware
before using the scanner against production. The `checked_in_at` /
`checked_in_by` columns are created automatically on first use, or by running
`dart run tool/setup_admin_schema.dart`.

## Running

```sh
flutter run --dart-define=IS_PRODUCTION=true            # production middleware
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8080   # dev machine on LAN
```

Without flags the app targets the local middleware (`10.0.2.2:8080` on the
Android emulator, `localhost:8080` elsewhere). A physical phone is needed to
scan real QR codes; on an emulator use **Enter code or PNR**.

Optional one-tap demo login (never commit credentials):

```sh
flutter run --dart-define=DEMO_EMAIL=... --dart-define=DEMO_PASSWORD=...
```

## Tests

```sh
flutter test
```
