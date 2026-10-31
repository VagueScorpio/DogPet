# DogPet — Implementation-Independent Specification

**A desktop virtual-pet application: complete design, architecture, defect history and roadmap.**

Document version 1.0 · Describes a working application built and hardened over 27 iterations

---

## 0. How to use this document

This specifies an application that exists and works. It is written so that an
implementer — human or AI — can rebuild it in **any language, with any
framework, renderer or animation approach they choose**, and arrive at
substantially the same product.

Nothing here names a programming language, a game engine, a rendering library or
an animation system. Where a decision *does* depend on your stack, it is stated
as a requirement plus the question you need to answer about your own tools.

**No artwork is included or specified.** The application is deliberately built so
that all art is supplied as external content, authored by whoever builds it. §7
specifies the *contract* that content must satisfy; what the art looks like is
entirely yours.

| Section | Contents |
|---|---|
| 1 | What the product is and who it is for |
| 2 | Design principles and hard constraints |
| 3 | The domain model — the data and rules, free of presentation |
| 4 | Architecture: services, components, events, startup |
| 5–6 | Full behavioural specification: needs, and the mortality mode |
| 7 | The content-pack system |
| 8 | Presentation and animation requirements |
| 9 | Window, tray and notification behaviour |
| 10 | Persistence and settings, with complete file schemas |
| 11 | Testing strategy |
| 12 | Packaging and distribution |
| **13** | **Every defect found, how it was fixed, and why that fix** |
| 14 | The complete roadmap as actually built |
| 15 | A recommended build order for a fresh implementation |
| 16 | Appendices: every constant, every schema, a platform hazard checklist |

**Read §2.1 and §4.1 before writing code** — they contain the two structural
decisions everything else depends on. **Read §16.3 before trusting any
assumption about your platform**; it is a checklist of nineteen behaviours that
cost real time to discover, two of which were documented incorrectly in the
original project's own specification.

### 0.1 A note on terminology

To stay implementation-independent this document uses neutral terms:

| Term used here | Means |
|---|---|
| **Service** | A long-lived global object, created once at startup, available application-wide |
| **Model** | A pure object: no I/O, no clock, no global state. All inputs are arguments |
| **View / component** | A unit of on-screen structure and behaviour |
| **Event** | A one-to-many notification: publish/subscribe, signal, observer — your choice |
| **Content pack** | A folder of art plus a manifest file, loaded at runtime |
| **Manifest** | A small structured text file describing a content pack |

Structured data files are described below as JSON because that is what the
reference implementation used. Any equivalent human-readable structured format
works; the schemas in §10 and §16.2 carry over unchanged.

---

## 1. The product

### 1.1 In one paragraph

A virtual pet dog lives in a small window on the user's desktop. It has three
needs — **Hunger**, **Happiness** and **Energy** — which change continuously
**including while the application is closed**. On launch the app determines how
long it was shut, advances the needs accordingly, and shows a summary of what
changed. The user cares for the dog with three actions — **Feed**, **Play** and
**Walk** — each of which moves the dog to its own room, plays an animation, and
then applies its effect. The window minimises to the system notification area,
where the app raises OS notifications when a need gets low. All art is supplied
as external content packs that can be added, swapped, exported and imported
without rebuilding the application.

### 1.2 The core design bet

Most virtual pets are either a game you open deliberately, or a background
process you forget about. This one is neither: **the needs advance in real time
whether or not the app is running**, so the dog is genuinely waiting when the
user comes back. Everything else follows from that single decision — the
persistence design (§10), the offline catch-up (§5.5), the notification
behaviour (§9.3) and the tray-residency model (§9.2).

### 1.3 Two modes of play

- **Casual** (the default): the dog **can never die**. It becomes sad until
  cared for, and that is all.
- **Mortal**: the dog ages, can fall ill, needs treatment, and can be lost to
  starvation or to untreated illness. A permanent record remembers every dog
  that has lived.

The second mode was added later, at the owner's explicit request, and is strictly
additive: nothing in Casual mode can harm the dog, and any state left over from
a spell in Mortal mode is cleared rather than lying in wait.

### 1.4 Product requirements

1. **Fully portable.** The application runs from an unpacked folder. Nothing is
   installed, no system-wide state is written, and deleting the folder removes
   it completely.
2. **No runtime dependencies the user must install.** Anything that requires
   calling out to the operating system must use facilities already present on a
   stock installation.
3. **Content is external and user-editable.** Art lives in a plain folder beside
   the executable, in ordinary files with a small manifest. The user can replace
   the dog and the rooms without rebuilding anything.
4. **The application must never fail to start.** Missing, corrupt or malicious
   content degrades gracefully to a built-in fallback set, with a notice.
5. **Accessibility: never rely on colour alone.** Every status conveyed by
   colour is also conveyed in words and by a number.

---

## 2. Design principles and hard constraints

### 2.1 The two structural decisions

Everything in this specification rests on two choices. Make them first.

**(a) Separate pure logic from everything that touches the world.**

All rules — arithmetic, thresholds, state transitions, text selection, validation
— live in **models**: objects with no I/O, no access to global services, and no
clock of their own. Time, randomness and configuration arrive as **arguments**.
The services that own a clock, a file handle or an event channel are thin
wrappers around them.

This is not stylistic preference. It has three concrete payoffs:

- The same code runs the live application, the offline catch-up, and the tests.
  There is no second implementation of the rules to drift out of agreement.
- A state can be evaluated at any point in time rather than only played forwards,
  which is what makes the offline catch-up possible at all.
- The rules are testable without constructing any part of the application.

And one practical constraint that may apply to you: in the reference
implementation, **a source file that referenced a global service could not be
compiled by the test harness at all**, because the harness started before the
services were registered. That made any rule living alongside a service
reference *permanently untestable*. Whether or not your stack has the same
quirk, adopt the discipline:

> **If a rule is worth testing, it goes in a model.**

During a later security review this rule was violated three times by fixes that
were written into service-bound files, and all three had to be moved before they
could be verified (§13.2, D-15 and D-20).

**(b) Make the offline catch-up a first-class concern, not an afterthought.**

The app's defining feature is that time passes while it is closed. That means:

- persisted state must include the timestamp it was written at;
- every rule that advances state must accept an arbitrary elapsed duration, not
  a per-frame delta;
- the catch-up must be *correct* for long durations, not merely not-crash — see
  the starvation-window problem in §6.1 and defect **D-8**.

### 2.2 Hard constraints

1. **Typed, explicit style throughout.** Declare types where the language allows
   it; prefer explicitness over cleverness.
2. **No third-party dependencies** beyond the chosen framework itself. Anything
   that calls the OS must use stock facilities.
3. **No hard-coded art paths in application logic.** All art arrives through the
   content loader. The only art embedded in the binary is the fallback set.
4. **Never crash on bad content.** Every loader degrades: a broken pack is
   described and skipped, a missing picture costs one decoration, a missing
   content folder falls back to the built-in copy.
5. **One version number**, in one place, displayed in the About screen, and
   incremented with every change.
6. **A rolling changelog** with *what / why / how* for every version, and a
   table of contents kept current.
7. **Source files stay focused and modest in length** (the reference
   implementation targeted ~300 lines), commented in plain language. When a file
   outgrows that, split the cohesive piece out as a new model — this happened
   four times and is recorded in the roadmap.

### 2.3 Window and display requirements

| Property | Value |
|---|---|
| Default window size | 540 × 760 (portrait; a tall narrow window suits a standing dog and three stacked bars) |
| Minimum window size | 420 × 600 |
| Scaling | The layout scales with the window and must not break at the minimum size |
| Image filtering | Nearest-neighbour, since the reference content was pixel art. If your art is not, choose accordingly |
| Resizable | Yes |
| Window title | `DogPet — <pet name>` |

---

## 3. The domain model

This section defines the application's data and rules with no reference to
presentation. An implementation that gets this right has the hard part done.

### 3.1 Entities

**Pet state** — the dog that exists now:

| Field | Type | Meaning |
|---|---|---|
| `hunger` | number 0–100 | Rises over time. 100 = starving |
| `happiness` | number 0–100 | Falls over time. 0 = miserable |
| `energy` | number 0–100 | Rises over time. 100 = restless |
| `name` | text | User-chosen; defaults to "Biscuit" |
| `pack_id` | text | Which content pack the dog is wearing |
| `last_saved_at` | timestamp | When this state was written |

**Life state** — only meaningful in Mortal mode, but always persisted:

| Field | Type | Meaning |
|---|---|---|
| `born_at` | timestamp | When this dog began |
| `age_days` | number | Age in *dog-days* (see §6.3) |
| `sickness` | number 0–100 | Illness severity. 100 = fatal |
| `ill` | boolean | Whether an illness is in progress |
| `starving_seconds` | number | How long hunger has been at its maximum |
| `alive` | boolean | |
| `died_at` | timestamp | |
| `cause` | enum | none / starvation / illness |

**History record** — one per dog that has died, kept permanently:
`name`, `born_at`, `died_at`, `age_days`, `cause`.

### 3.2 The unifying abstraction: "badness"

The three needs do not point the same way: two rise towards trouble and one
falls. Rather than special-casing each, define:

```
badness(need) = 100 - value   for happiness
              = value         for hunger and energy
```

Badness always runs 0 (just cared for) to 100 (critical), whichever direction the
underlying need runs. Every threshold, label, countdown and ordering decision is
then expressed once, over badness, and works for all three without branching.

Two companion helpers follow: `cared_value(need)` (100 for happiness, 0
otherwise) and `critical_value(need)` (0 for happiness, 100 otherwise).

**This abstraction is worth adopting verbatim.** It eliminates an entire class of
sign-error bug, and it is why the needs logic stayed clean through 27 iterations
while almost every other defect found was elsewhere.

### 3.3 Rules the model must implement

All of these are pure functions or methods on pure objects:

| Rule | Signature (conceptual) |
|---|---|
| Advance needs | `drain(seconds, interval_table)` |
| Offline catch-up | `catch_up(elapsed_seconds, real_interval_table)` |
| Elapsed between timestamps | `elapsed_between(then, now) → never negative` |
| Clamp an implausible elapsed | `capped_elapsed(elapsed, limit)` |
| Current level of a need | `level_of(need) → fine / warning / critical` |
| Time until critical | `seconds_to_critical(need, intervals)` |
| Time spent at critical during a drain | `seconds_at_critical(need, start_value, elapsed, interval)` |
| Apply a care action | `apply_action(action, effect_table)` |
| Current mood | `mood_state(seconds_since_action)` |
| Worst need right now | `worst_need()` |
| Advance life | `advance(seconds, hunger_is_critical, mortal_mode, hunger_interval, config, random_roll, now)` |
| Treat illness | `treat(amount) → was_cured` |

Note the shape of `advance`: **the random roll is supplied by the caller.** That
is what keeps the life rules pure and lets tests decide exactly what happens.

---

## 4. Architecture

### 4.1 Services (8)

Long-lived, created once at startup, in this order. **The order matters** —
see §4.4.

| Service | Responsibility |
|---|---|
| **Paths** | Resolves all folder locations; verifies writability; records startup notices |
| **Log** | Timestamped append-only log with size rotation |
| **Settings** | Owns the settings file; publishes a `changed(key)` event; serves tuning lookups |
| **Needs** | Owns the live pet state, the clock, autosave, the offline catch-up, the dog's name and pack |
| **Content** | Scans the content folder; owns the active pet and rooms; owns the UI icon set |
| **Notifier** | Decides when to speak and raises an OS notification or an in-app banner |
| **Tray** | The notification-area icon and menu; close-button behaviour; low-power mode |
| **History** | The permanent record of past dogs (may be a model + file rather than a service) |

### 4.2 Models (pure, testable)

