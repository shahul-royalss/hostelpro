# DESIGN.md — Stitch UI Specification (PG / Hostel Management SaaS)

How to use this file with Google Stitch:

1. Start a Stitch project per role (5 projects keeps exports tidy: Super Admin, Owner, Manager, Warden, Student).
2. Paste **§1 Design Language** as the first message in every project so all screens share one style.
3. Then generate one screen at a time by pasting its prompt from §3 exactly as written.
4. Desktop screens (Super Admin, Owner, Manager) → generate as **web / desktop**. Warden and Student screens → generate as **mobile**.
5. Export each screen's code and save it to `/design-exports/<screen-id>/` — the screen IDs here (SA-1, OW-2, WD-3…) match `CLAUDE.md` §10.

---

## 1. Design language (paste this first in every Stitch project)

> Design system for a premium hostel-management SaaS. Aesthetic: soft "liquid glass" — frosted, translucent white cards floating over a warm ivory background, generous whitespace, calm and expensive-feeling, never flashy.
>
> Colors: background warm ivory `#F6F4EF`; secondary surface stone `#EDEAE3`; cards are frosted translucent white (white at ~65% opacity with a strong background blur and a 1px soft white border) with a very soft, wide shadow. Primary color deep navy ink `#1C2B45` — used for primary buttons, active nav items, headings, and key numbers. Accent teal `#3E7C74` for success, paid, occupied-healthy, and positive trends. Sage `#8CA687` for free/available states. Sand `#D8B98A` for pending/partial/warning states. Muted red `#C4574E` for overdue, unpaid, open complaints, and errors. Body text charcoal `#2A2E35`, secondary text `#6E7480`.
>
> Typography: Inter everywhere. Big stat numbers bold 28–36px, page titles semibold 22–24px, card titles medium 15–16px, body 14px, labels/captions 12px uppercase with letter-spacing.
>
> Shape & components: cards radius 20px; inputs and buttons radius 12px; status chips are full pills. Primary button = solid navy with white text; secondary = frosted glass with navy text. Status pills: paid/success = soft teal tint with teal text; pending = soft sand tint; unpaid/overdue/open = soft red tint; free = soft sage tint. Charts use navy as the main series and teal as the comparison series, with rounded bars and no heavy gridlines. Icons: thin-line, rounded (Lucide style). Avatars are circles with warm-toned initials.
>
> Layout: desktop screens use a fixed left sidebar (232px, frosted glass, navy active pill on menu items, logo top, user card bottom) and a top bar with page title left and a notification bell + avatar right. Mobile screens use a top app bar (greeting or title + bell) and a frosted bottom navigation bar with 4–5 icons, active item in navy. Everything airy: 24px page padding on desktop, 16px on mobile.

---

## 2. App shells

- **Desktop shell** (Super Admin / Owner / Manager): left sidebar nav + top bar, content area on ivory background, cards in a 12-column grid.
- **Mobile shell** (Warden / Student): top app bar, scrollable content, frosted bottom nav. Primary actions as full-width navy buttons or a floating action button when specified.

---

## 3. Screens

### Auth

**A-1 · Login (responsive)**
> A centered login screen on the warm ivory background with a very subtle blurred navy-and-teal gradient glow behind a single frosted glass card. Card contains: small logo, the product name, "Sign in to your hostel workspace" subtitle, email/phone field, password field with visibility toggle, a solid navy "Sign in" button full-width, and a small "Forgot password?" link. Below the card, tiny footer text. No signup link — accounts are created by admins.

**A-2 · Change password (first login, responsive)**
> Same centered frosted card style as the login screen. Title "Set a new password", explanation line that a temporary password was issued, new password + confirm password fields with strength hint, navy "Save & continue" button.

---

### Super Admin (desktop)

**SA-1 · Super Admin dashboard**
> Desktop dashboard with the sidebar (menu: Dashboard, Hostels, Subscriptions, Create Owner). Top row: four frosted stat cards — Total Hostels, Active Subscriptions, Expiring Soon (sand-tinted number), Total Students on platform. Second row: a wide line chart card "Hostels onboarded" over the last 12 months (navy line), next to a donut card "Subscription status" (active teal / expiring sand / expired red). Third row: a table card "Expiring soon" with columns Hostel, Owner, Ends on, Days left (sand pill), and a small navy "Renew" button per row.

**SA-2 · Create Owner & Hostel (wizard)**
> Desktop screen with a 4-step wizard inside one large frosted card, a slim stepper at top (Owner → Hostel → Subscription → Review). Step shown: "Hostel" with fields Hostel name, Number of floors (stepper input), Number of rooms (stepper input), Address textarea, and a helper note "Rooms and beds will be auto-generated". Footer: ghost "Back" and navy "Continue" buttons. Right side shows a compact summary panel of entries so far.

