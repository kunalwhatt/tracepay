# trace.pay email verification (Supabase Auth) · setup

## 1. Supabase project
1. Go to https://supabase.com → New project (free tier is fine). Pick a strong database password and region **Mumbai (ap-south-1)**.
2. Project Settings → **API**: copy the **Project URL** (`https://<ref>.supabase.co`) and the **anon public** key.

## 2. Auth settings
1. Authentication → Sign In / Providers → **Email**: enabled, **Confirm email** on.
2. Authentication → Email → **OTP length 6** (the email shows six tiles) and an expiry you like (e.g. 3600 s).
3. Authentication → URL Configuration → **Site URL** = your web console URL
   (`https://tracepay-web.livelystone-3bd01cb7.centralindia.azurecontainerapps.io`). The email loads the logo from `<Site URL>/tracepay-app-icon.png`.

## 3. Email template
Authentication → **Email Templates**. For **Confirm signup** and **Magic Link**:
- Subject: `Your trace.pay code: {{ .Token }}`
- Body: paste all of `verify-email.supabase.html`.
It greets the person by first name (`{{ .Data.full_name }}`, sent by the trace.pay server), splits the code into six tiles and shows a copy-friendly line.

## 4. Real email delivery (needed for actual users)
Supabase's built-in sender is for testing and allows only a few emails per hour.
Project Settings → Authentication → **SMTP Settings** → enable custom SMTP with a provider such as Resend, Brevo or Amazon SES.
Sender: e.g. `trace.pay <verify@your-domain>` (verify the domain with the provider first).

## 5. Connect the trace.pay server
```bash
source ~/tracepay-azure.env
az containerapp update -g $RG -n tracepay-api --set-env-vars SUPABASE_URL=https://<ref>.supabase.co SUPABASE_ANON_KEY=<anon-key>
```

## 6. Deploy 5.6.0, then test
- `/health` shows `5.6.0`.
- Sign up with an email on iPhone → last step "Check your email" → code arrives → enter it → account ready.
- Existing email accounts see **"Verify your email to pay"** on Home (iOS) or when opening Pay (Android).
- Web console → **Accounts & Data** → "Unverified only" filter; admins can **Mark verified** for support cases.

## The rule
Accounts that signed up with an email **cannot make any payment until the email is verified**. The server enforces it on
Trace.Pay transfers, UPI app hand-offs and recorded external payments (HTTP 403 with a clear message). Mobile-number accounts have no email and are not affected.