| Model | Responsibility |
|---|---|
| **NeedsModel** | The needs arithmetic: drain, clamp, thresholds, catch-up, actions, mood |
| **NeedsText** | All user-facing wording: names, labels, countdowns, durations, reactions |
| **CareSettings** | The shipped defaults, the lookups over them, and the safety floors |
| **LifeModel** | Ageing, illness, starvation, death |
| **PetHistory** | Reading and writing the permanent record |
| **SaveFile** | Safe write protocol and read-with-fallback |
| **PetPack** | Parsing and validating a pet manifest; fit-and-scale geometry |
| **ScenePack** | Parsing and validating a room manifest |
| **UiPack** | Parsing the icon manifest |
| **PetMotion** | Procedural poses: `(state, time, variation) → pose` |
| **Pose** | The pose value object (offset, scale, rotations, facing, tint) |
| **PetAnimator** | State machine, blending, idle fidget scheduling |
| **ActionPlan** | What each care action involves, as lookups |
| **NotificationRules** | Whether to speak, and what to say |
| **ImageLimits** | How large an image may be; reading dimensions from a file header |
| **PackArchive** | Reading and writing content-pack archives; entry safety; size limits |
| **PackLinks** | Which of a pack's hyperlinks are safe to open |
| **ArchiveSizes** | An archive's declared entry sizes, read from its index |
| **ScenePainter** | Drawing the procedurally generated backgrounds |
| **UiBits** | The small shared building blocks panels are assembled from |

### 4.3 Views

| View | Role |
|---|---|
| **Main** | The window: menu, need bars, pet area, action buttons, overlays |
| **PetView** | The dog itself, for both content kinds (§8.1) |
| **NeedsBar** | One need, or the illness meter |
| **SettingsPanel** | The seven-section settings screen |
| **AwayCard** | "While you were away" summary |
| **Banner** | In-app message strip |
| **DeathCard** | Mortal mode: the dog has died |
| **Scoreboard** | Every dog that has lived |
| **HelpPanel** | How to change the art |
| **AppMenu** | The menu bar |
| **SceneStage** | Holds the current room and transitions between rooms |
| **SceneView** | Draws one room: background, then decorations |
| **ActionRunner** | Runs a care action from beginning to end |
| **PackTransfer** | The import/export flow: dialogs, confirmation, backups |
| **CreditsList** | Builds the credits block |

**Build the panels programmatically, not as fixed layouts.** Almost everything
they show is a list of whatever happens to be installed — the packs found, the
rooms offering themselves for each slot, each pack's credit line — none of which
can be known in advance.

#### Main view structure

```
Main
├── Background
└── Shell (vertical)
    ├── MenuHost                      ← menu bar inserted here
    └── Layout (padded)
        └── Column (vertical)
            ├── HeaderRow: pet name · spacer · demo-speed badge
            ├── NoticePanel: startup notice text · dismiss button
            ├── Bars: one NeedsBar per need (+ illness bar in Mortal mode)
            ├── PetArea: [room layer] + [pet layer]
            ├── ReactionLabel: one line of how the dog seems
            └── ActionRow: Feed · Play · Walk · (Treat) · Settings
```

Overlays — AwayCard, Banner, SettingsPanel, HelpPanel, DeathCard, Scoreboard —
are siblings drawn above the shell, each hidden until needed.

#### Need bar structure

```
NeedsBar (vertical)
├── TopRow:    icon · name · spacer · status word
├── Bar:       a proportional fill
└── BottomRow: countdown text · spacer · hint text
```

The **status word** (*Fine* / *Getting low* / *Needs care now*), the
**countdown** ("needs care in ~1h 20m") and the **hint** ("full bar = starving")
are all mandatory: colour is never the only signal, and a full bar means
opposite things for Hunger and Happiness.

### 4.4 Events

Components communicate by event. Avoid reaching across the view tree by path.

| Event | Published by | Consumed by |
|---|---|---|
| `need_changed(need, value)` | Needs | NeedsBar |
| `threshold_crossed(need, level)` | Needs | NeedsBar, Notifier |
| `pet_name_changed(name)` | Needs | Main |
| `pet_died(cause, name, age)` | Needs | Main → DeathCard |
| `fell_ill()` / `healed()` | Needs | Main |
| `pet_started()` | Needs | Main, Notifier |
| `settings_changed(key)` | Settings | Main, panels |
| `pet_changed(pack)` | Content | PetView |
| `room_changed(role, pack)` | Content | SceneStage |
| `library_reloaded()` | Content | SettingsPanel |
| `banner_requested(title, body)` | Notifier | Banner |
| `transition_finished(role)` | SceneStage | — |
| `action_started/finished(action)` | ActionRunner | Main |
| `transfer_finished(message)` | PackTransfer | SettingsPanel |
| `new_pet_requested(name)` | DeathCard | Needs |
| menu requests (rename, help, settings, scoreboard) | AppMenu | Main |

**Debounce the two high-frequency events.** `need_changed` fires only when the
*rounded displayed* value changes, and `threshold_crossed` only on an actual
level change. The Needs service keeps a map of last-announced values and last
announced levels to do this. Without it, both fire every frame and every
subscriber pays.

### 4.5 Startup sequence

1. **Paths** — resolve folders; create the save folder; **verify writability by
   actually writing a probe file**; fall back if that fails; record notices.
2. **Log** — open the log, rotate if oversized, replay Paths' notices, record
   version and folder locations.
3. **Settings** — load defaults, merge the stored file over them, then **always
   rewrite the file**, so a missing or partial one is repaired.
4. **Needs** — read the pet state (falling back to the backup copy), apply the
   offline catch-up, build the away-summary, save.
5. **Content** — scan for packs and rooms, load the icon set, fall back to
   built-ins where needed, activate the remembered pet and rooms.
6. **Notifier** — subscribe to Needs, clear stale temporary files, **adopt the
   current levels** (below).
7. **Tray** — build the icon and menu if the platform supports it.
8. Finally, construct the **Main** view.

**Two consequences of this ordering caused real defects (§13.1):**

- **All services finish before any view exists**, so nothing is subscribed to
  events during startup. Anything that happens during the catch-up therefore
  cannot be *announced* — it must be **stored and collected**. The Needs service
  holds the away-summary for Main to fetch in its own setup, and a death during
  catch-up must be detectable by reading `alive` rather than by having heard the
  event. Defect **D-7** is precisely this, and it made saves permanently
  unplayable.
- **A need can already be critical at launch with no crossing to observe.** The
  Notifier must therefore *adopt* the current levels as its starting point and
  schedule reminders for anything already critical — otherwise a dog left in a
  bad state overnight is never mentioned again. Defect **D-12**.

---

## 5. The needs system

### 5.1 Meanings and presentation

| Need | Over time | Bad end | Restored by |
|---|---|---|---|
| **Hunger** | rises | 100 = starving | Feed |
| **Happiness** | falls | 0 = miserable | Play |
| **Energy** | rises (pent-up) | 100 = bouncing off the walls | Walk |

Hunger and Energy bars **fill as things get worse**, which is counter-intuitive
and must be labelled explicitly — hence the mandatory hint text.

### 5.2 Care intervals

An *interval* is the time from fully cared for to critical. Each need drains
linearly at `100 / interval` per second.

| Setting | Hunger | Happiness | Energy |
|---|---|---|---|
| Frequent | 40 min | 45 min | 50 min |
| Moderate (default) | 3 h | 3 h 30 m | 4 h |
| Long | 10 h | 11 h | 12 h |
| Demo | 45 s | 50 s | 55 s |

**The three needs are staggered on purpose** so they do not all reach critical
at the same moment — which would reduce three decisions to one.

**Demo is a toggle, not a fourth setting.** When enabled, the live drain uses the
Demo row and a visible badge shows in the header. **The offline catch-up always
uses the user's chosen real setting, never Demo** — otherwise a 45-second row
applied to hours of real absence would max every bar the instant the app
reopened. Implement this as *two separate lookups* (`live_interval_set()` and
`catch_up_interval_set()`) rather than one function with a flag, and test it: it
is the kind of rule that is easy to get quietly wrong.

### 5.3 Thresholds

- **Warning** at 70 badness.
- **Critical** at 100 badness.
- Values clamp at the bad end.
- **Use an epsilon of 0.001 at both thresholds.** Draining for exactly 70% of an
  interval lands on 69.99999, and a full interval on 99.99999. Without the slack
  a need can sit one ten-millionth below a threshold, *display as 70*, and never
  fire its warning. This is a real bug that an exact comparison will give you.

### 5.4 Care actions

Each action, in order: **lock the action controls → transition to the action's
room → play the animation for the action's duration → apply the effects →
transition home → unlock.**

Effects land **after** the animation, so the bars move when the dog has actually
been fed rather than when the button was pressed.

| Action | Room | Animation | Duration | Primary effect | Side effects |
|---|---|---|---|---|---|
| Feed | eat | eat | 5 s | Hunger → 0 | Happiness +5 |
| Play | play | play | 8 s | Happiness → 100 | Energy −15, Hunger +5 |
| Walk | walk | walk | 10 s | Energy → 0 | Happiness +10, Hunger +10 |
| Treat | clinic | sad | 7 s | (illness −60) | Happiness −8 |

Durations are **unchanged** in Demo mode — the animations still need to be
watchable.

**Apply all absolute sets before any relative deltas.** Otherwise the result
depends on the order the configuration file happened to list them in, which is
not a property you want your game balance to have.

While an action runs the care controls are locked so nothing can be started
twice or interrupted. The settings screen stays reachable: changing a room
mid-walk is harmless, and locking the user out of their own settings is worse.

### 5.5 Offline catch-up

1. On write, persist the current timestamp.
2. On launch, compute `elapsed = now − last_saved_at`.
3. **Floor it at zero.** A clock that moved backwards would otherwise heal the
   dog for free.
4. **Cap it** at a plausible maximum — 30 days — and treat a non-finite value as
   zero. See defect **D-17**, which explains at length why the cap alone is
   *not* sufficient and what must accompany it.
5. Advance the needs by the capped elapsed, using the real interval set.
6. In Mortal mode, advance the life state too — **but only if the elapsed time
   is believable** (D-17).
7. If elapsed exceeds 60 seconds, show the away-summary: each need's before →
   after and the dog's reaction.

### 5.6 Mood

When no action is running, evaluate **worst-first**:

```
energy ≥ 85                        → restless
happiness ≤ 25 OR hunger ≥ 85      → sad
within 4 s of a completed action   → happy
otherwise                          → idle
```

An ill or dead dog is always `sad`, whatever its needs say. The ordering matters:
a dog with energy to burn cannot settle even if it is also hungry, and a
miserable one does not bounce.

### 5.7 Autosave

Every 30 seconds, on minimise to tray, and on quit — using the safe write
protocol in §10.2.

---

## 6. Mortal mode

Strictly additive. **Nothing here can happen in Casual mode**, and any residue
from a spell in Mortal mode is cleared on the next advance rather than lying
dormant.

All tuning values are **counted in hunger intervals**, not in absolute time, so
the whole subsystem scales with the user's care setting automatically: on Demo an
illness runs its course in a minute; on Long it takes most of a day. This is a
small decision with a large payoff — it means there is one set of numbers rather
than one per care setting.

### 6.1 Starvation

Hunger reaching 100 starts a countdown of **one further care interval**. On the
Moderate setting that is 3 hours to reach starving, then 3 hours more. **The
countdown resets the moment the dog is fed.**

This can occur during the offline catch-up — the owner's explicit choice — but
the absence must be **split in two**: the stretch before hunger reached its
maximum, and the stretch after it. **Only the second feeds the starvation
clock.**

> Computed in one piece instead, a dog fed immediately before the app closed and
> away for three hours and one minute on Moderate would be credited with three
> hours and one minute of starvation and die instantly — when in truth it had
> been starving for one minute.

