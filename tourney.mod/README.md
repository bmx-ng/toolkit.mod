# Toolkit.Tourney

`Toolkit.Tourney` builds and plays tournaments from serializable definitions. It generates fixtures, accepts results, calculates standings, advances entrants, and keeps display code outside the engine.

**Start with the [module introduction](doc/intro.bbdoc).** It has a complete first example, a guide to stage formats and scheduling, result and persistence workflows, and an index of historical replays. The [technical notes](doc/technical-notes.md) retain detailed rule behaviour and current boundaries.

## At a glance

| Need | Entry point |
| --- | --- |
| Assemble and check a competition | `TCompetitionBuilder`, `TTourneyAuthoring`, `BuildChecked()` |
| Start play and record results | `TCompetitionEngine.Initialize`, `RecordResult` |
| Generate or revise a calendar | `PlanSchedule`, `PlanCalendar`, `ReviseFixtureSchedule` |
| Inspect standings and decisions | `TStageState.leaderboard`, `UnresolvedTableTies`, `RecordTableTieDecision` |
| Correct a result | `CorrectResult` and its returned state and invalidated actions |
| Present progress | `ICompetitionResultObserver`, `TCompetitionTimeline` |
| Add a sport-specific format | `TStage.formatCode`, `RegisterFormat` |

The [groups-to-final example](examples/builder_example.bmx) is a short runnable starting point. The [examples guide](examples/README.md) distinguishes standalone programs, historical replays, and viewers, and points to the rules each demonstrates.

## Build and test

From `tests/`, build and run the suite with:

```sh
../../../../bin/bmk makeapp -r test.bmx
./test
```

The tests cover the engine and historical replays. Run them after changing a format handler, routing, serialization, or scheduling. To develop a new format, keep its definition serializable and add a small repeatable test alongside any historical acceptance example.

## Source layout

`model.bmx` defines the saved model; `tourney.bmx` owns the engine and registration. `builder.bmx` and `authoring.bmx` help create definitions. Format handlers live in files such as `groups.bmx`, `league.bmx`, `brackets.bmx`, `series.bmx`, `swiss.bmx`, `heats.bmx`, `strokeplay.bmx`, `regatta.bmx`, and `cycling.bmx`. `calendarplanner.bmx` handles joint fixture placement; `correction.bmx`, `timeline.bmx`, `clinching.bmx`, and the qualification files support replay and analysis.

The engine is a configurable framework, not a complete rulebook for every sport. See [current boundaries](doc/technical-notes.md#current-boundaries) before relying on an exact federation rule or a very large generated schedule.
