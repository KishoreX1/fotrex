# Deploy to Vercel

The Redline zip contained **no keys or tokens** — every secret is read from environment variables. You supply them once, in Vercel.

## 1. Supabase (database + auth)
1. Supabase Dashboard -> SQL Editor -> paste `supabase/schema.sql` -> Run.
2. Authentication -> Providers: enable **Email**, **Google**, **GitHub**.
   - GitHub: create an OAuth App at github.com/settings/developers; set the callback URL to the one Supabase shows (`https://<project>.supabase.co/auth/v1/callback`); paste Client ID/Secret into Supabase.
   - Google: Google Cloud Console -> Credentials -> OAuth client (Web); same callback URL; paste Client ID/Secret into Supabase.
3. Authentication -> URL Configuration: set **Site URL** to your Vercel URL and add `https://<your-domain>/**` to Redirect URLs (also `http://localhost:3000/**` for local testing).
4. Project Settings -> API: copy the URL, anon key and service_role key.

## 2. Vercel
```bash
npm i -g vercel
cd zeoxis
vercel            # first deploy, accept defaults (framework: Other)
```
Add the variables from `.env.example` (Project -> Settings -> Environment Variables), then `vercel --prod`.
Minimum for login + scans: `SUPABASE_URL`, `SUPABASE_ANON_KEY`. Add `HIVE_API_KEY` for AI chat/fix reports.

## 3. Stripe (optional)
Create a recurring Pro price, set `STRIPE_PRICE_ID_PRO`, then add a webhook to `https://<domain>/api/stripe-webhook` for `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted` and set `STRIPE_WEBHOOK_SECRET`.

## 4. Before launch
- Replace the template text in `/legal` with a real privacy policy and terms.
- Replace `hello@zeoxis.com` (contact links) with your real address.