This requires a dedicated rule, `seconds_at_critical(need, start_value, elapsed,
interval)`: given a starting value and a drain duration, how much of that
duration was spent at the bad end. It is defect **D-8**, and it is the single
least obvious piece of arithmetic in the application.

### 6.2 Illness

At random — on average once every 8 hunger intervals — the dog falls ill. An
illness meter climbs 0 → 100 over 1.5 hunger intervals; at 100 the dog dies. A
newly ill dog starts at 4 rather than 0, so the meter is visible the moment it
appears. **Treatment removes 60**, so a badly ill dog needs more than one visit.

**Express the chance as an average wait, not a per-tick probability:**

```
fell_ill = random_roll < 1 - exp(-seconds / mean_wait)
```

This makes one long catch-up exactly as likely to produce an illness as the same
duration spent watching — and no more likely. A naive per-tick probability gives
you a dog that is overwhelmingly likely to be ill after any absence, which feels
arbitrary and punishing.

### 6.3 Ageing

Two hunger intervals to the **dog-day**, through four life stages: **Puppy**
(under 3 dog-days), **Young** (under 10), **Adult** (under 40), **Senior**.

Ageing happens in **both** modes. **Old age is never fatal** — the owner chose
that deliberately; the stages exist for attachment, not as a timer.

### 6.4 The permanent record

Every dog that dies is written to the record **at the moment of death**, with
name, birth, death, age and cause.

Write it **there and nowhere else**, so that reloading an already-dead state
cannot record the same dog twice — which works because the life rules return
early once `alive` is false. Cap the record (200 entries), newest first, oldest
trimmed.

**Keep the record in a separate file from the pet state.** It outlives every pet
in it: starting a new dog wipes the pet state and must not wipe the record of the
one before. This is a one-line decision that is very annoying to retrofit.

The scoreboard screen lists the record, and also lists the dog the user has now,
marked as still living — because a scoreboard showing only the dead is a strange
thing to open when your dog is fine.

---

## 7. The content-pack system

This is the application's defining feature and — as §13.2 shows at length — its
entire attack surface. Design it as if every file in it were written by a
stranger, because eventually one will be.

### 7.1 Layout

```
<app folder>/
├── <executable>
├── content/
│   ├── pets/<any folder name>/      pet manifest + art
│   ├── rooms/<any folder name>/     room manifest + art
│   ├── ui/                          icon manifest + icons
│   ├── licenses/                    licence files for third-party art
│   └── CREDITS.txt                  the combined credit text
└── saves/                           created on first run
```

The content folder is **excluded from any build-time asset pipeline**. It must be
read from disk at runtime, exactly as it will be in the shipped product, so that
development and production behave identically. If your toolchain imports or bakes
asset folders automatically, mark this one excluded — and see defect **D-2** for
what happens when a *build output* folder is not similarly excluded.

### 7.2 Pet packs

A folder containing a manifest is a selectable pet. Two kinds must be supported,
because they exercise genuinely different presentation paths and keeping both
honest prevents the renderer collapsing into one special case.

**Kind A — a 3D model:**

```json
{
  "format_version": 1,
  "id": "my_dog",
  "name": "My Dog",
  "kind": "model3d",
  "model": "model.<ext>",
  "target_height": 1.0,
  "rotation_y_degrees": -29,
  "animations": {},
  "credit": "...", "license": "...", "license_url": "...", "source_url": "..."
}
```

Requirements:

- **Load at runtime from a plain file**, not through a build-time asset pipeline.
- **Normalise the size automatically.** Compute the combined bounding box of all
  renderable geometry, scale uniformly so the height equals `target_height`, and
  translate so the feet sit at ground level and the model is centred
  horizontally. **This is not optional:** models from different sources arrive at
  wildly different scales — the two reference models differed by about 3× — and
  without normalising, every pack needs hand-tuning.
- Apply `rotation_y_degrees` so the dog faces the viewer. Models are rarely
  authored facing the camera.
- `animations` optionally maps application states to animation clip names inside
  the model file. **If a clip exists for a state, play it; otherwise use the
  procedural animation (§8.2).**
- **Assume the procedural path is the normal one.** Both reference models were
  static geometry with no rig and no clips at all. Treating procedural animation
  as a fallback rather than the main path will produce a lifeless application.

**Kind B — a 2D sprite sheet:**

```json
{
  "format_version": 1,
  "id": "my_sprite_dog",
  "name": "Sprite Dog",
  "kind": "sprite2d",
  "pixel_art": true,
  "display_height_px": 160,
  "faces": "right",
  "animations": {
    "idle": { "file": "idle.<ext>", "frames": 1, "fps": 1 },
    "walk": { "file": "walk.<ext>", "frames": 4, "fps": 6 }
  },
  "credit": "..."
}
```

Requirements:

- Each animation is a **horizontal strip of equal-width cells**. Slice by frame
  count. Reference the strip's regions rather than copying each cell, so a
  four-frame walk costs one image in memory, not four.
- If `pixel_art` is set, use nearest-neighbour filtering and **whole-number
  scaling only**. Choose the largest integer scale not exceeding
  `display_height_px`.
- **Choose one scale for the whole pack, from its tallest frame.** The reference
  sprite pack had 43-pixel idle frames and 32-pixel walk frames; scaling each to
  fit independently made the dog visibly change size the instant it started
  walking.
- `faces` declares which way the art is drawn; mirror it for the other direction.
- Validate the sheet at load: if its width does not divide evenly by the frame
  count, reject that animation with a readable reason.

**Valid state names, both kinds:** `idle`, `happy`, `sad`, `eat`, `play`,
`walk`, `restless`, `sleep`. Any state without its own art falls back to `idle`
plus the procedural layer.

**`credit` is required.** It is a licensing obligation, not decoration — see
§16.4. A pack without one is still usable, but the omission is reported.

### 7.3 Room packs

Five fixed **roles**: `home` (the default view), `eat`, `play`, `walk`, `clinic`.

A room declares which role it fills **in its own manifest**, so the folder may be
named anything and **several rooms can offer themselves for the same role**, for
the user to choose between. A folder with no declared role falls back to its
folder name. The chosen room per role is remembered in settings.

```json
{
  "format_version": 1,
  "role": "eat",
  "name": "Kitchen",
  "background": { "type": "tiled", "wall": "wall.<ext>", "floor": "floor.<ext>",
                  "floor_ratio": 0.38, "tile_scale": 4 },
  "decorations": [
    { "file": "bowl.<ext>", "x": 0.78, "y": 0.78, "scale": 3, "role": "food_bowl" }
  ],
  "pet_spot": { "x": 0.5, "y": 0.82 },
  "transition": "fade"
}
```

**Three background types:**

| Type | Fields | Behaviour |
|---|---|---|
| `image` | `file` | One picture scaled to **cover** the window — cropped, never stretched |
| `tiled` | `wall`, `floor`, `floor_ratio`, `tile_scale` | Repeating tiles, with a thin darker line where wall meets floor. **Enforce a minimum drawn tile size** — see **D-26** |
| `generated` | `style` + colours | Drawn entirely in code from colours — no art files at all |

**Generated styles** — these are what let the application ship a working room
with no art whatsoever, and are worth implementing early:

- `yard` / `park`: a banded gradient sky (48 bands reads as smooth), ground, a
  few clouds; trees and bushes for `park`; a path when a path colour is given.
- `room`: a plain interior — wall, a skirting band along its base, and a floor
  with faint seams. Takes wall, skirting and floor colours plus a floor ratio.

With scrolling enabled, a generated scene scrolls horizontally with **parallax**:
clouds slowest (0.25× ), trees medium (0.6×), ground detail at full speed. This
is how the walk room conveys travel.

**Size all generated scenery as a fraction of the view's height, never in fixed
pixels.** The dog's own on-screen size derives from the view, so the scenery must
too or the proportions fall apart at other window sizes — defect **D-1**.

**Decorations:**

- `x` and `y` are fractions of the window, 0–1. `x` is the decoration's centre;
  **`y` is its bottom edge**, so objects sit on surfaces instead of floating.
- `scale` is an integer for pixel art.
- Draw in ascending `y` order, so items lower in the window (nearer the viewer)
  overlap those behind them.
- An optional `role` gives a decoration a job: `food_bowl` is where the dog walks
  to eat, `toy` is what gets thrown during play, `exam_table` is where it stands
  for treatment. First match wins; a `<role>_alt` entry is a backup used only if
  the primary is missing.
- `pet_spot` optionally overrides where the dog stands.
- When the dog walks to a decoration, **stand it beside the object, not on it** —
  interpolate the dog's position 35% back towards the centre of the room. This
  stops it covering the bowl it is eating from and hanging off the edge when the
  object is near one.

**Transitions:** `fade` cross-dissolves over 0.5 s; `slide` pushes the old room
out sideways, which reads as travelling and suits starting a walk. **Both legs
of a journey use the same transition**, so returning matches departing.

A missing file costs that one decoration, or falls the background back to
`generated`, with a warning logged. Never crash.

### 7.4 Icon pack

A manifest naming the tray icon, its alert variant, one icon per need (plus
illness), and one per action button, with an integer scale. **No icon is
load-bearing**: a missing one is simply not drawn. The pack counts as usable if
it has at least a tray icon.

### 7.5 Built-in fallback set

Embed a minimal set in the binary: one pet, four rooms (`home`, `eat`, `play`,
`walk`) and the icons. **This is the only art that ships inside the executable.**

If the content folder is missing, damaged, or every pack in it fails to load, use
these and log a notice. **The application must never start with no dog at all.**

Note that an embedded pack may need a *different loading path* from an external
one, if your toolchain pre-processes embedded resources. Branch on where the pack
came from. (In the reference implementation an embedded model was a pre-built
scene object while an external one needed runtime parsing — see §16.3, item 17.)

### 7.6 Import and export

**Export:** choose a pack, pick a destination, write an archive of the folder
with a credits file alongside — so the credit travels with the art instead of
being left behind. Built-in packs cannot be exported.

**Import:** choose an archive; it must contain a pet or room manifest at its root
or inside one top-level folder. **The manifest nearest the root wins**, so a
stray nested manifest cannot hijack the import. Validate, then extract to a
folder named from the pack's cleaned id — for rooms, from the *folder* name
rather than the role, so importing a second kitchen adds one rather than
replacing the first.

Replacing an existing pack must **ask first**, **copy the old one to a
timestamped backup folder**, and only then empty and replace it — in that order
(see **D-19** for what happens when the emptying step is missing, and **D-16**
for why the ordering is load-bearing).

**Archive entry safety — mandatory.** Before extracting anything, reject:

- empty entry names;
- names beginning with a path separator;
- names containing a volume or scheme separator;
- **any path component equal to `..`** — the classic archive-traversal attack;
- **reserved device names** for your target OS (on Windows: `CON`, `PRN`, `AUX`,
  `NUL`, `COM1`–`COM9`, `LPT1`–`LPT9`, matched on the portion before the first
  dot, case-insensitively).

Check in the inspection pass **and again per entry during extraction** — the
extractor must not trust the inspector.

**Archive size safety — mandatory.** See **D-14**; an archive's compression ratio
is unbounded.

### 7.7 Content size limits

Two independent guards, because they catch different attacks:

**Image dimensions.** A maximum decodable pixel count (33,554,432 — roughly
8192 × 4096, about 128 MB uncompressed). **Read the declared dimensions from the
image file's header before decoding anything**, because pixel count has little to
do with file size: a 200-megapixel image can compress to a couple of megabytes
and then demand most of a gigabyte the moment it is decoded. A size that cannot
be read counts as *unknown* and is not refused — refusing every format whose
header you do not parse would refuse every format you did not anticipate — so
keep a post-decode check behind it as well.

**Archive entry sizes.** Per-manifest, per-file and per-archive ceilings plus an
entry count limit, checked **before** any entry is read. Details and the
reasoning in **D-14**.

---

## 8. Presentation and animation

