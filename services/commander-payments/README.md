# Commander Payments

Server-side payment core for Bohanes Technologies / Lázeňský Commander.

## Current scope

Prepared without any live credentials:

- authoritative product catalog: 1–15 days = 129 CZK, 16–35 days = 299 CZK;
- Comgate REST API client in TEST/production mode;
- server-generated payment reference (`refId`);
- status rules: only a Comgate-verified `PAID` state may activate a stay;
- no secret is exposed to the static website;
- unit tests run without contacting Comgate.

## Security rule

`COMGATE_SECRET` is server-only. Never place it in `site/index.html`, browser JavaScript, mobile app resources, Git, screenshots, or logs.

The browser return URL is informational only. It must never activate a stay. Comgate's background PUSH is received by our future backend and its `transId` must be verified against Comgate's status API before activation.

## Planned HTTP contract

The deployment adapter will expose:

- `GET /api/payments/catalog`
- `POST /api/payments/create`
- `POST /api/payments/comgate/push`
- `GET /api/payments/status/:refId`

Return pages:

- `/platba/zaplaceno`
- `/platba/ceka`
- `/platba/zruseno`

The exact backend adapter is intentionally not chosen yet. The core can be wrapped by Vercel Functions, a normal Node server, or another server runtime.

## Payment flow

1. Browser asks our server to create a payment by `planId`; it never sends an authoritative price.
2. Server loads the price from `catalog.mjs` and creates a Comgate payment.
3. Server returns only the Comgate redirect URL and our public order reference.
4. Customer pays on Comgate (card / Apple Pay / Google Pay where available).
5. Comgate sends a background PUSH to our backend.
6. Backend verifies `transId` via Comgate status API.
7. Only verified `PAID` creates/extends the Commander stay entitlement.
8. Browser/mobile app asks our backend for the entitlement state.

## Configuration needed later

Copy `.env.example` to the deployment's secret/environment settings and fill:

- `COMGATE_MERCHANT`
- `COMGATE_SECRET`
- `COMGATE_TEST=false` only for production
- `PAYMENTS_PUBLIC_ORIGIN`

Fio is the settlement bank account configured in the Comgate merchant portal. Fio credentials are not needed by this module.

## Local validation

```sh
npm test
npm run check
```
