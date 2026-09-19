# Envoice

Offline-first premium invoicing for Nigerian businesses.

**Product name:** Envoice  
**Company brand on invoices:** each business sets their own name, logo, address, and contact details.

## Why offline-first

Nigerian networks drop. Creating an invoice, looking up a client, or generating a PDF must work with zero connectivity. Sync and email are optional when the network returns.

## v1 scope (business minimum)

- **Business profile** — company name, logo, address, phone, email, TIN (optional)
- **Clients** — create, edit, list, search
- **Invoices** — line items, quantity, unit price, discount, VAT toggle, notes
- **Statuses** — draft, sent, paid, partial, overdue
- **Payments** — record full or partial payments against an invoice
- **PDF** — generate and share offline (branded with company logo/name)
- **Dashboard** — outstanding, paid this month, overdue count
- **Local-first storage** — all data on device (Drift / SQLite)

Out of v1 (later): cloud sync, multi-user, recurring invoices, expenses.

## Stack

| Layer | Choice |
|-------|--------|
| App | Flutter 3.x |
| Local DB | Drift (SQLite) |
| State | Riverpod |
| PDF | `pdf` + `printing` |
| Currency | NGN (₦) default |

## Design

Premium, restrained. Near-black / off-white, one accent, generous space. Invoice PDFs should feel suitable for island and classy clients.

## Getting started

```bash
flutter pub get
flutter run
```

Generate Drift code after schema changes:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Repo note

Previous `FADAREC/Invoice` only contained a release APK with no recoverable source. This repo is the full rebuild.