How you render and animate is yours to choose. This section specifies the
*behaviour* the chosen approach must deliver.

### 8.1 Composing two kinds of pet into one layout

The view is layered: **background → decorations → pet → interface.**

The pet layer must accept **either** a 3D model **or** a 2D sprite, and the rest
of the application must not care which. For a 3D model this means rendering it
over a **transparent background** so it composites onto a flat 2D room — in the
reference implementation, an off-screen render surface with transparency enabled,
containing the model, a camera at a slight three-quarter overhead angle (raised
0.85 units, back 2.2, pitched down 10°, ~40° field of view), a key light and a
fill light.

**Draw a soft dark elliptical shadow beneath the pet, for both kinds.** It is
what makes the dog read as standing on a floor rather than floating in front of
one, and it costs almost nothing — generate it once as a radial alpha falloff
(the reference used 128 × 56 with alpha ∝ (1 − distance)²).

**Positioning a 3D pet:** rather than moving the model around the world, keep it
at the origin and **move the whole render surface** until the point where its
feet project to lands on the wanted screen position. Measure one body height in
screen pixels the same way (project the top of the model and subtract), so the
shadow and other decorations can be sized identically for both pet kinds.

The pet's on-screen position is per-room (`pet_spot`) and is **tweened** when it
changes, over about half a second.

### 8.2 Procedural animation

**This subsystem exists because the reference content had no animation at all** —
static geometry, no rig, no clips. The life has to come from moving the whole
body: breathing, hopping, bobbing, tilting. It then turned out to work just as
well on a 2D sprite, and it means **any** art works immediately, however
minimal.

Specify it as a **pure function**: `pose_for(state, time, variation) → pose`,
where a pose carries position offset, non-uniform scale, three rotations, a
facing sign and a colour tint. Same state at the same time always gives the same
pose. This makes it testable, and it means a state can be evaluated at any point
rather than only played forwards.

Anything genuinely random — which idle fidget, whether this particular happy
moment includes a spin — is decided by the animator and **passed in as the
`variation` argument**, keeping the pose function pure.

| State | Motion |
|---|---|
| `idle` | Slow breathing: vertical scale ±2% over a 3 s cycle. Every 4–9 s, one fidget: a head tilt (roll ±8°), a small turn toward the viewer, or a little hop |
| `happy` | 2–3 quick hops with squash-and-stretch on landing; a full 360° spin about 30% of the time |
| `sad` | Sinks ~8% lower, nose pitched down 14°, breathing speed halved, a slow sway every 7 s, desaturated tint |
| `eat` | Repeated nod — pitch down 20° and back — about 2.5 times per second |
| `play` | A 1.6 s cycle: fast low run-bobs for the first 65%, then a pounce (jump with stretch going up, squash on landing). Turns back and forth to chase |
| `walk` | Steady trot bob around 4 Hz, body turned side-on (~70° yaw), while the room scrolls past |
| `restless` | Pacing left and right over a 1.6 s cycle with faster bobs, plus a spin roughly every 5 s |
| `sleep` | Lies low (vertical scale 0.85, slight roll), very slow breathing, with floating "z" marks |

**Blend between states rather than tweening.** Mix the pose the dog was holding
into the new state's pose over ~0.3 s. The obvious alternative — a tween from
old pose to new — breaks when the state changes again mid-transition, which it
frequently does. A blend survives that for free.

**Sprite adaptations.** A sprite cannot turn, so express a yaw as a horizontal
squeeze — interpolate 60% of the way towards `|cos(yaw)|`. **But only when the
pack has no art of its own for that state:** a walk strip is already drawn
side-on, and squeezing it as well just makes the dog look thin. Keep the facing
sign (mirror) and the yaw (turn) as *separate* pose fields, and let each
presentation path use the one it can honour.

---

## 9. Window, tray and notifications

### 9.1 Window

As §2.3. A menu bar across the top with Pet / Mode / Care / Content / Window
menus. **Rebuild each menu's state as it opens** rather than keeping it in sync
by hand — most of what it shows is the state of something, and refreshing on
open is far harder to get wrong.

### 9.2 Tray residency

An icon in the system notification area with a menu: **Open**, **Pause
notifications for 1 hour** (checkable), **Quit**. A tooltip showing all three
need percentages, refreshed every 10 seconds. An **alert variant of the icon**
while anything is at Warning or worse — so the tray itself carries the message
without a notification having to. Primary click restores the window.

**Close-button behaviour is a setting, defaulting to minimise-to-tray.** Take
over the window's close request rather than letting the framework quit. Quitting
from the tray menu always saves first. The first time the window hides, say so
once — "still running in the tray" — so nobody thinks they have quit the app and
left it consuming battery.

**While hidden or minimised, drop the frame rate hard** (the reference used 5 fps
plus a low-power mode) and restore it on show. **The needs must keep advancing
throughout.** This is what makes tray residency cheap enough to be the default.

If the platform has no notification area, say so and make the close button quit
normally. Detect this rather than assuming.

**Expect platform surprises here.** §16.3 items 11 and 12 record two from the
reference implementation: a documented "hide the window" call that did nothing at
all, and window state properties that reported *incorrect values* while
minimised, requiring a different API to be consulted instead. Verify both
behaviours in your stack before building logic on them.

### 9.3 Notifications

If the platform offers no in-process notification API available to the
application, raise notifications by **invoking a stock OS facility as a child
process** — detached, so the application never stalls waiting for it.

**If you do this, read D-25 before writing a single line of it.** Passing
user-controlled text to a child interpreter was the most serious defect found in
this application's entire history, and the mistake is extremely easy to make.

The requirements:

- Launch detached, never blocking the main loop.
- **Never interpolate user-controlled text into a command or script.** Pass it as
  data — encoded arguments, environment, or a structured payload the child
  decodes — and build any markup through a document API that escapes values,
  not by string substitution.
- Verify no console window flashes on screen. If one does, route through a
  different stock launcher; if that launcher needs a temporary script file, see
  **D-22** for where to put it.
- Notifications may appear to come from the OS facility rather than from your
  application, because registering an application name is exactly the kind of
  system-wide installation a portable app cannot do. Accept it and document it.

**When to notify** — only while the window is hidden, minimised or unfocused:

- on crossing **Warning**: "<name> is getting hungry."
- on reaching **Critical**: "<name> is starving! Time to feed."
- **at most once per crossing.** Reset the flag when the need is cared for, and
  when things improve, so the next decline is announced again.
- while still critical, repeat every 30 / 60 / 120 minutes (Frequent / Moderate /
  Long) or 60 seconds on Demo — **floored at 10 seconds** (see **D-10**).
- never while notifications are paused or disabled.

While the window **is** visible and focused, show the identical message as an
**in-app banner** instead — which slides in, sits about 7 seconds and leaves by
itself. A system notification appearing over the very app it is talking about is
silly.

---

## 10. Persistence and settings

Three files, in a `saves` folder beside the executable.

### 10.1 Locating and verifying the save folder

- Resolve the base folder from the running executable's location, so the app is
  portable.
- Create the save folder if missing, then **write a probe file into it and delete
  it**. Creating a directory can succeed where writing a file still fails, so the
  probe is the part that matters.
- If the probe fails — the app was unpacked into a protected location — **fall
  back to the per-user application-data folder**, and tell the user on screen
  where the saves went. The About screen always shows the real paths.

**Bootstrapping note:** the path service necessarily runs before the logging
service exists, so it cannot log. Have it collect messages into a list that the
logger drains as soon as it starts.

### 10.2 Pet state file, and the safe write protocol

```json
{
  "format_version": 1,
  "pet_name": "Biscuit",
  "pet_pack_id": "my_dog",
  "last_saved_unix": 1762000000.0,
  "hunger": 42.0, "happiness": 61.0, "energy": 18.0,
  "life": {
    "born_unix": 1761000000.0, "age_days": 5.8,
    "sickness": 0.0, "ill": false, "starving_seconds": 0.0,
    "alive": true, "died_unix": 0.0, "cause": 0
  }
}
```

A state is trusted only if it has `hunger`, `happiness`, `energy` and
`last_saved_unix`.

**The write protocol. The ordering is the whole point** — see **D-16** for the
data-loss bug the obvious ordering produces:

1. Write the new state to a temporary file.
2. **Copy** — never move — the current state file to a temporary backup name,
   then rename that over the real backup.
3. If step 2 fails, **keep the existing backup** and record that the backup is
   now stale. A slightly old backup is worth incomparably more than none.
4. Rename the temporary file over the real state file.
5. If step 4 fails, **leave the existing state file alone** and report failure.
   Never delete it to make room.
6. Report separately whether the write succeeded and whether a backup survives,
   so the caller can warn when the safety net has quietly gone.

**The read protocol:** try the main file; if it is missing, empty, unparseable or
incomplete, try the backup; otherwise report "no usable state", meaning start a
fresh dog. Record which source was used, and log it.

Route the permanent record through the same protocol. It is rewritten in full on
every death and is the one file meant to outlive everything else.

### 10.3 Settings file

Written with the shipped defaults when absent. On load, **merge stored values
over the defaults only where the key is one you know and the type matches** — so
an unknown key is ignored, a typo cannot put text where a number belongs, and an
older file gains any new keys instead of breaking. Numbers must additionally be
**finite** (see **D-21**). Then **always rewrite the file**, so a partial one is
repaired.

```json
{
  "format_version": 1,
  "care_interval": "moderate",
  "play_mode": "casual",
  "demo_speed": false,
  "intervals_seconds": {
    "frequent": { "hunger": 2400,  "happiness": 2700,  "energy": 3000 },
    "moderate": { "hunger": 10800, "happiness": 12600, "energy": 14400 },
    "long":     { "hunger": 36000, "happiness": 39600, "energy": 43200 },
    "demo":     { "hunger": 45,    "happiness": 50,    "energy": 55 }
  },
  "action_effects": {
    "feed":  { "hunger_set": 0,     "happiness_delta": 5 },
    "play":  { "happiness_set": 100, "energy_delta": -15, "hunger_delta": 5 },
    "walk":  { "energy_set": 0,     "happiness_delta": 10, "hunger_delta": 10 },
    "treat": { "happiness_delta": -8 }
  },
  "action_seconds": { "feed": 5, "play": 8, "walk": 10, "treat": 7 },
  "mortal": {
    "age_day_intervals": 2.0,
    "starve_grace_intervals": 1.0,
    "sickness_rise_intervals": 1.5,
    "illness_mean_intervals": 8.0,
    "treatment_heals": 60.0
  },
  "critical_reminder_minutes": { "frequent": 30, "moderate": 60, "long": 120, "demo": 1 },
  "rooms": { "home": "", "eat": "", "play": "", "walk": "", "clinic": "" },
  "close_button": "tray",
  "tray_notice_shown": false,
  "start_minimized": false,
  "notifications_enabled": true
}
```

**This file is intended to be hand-edited**, which is why several values need
enforced floors in code — §16.1, and defects **D-10** and **D-15**.

**Security limits deliberately do not live here.** A limit the user can edit is a
limit an unpacked content pack could edit, and then it is not a limit. Hard-code
them.

### 10.4 Permanent record file

```json
{ "format_version": 1,
  "pets": [ { "name": "Biscuit", "born_unix": 0, "died_unix": 0,
              "age_days": 7.4, "cause": 1 } ] }
```

`cause`: 0 none, 1 starvation, 2 illness. Entries lacking a name are discarded on
load; the list is sorted newest-death-first and trimmed.

### 10.5 Log file

Timestamped lines, appended one at a time and flushed — so nothing is lost if the
process is killed. **Rotate on size** (1 MB), keeping one previous generation.

**Rotate continuously, not only at startup.** See **D-23**: this application is
designed to be left running for days, so a check that only runs at launch is not
a limit at all. Track the byte count as you write rather than measuring the file
each line.

### 10.6 Settings screen

