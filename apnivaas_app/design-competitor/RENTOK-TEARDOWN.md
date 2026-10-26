# RentOk Manager — what they built, and what it means for Apnivaas

Static teardown of the Android app the owner supplied in `RentOk/` (six split APKs pulled from a
phone), done 2026-10-16. Nothing was installed or run: the APKs were unzipped into a scratch folder
and read — the manifest, the asset folder, the language files and the compiled Dart code's library
names and text. Their copy is **paraphrased** here on purpose; their illustrations, animations and
wording are their property, and nothing from the APKs is to be copied into Apnivaas.

---

## 1. The app at a glance

| | |
|---|---|
| Name / package | RentOk Manager · `net.eazypg.eazypgmanager` (the company was EazyPG) |
| Version | 8.10.32, versionCode **667**, targetSdk 36 — a mature product with hundreds of releases |
| Framework | **Flutter**, like Apnivaas. The app's own code is **1,371 Dart files** (`package:rentokmanagerflutter`); Apnivaas is far smaller |
| Languages | English + Bengali, Gujarati, Kannada, Marathi, Tamil (language picker before sign-in) |
| Updates | **Shorebird** code push: Dart fixes reach phones without a Play release |
| Fonts | DM Sans and SF Pro Text (an iOS feel on Android) |
| Separate apps | A tenant app exists; the manager app routes tenants to it |

---

## 2. Onboarding and account setup, in order

1. **Choose language** — a full-screen picker, first thing after install.
2. **Intro** — four Lottie animations, plus a five-slide "story" told with glossy 3D icons
   (problem → tool → reward: a frustrated settings panel, an announcement with stars, a trophy,
   a five-star thumbs-up).
3. **Sign in** — phone number + OTP, with the OTP also offered over **WhatsApp**; one-tap
   **Truecaller**, **Google** and **Apple** sign-in; a picker when one phone has several accounts.
4. **Sign-up stepper** — a progress bar across the remaining steps.
5. **Persona** — big 3D character cards, Pixar-style Indian characters: *Landlord*, *Property
   Manager*, *Broker*, *Tenant*. Choosing Tenant asks whether they are looking for a place or
   already staying in a RentOk property, and routes them away from the manager app.
6. **First property wizard** — a short instruction screen, then **property type** (PG, co-living,
   flats, studio and more, each with an avatar), **property name**, then **location** (permission
   prompt, map, drop a pin). Then straight onto the home screen.
7. **Guided tour** — coach marks over the home screen on first use.

Everything else is asked **later, at the moment it matters**, as plain questions rather than form
labels — how many floors, which floor a room is on, whether a room is available to rent, the
sharing type (single up to "more than ten", or custom), boys / girls / both (with little emoji
avatars), daily-stay charges.

### The pattern worth copying
- **Persona first, property second, details last.** The app is useful after four taps; the
  long settings (rent cycle, late fine, meals) wait until the owner reaches the feature.
- **Questions, not labels.** Forms read like a conversation: "how many floors do you have?",
  "when should students be back at night?", "who must approve a late entry?".
- **Answers next to the question.** Money screens carry their own FAQ: how a tenant pays, whether
  UPI apps work, whether a receipt is sent, when money reaches the bank, what happens if the tenant
  pays more or less, what it costs.

---

## 3. Structure

**Four main tabs:** Home · Money · People · Property (plus Settings and Security). Two navigation
bar styles ship side by side (adaptive and classic).

**Multi-property:** a property switcher sheet, a floor selector, and **property groups** — group
properties by gender, by landlord, by property, or a custom group ("lenses").

**Global search** across local and server data, from anywhere.

