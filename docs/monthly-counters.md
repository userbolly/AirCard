# Monthly tap counters in AirCard for Mac

AirCard can place a small label such as **Oct · 12 taps** on any verified card
with an assigned skin. The default is plain white text near the bottom left,
above Wallet's card-number area. No box or background is drawn.

This is part of the existing **AirCard.app on your Mac**. The phone uses Apple's
built-in Shortcuts app; it does not need a separate AirCard app or Xcode signing.

## How updates work

An iPhone Wallet Transaction automation appends a timestamp to a file in iCloud
Drive each time the selected card triggers it. AirCard reads the file every five
seconds while open, saves the count, and renders it over the original skin. Use
**Flash Skins**, **Apply this card now**, or enable automatic application.

The displayed Wallet artwork only refreshes when this Mac can reach the unlocked,
trusted iPhone and the card has been verified in the current connection's scan.
Counts recorded while away arrive through iCloud later. The image on your phone
keeps its last applied count until that connection is available. Wallet does
not render a live widget inside payment-card artwork.

The counter records delivered Shortcuts tap events, rather than bank-confirmed
purchases or amounts. Opening or selecting a card in Wallet is not a payment tap.
See Apple's [Transaction trigger documentation](https://support.apple.com/guide/shortcuts/transaction-trigger-apd65c67538a/ios).

## Set up one card

### 1. Configure the Mac app

1. Connect, unlock, and trust your iPhone. In AirCard, click **Scan Cards**, then
   open Apple Pay, authenticate, and switch cards as usual.
2. Assign the original skin image to the card. Keep that image in a stable local
   folder: every update starts from it so text never stacks over previous text.
3. Click **Monthly tap counter** below the card.
4. Choose a name and appearance, then click **Save**. The editor stays open so
   you can finish setup and apply the card.
5. Expand **Set up automatic counting in Shortcuts**, click **Create iCloud
   events folder**, then **Copy event template**.

The folder is `iCloud Drive/Shortcuts/AirCard-Taps/`, and the file is `events.txt`.
If you use a different synced folder, choose it in AirCard and use the same
folder in the phone's automation. iCloud Drive must be enabled on both devices.

### 2. Create the phone automation

On iOS 27, create or edit a shortcut, open the action picker, then choose
**Automation → Wallet**. Select only the card matching this AirCard counter.
Expand the trigger and keep **Automation** on; **Notify** can stay off. In
shortcut **Details → Privacy**, enable **Allow Running When Locked**.

On earlier iOS versions, use **Shortcuts → Automation → + → Transaction**,
select the matching card under **When I tap**, and choose **Run Immediately**.
Add these actions:

1. **Date**: use **Current Date**.
2. **Format Date**: input the Date action's output, choose **Custom**, and enter
   `yyyy-MM-dd'T'HH:mm:ss.SSSXXX`. Include the quoted `T` and the timezone `XXX`.
3. **Text**: paste the copied event template. Keep its identifier and `|`, but
   replace the literal `[Formatted Date]` with the **Formatted Date** variable
   from step 2. Insert the variable directly after the `|`, with no spaces or
   line break between them. A visual wrap is fine; pressing Return here is not.
   Keep a newline after the date variable (press Return after it). The copied
   template includes that newline; AirCard waits for it before consuming the event.
4. **Append to Text File**: use the Text action's output. Select **iCloud Drive →
   Shortcuts → AirCard-Taps** as the folder, enter **events.txt** in **File Path**,
   and enable **Make New Line**. Choose the native Shortcuts folder with its app
   icon; unrelated folders can have the same name. Select the destination now so
   the automation does not ask for a folder on each run.

The event line is an opaque per-card key, a `|`, and a timestamp. It contains no
card number, bank credentials, purchase amount, or payment details.

If the file has not appeared in Files yet, wait for iCloud Drive to sync. Grant
Shortcuts access to this file when prompted. Make one automation per card, using
that card's own copied template; they can all append to the same `events.txt`.

### 3. Test before relying on automatic counting

1. Run the automation's actions once manually. This creates one **test tap**.
2. Wait for iCloud to sync and AirCard's next poll. Confirm the Mac preview shows
   **1 tap**. Running it again intentionally records a second event; rereading
   the same file does not add another tap.
3. Use **Apply this card now**. Force-close and reopen Wallet if it retains the
   previous artwork, then check the label on the phone.
