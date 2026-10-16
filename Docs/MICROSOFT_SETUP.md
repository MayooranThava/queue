# Microsoft Outlook Integration Setup

Phase 5 capability. Not required for core Queue usage.

## Overview

Queue uses **MSAL** (public client) + **Microsoft Graph** `calendarView` with authorization code + PKCE. No embedded client secret.

## Azure App Registration (product owner)

1. Azure Portal → App registrations → New registration
2. Name: `Queue iOS`
3. Supported account types: personal Microsoft accounts + work/school (as desired)
4. Redirect URI (public client / mobile):
   - `msauth.com.queueapp.Queue://auth` (replace with final bundle ID form)
5. Authentication → **Allow public client flows**: Yes
6. API permissions (delegated only):
   - `Calendars.Read`
   - `User.Read` (optional, for account label)
   - **Do not** request `Mail.*`
7. Admin consent may be required by some tenants — Queue must fail gracefully

## iOS configuration

Add to the app target (when implementing Phase 5):

- MSAL Swift package dependency
- URL scheme for redirect
- `Info.plist` / Entitlements as required by MSAL
- Configuration keys (not secrets):
  - `MSAL_CLIENT_ID`
  - `MSAL_REDIRECT_URI`
  - Authority: common or consumers/organizations as chosen

Store tokens via MSAL cache only. Never log access tokens.

## Graph usage

- `GET /me/calendarView?startDateTime&endDateTime`
- Handle `@odata.nextLink` pagination
- Expand/recurrence handled by calendarView
- Respect `Retry-After` on 429
- Normalize into `CalendarEvent` domain model
- `disconnect()` clears MSAL account + local sync metadata

## Privacy copy

Explain before OAuth: Queue reads calendar busy/events to suggest focus gaps; it does not read mail or modify events.

## Tenant restrictions

Organizational admins may block third-party apps. Do not attempt bypasses. Surface a clear message and keep Apple Calendar / local tasks working.