### Module map (Dart files per area)
| Area | Files | What is in it |
|---|---|---|
| Money | 190 | dues and due categories, collection, bank and settlements, wallet, "due packs", expenses, reports, add-dues |
| People | 161 | tenants, team, leads (a small CRM), bookings, a property microsite |
| Property | 113 | rooms (floors and wings), complaints (two generations), food, listings, new property |
| Home | 102 | the server-driven dashboard, stories, dynamic bottom sheets, global search, coach marks |
| Analytics | 77 | a second-generation analytics section |
| Property settings | 69 | every rule the property runs on |
| Tenant details | 69 | profile, **passbook**, document **vault**, a **virtual bank account per tenant**, activity log |
| Add tenant | 67 | the **party wizard**: tenant, co-tenants, parent/guardian for minors, witnesses, agreement preview, e-signature |
| Attendance | 35 | marking, history, pending requests, settings; verification by **Wi-Fi** and **location** |
| Remote widgets | 34 | server-pushed announcements, rent-agreement and referral widgets |
| Reviews | 33 | tenant surveys and review collection |
| AI | 25 | "Rio", a voice + chat assistant |
| Food attendance | 19 | who is eating which meal |
| Activity logs | 17 | guest ("host a friend") and late check-in logs |
| Plans | 17 | Gold subscription, KYC credits, Cashfree checkout |
| Website builder | 14 | a public website for the property |
| Also | | add-on services, support tickets, deep links, an events manager, a message sender, payment QR, book-a-demo |

---

## 4. Home: a dashboard the server assembles

The home screen is a list of **blocks** the server decides: header stats, financials, occupancy,
property overview (drawn as wings), pending tasks, quick actions, shortcuts, smart tools, student
attendance, food management, upcoming reports, platform services, a lifecycle block, an
early-payout ("FlexPe") offer, image and pager blocks. Each block has a filter chip, a shimmer
skeleton and an empty state. On top of that:

- **Stories** — Instagram-style slides (image, video or HTML) the server launches as campaigns.
- **Dynamic bottom sheets** — promos and announcements without an app release.
- **Coach marks** — a stepped tour on first run.
- **A gold promo overlay** — the upsell to the paid plan.

---

## 5. Money

- **Dues** with categories; **bulk electricity and food charges** from CSV templates.
- **Collection:** UPI apps, a **virtual bank account per tenant** (direct bank transfer is
  reconciled automatically), and **auto-debit on the due date with retries on failure**.
- **Rent rules:** rent cycle, due date, security deposit (including a "cashless" deposit),
  advance and adjustments, **lock-in period** (months), **notice period** (days).
- **Late fine:** a fixed amount or a percentage, added automatically after a grace period, and
  can be paused, resumed or adjusted by hand.
- **Electricity:** meter readings per room and per tenant, cost per unit.
- **Wallet, passbook, team passbook, expenses, GST invoices, receipts, payment QR.**
- **Reports** that deliver themselves: which report, which day of the month, what time, to whom.

## 6. People

- **Tenant profile** with passbook, documents vault, KYC, virtual account, activity log, and
  **blacklisting** with a reason.
- **Add-tenant wizard** that ends in a **rent agreement**: parties, co-tenants, a guardian when the
  tenant is under 18, witnesses, a preview from templates, signatures on a signature pad.
- **Invite tenant** to the tenant app.
- **Team** with roles, attendance and a team passbook; "has anyone left your team?" off-boarding.
- **Leads and bookings** — enquiries tracked to a booking.

## 7. Property operations

- **Rooms** by floor and wing; availability; sharing type.
- **Complaints / tickets.**
- **Food:** menus, meal timings per meal, a confirmation deadline before each meal, a **meal QR**
  to redeem, and food attendance.
