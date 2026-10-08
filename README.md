# Zeoxis

Security scanner for AI-generated code. Static pages in `public/`, serverless API in `api/`, Supabase for auth + data.

| Route | Purpose |
|---|---|
| `/` `/how-it-works` `/product` `/engine` `/security` `/pricing` | Marketing |
| `/signin` `/signup` | Email, Google and GitHub auth (Supabase) |
| `/dashboard` | Your saved scans (requires sign-in) |
| `/scan` | Paste code / GitHub repo / upload files |
| `/chat` | AI security analyst |
| `/settings` | Profile, plan, billing portal |

Deploy: see **DEPLOY.md**. Env vars: see `.env.example`.
`public/assets/zx.js` is the one client script that wires every page; `_archive/` holds the original Redline index.html.