Seven sections, **rebuilt from scratch each time it opens** — cheap, and nothing
can drift out of step with what is actually installed:

1. **Care** — the three interval choices, the full interval table so the choice
   is informed, and the Demo toggle.
2. **Pet** — name field, and a pack picker listing every valid pack with its name,
   kind and credit. **Switching packs keeps the needs** — it is the same dog in a
   new body, not a new dog.
3. **Rooms** — one picker per role, listing every room offering itself for it.
4. **Content** — open folder, reload, import, export.
5. **Window** — close-button behaviour, start minimised.
6. **Notifications** — on/off, send a test, resume if paused.
7. **About** — version, the save and content folder paths (clickable), and the
   credits.

**The credits block is a licensing obligation, not a nicety.** Show every
installed pack's credit line **exactly as its author wrote it**, active pet
first, with licence and source links clickable **only when they are plain web
addresses** — anything else is shown as inert text (see **D-18**, which is why).
Show the combined credits file underneath.

Every change saves immediately.

---

## 11. Testing strategy

Eight suites, run headlessly from a command line, each printing a pass/fail line
per check and exiting non-zero on any failure. The reference implementation
reached **760 checks**.

| Suite | Covers |
|---|---|
| Needs | Drain rates per setting, clamping, threshold crossings, catch-up (0 s / 1 h / 3 days / negative / capped), Demo exclusion, action effects, corrupt-state fallback |
| Pets | Manifest parsing, fit-and-scale geometry, integer scaling, every procedural pose, image limits |
| Life | Casual never kills, ageing, starvation, the offline starvation split, illness, treatment, broken tuning, persistence |
| Packs | Archive traversal and device names, archive sizes, link validation, inspection, round-trip, replacement, broken archives |
| Rooms | Real installed rooms, roles, all three background types, decorations, tile sizes, action plans |
| Notify | When to speak, what to say, tray display, icon pack, log rotation |
| History | Empty, recording, ordering and trimming, broken file, formatting |
| **Integration** | **Cold starts of the real application** |

### 11.1 Why the integration suite is not optional

Every other suite tests a pure model in isolation — and that is exactly why a
mid-project review found **all eight** of its defects in the **wiring between
correct parts**: a death announced to an empty room, actions that still worked on
a dead dog, reminders never scheduled. None of it was arithmetic, so none of it
was visible to any amount of unit testing.

The integration suite starts the **real services and the real main view**. Three
things make it work:

1. **One process per scenario.** A cold start is the thing being tested, and the
   services are singletons that load state once — "what happens when the app
   starts" cannot be tested twice in one start. A parent process spawns a child
   per scenario and tallies what it prints.
2. **A scenario that printed nothing is itself a failure.** Otherwise a child
   that crashed before reaching its checks passes silently.
3. **Every scenario ends with the same assertion: that saves never left the
   sandbox.** Getting this wrong does not fail a test — it quietly destroys the
   user's real pet. It happened once, when the setup waited a fixed number of
   frames for startup instead of waiting for the path service to have actually
   run.

Scenarios worth having: a dead state shows its death screen and allows a restart;
no action, treatment or effect touches a dead dog; a need already critical at
launch gets its reminder scheduled; a new dog inherits none of the notifier's
memory of the last; a bad reminder interval is clamped at the live layer and not
only in the pure helper; two room transitions overlapping; every panel builds; a
clock that jumped forward.

### 11.2 Test-harness constraints

Point the path service at a sandbox folder, and have each scenario **wait for
startup to have genuinely completed** — in the reference implementation the test
entry point ran *before* the services had initialised, so the obvious "wait one
frame" was wrong and silently destructive.

If your harness cannot construct globals (see §2.1), fetch them from the
application root by name rather than referencing them statically.

---

## 12. Packaging and distribution

Ship an archive containing **one top-level folder** (see **D-5**) holding:

```
DogPet-v<version>/
├── <executable>        single file, self-contained
├── content/            copied from the project, build markers stripped
└── README.txt          generated, including the full art credits
                        (saves/ is created by the app on first run)
```

The build script should, in order:

1. Verify the toolchain is present and that **anything needing a separate
   download is installed** — report its absence plainly rather than letting a
   confusing toolchain error through. This is the most common first-build
   failure.
2. Read the version from its single source of truth.
3. **Prepare any toolchain caches *before* running the tests**, not just before
   the build — a fresh checkout may be unable to resolve its own symbols, and
   the tests are code too.
4. Run **every** test suite, **discovered by scanning the test folder rather than
   from a hand-written list** — a hand-written list silently stopped covering two
   suites when they were added, so a failure in either would not have blocked a
   release.
5. Exclude the build output folder from any asset pipeline (**D-2**).
6. Build the executable.
7. Copy the content folder in beside it, stripping development-only markers and
   any import-backup folder.
8. Generate the player-facing README, including credits from the content folder.
   Write it without a byte-order mark, with the target OS's line endings.
9. Archive **the staging folder itself, not its contents** (**D-5**).
10. Report the archive path and size.

One subtlety worth carrying over: if your build shell treats a child process's
error output as a failure, the test step will abort spuriously — these tests
*deliberately* provoke error output, since one of them feeds a corrupt file to a
parser on purpose. Relax that behaviour around the test loop and **trust the exit
code**.

---

## 13. Defects: every bug found, how it was fixed, and why

This is the most valuable section in the document. §13.1 covers defects found
during development; §13.2 covers a full external security review of the finished
application. Each entry gives the symptom, the fix, and — most importantly — **why
that fix rather than an easier one**.

Several of these are hazards of a *class* that any implementation can hit, not
quirks of one toolchain. They are flagged **[universal]**. The rest are flagged
**[verify]**: the specific trigger was platform-dependent, but you should check
whether your own stack has the equivalent.

**Twenty-six defects in total** — thirteen found during development, thirteen by
the review. The identifiers are stable labels, so entries are grouped by theme
and severity rather than appearing in numerical order.

### 13.1 Found during development

#### D-1 — Scenery dwarfed the dog at other window sizes **[universal]**

Generated scenery — trees, bushes, clouds, ground detail — was sized in **fixed
pixels**, so at a larger window the dog shrank relative to it and the composition
fell apart.

**Fix:** size all scenery as a fraction of the view's height.
**Why:** the dog's own on-screen size is already derived from the view, so
deriving the scenery from the same quantity is the only way the two remain in
agreement at any size. Scaling the scenery by a window-size *ratio* would have
worked too but needed a reference size to be meaningful; a fraction needs
nothing.

#### D-2 — Every build absorbed the previous one **[verify]**

The build output folder sat inside the project, and the content copied into it
had its "exclude from asset pipeline" markers stripped on purpose (the end user
has no use for them). That left the toolchain free to treat every staged copy as
project content and embed it in the **next** build — so the executable grew by
several megabytes every single build.

**Fix:** one exclusion marker at the top of the build output folder.
**Why:** one marker covers the whole tree, where stripping per-file markers
cannot. The alternative — building outside the project folder — was rejected
because it complicates every relative path in the build script for no other gain.

#### D-3 — Scenery that scaled but did not compose

Fixing D-1 revealed that the parallax layers were also spaced in fixed pixels, so
at wide windows the repeat became visible.

**Fix:** express layer spacing as a fraction of view height too, and derive the
visible index range from the scroll offset rather than accumulating positions.
**Why:** deriving indices means a layer can scroll forever with nothing
accumulating and no drift, and the count of items drawn is naturally bounded by
the view width divided by the spacing.

#### D-4 — Four files had outgrown comprehension

Four source files had grown past 350 lines and were doing several jobs each.

**Fix:** split out four cohesive models — the generated-background painter, all
user-facing wording, the image size rules, and the shared interface building
blocks.
**Why these four:** each was a *cohesive* responsibility that several callers
wanted, not merely a convenient slice. The wording split in particular paid for
itself immediately: it meant every part of the app — bars, away card, banners,
notifications — necessarily says the same thing about the same state, because
there is only one place that decides.

#### D-5 — The distributed archive unpacked all over the user's folder **[universal]**

The archive was built from the staging folder's **contents**, so it contained the
executable, the content folder and the README loose at the top level. Unpacking
it into a downloads folder scattered a 113 MB executable and a content tree in
among everything already there.

**Fix:** archive the staging folder itself.
**Why it matters out of proportion to its size:** "unpack it anywhere and run it"
is the entire distribution model. A one-word error undermined the product's main
promise, and only showed up by unpacking a real build into a real messy folder —
which is why §12 ends with "unpack the shipped archive into a clean folder" as a
mandatory manual test.

#### D-6 — Overlapping room transitions corrupted the stage **[universal]**

Two transitions running at once trod on each other: the older one destroyed the
room the newer one was displaying, cleared the "busy" flag early, and announced
arrival in a room that had already been left. Choosing a room from settings
during an action was silently dropped.

**Fix:** a **generation counter**. Each transition takes a ticket; one that finds
itself overtaken steps aside quietly without destroying anything or announcing
anything, and the newest call owns the stage.

**And a second, subtler fix:** wait out the transition on a **timer, not on the
animation's completion**. A second call destroys the object the first was
animating, which cancels that animation *without it ever reporting completion* —
so the first call would wait forever, holding the busy flag behind it. Any
"await this animation" pattern has this hazard wherever the animated object can
be destroyed; prefer waiting on a duration you control.

#### D-7 — A death nobody was told about made saves permanently unplayable **[universal]**

The most serious functional defect in the project's history, and the clearest
lesson in it.

A dog that died during the **offline catch-up** published its death event
*before any view existed*, so nothing was subscribed and the event was lost. The
window opened with everything frozen, no death screen, and **no way to start
another dog**. The save was unplayable for good, and nothing ever told the user
what had happened.

**Fix:** the main view **reads `alive` directly** during its own setup, as well as
subscribing to the event.

**Why that fix:** an event cannot be the only channel for something that may
happen before there are listeners. The general rule this produced:

> **Anything that can happen during startup must be readable as state, not only
> observable as an event.** If you publish it during startup, also store it.

The same reasoning produced the away-summary design (stored, then collected) and
the notifier's level adoption (D-12).

#### D-8 — Offline starvation was credited for the whole absence **[universal]**

The starvation clock was advanced by the entire elapsed absence whenever hunger
ended at maximum — so a dog fed just before closing and away three hours and one
minute on Moderate was credited with three hours and one minute of starvation and
died instantly.

**Fix:** split the absence at the moment hunger reached its maximum, and feed only
the later portion to the starvation clock. This required a dedicated pure rule
(§6.1).

**Why not simply cap the credited time:** because the correct answer is
computable exactly. The need drains linearly, so the moment it crosses is
`remaining_badness / rate` into the absence. Approximating something you can
calculate is how you get a game that feels arbitrary.

#### D-9 — Actions still worked on a dead dog **[universal]**

Feed, Play, Walk and Treat all functioned after death, topping up the needs of a
dog that was gone; an action already in flight when the dog died also re-enabled
the controls as it finished.

**Fix:** guards at **three** separate entry points — the action runner, the needs
mutator and the treatment mutator — plus a control-state rule that keeps the
buttons locked for a dead dog regardless of what else asks for them.

**Why three guards and not one:** a disabled button is a *presentation fact*, not
an invariant. A keyboard shortcut, or a click landing in the same frame as the
death, got through. Each public mutator has to defend itself.

#### D-10 — Three configuration values that could wreck the application **[universal]**

The settings file is designed to be hand-edited, and three values had no floor:

- **A zero reminder interval** meant a reminder every frame — and each reminder
  raised while the window is hidden spawns a child process to display it. Roughly
  **sixty new processes per second.**
- **A negative action duration** made the timer fire on the very next frame, so
  the animation never played and the dog was home before it had left.
- A third: the notifier retained its memory of the previous dog, so a new dog's
  first warning read as an *improvement* on the dead one's critical state and was
  swallowed silently.

