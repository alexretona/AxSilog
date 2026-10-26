# Axsilog

Single-file lunch-ordering app for an office/community: organizers publish a daily
menu, customers order, pay by QR, and upload payment proof; the organizer confirms
and marks batches delivered.

## Repo shape

Everything lives in **`index.html`** (~1760 lines) — markup, CSS, and JS in one
file, no build step, no dependencies to install. Vercel serves it as a static site.

| Lines | Contents |
|-------|----------|
| 1–16 | `<head>`, PWA meta, Supabase CDN script, Google font |
| 17–205 | `<style>` — CSS custom properties, then component styles |
| 207–285 | `<body>` markup: header, tab bar, `#view` container, modal host |
| 286–1758 | `<script>` — config, helpers, then one `view*()` function per tab |

Because it is one file, **edit it surgically**. Never regenerate the whole file:
find the function or style rule by name and change only that.

## Deploy pipeline

`git push origin main` → Vercel auto-builds → **https://axosilog.vercel.app**

There is no staging branch and no preview gate on `main`; a push to `main` is a
production deploy. Vercel project `axosilog` under team `alexretonas-projects`
(ids in `.vercel/project.json`, gitignored).

## Supabase

Project ref `nstktluzwkdnewobjnep` — https://nstktluzwkdnewobjnep.supabase.co

URL and **anon** key are hardcoded at `index.html:288-289`. That is correct for
this app: the anon key is a public client credential and security lives in Row
Level Security policies, not in hiding the key. Never put the *service role* key
in this file.

**There are no migration files in this repo.** The live Supabase project is the
only source of truth for schema and RLS. Before writing a query against a table,
check the actual columns in the dashboard rather than inferring them from usage.

Tables in use: `profiles`, `menus`, `menu_items`, `orders`, `order_items`,
`proofs`, `qr`, `reviews`, `public_reviews`.
RPC: `get_public_reviews`. Storage buckets: `proofs`, `qr`, `food`.

### Food photos are feature-gated

`menu_items.photo_url` / `.photo_path` and the `food` bucket come from
`supabase/2026-09-09-food-photos.sql`. The app probes for the column once per
session (`detectPhotoSupport()`) and stores the answer in `PHOTOS_OK`:

- `PHOTOS_OK === false` — no photo UI renders, and `withPhoto()` strips the photo
  keys off every `menu_items` write, so payloads are identical to the
  pre-photo app. This is what makes it safe to deploy the page before running
  the SQL.
- `PHOTOS_OK === true` — organizers get a photo square per item row, and
  customers see thumbnails.

Keep that gate intact when touching menu writes: sending `photo_url` to a
database without the column makes PostgREST reject the whole statement, which
would break publishing a menu entirely.

Photos are compressed to a hard ~90 KB budget (`FOOD_PHOTO_OPTS`) by
`compressImage`, which drops JPEG quality first and only then shrinks
dimensions. Callers that pass no `maxBytes` (proof and QR uploads) keep their
original single-pass behaviour.

A photo can be **shared by several `menu_items`** once an organizer reuses it
from the library, so removing a photo from an item only clears the columns —
storage objects are deliberately never deleted. Do not add cleanup that deletes
a `food` object when an item is removed.

### Order limits and delivery time are feature-gated

`menus.max_orders`, `menus.deliver_time`, `menu_items.max_qty`, the
`get_menu_availability` RPC and two enforcement triggers come from
`supabase/2026-10-26-order-limits-delivery.sql`. Same pattern as photos:
`detectLimitSupport()` probes once per session into `LIMITS_OK`; while it is
`false` no limit/delivery UI renders and `withMaxQty()` / `readMenuLimits()`
add nothing to writes.

- Customers can't read other people's orders (RLS), so "slots left" / "N left"
  come from `get_menu_availability`, which counts server-side.
- The page pre-checks before ordering, but the **triggers are the real
  enforcement** (they lock the menu row so simultaneous orders queue). If the
  `order_items` insert is rejected, `placeOrder()` deletes the just-created
  order so no item-less order is left behind.
