# Play Console — release notes

Paste the block below into **Release notes** for the release. Play accepts one block per language;
`en-US` is the only one this listing declares. The limit is **500 characters per language**, and
Play counts the characters *inside* the tags, not the tags themselves.

---

## v1.0.0 (versionCode 4) — first release

`pubspec.yaml` says `version: 1.0.0+4`, and the bundle for this upload was built from it at 20:21 IST
on 2026-09-13 (`dist/NIVORA-1.0.0.aab`, which reports `versionCode='4'`). The number sits above
every bundle already built: a versionCode-1 bundle was built and handed over on 2026-09-12, and
versionCode 2 and then 3 were built on 2026-09-13. Play refuses a versionCode that has *ever* been
uploaded to a listing's bundle library, even when the release it sat in was discarded, so whichever
of those reached Console, 4 cannot collide with it. This section used to name versionCode 2; it
names 4 because 2 and 3 have both been built since. Every upload after this one must raise the `+N`.

**Release name** (a Console field, never shown to users, 50 characters max): `1.0.0 (4)`

```
<en-US>
Nivora runs a PG or hostel end to end.

• Owners: every property in one place, staff logins (5 managers and 5 wardens each), rent and payment history, monthly expense charts, and tasks for your manager.
• Wardens: rooms and beds, resident registration, fees at the desk, complaints and leave.
• Managers: daily and monthly expenses, the mess menu, and your assigned jobs.
• Residents: rent, receipts, UPI payment, complaints and notices.
</en-US>
```

**437 characters** inside the tags, against Play's limit of 500 (counted in Python on 2026-09-13).

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
