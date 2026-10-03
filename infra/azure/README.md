# Trace.Pay 2.0 — Azure production deployment

This repository includes a cloud deployment path; it does **not** create resources in your Azure subscription automatically. You must own the subscription, choose a region, create secrets, and run the deployment. For a continuously reachable service, deploy the API and web console to Azure Container Apps, use Azure Database for PostgreSQL Flexible Server for persistent records, and use Azure Managed Redis for rate limits / live coordination. Do not expose Redis or PostgreSQL publicly.

## Recommended production topology

- **Web:** Azure Container Apps, external HTTPS ingress.
- **API:** Azure Container Apps, HTTPS ingress; health probe `/health`.
- **Database:** Azure Database for PostgreSQL Flexible Server with private networking, backups, TLS and restricted access.
- **Cache/live coordination:** Azure Managed Redis (TLS); set `REDIS_URL=rediss://:<access-key>@<host>:10000/0` (use the exact endpoint and port shown in your Azure resource; store the URI as a Container App secret).
- **Private profile photos:** the app encrypts photos before writing them to `PRIVATE_PHOTO_DIR`. For production, mount a private Azure Files share to this directory using Container Apps Environment storage and a Container App volume mount, or implement a private Blob Storage adapter before using ephemeral containers. Do not deploy with ephemeral local storage for photos.
- **Secrets:** Container Apps secrets / Key Vault references. Never commit `.env`, JWT secrets, database passwords, Redis keys or signing keys.
- **Observability:** Container Apps logs, Azure Monitor / Application Insights, alerts for 5xx, restarts, DB connectivity, Redis connectivity and WebSocket disconnects.

## Build and deploy outline

1. Create an Azure Container Registry (ACR), Container Apps Environment, PostgreSQL Flexible Server, Azure Managed Redis and a private Azure Files share.
2. Build and push `backend/Dockerfile` and `web-console/Dockerfile` images to ACR. The web image is a production Nginx static build; pass `--build-arg VITE_API_BASE_URL=https://<api-app-fqdn>` when building it because Vite compiles this value into the bundle.
3. Create the API Container App with `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `PII_ENCRYPTION_KEY`, `CORS_ORIGINS`, `BOOTSTRAP_ADMIN_EMAIL`, `BOOTSTRAP_ADMIN_PASSWORD`, and `PRIVATE_PHOTO_DIR=/var/lib/tracepay/private-photos` as secrets/environment values. Mount the Azure Files share at the photo directory.
4. Create the web Container App with `VITE_API_BASE_URL=https://<api-app-fqdn>` **at build time**. Vite variables are compiled into the web bundle; rebuilding the web image is required when the API URL changes.
5. Set `CORS_ORIGINS` to the exact HTTPS web origin. Run database migrations/backup checks before directing real participants to the service.
6. In iOS `TracePay.Release.xcconfig` and Android `app/build.gradle.kts`, replace the API URL placeholder with the deployed HTTPS API hostname, then rebuild the mobile apps.
7. Verify `/health`, `/api/v1/pilot/health` (authenticated), login, a controlled ledger transfer, transfer history, WebSocket updates, photo retrieval and restore from backup.

## Important boundaries

- The backend is a closed-loop Trace.Pay ledger. Azure hosting does not create UPI connectivity or bank settlement. Real external UPI requires an authorised PSP/bank integration and applicable approvals.
- Biometric authentication happens on-device and authorises the app flow; it is not sent to the API as biometric data.
- Risk output is advisory. Preserve source records and do not interpret missing records as proof no transfer occurred.
- Before a public production launch, complete a security review: rate limits, brute-force controls, access control, secrets rotation, dependency scanning, backups, privacy/retention, incident response and load testing.

## Local development

Use the root `.env.example` and Docker Compose. Mobile apps must point at the host-accessible API URL (iOS Simulator can usually use `http://127.0.0.1:8000`; a physical device must use the Mac's LAN address or the deployed HTTPS URL). Never use a loopback URL for a remotely hosted release.

## Optional GitHub Actions image publishing

The workflow `.github/workflows/build-images.yml` builds and pushes both images to ACR on a `v2.*` tag or manual dispatch. Configure repository secrets `ACR_LOGIN_SERVER`, `ACR_USERNAME`, `ACR_PASSWORD`, and repository variable `VITE_API_BASE_URL` (the API HTTPS origin) before enabling it. After a successful publish, update the Container Apps image tags to the workflow's commit SHA. Use a managed identity/short-lived credentials where possible instead of long-lived registry passwords.
