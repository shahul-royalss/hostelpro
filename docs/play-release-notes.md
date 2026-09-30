# Play Console — release notes

Paste the block below into **Release notes** for the release. Play accepts one block per language;
`en-US` is the only one this listing declares. The limit is **500 characters per language**, and
Play counts the characters *inside* the tags, not the tags themselves.

---

## v1.1.0 (versionCode 7) — staff across several PGs, and the first production release

`nivora_app/pubspec.yaml:19` says `version: 1.1.0+7`. Built on 2026-09-30 by
`nivora_app/scripts/release.sh` (analyzer clean, 1,458 tests passed) and checked independently:

| File | Bytes | SHA-256 |
|---|---|---|
| `dist/NIVORA-1.1.0.aab` (upload this) | 66,416,290 | `2daac0451fb2ca3123fe097162e0565d6bd2aeded0a2d9166734f0957f7e16c2` |
| `dist/NIVORA-1.1.0.apk` (arm64, to install) | 25,290,785 | `7c373e9e9d44ec68f5fd3f6ab7ac69a97500729f0801ae46e3fa06984102cc48` |
| `dist/NIVORA-1.1.0-universal.apk` (any CPU) | 68,849,239 | `d0967f8c89f1e160ebfc8507007eba30de95e1b69c5df5fe0012f4b3e4dc441c` |

Package `com.nivorasr.app`, versionCode 7, versionName 1.1.0, targetSdk 36, the same 10 permissions
as versionCode 6, no AD_ID, every arm64 and x86_64 library 16 KB aligned, signed with the upload key
(`24:23:97` … `FB:64:65`). Camera and NFC are both declared optional, so no phone is filtered out for
lacking either.

This build reads `public.owner_hostel_staff`, `public.my_staff_hostels`,
`public.staff_switch_hostel` and `public.owner_set_staff_hostels`. They have been live since
2026-09-30, when `db/migrations/2026-09-30-multi-pg-staff-access.sql` was applied, so the build is
safe to install and upload. The Edge Function redeploy that completes multi-PG account creation is
the one backend step left; see
[play-console-submission.md, Step 4](play-console-submission.md#step-4--versioncode-7-and-production).

**Release name:** `1.1.0 (7)`

```
<en-US>
Nivora runs a PG or hostel end to end.

• Owners: every property in one place, staff logins for one PG or several, rent and payment history, expense charts, and tasks for your manager.
• Wardens: rooms and beds, resident registration, fees at the desk, complaints and leave.
• Managers: daily and monthly expenses, the mess menu, and your assigned jobs.
• Residents: rent, receipts, UPI payment, complaints and notices.

New: staff who work in several PGs tap Switch PG to move between them.
</en-US>
```

**491 characters** inside the tags, **498** if every line break becomes CRLF on paste, against Play's
500 (counted in Python on 2026-09-30). That is close, so recount after any edit. It keeps the full
description of the app because this is the release production users will see first: nobody in
production ever had versionCode 6, so a "what changed" list alone would describe nothing to them. The
owners line lost "(5 managers and 5 wardens each)" and "monthly" to make room for the new line.

---

## v1.0.0 (versionCode 6) — first release

`nivora_app/pubspec.yaml:19` says `version: 1.0.0+6`. The bundle that went up is
`dist/NIVORA-1.0.0.aab`, built from it on 2026-09-16, 66,433,003 bytes, SHA-256 `d1283f6b173eecf37d6ebbbb2d026e414d8e60b0dc7480a5505583075a888541`. Check the
hash before any upload; the steps are in [play-console-submission.md](play-console-submission.md).
That bundle is already up: the closed testing release `1.0.0 (6)` passed review and is published to
the closed track. Production is still Inactive.

versionCode 6 is the first bundle **uploaded** to the new Play Console app, package
`com.nivorasr.app`. That app's bundle library was empty until then, so 6 was accepted. It gets 6 so
that no two different bundles share a number in these docs. versionCode 5 was built on 2026-09-14
and never uploaded; versionCode 6 superseded it two days later. versionCodes 1 to 4 were all built
for the abandoned `com.srnivora.app` listing: 1 on 2026-09-12, and 2, 3 and 4 on 2026-09-13.
Nothing was ever released from that listing. This section named versionCode 4 until 2026-09-14
(`aca872f`), and versionCode 5 until 2026-09-20.

Play refuses a versionCode that has *ever* been uploaded to an app's bundle library, even when the
release it sat in was discarded. 6 is in that library now and cannot be reused, so the next release
must be 7 or higher.

**Release name** (a Console field, never shown to users, 50 characters max): `1.0.0 (6)`

```
<en-US>
Nivora runs a PG or hostel end to end.

• Owners: every property in one place, staff logins (5 managers and 5 wardens each), rent and payment history, monthly expense charts, and tasks for your manager.
• Wardens: rooms and beds, resident registration, fees at the desk, complaints and leave.
• Managers: daily and monthly expenses, the mess menu, and your assigned jobs.
• Residents: rent, receipts, UPI payment, complaints and notices.
</en-US>
```

**437 characters** inside the tags, against Play's limit of 500 (counted in Python on 2026-09-14).
The text is unchanged from the versionCode 4 draft; nothing in it names the package.

Two lines changed from the previous version of this block, and a reader who remembers it should
know why:

- **The Residents line no longer lists leave.** The resident Android app has no leave feature.
  Wardens still handle leave, so it stays on their line.
- **"Rent reminders arrive as notifications." is out until push has been confirmed on a real
  phone.** It has not been yet, and release notes should not promise a notification nobody has
  seen arrive. Once it has been confirmed, restore the sentence as its own paragraph after a blank
  line below the Residents line. That adds 41 characters, 478 in all (485 in the CRLF worst case),
  still inside the limit, but recount anyway. The same sentence has come out of the shorter block
  below for the same reason; restoring it there brings that block to 295.

An earlier draft of this block ran to 523 and would have been refused on paste. If you edit it,
count it rather than eyeing it — and count the worst case, because a paste that converts each
line break to CRLF adds one character per line (442 here, still inside):

```bash
python3 -c "import re,sys;print([len(m) for m in re.findall(r'<en-US>\n(.*?)\n</en-US>', open('docs/play-release-notes.md',encoding='utf-8').read(), re.S)])"
```

### A shorter one, if the listing prefers it

```
<en-US>
The first release of Nivora — PG and hostel management for owners, wardens, managers and residents. Rooms and beds, resident records, rent and receipts with UPI payment, expenses with month-by-month charts, mess menu, complaints, leave, notices and tasks.
</en-US>
```

---

## Writing the next one

Play shows release notes on the store listing's *What's new*, so they are read by people deciding
whether to install, not only by existing users. Two rules that keep them useful:

1. **Name the thing that changed, not the layer it changed in.** "Floors can be named" beats
   "improved layout editor". Nobody has ever installed an app for a refactor.
2. **Do not list fixes nobody saw.** A bug that shipped and was fixed inside one release cycle was
   never in anyone's hands; saying so only advertises that it existed.
