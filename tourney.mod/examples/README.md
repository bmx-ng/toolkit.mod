# Tournament examples

Start with [the module introduction](../doc/intro.bbdoc) for the model and API. The small programs below are the best entry points before reading a full historical replay.

| Start here | What it demonstrates |
| --- | --- |
| [Builder example](builder_example.bmx) | Create a four-team groups-to-final competition, record results, and read the winner. |
| [Shared-stadium planner](shared_stadium_planner.bmx) | Assign two clubs' home games without booking their shared venue twice. |

From this directory, build a standalone example with `../../../../bin/bmk makeapp -r builder_example.bmx`, then run `./builder_example`. Substitute `shared_stadium_planner.bmx` and `./shared_stadium_planner` for the scheduling example.

## Historical replays

These files are larger acceptance examples. The replay sources define types used by [the test suite](../tests/test.bmx); they are not all standalone programs. Each checks its outcome against saved results. Read the one closest to the rules you want to configure.

| Replay | Rules and data flow to study |
| --- | --- |
| [Wimbledon 2025](wimbledon_2025_replay.bmx) | Seeded knockout and match results. |
| [World Cup 2026](world_cup_2026_replay.bmx) | Groups, best third-place teams, and conditional bracket placement. |
| [F1 2021](f1_2021_replay.bmx) | Several scoring sessions, driver and constructor championships, fastest laps, and half points. |
| [NFL 2024](nfl_2024_replay.bmx) | Divisions, conference qualifiers, playoff seeds, and a published calendar. |
| [MLB 2024](mlb_2024_replay.bmx) | Full regular season, wild cards, best-of playoff series, and state restoration. |
| [Cricket World Cup 2011](cricket_2011_replay.bmx) | Innings, match points, net run rate, and knockout qualification. |
| [Masters 2024](masters_2024_replay.bmx) | Stroke totals and a cut after two rounds. |
| [Paris 2024 men's 800 m](paris_2024_mens_800m_replay.bmx) | Timed heats, repechage, semifinals, and lanes. |
| [Paris 2024 men's dinghy](paris_2024_mens_dinghy_replay.bmx) | Sailing race scores, penalties, discards, and a medal race. |
| [Tour de France 2024](tour_2024_replay.bmx) | Stage results and changing individual and team classifications. |

Run the suite from `../tests` to execute these replays. The [technical notes](../doc/technical-notes.md) explain each replay's source data, checks, and rule boundaries.

## Viewers and snapshot exporters

The [Tour](tour_2024_viewer.bmx), [F1](f1_2021_viewer.bmx), [World Cup](world_cup_2026_viewer.bmx), and [MLB](mlb_2024_viewer.bmx) viewers read saved snapshots. Their matching `*_export_app.bmx` programs generate those files through the engine; `*_snapshot_export.bmx` contains reusable exporter code. This keeps rendering separate from tournament scoring. Each viewer accepts `--check` to validate its snapshots without opening a window.

For example, from this directory:

```sh
../../../../bin/bmk makeapp -r mlb_2024_export_app.bmx
./mlb_2024_export_app
../../../../bin/bmk makeapp -r mlb_2024_viewer.bmx
./mlb_2024_viewer
```