- Dish servings are matched by `lower(trim(name))` within the menu, because
  `order_items` stores the dish name, not a `menu_items` id. Renaming a dish
  mid-day resets its count.

### Password reset

`resetPasswordForEmail()` sends the user back to `location.origin +
location.pathname`. **That exact URL must be in Supabase's Auth -> URL
Configuration -> Redirect URLs**, or the emailed link fails. The return visit
carries `#type=recovery`, which is captured synchronously at startup (the
Supabase client strips the hash once it parses it) and routes the user to
`#screen-reset` instead of into the app.

### Roles

`profiles.role` is one of `customer` | `organizer` | `admin`, paired with
`profiles.status` (`pending` | `approved`). A user applies to be an organizer,
which sets `role='organizer', status='pending'`; an admin approves them from the
Admin tab. Tabs are gated on this pair in `buildTabs()` (`index.html:517`).

### Order lifecycle

`new` → `confirmed` (organizer accepts, after proof upload) → delivered
(batch via `applyBatchDeliver()`, or one-off via `singleDeliver()`).

## Local backups

Every iteration should be snapshotted before and/or after a change:

```
.\snapshot.cmd "before-qr-rewrite"   # -> backups\index-<stamp>-before-qr-rewrite.html
.\snapshot.cmd -List                 # browse snapshots
.\snapshot.cmd -Restore backups\index-20260909-174434-initial-clone.html
```

**Use `snapshot.cmd`, not `snapshot.ps1` directly.** PowerShell's execution policy
on this machine is the Windows default (`Restricted`), so calling the `.ps1`
straight from a terminal fails with `UnauthorizedAccess`. The `.cmd` wrapper
re-invokes it with a per-process `-ExecutionPolicy Bypass` and forwards all
arguments, so no machine-wide policy change is needed. (No Group Policy is in
force here — `MachinePolicy` and `UserPolicy` are both `Undefined` — which is why
the per-process bypass is honoured.)

`backups\` is gitignored — it is a local safety net, separate from git history.
`-Restore` snapshots the current file first, so restoring is never destructive.
`backups\MANIFEST.txt` maps each snapshot to the commit it was taken at.

## Git

Repo-local identity is set to `Alex Retona <alexretona@gmail.com>` — the *global*
identity on this machine is a different account (Megawide Foundation), so never
rely on the global config here.

### Two GitHub accounts on this machine

The globally active `gh` account is **`megawidefoundationdashboard`** (a different
project) and must stay that way. This repo belongs to **`alexretona`**.

`git push` works normally — repo-local config appends Windows Credential Manager
back onto the helper chain (`credential.https://github.com.helper=manager`),
because the global `~/.gitconfig` clears it for GitHub URLs and `gh`'s own
credential helper only ever serves the *active* account.

**`gh` CLI commands do not.** Bare `gh` runs as megawide and will fail or act on
the wrong account. Use the wrapper, which pulls alexretona's token from the
Windows keyring at call time:

```
.\gha.cmd pr create --fill
.\gha.cmd repo view
```

Equivalent one-liner in a POSIX shell:
`GH_TOKEN=$(gh auth token --user alexretona) gh <args>`

Never fix this with `gh auth switch` — that flips the active account globally and
breaks the other project.

`core.autocrlf=true` system-wide: the working tree is CRLF, the repo stores LF.
When comparing this file against a copy from elsewhere (a download, the GitHub web
editor), normalize line endings first or the whole file will look changed.

## Conventions

- Vanilla JS, no framework. `$(id)` is the `getElementById` helper.
- Views render by assigning `innerHTML` to `#view`, then wiring handlers with
  `querySelectorAll(...).forEach(el => el.onclick = ...)`. Follow that pattern —
  do not introduce event delegation or a router.
- All user-supplied text goes through `esc()` before landing in a template string.
- Colors come from the CSS custom properties in `:root` (navy `--navy` is primary,
  orange `--accent`). Do not hardcode hex values in new styles.
- The layout is mobile-first and capped at `max-width:560px`; test at phone width.