**SA-3 · Subscriptions**
> Desktop table page titled "Subscriptions". Filter chips (All, Active, Expiring, Expired) and a search field above a frosted table card: columns Hostel, Owner, Start, End, Amount, Status (pill), Actions (Renew, Suspend as small buttons). Pagination at bottom. A slide-over panel on the right shows one subscription's history timeline.

**SA-4 · Hostel detail (monitoring)**
> Desktop detail page with a header card: hostel name, owner name and phone, status pill, subscription end date. Below, stat cards: Occupancy %, Students, Open complaints, This-month revenue. Then two charts side by side: "Revenue vs Expenses" grouped bar chart (teal vs red) and "Complaints per week" small line chart. Read-only feel — no edit buttons except a navy "Renew subscription" in the header.

---

### Owner (desktop)

**OW-1 · Owner dashboard**
> Desktop dashboard, sidebar menu: Dashboard, Complaints, Updates, Staff, Students, Finance. Header greeting "Good morning, {name}" with a small sand-tinted card on the right showing "Subscription: 42 days left". Stat row: Occupancy (beds occupied/total with a thin progress ring), Active Students, Fees collected this month (teal), Fees pending (red), Open complaints. Middle: wide "Revenue vs Expenses — last 30 days" area chart card (navy revenue, red expenses). Right column: "Latest updates" card listing recent broadcast announcements, and a "Recent complaints" card with status pills.

**OW-2 · Complaints inbox**
> Desktop two-pane layout inside frosted cards: left pane is a complaint list with search and status filter pills (Open red, In progress sand, Resolved teal), each row showing category icon, title, student name, time. Right pane shows the selected complaint: title, student + room chip, description, optional photo, a status timeline, a resolution note textarea and a navy "Mark resolved" button.

**OW-3 · Broadcast update composer**
> Desktop page split in two frosted cards. Left card "Send an update": Title field, Message textarea, Audience selector as segmented pills (Everyone, Manager, Warden, Students), navy "Send update" button. Right card "Sent history": list of past updates with audience pill, date, and a small eye icon showing reach.

**OW-4 · Staff & tasks**
> Desktop page with two staff cards at top: "Manager" and "Warden", each frosted with avatar, name, phone, Active pill, and buttons "Reset password" (ghost) — or an empty-state version with a navy "Add manager" button. Below, a "Tasks for manager" card: input row to add a task (title, due date, navy Add), then a task list with status pills (Pending sand, In progress navy, Done teal) and due dates.

**OW-5 · Students directory**
> Desktop table page titled "Students" with a search bar, filters for Floor and Fee status. Frosted table: Photo+Name, Room, Phone, Joined, Monthly fee, Fee status pill (Paid teal / Unpaid red / Partial sand). Clicking a row opens a right slide-over with the student's full profile details, read-only.

**OW-6 · Finance overview**
> Desktop analytics page: month selector top right. Stat cards: Total revenue (teal), Total expenses (red), Profit (navy). Left chart card "Expenses by category" donut (groceries, staff, electricity, water, maintenance, other in the muted palette). Right chart card "Daily profit trend" line chart. Bottom: a compact table of the latest expense and revenue entries with who recorded them.

---

### Manager (desktop)

**MG-1 · Manager dashboard**
> Desktop dashboard, sidebar menu: Dashboard, Expenses, Revenue, Tasks, Menu. Stat row: Today's expenses (red), Today's revenue (teal), This-month profit (navy), Pending tasks (sand). Middle: "This month — expenses by category" donut card next to a "My tasks from owner" card listing tasks with due-date and status pills and a checkbox to mark done. Bottom: quick-add strip — a slim frosted bar with "＋ Add expense" and "＋ Add revenue" navy buttons.

**MG-2 · Daily expenses**
> Desktop page. Top frosted card "Add expense": Date (defaults today), Category dropdown, Amount, Note, Upload receipt (dashed drop area), navy "Save expense". Below, "This month" table: Date, Category chip, Amount, Note, Receipt icon, Edit; footer shows month total in red and a ghost "Export CSV" button.

**MG-3 · Daily revenue**
> Same layout as the expenses screen but for revenue: Add revenue card (Date, Source dropdown: Fees / Mess / Other, Amount, Note) and a monthly table with a teal month total and Export CSV.

**MG-4 · Mess menu editor**
> Desktop page titled "Weekly mess menu". A frosted grid card: columns Breakfast, Lunch, Snacks, Dinner; rows Monday–Sunday. Each cell is an editable text area with placeholder "e.g., Idli, sambar, chutney". Sticky footer bar with ghost "Reset" and navy "Save menu" buttons. Small note: "Students see this menu in their app."

---

### Warden (mobile)

**WD-1 · Warden home**
> Mobile home screen. Top app bar with "Hostel name" and a bell icon. A frosted hero card "Occupancy" with a big navy number "86 / 120 beds" and a thin progress bar, plus two small stats: Free beds (sage) and Fees pending (red). Below, a 2×2 grid of frosted quick-action tiles with icons: Register student, Rooms & beds, Fees, Visitors. Then an "Announcements" card listing the latest owner updates. Bottom nav: Home, Rooms, Register (center, raised navy circle), Fees, More.

