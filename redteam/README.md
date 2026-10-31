# Red team audit, October 2026

**Everything described in this folder is fixed.** These are not live
vulnerabilities in DogPet. They were found by an outside audit of the whole of
`scripts/` at **v1.21**, and fixed across **v1.22 – v1.25**; the proofs of
concept are kept because a fix you cannot re-break is a fix you cannot trust.

If you are reading this from the public repo: the versions that carried these
flaws were never released. The first release after the audit is the first one
anybody should run.

## What happened

Thirteen findings, all thirteen fixed.

| | Found | Fixed |
|---|---|---|
| Critical | 2 | 2 |
| High | 2 | 2 |
| Medium | 3 | 3 |
| Low | 5 | 5 |
| Info | 1 | 1 |

Tests went from **637 to 760 checks**, 0 failures. The 123 new checks are
permanent regression guards in the project's own suites under `tests/`, not in
here — so the ordinary `godot --headless --script res://tests/...` runs keep
them honest.

The two Criticals were both code execution reachable from data a user would
think harmless: a dog's name, and a licence link on an imported pack. The common
root cause behind most of the thirteen is that `assets/` being loose and
shareable is this app's best feature and its entire attack surface, and pack
data was being trusted the way typed-in text is trusted.

## What is in here

| | |
|---|---|
| `00-findings-report.md` | The findings as first reported: what broke, how to reproduce it, why, and the recommended fix. Statuses updated as each was fixed. |
| `99-master-report.md` | The whole engagement: architecture, trust boundaries, every fix, how they connect, what is deliberately left alone, and how to keep the app hardened. |
| `fixes/RT-NN-*.md` | One per finding. Each was written **before** its code was touched and updated after it was proven, so it records the plan as well as the outcome — including three plans that turned out to be wrong. |
| `tests/probe_*.gd` | The reproductions. |

Start with `99-master-report.md` for the overview, or go straight to a
`fixes/RT-NN-*.md` for one finding end to end.

## Running a probe

Each is a standalone `SceneTree` script, run the same way as the project's own
suites:

```
godot --headless --path . --script res://redteam/tests/probe_d_injection.gd
```

They write only inside Godot's user data folder (`OS.get_user_data_dir()`) and
never touch `saves/` or `assets/`. Several raise real Windows toasts, because
that is the thing being tested. Each prints what it found and what the behaviour
was before the fix, so running one tells you whether the hole is still shut.

Two of them (`probe_d_injection`, `probe_e_shell_open`) prove code execution by
writing a harmless marker file. Nothing in here is weaponised, and nothing in
here targets anything but this app.

| Probe | For |
|---|---|
| `probe_a_dict_append` | Whether a `PackedStringArray` in a `Dictionary` really mutates — the zip-slip refusal depends on it |
| `probe_b_time`, `probe_b2_time` | Out-of-range timestamps through `Time` |
| `probe_c_numbers` | Infinities and NaN through the needs, life and settings maths (RT-04, RT-09, RT-10) |
| `probe_d_injection` | RT-01, pet name as PowerShell |
| `probe_e_shell_open` | RT-02, a pack's licence link |
| `probe_f_save` | RT-06, the save/backup ordering |
| `probe_g_zipbomb` | RT-03, a 597 KB zip that asked for 3 GB |
| `probe_h_tiles` | RT-05, draw calls per frame for tiny tiles |
| `probe_i_misc` | RT-09 and RT-13, hostile `history.json` and device names |
| `probe_j_toast_live` | RT-01 regression: notifications still work |
| `probe_k_encoding` | RT-01 regression: accented and Japanese names survive |
| `probe_l_zipapi` | What `ZIPReader` actually offers in Godot 4.7.2 |
| `probe_m_real_pack` | RT-03 regression: the shipped packs still round-trip |
| `probe_n_rename` | Whether `rename_absolute` overwrites on Windows — RT-06 turns on the answer |
| `probe_o_vbs` | RT-12, where the wscript helper lives |

## Worth knowing

Six things the probes caught that reading the code did not, recorded in full in
`99-master-report.md` §7:

1. **RT-07's whole approach was wrong.** The cap I designed did not fix the
   finding, and the integration test said so in one run.
2. **An engine claim in `CLAUDE.md` is wrong:** `ZIPReader.get_file_info()` does
   not exist in Godot 4.7.2.
3. **A code comment justified a bug.** `SaveFile` said Windows cannot rename
   onto an existing file. It can — and that comment was the stated reason for
   the destructive ordering that lost saves.
4. **Two defects introduced by the fixes themselves**, caught by running the
   probes rather than by reading the diff.
5. **A gap in a new limit**, found by a test expectation written for the wrong
   reason.
6. **A measurement of mine that was off by six orders of magnitude**, because a
   process-wide peak-memory figure included the probe's own allocation.
