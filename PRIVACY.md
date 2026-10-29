# Townloader Privacy Policy

Effective date: September 23, 2026

Townloader ("the app") does not collect personal information. This document explains
what information the app handles and where.

## 1. Information we collect

If you don't sign in, the app does not send any personal information to the developer.

- Signing in is optional. It is only needed to back up your links or share a map (see "Account and map sharing" below).
- The app does not ask for or collect your name, phone number, contacts, or location. Your email is received only when you sign in.
- The app contains no advertising, analytics, usage statistics, or crash reporting tools.
- The app does not track you or link your activity with other companies' apps or websites.

## 2. Information stored only on your device

The following stays on your device and is never transmitted.

- **App settings**: download quality and whether to save to Photos, kept in the device keychain.
- **Downloaded files**: saved to the "Townloader" album in Photos or to the app's documents folder.
- **Download list**: kept in memory only while the app is running and cleared when it closes.

Deleting the app removes its settings and the files stored inside it. Files saved to Photos
can be deleted from the Photos app.

## 3. Information sent to third-party services

When you enter or share a link, the app sends a request to the services below to
load that content. Your device's IP address may be visible to these services along with the
request.

| Service | What is sent | Purpose |
| --- | --- | --- |
| HikerAPI (hikerapi.com) | The post code or username from the Instagram link you entered | Look up public post information |
| Threads (threads.com) | The Threads post address you entered | Look up public post information |
| Each service's content servers (CDN) | The file address | Download the photo or video |
| Poe (poe.com), using ElevenLabs voices | The text of the replies you choose to have read aloud | Turn the text into speech (only when you tap "Read aloud") |

HikerAPI and Poe voice requests pass through the developer's server on Cloudflare Workers so
that API keys are not built into the app. The server forwards the request and limits the number
of requests per IP address; it does not keep the request content. Each service handles it under
its own privacy policy.

**AI summaries.** When you agree to AI summaries, the public text of the thread's posts and
replies (with each author's username) is sent to the developer's summary server on Cloudflare
Workers, which forwards it to the AI service you chose: Anthropic (Claude) or Poe. No account
information, photos or videos are sent. The summary server keeps the finished summary for 7 days
so the same thread isn't summarized again, and keeps a count per IP address for about one day to
limit daily use. It does not keep the post text itself. Anthropic and Poe handle the text under
their own privacy policies.

**Account and map sharing.** When you sign in with Google or Apple in Settings, the links you
saved in the Links tab, their categories, the places found, and the post details the app loaded
(author username, caption, photo addresses) are stored on the developer's server (Cloudflare
Workers, D1) so you can keep using them on another device. The account ID and email address given
by the sign-in service are stored to tell accounts apart. Your Google or Apple password is never
received.

When you share a category map, that category becomes public: anyone with the link can see the
short title, photos, caption (without hashtags) and author username of each post saved in it,
along with the place names, addresses, coordinates and a link to the Instagram post. Photos are
shown from Instagram's own servers and are not copied. You can stop sharing at any time from the
Links tab.

**Post titles.** To give each saved post a short title, its caption, the names of the places
found, and a few large text lines read from its first photo are sent through the developer's
server on Cloudflare Workers to Anthropic (Claude). The photos themselves are not sent. Only the
finished title is kept, for 30 days, so the same post isn't titled again.

Tapping "Delete account" in Settings immediately removes your account, synced links and shared
maps from the server, and the links you sent stop working. Links saved on your device stay.

## 4. Device permissions

- **Photo library access**: used only to create the "Townloader" album in Photos and add
  downloaded photos and videos to it. iOS requires full access to create an album, so the app
  asks for it, but it never reads or sends out the existing photos in your library.
- **Share extension**: when you share to Townloader from another app, only the shared link is
  passed to the app.

You can change permissions at any time in Settings → Townloader.

## 5. Children's privacy

The app collects no personal information from anyone, including children.

## 6. Changes to this policy

If this policy changes, the updated version and its effective date will be posted on this page.

## 7. Contact

For privacy questions, please open a [GitHub issue](https://github.com/tangible-idea/Tandi/issues/new).

_한국어: [PRIVACY.ko.md](PRIVACY.ko.md)_