**WD-2 · Register student (multi-step form)**
> Mobile multi-step form, step 2 of 5 shown, slim progress bar under the app bar titled "New student". Frosted form card with fields: Guardian name, Guardian phone, Permanent address (textarea). Sticky bottom bar with ghost "Back" and full-width navy "Continue". The stepper labels: Personal, Guardian, ID proof, Room & fee, Review.

**WD-3 · Rooms & beds**
> Mobile screen titled "Rooms". Floor filter chips at top (All, Floor 1, Floor 2, Floor 3). A vertical list of frosted room cards: room number bold left, right side shows bed dots (filled navy = occupied, sage outline = free) and a "3/4 occupied" caption. Fully free rooms get a sage "All free" pill; full rooms a navy "Full" pill. Tapping a card navigates to room detail.

**WD-4 · Room detail**
> Mobile detail screen titled "Room 204 · Floor 2". A frosted summary card: capacity, occupied count, monthly fee range. Then one card per bed: Bed number, occupant avatar + name + phone, joined date, fee status pill, and an overflow menu (Reassign bed, Vacate). Free beds show a dashed-border card "Bed 3 — Free" with a sage pill and a small "Assign student" ghost button.

**WD-5 · Fees tracker**
> Mobile screen titled "Fees" with a month selector chip row (Jun, Jul, Aug active). Summary strip: Collected (teal) vs Pending (red) amounts. Filter pills: All, Unpaid, Partial, Paid. List of frosted rows: student avatar, name, room chip, amount, status pill; tapping an unpaid row opens a bottom sheet "Record payment" with Amount, Mode (Cash/UPI/Bank segmented), Date, and a navy "Save payment" button.

**WD-6 · Leaves & visitors**
> Mobile screen with a top segmented control: Leaves | Visitors. Leaves tab: pending requests as frosted cards — student name, room, date range, reason, and two buttons: sage-outline "Approve" and red-outline "Reject"; below, a history list with status pills. Visitors tab: navy "＋ Log visitor" button on top, then today's visitors as cards with name, relation, visiting student, check-in time, and a ghost "Check out" button.

---

### Student (mobile)

**ST-1 · Student home**
> Mobile home. Top app bar "Hi, {first name}" with bell. Hero frosted card: "Room 204 · Bed 2 · Floor 2" in navy with a small building icon, and beneath it the current-month fee status — either a teal "Paid" pill or a red "Due ₹6,500" pill with a caption "Pay at warden desk". Below: "Updates from hostel" card listing announcements, then a 2×2 quick grid: Mess menu, Raise complaint, Apply leave, My room. Bottom nav: Home, Menu, Complaints, Room, Profile.

**ST-2 · My details**
> Mobile profile screen. A frosted header card with photo, name, phone, joined date. Grouped read-only detail rows in frosted sections: Guardian (name, phone), Address, ID proof (type + view chip), Room & fee. A note "To correct details, contact your warden." At bottom, a "Change password" list row and a red ghost "Log out".

**ST-3 · Mess menu**
> Mobile screen titled "Mess menu". Horizontal day chips (Mon–Sun, today highlighted navy). For the selected day, four frosted meal cards stacked: Breakfast, Lunch, Snacks, Dinner — each with a small icon, meal name, timing caption, and the item list. Today's next meal card has a subtle teal left border.

**ST-4 · Complaints**
> Mobile screen titled "Complaints" with a floating navy "＋" button. List of my complaints as frosted cards: category icon, title, date, status pill (Open red, In progress sand, Resolved teal); tapping expands a status timeline with the resolution note. The new-complaint bottom sheet: Category dropdown, Title, Description, Add photo tile, navy "Submit complaint".

**ST-5 · My room & roommates**
> Mobile screen titled "My room". Header frosted card: Room 204, Floor 2, capacity, my bed number highlighted. Below, "Roommates" list — one frosted row per roommate with avatar, name, and phone number with a small call icon. Nothing else about them is shown. Empty state if living alone: an illustration-free card saying "No roommates yet".

---

## 4. Component inventory (recurring across screens)

Stat card (label caption + big navy number + optional trend), frosted table with pill statuses, segmented pill filters, month selector chips, status pills (paid/pending/unpaid/free/full/open/resolved), bed-dot occupancy indicator, wizard stepper, bottom sheet form (mobile), slide-over panel (desktop), donut + line + grouped bar charts, empty states (one-line message + single navy action), toast confirmations.

## 5. Export → Claude Code handoff

Export every screen's code from Stitch into `/design-exports/<screen-id>/`. Claude Code then rebuilds each as a real component per `CLAUDE.md` §10 — keeping the tokens from §1 (ivory background, frosted cards, navy/teal/sage/sand/red states, Inter, 20px card radius) and replacing all dummy data with live data from the schema in `CLAUDE.md` §5.