- **Entry–exit gate control:** who can use the gate and how, the last entry time ("when should
  students return at night?"), late-entry reasons, who must approve and when, a QR scanner at the
  gate, informing parents.
- **Smart attendance:** verified by the property's Wi-Fi or the phone's location; day and night
  shifts.
- **Leave:** when the tenant leaves, when they return, why.
- **Listing and website builder,** with reviews and automatic tenant surveys.

## 8. Growth and money-making

- **Gold plan** (even a gold launcher icon), a **pay-per-use KYC credit** pack, **add-on
  services**, **referral coins**, **book a demo**, a **web dashboard** promoted in the app, partner
  PG brands shown as social proof, and in-app prompts asking happy owners for a review.
- Marketing and analytics stack: **CleverTap** (campaigns, push), **Airbridge** and **Facebook**
  (install attribution), **Microsoft Clarity** (session recording), Firebase, **Sentry**.

## 9. AI: "Rio"

A voice-and-chat assistant marked Beta, with a Pixar-style avatar. Speech in Indian languages
through **Sarvam AI**, with device speech as a fallback. It answers dashboard questions in plain
language — what was collected this month, what is still pending, who has not paid, how many units
are vacant, which category has the most unpaid.

## 10. Visual language

- **Glossy 3D "clay" icons** (stars, trophies, megaphones, thumbs-up) for stories and empty states,
  and **Pixar-style Indian characters** for personas and the assistant. Warm, friendly, very
  "Indian small business".
- **Lottie animations** for intro, success, attendance and Wi-Fi/location checks; a **success
  sound**.
- **Emoji are used sparingly and with a job to do:** a celebration on success ("reminder sent",
  "check-in completed"), pointing fingers in WhatsApp share messages, a red circle for urgent, a
  moon for night shift, a lock for a secure network, a bulb for instructions, folded hands in an
  apology. The "emoji look" people notice is mostly the 3D illustration set, not text emoji.
- **WhatsApp-native sharing:** messages formatted for WhatsApp (bold with asterisks, emoji
  pointers) for reminders, bookings and tenant lists.
- **An empty state for everything** (no collection, no expense, no discount, all dues paid, no
  results), each with its own illustration.

## 11. How they ship

- **Server-driven UI** (home blocks, stories, remote widgets, dynamic sheets) plus **Shorebird** code
  push — most changes reach users without a Play review.
- Offline cache (sqflite), PDF generation and viewing, QR scan and generate, maps and places,
  camera and image crop, video player for tutorials.

## 12. Their permissions, and why Apnivaas should not match them

RentOk asks for contacts, phone state and phone numbers, precise location, Wi-Fi state and nearby
Wi-Fi devices, camera, **microphone**, NFC, the **advertising ID** and Android's ad-services
attribution. Apnivaas ships **ten permissions and no advertising ID**, and its Data safety form,
privacy policy and legal version depend on that. Every one of their tracking SDKs (Clarity session
recording, Facebook, Airbridge, CleverTap) would mean a Data safety change and a legal version
bump. Copy the **experience**, not the data collection.

---

## 13. Apnivaas against RentOk

| RentOk has | Apnivaas today |
|---|---|
| Language picker, 6 languages | English only |
| Persona cards + 4-tap first property | Accounts created by staff or super admin; 1.3.0 plans self sign-up |
| Conversational setup questions with inline FAQs | Standard forms |
| Server-driven home blocks, stories, coach marks | Fixed role dashboards |
| Late fine rules, lock-in, notice period, advances | Partly (rent, dues, receipts) |
| Electricity meters, bulk charges from CSV | Not yet |
| Auto-debit, virtual account per tenant | Razorpay checkout and route transfers |
| Rent agreement wizard with e-sign | Not yet |
| Gate entry/exit, curfew, late-entry approvals | Leave requests only |
| Wi-Fi / location attendance | Not yet |
| Meal settings, meal QR, food attendance | Mess menu |
| Leads, bookings, website, reviews | 1.3.0 plans nearby PGs and visit booking |
| Rio AI assistant | Not yet |
| Gold plan, KYC credits, referrals | Subscription plans |
| 3D illustration set, Lottie, success sound | Purple theme, Apnivaas launch animation |

## 14. Suggested order (to plan from)

1. **Onboarding:** language picker, persona cards, the 4-tap first property, coach marks. Fits the
   1.3.0 self sign-up already decided.
2. **Conversational setup:** rewrite property and rent settings as questions with inline answers;
   add lock-in, notice period, late-fine rules, advances.
3. **Home as blocks:** pending tasks, quick actions, occupancy, collections; empty states with our
   own illustrations.
4. **Money depth:** electricity meters, bulk charges, automatic late fines, scheduled reports.
5. **Operations:** gate entry/exit with curfew and approvals; meal settings and food attendance.
6. **Growth:** listing/website and reviews (overlaps 1.3.0 nearby PGs and visits), referrals.
7. **Later, with care:** AI assistant; Wi-Fi/location attendance (needs new permissions, Data
   safety and a legal version bump).
