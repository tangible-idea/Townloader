Hello App Review team,

Thank you for the review. Here is the requested information. We have also added it to the Notes field of App Review Information.

1. SCREEN RECORDING
Attached is a recording made on a physical iPhone running the latest iOS. It starts at app launch and shows:
- opening a multi-part Threads post, reading the author's full thread and its replies, playing a video inline and long-pressing a post to preview its media
- choosing which posts of the thread to save, and saving them to Photos
- sharing a post from the Threads app to Townloader
- pasting a public Instagram post link and saving it
- browsing a public profile, and the Downloads and Settings screens
About the items you listed:
- The app has no account registration, login or account deletion. Nothing requires an account.
- Users cannot post, comment, message or upload anything in the app. When a Threads post is opened, the app shows the public replies to it as read-only text, the same as the public post page on threads.com.
- The app has no paid content, subscriptions or in-app purchases.

2. PURPOSE AND AUDIENCE
Townloader is a reader and personal archive for public Threads and Instagram posts.
Problem it solves: long Threads posts are often split into many parts (1/17, 2/17 ...), which are hard to follow and impossible to keep for later. Townloader opens a post link and lays out the author's whole thread in order, with its replies, in one screen. Videos play inline, and long-pressing a post previews its media. The user can then choose which parts to keep and save their photos and videos to the Photos app in the original quality, for offline reading and backup.
Typical users are creators backing up their own posts, and people who want to keep a public thread they will read again later.
Audience: general adult users of Threads and Instagram.

3. HOW TO USE THE APP
No account, login or setup is needed.
1. Open the app. The Download tab is shown.
2. Paste a public post link and tap Fetch. Sample links:
   - Threads (17-part thread with replies): https://www.threads.com/@choi.openai/post/DdckNs5k8qw
   - Instagram: [INSTAGRAM_SAMPLE_LINK]
3. For a Threads link, the author's thread and the replies are shown in order. Tap a video to play it inline, or long-press a post to preview its media. Select posts and tap "Download selected", or tap "Download all". Allow photo access when asked.
4. The Downloads tab shows progress. Finished files are saved to the "Townloader" album in Photos. Each item has a Share button and a folder button that opens Photos (or Files, if album saving is turned off in Settings).
5. Share extension: in the Threads or Instagram app, tap Share on a post and choose Townloader (under "More" the first time). The app opens with that post. Nothing is saved until the user chooses to save.
6. Profile tab: enter a public Instagram username (for example "instagram") and tap Open to browse that account's posts, reels and stories.
7. Settings: choose download quality and whether to save to Photos or to Files.

4. EXTERNAL SERVICES
- Threads public post pages (threads.com): the public, logged-out post and embed pages, read to show a post, its thread and its replies, and to find its media.
- HikerAPI (hikerapi.com): a third-party data service used to look up public Instagram posts and profiles and get their media links. The app sends only the post code or username from the link the user entered. The API key is built into the app.
- Threads and Instagram content delivery networks: photos and videos are loaded and downloaded directly from there.
- AI summaries (optional): when the user agrees in an in-app consent dialog, the public text of a thread's posts and replies is sent through our summary server on Cloudflare Workers to Anthropic (Claude) or Poe to create a short summary. API keys stay on the server; no account information, photos or videos are sent.
The app uses no authentication, payment, analytics or advertising services, and it collects no personal data.

5. REGIONAL DIFFERENCES
The app has the same features and content in all regions. The interface is in English, or Korean on devices set to Korean. Lookups need Threads and Instagram to be reachable, so they fail in regions where those services are blocked.

6. REGULATED INDUSTRY AND THIRD-PARTY MATERIAL
The app is not in a regulated industry. It does not host, include or redistribute any third-party content. At the user's request, it shows and saves media that is already public without logging in, to that user's own device. It cannot access private accounts. We do not have a separate agreement with Meta. The App Store description tells users that saved content belongs to its creators, that it is for personal use only, and that Townloader is not affiliated with or endorsed by Instagram, Threads or Meta.
