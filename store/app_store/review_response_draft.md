# App Review response draft

Status: NOT SENT. Review Notes have NOT been saved in App Store Connect.
App: Townloader (App Store Connect ID 6814762239)
Submission: iOS version 1.0, build 1.0.0 (2)
Submission ID: 626bec40-ea41-4751-81c6-874e00f84268

Complete the pending items below before sending. The text in the next section is also intended for the App Review Information Notes field (4,000-character limit).

## Text for the reply and Notes field

Hello App Review team,

Here is the information about Townloader requested under Guideline 2.1.

1. PHYSICAL-DEVICE RECORDING
[PENDING: recording attachment/URL, iPhone model, iOS version, and date. Verify the submitted build and latest public iOS.]
Show app launch, link entry, preview, download, saved media in Photos, share extension, Profile, Downloads, and Settings.
There are no accounts, registration, login, deletion flows, in-app purchases, subscriptions, or paid feature unlocks.
Townloader displays public user posts from Instagram and Threads. Users cannot post, comment, or message within Townloader. There are no in-app reporting or blocking controls.

2. PURPOSE AND TARGET AUDIENCE
Townloader saves photos and videos from public Instagram and Threads posts for offline viewing and backup. Its intended audience includes creators backing up their own posts and people saving content they have permission to download. It converts a pasted or shared link into downloadable media, including carousels and quality choices where available.

3. SETUP AND FEATURE ACCESS
Internet is required; user accounts, credentials, and sample files are not. Instagram uses a developer-configured HikerAPI key; users do not enter it. Threads uses public embed pages.
[PENDING: confirm HikerAPI works in submitted build 2; add verified, authorized Instagram and Threads sample URLs.]
a. Launch the app and open Download. Paste a public post link and tap the arrow (Fetch). The Paste button also reads and resolves a copied link.
b. Tap Download for one item or Download all for a carousel. Allow Photos access when prompted.
c. Downloads shows progress, completion, cancellation, and retry. Media is saved to the Townloader album in Photos. Completed items offer Share and Open folder.
d. Share a post link from Instagram or Threads to Townloader in the iOS share sheet; enable it under More if needed. The app resolves and queues media automatically.
e. In Profile, enter a public Instagram username and tap Open. Browse Posts, Reels, and Stories. Threads profile browsing is not supported.
f. Settings offers Best or Low size quality and Save to Photos. Turning off Save to Photos saves to the app documents folder, accessible in Files.

4. EXTERNAL SERVICES AND TOOLS
- HikerAPI (api.hikerapi.com): Instagram metadata and media URLs, requested using post identifiers, usernames, or shared URLs.
- Threads (threads.com): public embed HTML, shared-link redirects, and post-page thumbnails.
- Instagram/Threads content delivery networks: media and preview downloads directly to the device.
- Flutter and native iOS facilities: app UI, share extension, Photos, Files, Keychain settings storage, and the system share sheet.
No analytics, advertising, AI, user authentication, or payment SDKs are included. External services receive requests and can see the device IP address.

5. REGIONAL BEHAVIOR
No app-defined regional feature restrictions or content catalogs exist. The UI supports English and Korean; some quality-selection and error text is Korean. Service reachability and post availability can differ by region, affecting lookups and downloads.

6. REGULATED SERVICES AND THIRD-PARTY MATERIAL
Townloader does not provide regulated-industry services. It retrieves and displays third-party photos and videos and saves requested files locally. Content remains owned by its rights holders. Townloader is not affiliated with or endorsed by Instagram, Threads, or Meta.
[PENDING: provide applicable written service/source authorization and content licenses or permissions. Public accessibility and personal-use intent do not establish authorization.]

## Items required to finish

- A physical iPhone recording and device/iOS details; an accessible recording URL is useful for future review Notes.
- Verified sample Instagram and Threads links with permission to use their media.
- Confirmation that the submitted build's Instagram service works without reviewer setup.
- Applicable third-party authorization documents, or an accurate developer statement about the absence of such documentation.
- A signed-in App Store Connect session in the Orca embedded browser. The existing Chrome session has no available CDP connection. The user has prohibited `orca computer` use.

The source was inspected for these facts; the submitted binary was not tested on a physical device during this task. No claim is made that the missing recording or authorization documents exist.

Apple's current guidelines address reporting and blocking in section 1.2, service authorization in 5.2.2, and authorization for media downloading in 5.2.3: https://developer.apple.com/app-store/review/guidelines/
