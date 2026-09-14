# Play Console — release notes

Paste the block below into **Release notes** for the release. Play accepts one block per language;
`en-US` is the only one this listing declares. The limit is **500 characters per language**, and
Play counts the characters *inside* the tags, not the tags themselves.

---

## v1.0.0 (versionCode 5) — first release

`nivora_app/pubspec.yaml:19` says `version: 1.0.0+5`. The bundle for this upload is
`dist/NIVORA-1.0.0.aab`, built from it at 15:47 IST on 2026-09-14, SHA-256 `ec552f06eb45d1f52daeeffdb2f69cfaa087bfab70c34a4f3acee90d491f186f`. Check the
hash before uploading; the steps are in [play-console-submission.md](play-console-submission.md).

This is the first bundle for the **new** Play Console app, package `com.nivorasr.app`. That app's
bundle library is empty, so any versionCode would be accepted. It gets 5 so that no two different
bundles share a number in these docs. versionCodes 1 to 4 were all built for the abandoned
`com.srnivora.app` listing: 1 on 2026-09-12, and 2, 3 and 4 on 2026-09-13. Nothing was ever released
from that listing. Until 2026-09-13 this section named versionCode 4, for that listing.

Play refuses a versionCode that has *ever* been uploaded to an app's bundle library, even when the
release it sat in was discarded. So every upload after this one must raise the `+N`.

**Release name** (a Console field, never shown to users, 50 characters max): `1.0.0 (5)`

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