4. Set **Count correction → This month** back to zero and **Save**, then apply
   again. The test event stays marked as consumed and will not reappear.
5. Enable **Auto-apply connected counter updates** if desired. Keep AirCard open,
   the iPhone connected and unlocked, and finish the card scan. Automatic retries
   are limited to one attempt per minute.

A manual test proves the actions, sync, counting, and artwork flow. Confirm the
Transaction trigger itself on your next real tap. AirCard cannot force that
physical payment trigger or recover events the phone never recorded.

## Appearance controls

Each card has independent settings and a preview:

- A Wallet number guide with four dots, matching the bottom-left position,
  dot spacing, and system font in the supplied Wallet screenshots. Choose gray,
  black, or white and enter the last four digits for each card. These preferences
  stay on this Mac. Toggle it on or off; it appears only in the editor preview
  and is never included in flashed artwork. Wallet supplies its real digits.
- System, rounded, monospaced, or serif font; five weights; size and text color.
- Bottom left, bottom right, top left, top right, or center anchor, with horizontal
  and vertical offsets.
- Optional text shadow and outline, each with its own color.
- Month, card name, prefix, suffix, unit, separator, and uppercase text. Blank the
  unit and hide the month for a number alone.
- Count correction for a test or a missed event. Changing appearance preserves
  incoming taps unless you explicitly edit the count.

**Save** persists settings; **Apply this card now** applies the saved settings.
Disabling a counter removes the text on the next flash. Its history remains,
and events delivered while it is disabled are consumed without increasing it.

## Monthly rollover and storage

Counts are grouped by calendar month in the **Mac's local timezone**. Each new
month starts at zero automatically. Previous months remain stored; delayed
events are assigned to their original month. At a month boundary, the preview
and connected automatic artwork refresh on the next poll. An offline phone
keeps the last applied image until it reconnects.

The Mac keeps counts and delivered-event deduplication in
`~/Library/Application Support/AirCard/TapCounters/store.json`. It saves events
atomically before attempting a flash, so failed artwork writes do not lose or
double-count taps. A tap arriving during a flash stays pending for a later update.

Keep this local store when replacing the app. Do not delete `events.txt` as a
way to reset a month: use count correction. Duplicate lines with the same card
key and timestamp are counted once, including after app relaunch. The importer
waits for a complete newline-terminated line before reading it.

## Apple Watch

This build applies artwork to the iPhone only. It has no Apple Watch artwork
writer, and the phone's render-cache changes do not provide Watch skin syncing.
Upstream users report that their Watch keeps the original artwork after a phone
skin change in [issue 118](https://github.com/Mak5er/AirCard/issues/118).
Watch support needs a separately verified implementation; enabling the shortcut's
Show on Apple Watch setting only makes the shortcut available there.

## Troubleshooting

- **Nothing counted:** check that the phone automation runs immediately, uses
  the correct card's event template, inserts the date variable, appends a newline,
  and writes to the same iCloud file that AirCard watches. Open the file in Files
  and confirm that a new line appears after a manual test.
- **The file could not be opened:** select the AirCard-Taps folder directly in
  Append to Text File, then use only events.txt for File Path.
- **The file grows but the count stays at zero:** the key, `|`, and timestamp
  must be on one physical line, followed by a newline. Check the custom date
  format for extra punctuation, especially a comma before the milliseconds.
- **Preview changes, Wallet does not:** reconnect and unlock the phone, scan its
  cards, then apply. If AirCard reports a completed write but Wallet shows old
  artwork, force-close and reopen Wallet. A completed backend write alone does
  not prove Wallet has refreshed its on-screen image.
- **Original image missing:** assign the original skin again. A failed counter
  render leaves the update pending and does not flash a skin without its counter.
- **Events file larger than 10 MB:** choose a new events folder and point the
  automations there. Existing counts and delivered-event history stay on the Mac.
- **Incorrect month while traveling:** month boundaries follow the Mac's timezone,
  which may differ from the phone's current timezone.

## Build and validation

Build the same universal Mac app with `./build.sh`. Tests run with
`python3 -m unittest discover -s tests -v` on macOS. Counter coverage includes
per-card and per-device isolation, delayed events, duplicate delivery, concurrent
polling, monthly boundaries, disabled counters, corrupt-store preservation,
failed-write retries, taps arriving during a flash, and the AppKit text renderer.