**Fix:** enforced floors (10 s, 0.5 s) and clearing the notifier's memory when a
new dog starts.

**Why the floors live in the pure settings model:** they were deliberately moved
*out* of the settings service into the model, precisely so the tests could reach
them. A guard you cannot test is a guard you will break.

#### D-11 — A new dog inherited the dead one's red bars **[universal]**

Starting a new dog reset the values silently, so the bars still displayed "Needs
care now" in red — inherited from the dog before.

**Fix:** **announce** the reset rather than writing over the values quietly.
**Why:** the bars and the notifier both learn what a need is doing from the
threshold event. Mutating state that others mirror, without publishing, guarantees
they drift. The general rule: if a subscriber caches it, every change must be
published — including resets.

#### D-12 — A need already critical at launch was never mentioned again **[universal]**

The notifier only reacted to *crossings*. A dog left starving overnight was
already at critical when the app opened, so there was no crossing, so it was
never mentioned again — for as long as the app ran.

**Fix:** at startup, adopt the current levels as the baseline and schedule
reminders for anything already critical.
**Why:** an edge-triggered subscriber needs an explicit initial state. The levels
are *adopted* rather than announced, because at launch the user is usually looking
at the window where the away summary has just said the same thing.

#### D-13 — Countdowns promised care for a dead dog

Bars continued to show "needs care in 2h 14m" for a dog that had died and whose
needs no longer advanced.

**Fix:** display "no longer counting".
**Why:** the countdown is derived from a drain rate; when the rate is zero the
honest answer is not a large number but *no* number.

### 13.2 The external security review

A full external review of the finished application read every source file line by
line and found **13 defects: 2 critical, 2 high, 3 medium, 5 low, 1
informational.** All were fixed. The test count went from 637 to 760.

The review's own conclusion is the most portable sentence in it:

> **Every finding of substance was on a trust boundary, and the pure arithmetic
> layer was clean.** External, user-editable content is the application's best
> feature and its entire attack surface, and content-pack data was being trusted
> the way typed-in text is trusted.

**Catalogue your trust boundaries explicitly.** The reference implementation's
were: pet manifests, room manifests, the icon manifest, imported archives, the
pet state file, the settings file, the record file, the child process used for
notifications, the OS "open this link" facility, and the system clock. Every
single finding was on one of those ten.

---

#### D-14 — High — Unbounded decompression on import (archive bomb) **[universal]**

The import path read each archive entry whole into memory with **no size check**.

**Demonstrated:** a **597 KB** archive containing a manifest padded with 600 MB
of whitespace followed by valid content drove peak memory to **3,024 MB** and
froze the application for 4.4 seconds — and the import **accepted** the pack,
because the parser skips whitespace. At 4 GB of padding (archive still ~4 MB) it
is an out-of-memory crash, triggered the moment a file is *chosen*, before any
confirmation.

**The key insight that makes the fix sound rather than approximate:** the archive
reader allocated exactly the entry's **declared** uncompressed size and read at
most that many bytes. So **the declaration is the allocation** — an archive that
under-declares cannot force a larger allocation, it merely gets truncated.
Checking the declared size therefore bounds memory *completely*, which is the
difference between a real defence and a hopeful one.

**Fix:** a new model reads each entry's declared uncompressed size from the
archive's own index **without decompressing anything**, and the import enforces
four ceilings before the first read: 256 KB per manifest, 64 MB per file, 256 MB
per archive, 512 entries. Anything that cannot be measured confidently — no
index, a truncated index, or an extended-format index — is **refused rather than
read hopefully**.

**Result:** inspection allocates **1 KB in 1 ms** instead of ~3 GB in 4.4 s.

**Why hard-coded ceilings:** a limit in the settings file is a limit an unpacked
pack could edit.

**Why refuse the extended archive format outright:** it exists for archives over
4 GB or 65,535 entries. A content pack is neither, and supporting it would only
let larger things through the check.

**A gap the tests caught:** a 263 KB manifest passes the 64 MB per-*file* ceiling
onto disk. Harmless to copy — but the manifest is re-read and re-parsed on
**every** content reload. The manifest ceiling had to apply during extraction
too, not only during inspection.

#### D-15 — High — A zero grace period killed a healthy dog, repeatedly **[universal]**

```
grace = hunger_interval × starve_grace_intervals
if starving_seconds >= grace: die_of_starvation()
```

With `starve_grace_intervals` at zero, `grace` is zero — and `starving_seconds`
is **also** zero, because the line above resets it for a dog that is *not*
hungry. `0 >= 0` is true. **A perfectly fed dog died of starvation on the first
processed frame.** And again on the first frame after the user started another,
appending a record to the permanent history each time. The mode became unplayable
with nothing on screen to explain why.

**Fix, in two layers:**

- The settings model **floors** the dangerous values: the grace period (0.1
  intervals), the dog-day length (0.1 — zero divides by zero and makes the age
  infinite) and the treatment amount (1.0 — a treatment that heals nothing
  leaves an ill dog with no recourse). The configuration map is **copied** before
  clamping, so reading values cannot quietly rewrite and then persist over the
  user's own file.
- The life model **independently refuses** a non-positive grace period, whatever
  it is handed.

**Why two layers:** this is the one model where being wrong costs somebody their
pet. It should not depend on its caller for that.

**Why two other values were deliberately left unfloored:** the illness rise rate
and the illness frequency are already guarded at every use, where zero means "an
illness never worsens" and "the dog never falls ill". A floor there would
*introduce* a death rather than prevent one — the wrong direction to be wrong in
— and would remove a setting somebody might be using intentionally.

**The general lesson:** `>=` against a configurable bound is dangerous when both
sides can legitimately be zero. Audit every such comparison.

#### D-16 — Medium — The last good save was deleted before its replacement existed **[universal]**

The obvious write ordering:

```
delete the old backup
rename current → backup        ← if this fails…
    delete current             ← …destroy the only good copy
rename temporary → current
```

Three faults: the old backup went **before** anyone knew a new one could be made;
when the rename failed the only good copy was deleted and the result of that
deletion ignored; and the function still reported **success**.

The rename fails routinely in the real world — a background scanner, a file-sync
client, a preview pane holding the file open, or a read-only flag.

**Demonstrated:** with the backup made unusable, the save reported success, the
backup was gone, and a subsequent corruption left no recoverable state at all.

**Fix:** the copy-then-replace protocol in §10.2, plus a separate report of
whether a backup survived so the caller can warn that the safety net has gone.
The permanent record was routed through the same protocol.

**Why:** **nothing good may be destroyed before its replacement is in place.**
This is the same principle as D-19's ordering, and it generalises to every
destructive operation in the application.

**A cautionary note about documentation:** the comment justifying the original
ordering asserted that the platform could not rename onto an existing file.
**That was false** — checked directly, it overwrites fine. A false comment had
been protecting a data-loss bug for twenty versions. Verify claims like that in
your own stack (§16.3, item 3).

#### D-17 — Medium — A forward clock jump killed the pet, and the obvious fix did not work **[universal]**

The elapsed-time calculation floored at zero, guarding a clock that moved
**backwards**. A clock that jumps **forwards** — the more likely fault, since a
failed real-time-clock battery typically reads far in the future rather than at
the epoch — produced an arbitrarily large elapsed time that flowed into the
catch-up with no ceiling. A state one year old meant a year of starvation
credited during catch-up, so in Mortal mode the dog was dead before the window
opened.

The same path also produced a **non-finite value**: with an infinite elapsed
time, `well_fed_duration = elapsed − starving_duration` is `infinity − infinity`,
and the subsequent `> 0` comparison is false, so the well-fed portion was
silently skipped.

**The planned fix was wrong, and the test proved it.** A 30-day cap was
implemented; the dog **still died**, because 30 days of starvation is far past any
grace period. And **no cap can work**, because the requirements pull apart:

- to stop a clock jump killing the pet, the cap must be **below** one grace
  period;
- to leave genuine long absences behaving as designed, it must be far **above**
  one.

**What reconciles them** — and this is the transferable idea — is that a catch-up
does two *different kinds* of thing:

| | |
|---|---|
| **Reversible** | The needs advance. A maxed-out bar is one click from fixed |
| **Irreversible** | Ageing, illness, death |

The application cannot distinguish a faulty clock from a genuine long absence; it
has only one timestamp to go on, and that is not solvable. But it **can decline
to take an irreversible action on a number it does not believe, while still
taking the reversible one.**

**Fix:** cap the elapsed time at 30 days and treat non-finite as zero. Past the
cap, the needs still advance in full — the dog looks thoroughly neglected — and
the **life advance is skipped entirely**: no ageing, no illness, no starvation
death. The log records it and the away summary tells the user their clock looked
wrong.

**The behaviour change, stated plainly:** a dog genuinely left for forty days now
survives to be looked at rather than being found dead. Everything up to thirty
days is unchanged, and a starving dog still dies within one grace period of the
user opening the window. This was a **product decision**, put to the owner
explicitly and approved, and then **written into the specification beside the
original offline-starvation decision it qualifies** — so the spec and the code
cannot drift apart on the most consequential rule in the application.

**The general principle:** when an input is untrustworthy and the action is
irreversible, decline the action. Partition effects by reversibility and treat
the two differently.

#### D-26 — Medium — A room with tiny tiles froze the window **[universal]**

The tiled background draws by stepping across and down the window one tile at a
time, so a room's cost is **the window's area divided by the tile's**. A tile
scale floored at 1 is meaningless next to how large the tile actually is:

| Window | Tile | Draw calls per frame |
|---|---|---|
| 540 × 760 | 32 × 32 | 425 |
| 540 × 760 | 4 × 4 | 25,785 |
| 540 × 760 | 1 × 1 | 410,940 |
| 2560 × 1440 | 1 × 1 | **3,688,960** |

A hard freeze — and **the user cannot reach the settings screen to choose another
room from inside a frozen window**, while the choice is remembered in settings,
so restarting lands straight back in it. That combination turns a performance
bug into an unrecoverable one.

**Fix, in two layers:**

- **At load:** measure each tile from its file header and **raise** the tile
  scale until the drawn tile is at least 8 pixels on both axes.
- **At draw:** cap the number of tiles placed per axis (256) and stretch a single
  tile over the area instead if that would be exceeded.

**Why two layers:** the loader handles every case where the dimensions can be
read from the file header. The draw cap covers the case it cannot — an image
format whose header you do not parse, where the size is only known once it has
been decoded.

**Why raise the scale rather than refuse the room:** a pack with small tiles is
far more likely to be well-meant than hostile, and pixel art is scaled by whole
numbers throughout the application anyway, so a larger integer scale is an
ordinary thing for it to be. Refusing would punish a mistake that the
application can simply absorb.

**One subtlety worth copying:** check the **drawn** result, not the requested
scale. A 1 × 1 tile at a requested scale of 4 is still only 4 pixels and must
still be raised — otherwise a pack slips through by naming a scale that is
larger but still not large enough.

Result: 1 × 1 tiles cost 14,560 calls at 2560 × 1440 instead of 3,688,960 — a
**253× reduction** — and ordinary 32-pixel rooms are untouched, passing through
the loader with their requested scale exactly as authored.

#### D-18 — Critical — A content pack's credit link could launch programs **[universal]**

The credits screen passed each pack's licence and source URL straight to the
platform's "open this" facility. That facility opens documents, **launches
executables**, resolves bare command names against the search path, and hands
strings to any registered protocol handler. Nothing checked the scheme.

The clickable text is the **licence name** ("CC-BY 3.0"), so a hostile pack
presents an entirely ordinary-looking licence link.

**Demonstrated:** pointing it at an executable script ran it. Variants needing no
file on disk at all: a bare executable name resolved from the path, or an
executable on a remote network share.

**Fix:** a new pure model allows **only** `http://` and `https://` —
case-insensitively, trimmed, rejecting whitespace, control characters and a bare
scheme with nothing after it. Anything else is rendered as **plain, inert text**.

