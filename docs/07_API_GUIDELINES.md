# API Guidelines

- Use REST APIs.

- Return proper HTTP status codes.

- Validate all inputs.

- Authenticate protected APIs.

- Never trust userId from frontend.

- Never trust societyId from frontend.

- Always derive user from JWT.

- Return meaningful error messages.

## Listing status

Stored as lowercase strings on `Listing.status`:

| Value | Meaning |
| --- | --- |
| `active` | Visible to buyers (default) |
| `paused` | Hidden from buyers; seller can resume |
| `sold_out` | Quantity exhausted; may still be managed by seller |
| `inactive` | Soft-deleted / removed |

### Seller pause / resume

- `PATCH /listings/:id/pause` — owner only; sets `paused`. Errors if already paused.
- `PATCH /listings/:id/resume` — owner only; sets `active`. Errors if already active or not paused.

### Browse / search

- `GET /listings?societyId=…` defaults to `status=active` (buyers never see paused).
- Seller My Listings uses `status=all` to load `active`, `paused`, and `sold_out`.
