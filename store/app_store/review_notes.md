PURPOSE AND AUDIENCE
Townloader is a reader, personal archive and place organizer for public Instagram and Threads posts. Users save posts about trips or restaurants and see the places they mention on a map, read long Threads posts on one screen, and keep photos and videos on their own device. Audience: general adult users of Instagram and Threads.

HOW TO TEST
No account is needed for the main features. The app opens on the Links tab.
1. Links tab: paste a public Instagram post link and tap Save. The app finds the places in the post and gives it a title. Tap Show on map. Posts can be moved between categories.
2. Read tab: paste a public post link and fetch it. Threads sample (17 parts with replies): https://www.threads.com/@choi.openai/post/DdckNs5k8qw
Tap a video to play it inline, or long-press a post to preview its media. Agree in the consent dialog to see an AI summary. Select posts and tap "Download selected", or tap "Download all", then agree to the personal-use notice and allow photo access. Files go to the "Townloader" album in Photos, or to Files if chosen in Settings.
3. Share extension: in Threads or Instagram, tap Share and choose Townloader. The post opens in the app. Nothing is saved until the user chooses.
4. Profile tab: enter a public Instagram username (for example "instagram") to browse its posts, reels and stories.
5. Settings: quality, save location, theme, language, account.

OPTIONAL ACCOUNT
Sign in with Apple or Google from Settings. Sign-in is only needed to back up saved links across devices and to share a map. No demo account is needed: use Sign in with Apple. To test sharing, sign in, open a category or post map and choose Share map. The category or post becomes public to anyone with the link, and the user can stop sharing at any time. Delete account in Settings immediately removes the account, synced links and shared maps from the server.

USER CONTENT
Users cannot post, comment or message. Public replies are shown read-only. A shared map contains the title, photos, caption without hashtags, author username, places and original link of posts the user saved. It is reachable only through its link and is not listed or searchable in the app.

EXTERNAL SERVICES
API keys stay on our servers (Cloudflare Workers), which relay these requests.
- threads.com public pages: read to show a thread, its replies and its media.
- HikerAPI: looks up public Instagram posts and profiles. Receives the post code or username.
- Threads and Instagram CDNs: photos and videos load directly from them.
- Kakao Map and Mapbox: place search and geocoding, and the map display.
- TypeSafe (Jev): judges place matches and picks a category. Receives caption, title and category names.
- Anthropic (Claude): writes post titles from the caption, place names and a few lines of text read on the device from the first photo. Photos are not sent.
- Anthropic (Claude) or Poe (Google Gemini): AI summaries, only after in-app consent. Public thread text is sent. Summary ratings are stored without account information.
- Poe (ElevenLabs voice): reads replies aloud, only when the user taps it.
- Apple and Google: sign-in.
The app has no ads, analytics, tracking, payments or subscriptions. With sign-in, the account ID, email and saved links are stored on our server.

REGIONS
Features are the same in all regions. The interface is English or Korean. Lookups fail where Threads or Instagram are blocked.

THIRD-PARTY MATERIAL
The app is not in a regulated industry. It does not host or redistribute media files: it shows public media without logging in and saves it to the user's own device at their request. Shared maps show photos from Instagram's own URLs and are not copied to our servers. It cannot access private accounts. We have no separate agreement with Meta. The description states that saved content belongs to its creators, is for personal use only, and that Townloader is not affiliated with or endorsed by Instagram, Threads or Meta.
