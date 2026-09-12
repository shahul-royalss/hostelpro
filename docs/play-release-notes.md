# Play Console — release notes

Paste the block below into **Release notes** for the release. Play accepts one block per language;
`en-US` is the only one this listing declares. The limit is **500 characters per language**, and
Play counts the characters *inside* the tags, not the tags themselves.

---

## v1.0.0 (versionCode 1) — first release

`pubspec.yaml` says `version: 1.0.0+1`, and the built artifact reports `versionCode='1'`. That is
correct for a first upload: no bundle has ever been *accepted* on this listing, so there is nothing
for versionCode 1 to collide with. The earlier attempt was rejected before acceptance, and under a
different package name. Every upload after this one must raise the `+N`.

```
<en-US>
Nivora runs a PG or hostel end to end.

• Owners: every property in one place, staff logins (5 managers and 5 wardens each), rent and payment history, monthly expense charts, and tasks for your manager.
• Wardens: rooms and beds, resident registration, fees at the desk, complaints and leave.
• Managers: daily and monthly expenses, the mess menu, and your assigned jobs.
• Residents: rent, receipts, UPI payment, complaints, leave and notices.

Rent reminders arrive as notifications.
</en-US>
```

**485 characters** inside the tags, against Play's limit of 500.

An earlier draft of this block ran to 523 and would have been refused on paste. If you edit it,
count it rather than eyeing it — and count the worst case, because a paste that converts each
line break to CRLF adds one character per line (492 here, still inside):

```bash
python3 -c "import re,sys;print([len(m) for m in re.findall(r'<en-US>\n(.*?)\n</en-US>', open('docs/play-release-notes.md',encoding='utf-8').read(), re.S)])"
```

### A shorter one, if the listing prefers it

```
<en-US>
The first release of Nivora — PG and hostel management for owners, wardens, managers and residents. Rooms and beds, resident records, rent and receipts with UPI payment, expenses with month-by-month charts, mess menu, complaints, leave, notices and tasks. Rent reminders arrive as notifications.
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