**Why an allow-list and not a deny-list:** which schemes are dangerous depends
entirely on what is installed on the user's machine, which the application cannot
know. Enumerating the safe set is possible; enumerating the dangerous set is not.

**Why the refused URL is still displayed:** showing the licence URI is part of
the attribution obligation. Dropping it would trade a security hole for a
licensing one. It is shown, just not armed.

**Where the rule lives, and why that mattered:** it was first written into the
credits view — which proved **untestable**, because that file references a global
service (§2.1). A security rule that can never be tested is not much of a rule,
so it moved into its own pure model.

#### D-19 — Low — "Replace this pack" merged into it instead **[universal]**

Import backed up the existing folder and then extracted over it — and extraction
removes nothing, so **every file the new pack did not happen to overwrite
survived**. A manifest that no longer listed a walk animation, with the previous
pack's walk art still sitting beside it. The dialog said "replaced"; the
behaviour was a merge.

**Fix:** empty the target folder before extracting — **only after the backup has
been confirmed successful**, which is the same ordering principle as D-16.

**Why it matters more than it looks:** the stale file is not merely untidy. It is
a file the manifest does not describe, which means no validation applies to it
and its origin is unknowable later.

#### D-20 — Low — Non-finite numbers from a state file reached the screen **[universal]**

The structured-data format cannot express infinity directly, **but it can express
`1e999`**, which parsers typically read as infinity — and the serialiser wrote it
back out as `1e99999`. **Once an infinity was in a state file it round-tripped
forever.** Results on screen:

```
age            → "-9223372036854775808 days old"
countdown      → "~-9223372036854775808m"
date           → "27 Jan -292277022657, 08:29"
```

Converting a non-finite float to an integer is undefined and lands on the integer
minimum. Nothing crashed — but the scoreboard, the *memorial* feature, printed
exactly the kind of nonsense that makes someone believe the application has lost
their pet.

**Fix, at both ends:**

- **At every boundary:** the single numeric-read helper in each model now requires
  the value to be finite as well as numeric. One change per model covers every
  field.
- **At the last step before display:** the four formatting functions answer
  "unknown" for anything non-finite *or absurd* — beyond a million dog-days, a
  century of seconds, or a date past roughly the year 5000.

**Why both ends:** the boundary checks should mean the formatters never see such a
value, but the formatters are what the user actually reads, and "unknown" is a
perfectly dignified thing for a memorial to say about a figure nobody can
establish.

**Why absurd-but-finite values are also refused:** a finite `1e18` printed
"1000000000000000000 days old", which is no more useful than the infinity was.

#### D-21 — Low — A size guard silently inverted and skipped the files it existed for **[verify]**

The image header reader parsed the two dimension fields correctly as wide
integers, then stored them in a **fixed-size integer pair whose components were
half that width**. A declared width of 4,294,967,295 became **−1**, and the size
check treated a non-positive dimension as *"size unknown"* — documented as never
too large. So the one file the guard existed to refuse went **straight to the
decoder**.

**Fix:** **saturate instead of truncating** — clamp each dimension to the largest
representable positive value before storing it. The result is honest (the file
really is at least that big), stays positive so it still reads as *known*, and is
refused immediately — while a genuine zero keeps meaning "could not be read".

**Why saturating rather than widening the type:** the three-way distinction
(known-and-fine / known-and-refused / unreadable) is the thing that must survive,
and saturating preserves it with a one-line change and no API churn.

**A second defect found in the same place:** there were **two** header readers.
The duplicate checked neither the file signature nor the size, so an enormous
image was listed as a usable pack and only refused much later. Deleted; there is
one reader now. **Audit for duplicated validators** — the second copy is always
the one missing a check.

#### D-22 — Low — A generated helper script was written where others could replace it **[verify]**

An alternative notification route wrote a small script file into the
application's own folder and then **executed** it. The payload itself was safe,
but the **file** was at a predictable path in a folder whose permissions depend
entirely on where the user unpacked the application. Unpack it somewhere several
accounts can reach — a shared folder, a tools directory left writable, a removable
drive — and anyone who can write there can replace the script and have it run as
the user.

**Fix:** write it to the **per-user** application-data folder, under an
unpredictable name, and sweep the previous one away at startup and before each new
one.

**A defect introduced while fixing this one:** the plan used a scheduled timer to
delete the file. The timer required the application tree, which **is not
available in a global service before it joins that tree** — and a notification
genuinely can be raised from there. Sweeping needs nothing but a directory
listing, so the timer was removed. *Caught by running the test, not by reading
the change.*

**Note the dependency between findings:** fixing D-25's injection mattered far
more here. With that open, this route carried the same injected payload.

#### D-23 — Low — The log rotated only at startup **[universal]**

The size check ran once, at startup. The 1 MB ceiling was therefore enforced at
launch and never again — and this application is designed to be left running for
days. A long session with reminders firing grew the file without limit.

**Fix:** maintain a running byte count as lines are written, rotating when it
passes the ceiling, seeded from the real file size at startup and reset on
rotation.

**Why counted rather than measured:** the logger's entire design is one open, one
line, one close. Querying the file's size on every line would quietly make it
something much more expensive.

#### D-24 — Informational — Reserved device names passed the archive entry check **[verify]**

The entry check correctly refused traversal sequences, absolute paths and volume
specifiers, but not names the OS resolves to **devices** rather than files —
which it does regardless of the containing folder or the file extension.

Reported as **unconfirmed**, honestly: opening such a path fails and the
extractor handles the failure properly. The one case that could not be ruled out
is a machine with the corresponding hardware present, where opening the device
can **block**.

**Fix:** a refusal list matched on the portion before the first dot,
case-insensitively, inside the loop that already walks the path components.

**Why fix an unconfirmed finding:** it closes a gap in an otherwise careful check
for five lines of code, and "probably fine" is not worth keeping. **Why match
before the first dot and not as a prefix:** so that ordinary names which merely
*begin* like a device name are still allowed.

#### D-25 — Critical — User-controlled text was executed as code **[universal]**

Listed last because it is the most important, and because its lesson is the most
general.

Notifications were raised by constructing a small script **as text** and
substituting the pet's name into it:

```
script_template = "... display <text>{NAME}</text> ..."
script = script_template.replace("{NAME}", escape_markup(pet_name))
```

The surrounding literal form was one the child interpreter **expands** — it
evaluates embedded sub-expressions. And because the substitution happened in the
*application*, the name was physically present in the script's source **before
the interpreter parsed it**. So a sub-expression in a pet's name was evaluated
and **executed**.

The escaping function escaped the five markup characters. It did not escape the
interpreter's expansion sigil, because it had never occurred to anyone that there
were two parsers involved.

**Demonstrated** with a pet name containing a file-writing sub-expression, which
wrote the file.

**Where the name came from** — note that only the first is the user typing:

1. The rename dialog.
2. **The pet state file** — which can be shared between users.
3. **An imported content pack's icon manifest**, via the icon path that was
   interpolated into the same script.

**Fix:** stop interpolating entirely. The title, body and icon path travel as
**separately encoded data** which the child decodes, and the markup is built
through a **document API** that escapes values on insertion. The markup-escaping
function was **deleted**, not extended.

**Why that fix and not better escaping:** this is the heart of it. The escaping
was *correct for the markup layer*, and the text was placed where the interpreter
read it **first**. Two parsers saw the same bytes in sequence, and the escaping
only ever satisfied the second one.

> **Escaping is only ever safe against the parser that actually sees the text.
> When two parsers see it in sequence, escaping for one is worse than useless —
> it creates the appearance of safety.**

The only robust answer is to stop constructing code from data. Pass values as
data; let the consumer's own API handle insertion.

**Deliberately not done:** filtering the sigil out of pet names. After this fix a
name containing it is both reasonable and safe, and rejecting it would be an
arbitrary restriction imposed to paper over an architectural mistake.

### 13.3 What was attacked and held

Worth recording, so a reimplementation does not undo protections that are already
correct:

- **Archive traversal.** Parent-directory sequences in both separator styles,
  mixed separators, volume specifiers, nested traversal, leading separators — all
  refused before anything is extracted, and the extractor re-checks rather than
  trusting the inspector.
- **Corrupt and truncated state files.** Empty, truncated, an array where an
  object belongs, missing required keys, wrong types per field — all fall back
  cleanly to the backup and then to a fresh dog.
- **Broken content packs.** Missing manifest, invalid syntax, unknown kind,
  missing model or sheet, a sheet whose width does not divide by its frame count,
  no idle animation, unknown state names, zero and negative sizes, unknown
  background type, unknown role, missing decorations — every one described and
  either skipped or fallen back.
- **Division by zero.** Every rate-derived calculation guards its divisor, and the
  parallax layer range is bounded by view width over spacing.
- The overlapping-transition fix (D-6) and the dead-dog guards (D-9) both hold.
- The test sandbox genuinely keeps the suites away from real user data.

---

## 14. Roadmap

### 14.1 Phases as actually built

Each phase left something runnable, and each was tested before the next began.

| Version | Phase | Delivered |
|---|---|---|
| 1.0–1.2 | — | Specification, content licensing, repository conventions |
| 1.3 | **0** | Public repository, readme, code licence |
| 1.4 | **1** | **Skeleton:** window config, the Paths/Log/Settings/Needs services, the needs/settings/save models, the three bars with countdowns, the interval picker, the Demo toggle, instant care buttons, the away card. 129 checks |
| 1.5 | **2** | **Pets:** the Content service, both pack kinds, size normalising, procedural animation, the pet view, the embedded fallback pet. 222 checks |
| 1.6 | **3** | **Rooms and actions:** all three background types, decorations, transitions, the three care sequences, embedded fallback rooms. 300 checks |
| 1.7 | **4** | **Tray and notifications:** tray icon with menu, live tooltip and alert variant, close-to-tray, OS notifications, in-app banners, the icon pack. 362 checks |
| 1.8 | **5** | **Settings and sharing:** the seven-section screen, pack import and export, the credits list. 418 checks |
| 1.9 | **6** | **Shipped:** build pipeline, generated player readme, edge-case pass, first release |
| 1.10 | — | Screenshots; scenery scales with the window (**D-1**, **D-3**) |
| 1.11 | — | The build stops growing every run (**D-2**) |
| 1.12 | **7** | Menu bar, rename dialog, in-app instructions |
| 1.13 | **8** | **Mortal mode:** the life model, illness meter, treatment action, clinic room, the generated interior background style |
| 1.14–1.15 | — | Illness icon; a nurse in the clinic |
| 1.16 | **9** | **The permanent record** and the scoreboard screen. 542 checks |
| 1.17 | — | Mortal-mode wiring fixes (**D-7** … **D-13**). 560 checks |
| 1.18 | — | Configuration floors (**D-10**). 576 checks |
| 1.19 | — | **The integration suite** — tests that start the whole application. 606 checks |
| 1.20 | — | Image size limits, overlapping transitions (**D-6**), four files split (**D-4**). 637 checks |
| 1.21 | — | The archive unpacks into a folder of its own (**D-5**) |
| 1.22 | — | **Security review:** the two critical findings (**D-25**, **D-18**) |
| 1.23 | — | **Security review:** the two high findings (**D-14**, **D-15**). 686 checks |
| 1.24 | — | **Security review:** the remaining nine. 760 checks |
| 1.25 | — | The catch-up bound written into the specification |
| 1.26 | — | The review write-up added to the repository |
| 1.27 | — | A single rebuild-from-scratch blueprint |

**The shape of that history is worth noticing.** Phases 0–6 built the product.
Phases 7–9 extended it. Versions 1.17–1.24 — **eight of the twenty-seven** — were
spent fixing things, and almost all of those defects were in the **wiring between
correct parts** or on a **trust boundary**, not in the logic. Budget for that
phase; it is not a sign of having built it badly.

### 14.2 Deliberately not done

Each with its reason, so a reimplementation does not helpfully "fix" a decision:

- **The settings file is not written atomically.** A mangled settings file
  self-heals on the next launch from the merged defaults, so it costs preferences
  at worst, never the pet. The pet state and the permanent record *are* written
  atomically, because they cannot self-heal.
- **Files the user places in the content folder by hand have no size limit.** That
  is their own folder and they are invited to fill it; the *import* path is the
  one that accepts files from strangers.
- **Two illness tuning values have no floors** (D-15).
- **Pet names may contain anything.** After D-25 they are safe, and restricting
  them would be arbitrary.
- **Content manifests store their URLs verbatim.** Nothing acts on them unchecked
  any more, and parsing is the manifest reader's job, not validation of intent.
- **No extended-archive-format support on import** (D-14).
- **Notifications may be attributed to the OS facility** rather than to the
  application. Avoiding it requires registering an application system-wide, which
  a portable application cannot do.
- **The taskbar entry remains while minimised to tray**, where the platform
  offers no way to remove it.

### 14.3 Open and unverified

- **Not re-verified since version 1.21:** the real tray icon, close-to-tray, and
  the packaged build. Everything after that point was verified headlessly plus
  live notification tests. **Unpacking the shipped archive into a clean folder
  and running it remains the outstanding manual test**, and §12 makes it
  mandatory for a reason.
- No release has been published for versions 1.22–1.27.

### 14.4 Plausible next work

Not planned, but the natural candidates:

- **A sleep state driven by time of day.** The animation is specified and
  implemented but never triggered — the obvious hook is local clock time plus an
  idle period.
- **More rooms per role.** The architecture already supports several rooms
  competing for one slot and a picker to choose between them; only content is
  missing.
- **A fallback for the clinic room**, the one role without an embedded fallback.
- **Localisation.** All user-facing wording is already funnelled through a single
  model (D-4), which is exactly the seam a translation layer needs.
- **An application identity for notifications**, if a non-portable installed
  variant is ever wanted.

---

## 15. Build order for a fresh implementation

This mirrors how the application was actually built. Each step leaves something
runnable, and each should be tested before moving on.

1. **Project skeleton.** Window configuration per §2.3. Create the content, save,
   docs and build folders, each marked excluded from any asset pipeline.
2. **Paths and Log.** Get the base-folder resolution, the write probe, the
   fallback and the startup-notice buffer right **first** — everything sits on
   them.
3. **The needs, settings and save models, with their tests.** Pure, no
   application required. **Write the tests alongside, not after.** This is the
   heart of the product and the cheapest possible place to be correct.
4. **The Settings and Needs services.** Thin wrappers: autosave, the offline
   catch-up, the events.
5. **The main window, need bars and away card.** A plain functional screen: three
   bars, countdowns, the interval picker, the Demo toggle, instant care buttons.
   *The first point at which the thing can be judged by eye.*
6. **The pet subsystem.** Both pack kinds, size normalising, the pose function,
   the animator, the pet view, the mood rule. The embedded fallback pet. Tests.
7. **The room subsystem.** All three background types, decorations, transitions,
   the three care action sequences. Embedded fallback rooms. Tests.
8. **Tray and notifications.** Tray icon, close-to-tray, OS notifications,
   banners, reminders, pause, low-power mode. **Build the notification payload as
   encoded data from the very start** (D-25). The icon pack. Tests.
9. **The settings screen and content tooling.** Seven sections, import and export
   **with the entry-safety and size checks in place from the start** (D-14,
   §7.6), and the credits block **with link validation from the start** (D-18).
   Tests.
10. **Menu bar and in-app instructions.**
11. **Mortal mode.** The life model **with its configuration floors from the
    start** (D-15), the death screen, the illness meter, the clinic room. Tests.
12. **The permanent record and scoreboard.** Tests.
13. **The integration suite.** Do not defer this in spirit — the wiring between
    correct parts is where the expensive defects live (§11.1).
14. **Build pipeline**, then the edge-case pass: missing content folder, a
    read-only install location, a corrupt state file, a malformed manifest.
15. **Unpack the shipped archive into a clean folder and run it.** The one test
    nothing else substitutes for.

### 15.1 Invariants to preserve

If you change nothing else, keep these ten:

1. Pure logic has **no** global-service references (§2.1).
2. The offline catch-up **never** uses the Demo interval set.
3. The **irreversible** half of a catch-up is skipped when the elapsed time is
   not believable (D-17).
4. **Nothing good is destroyed before its replacement is in place** (D-16, D-19).
5. Untrusted values are **never** interpolated into another language, markup or
   command (D-25).
6. Only plain web addresses from content data reach the platform's "open this"
   facility (D-18).
7. A size is checked **before** the allocation (D-14, §7.7).
8. Security limits are **hard-coded**, never user-configurable (§10.3).
9. A broken content pack is **described and skipped**; the application never
   fails to start because of content.
10. Every pack's credit line is displayed **verbatim** — it is a licensing
    obligation (§16.4).

---

## 16. Appendices

### 16.1 Every tuning constant

**Needs:** warning threshold 70 badness · threshold epsilon 0.001 · restless at
energy ≥ 85 · sad at happiness ≤ 25 or hunger ≥ 85 · happy window 4 s after an
action

**Needs service:** autosave 30 s · away-card minimum 60 s · catch-up cap
2,592,000 s (30 days) · default name "Biscuit"

**Life:** puppy < 3 dog-days · young < 10 · adult < 40 · senior beyond · new
illness starts at 4 · maximum plausible age 1,000,000 dog-days

**Configuration floors:** reminder interval ≥ 10 s · action duration ≥ 0.5 s ·
grace period ≥ 0.1 intervals · dog-day length ≥ 0.1 intervals · treatment amount
≥ 1.0

**Formatting bounds:** countdown/duration ≥ absurd at 3,153,600,000 s (100 years)
· date absurd beyond ~year 5000

**Record:** 200 entries maximum

**Images:** 33,554,432 pixels maximum · header read 24 bytes · dimension
saturation at the largest positive value of the storage type

**Archives:** manifest 262,144 bytes · single file 67,108,864 · whole archive
268,435,456 · 512 entries

**Rooms:** minimum drawn tile 8 px · maximum tiles per axis 256 · default pet
spot (0.5, 0.82) · transition 0.5 s · sky bands 48 · cloud spacing 0.52 /
parallax 0.25 · tree spacing 0.46 / parallax 0.6 · bush spacing 0.34 · ground
detail spacing 0.17

**Animation:** state blend 0.3 s · fidget gap 4–9 s · fidget duration 0.9 s ·
breathing cycle 3 s · happy hop 0.45 s × 3 · pet-spot tween 0.5 s · shadow
128 × 56

**Window and tray:** minimum 420 × 600 · hidden frame rate 5 fps · tooltip
refresh 10 s · notification pause 3600 s · banner dwell 7 s / slide 0.25 s · log
ceiling 1,048,576 bytes

### 16.2 Schema summary

| File | Required | Notable optional |
|---|---|---|
| Pet manifest (3D) | `kind`, `model`, `credit` | `id`, `name`, `target_height`, `rotation_y_degrees`, `animations`, licence fields |
| Pet manifest (2D) | `kind`, `animations.idle`, `credit` | `pixel_art`, `display_height_px`, `faces`, licence fields |
| Room manifest | `role` (or folder name), `background` | `name`, `decorations[]`, `pet_spot`, `transition`, licence fields |
| Icon manifest | tray icon | alert icon, need icons, button icons, scale |
| Pet state | `hunger`, `happiness`, `energy`, `last_saved_unix` | `pet_name`, `pet_pack_id`, `life{}` |
| Settings | — (all defaulted) | §10.3 |
| Record | `pets[].name` | `born_unix`, `died_unix`, `age_days`, `cause` |

A pack id becomes a folder name on import, so clean it to lowercase
alphanumerics, underscore and hyphen, mapping anything else to underscore and
stripping leading and trailing separators.

### 16.3 Platform hazard checklist — verify these in your stack

Nineteen behaviours that cost real time to discover in the reference
implementation. **Two of them were documented incorrectly in the project's own
specification**, which is the real lesson: verify, do not trust.

| # | Question to answer about your stack | Why it matters |
|---|---|---|
| 1 | Can a source file that references a global service be loaded by your test harness? | If not, every testable rule must live in a service-free file. This shaped the whole architecture (§2.1) |
| 2 | Does your fixed-size numeric vector/point type use the same width as your general integer type? | The reference's did not — 32 vs 64 bits — and a size guard silently inverted (D-21) |
| 3 | Does a file rename overwrite an existing target? | Assumed "no" based on a code comment; it was **yes**. That false comment protected a data-loss bug (D-16) |
| 4 | Does your archive reader expose an entry's declared uncompressed size *without* decompressing? | The reference's did not, forcing a hand-written archive-index parser (D-14) |
| 5 | Does your archive reader allocate the declared size, or grow as it reads? | If the former, checking the declaration bounds memory completely — which is what makes D-14's fix sound |
| 6 | Does your parser read a huge float literal as infinity, and your serialiser write it back as one? | If so, an infinity in a data file round-trips forever (D-20) |
| 7 | Does your serialiser handle not-a-number? | The reference's replaced it with null, which prevented a worse bug |
| 8 | What does converting a non-finite float to an integer produce? | Undefined in the reference; landed on the integer minimum and printed as a huge negative (D-20) |
| 9 | Does your encoding helper error on empty input? | The reference's did, which turned every notification with no icon into a logged error |
| 10 | Is the application tree available to a global service before it joins that tree? | Not in the reference, so no timers in early service code (D-22) |
| 11 | Does your "hide the window" call actually hide the main window? | It did **nothing** in the reference; minimising was needed instead (§9.2) |
| 12 | Do window visibility/state properties report correctly while minimised? | They reported **incorrectly**; a different API had to be consulted (§9.2) |
| 13 | Does the literal form you pass to a child interpreter expand embedded expressions? | The one used did. This was the critical defect (D-25) |
| 14 | What exactly does your platform's "open this" facility accept? | It launched executables and resolved names against the search path (D-18) |
| 15 | Does mutating a collection stored inside a map mutate the stored copy, or a temporary? | Verified deliberately — had it been a temporary, every archive-safety refusal would have been silently discarded |
| 16 | How does your date library handle timestamps far outside the normal range? | The reference's handled them arithmetically (no hang) but returned nonsense (D-20) |
| 17 | Does embedded content need a different loading path from external content? | Yes in the reference: embedded models were pre-built objects, external ones needed runtime parsing (§7.5) |
| 18 | Does a fresh checkout need a toolchain preparation step before anything can run? | Yes, including before the tests, which are code too (§12) |
| 19 | Does your build shell treat a child's error output as failure? | It did, which aborted builds on tests that deliberately provoke errors (§12) |

### 16.4 Content licensing obligations

**No artwork is supplied with this specification.** When you add your own, note
the obligation the application is built to honour:

Third-party art is frequently licensed on condition that **its credit remains
visible in the finished application**. That is why:

- `credit` is a **required** manifest field;
- the About screen displays every installed pack's credit line **verbatim, as its
  author wrote it**, never reworded or summarised;
- licence and source links are displayed even when they are refused as clickable
  links (D-18);
- the export function writes a credits file into the archive, so the credit
  travels with the art;
- the build pipeline copies the combined credits into the player-facing readme;
- licence files live in a dedicated content subfolder and must not be deleted.

If all your art is your own, these mechanisms cost nothing and remain useful the
first time you accept a content pack from somebody else. **Do not remove them**
on the grounds that the initial content needs no attribution.

Keep the application's own source licence separate from the content licences, and
say so in both readmes.

---

*End of specification. Companion material in the reference project: the original
design brief, a rolling changelog with what/why/how per version, and the full
security review including every reproduction case.*
