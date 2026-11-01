SuperStrict

Framework brl.standardio
Import BRL.MaxUnit
Import toolkit.tourney
import brl.stringbuilder
Include "../examples/wimbledon_2025_replay.bmx"
Include "../examples/f1_2021_replay.bmx"
Include "../examples/world_cup_2026_replay.bmx"
Include "../examples/nfl_2024_replay.bmx"
Include "../examples/mlb_2024_replay.bmx"
Include "../examples/mlb_2024_snapshot_export.bmx"
Include "../examples/cricket_2011_replay.bmx"
Include "../examples/masters_2024_replay.bmx"
Include "../examples/paris_2024_mens_800m_replay.bmx"
Include "../examples/paris_2024_mens_dinghy_replay.bmx"
Include "../examples/tour_2024_replay.bmx"
Include "../examples/tour_2024_snapshot_export.bmx"

If AppArgs.Length > 1 And AppArgs[1] = "--export-tour" Then
	Local finishers:Int = TTourSnapshotExport.Export(AppDir + "/../examples/tour_2024_official.tsv", AppDir + "/../examples/tour_2024_snapshots.tsv")
	Print "Exported 21 Tour stages and " + finishers + " final GC riders"
	End
End If

Type TTour2024ReplayTest Extends TTest
	Method testAllStagesAndFiveFinalClassifications() { test }
		AssertEquals(141, TTour2024Replay.Run(AppDir + "/../examples/tour_2024_official.tsv"))
	End Method
End Type

Type TCompetitionBuilderTest Extends TTest
	Method MakeBuilder:TCompetitionBuilder()
		Local builder:TCompetitionBuilder = New TCompetitionBuilder("Builder cup")
		For Local id:Int = 1 To 4
			Local p:TParticipant = New TParticipant
			p.id = id
			p.name = "Team " + id
			p.kind = EParticipantKind.Team
			builder.AddParticipant(p)
		Next

		Return builder
	End Method

	Method testAuthoringHelpersComposeCheckedGroupCup() { test }
		Local builder:TCompetitionBuilder = MakeBuilder()
		builder.AddGroups("GROUPS", 2, 2)
		Local finalStage:TStage = builder.AddBracket("FINAL", 2, 3)
		builder.ConnectTop("GROUPS", "FINAL", 1, EFilterScope.PerGroup)
		AssertEquals(3, TBracketConfig(finalStage.config).matchFormat.bestOfMatches)
		AssertEquals(0, builder.Check().Length)
		Local comp:TCompetition = builder.BuildChecked()
		AssertEquals(EFilterKind.TopN.Ordinal(), comp.stages[0].advancement[0].rule.kind.Ordinal())
		AssertEquals(EFilterScope.PerGroup.Ordinal(), comp.stages[0].advancement[0].rule.scope.Ordinal())
		AssertEquals("GROUPS", comp.stages[1].input.fromStageIds[0])
	End Method

	Method testAuthoringSeriesAndSelectionRules() { test }
		Local scoring:TScoringSystem = TTourneyAuthoring.PositionScoring(["1.25", "0.5"], 4)
		scoring.bonuses = [TTourneyAuthoring.Bonus("FASTEST", "0.25", "0.5", 4)]
		Local event:TSeriesEvent = TTourneyAuthoring.Event("E1", ["SPRINT", "RACE"], "0.5")
		Local builder:TCompetitionBuilder = MakeBuilder()
		builder.AddSeries("SEASON", [event], scoring, 4)
		AssertEquals(0, builder.Check().Length)
		Local comp:TCompetition = builder.BuildChecked()
		Local config:TSeriesConfig = TSeriesConfig(comp.stages[0].config)
		AssertEquals(2, config.events[0].sessions.Length)
		AssertEquals(5, ConfigPointUnits(config.scoring.table[0].points, config.scoring.table[0].pointsExact, config.pointsScale))
		Local rule:TFilterRule = TTourneyAuthoring.BestAtRankAcrossGroups(3, 2)
		AssertEquals(EFilterKind.BestXAcrossGroups.Ordinal(), rule.kind.Ordinal())
		AssertEquals(3, rule.startRank)
		AssertEquals(2, rule.n)
	End Method

	Method testAuthoringPreflightReportsUnrepresentablePoint() { test }
		Local builder:TCompetitionBuilder = MakeBuilder()
		Local config:TSeriesConfig = New TSeriesConfig
		config.pointsScale = 2
		config.scoring = New TScoringSystem
		config.scoring.mode = EScoringMode.PositionTable
		Local entry:TPointsTableEntry = New TPointsTableEntry
		entry.position = 1
		entry.pointsExact = "0.1"
		config.scoring.table = [entry]
		config.events = [TTourneyAuthoring.Event("E1", ["RACE"])]
		builder.AddStage("SEASON", EStageType.Series, config)
		Local issues:TAuthoringIssue[] = builder.Check()
		AssertEquals(1, issues.Length)
		AssertEquals("SEASON", issues[0].stageId)
		AssertEquals("config.points", issues[0].fieldPath)
		Local rejected:Int
		Try
			builder.BuildChecked()
		Catch problem:Object
			rejected = True
		End Try

		AssertTrue(rejected)
		config.pointsScale = 10
		AssertEquals(0, builder.Check().Length)
	End Method

	Method testAuthoringPreflightCatchesBracketAndSwissRules() { test }
		Local builder:TCompetitionBuilder = MakeBuilder()
		Local bracket:TBracketConfig = New TBracketConfig
		bracket.size = 3
		builder.AddStage("BAD_BRACKET", EStageType.Bracket, bracket)
		Local swiss:TSwissConfig = New TSwissConfig
		builder.AddStage("BAD_SWISS", EStageType.Swiss, swiss)
		Local issues:TAuthoringIssue[] = builder.Check()
		AssertEquals(2, issues.Length)
		AssertEquals("BAD_BRACKET", issues[0].stageId)
		AssertEquals("config.size", issues[0].fieldPath)
		AssertEquals("BAD_SWISS", issues[1].stageId)
		AssertEquals("config", issues[1].fieldPath)
	End Method

	Method testCorrectionReplaysGroupsAndInvalidatesPlayedFinal() { test }
		Local builder:TCompetitionBuilder = MakeBuilder()
		Local groups:TGroupConfig = TTourneyAuthoring.Groups(2, 2)
		Local a:TPresetGroup = New TPresetGroup
		a.code = "A"
		a.participantIds = [1, 2]
		Local b:TPresetGroup = New TPresetGroup
		b.code = "B"
		b.participantIds = [3, 4]
		groups.presetGroups = [a, b]
		builder.AddStage("GROUPS", EStageType.Group, groups)
		builder.AddBracket("FINAL", 2)
		builder.ConnectTop("GROUPS", "FINAL", 1, EFilterScope.PerGroup)
		Local comp:TCompetition = builder.BuildChecked()
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Group, New TGroupScheduler)
		engine.RegisterScorer(EStageType.Group, New TGroupScorer)
		engine.RegisterAdvancer(EStageType.Group, New TGroupAdvancer)
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		Local timeline:TCompetitionTimeline = New TCompetitionTimeline
		engine.AddResultObserver(timeline)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local groupA:TFixtureState = state.stages[0].fixtures[0]
		Local groupB:TFixtureState = state.stages[0].fixtures[1]
		Local scoreA:TResultPayload = New TResultPayload
		scoreA.kind = EResultKind.HeadToHeadScore
		If groupA.homeTeamId = 1 Then scoreA.scoreHome = 1 Else scoreA.scoreAway = 1

		engine.RecordResult(comp, state, "GROUPS", groupA.id, scoreA)
		Local scoreB:TResultPayload = New TResultPayload
		scoreB.kind = EResultKind.HeadToHeadScore
		If groupB.homeTeamId = 3 Then scoreB.scoreHome = 1 Else scoreB.scoreAway = 1

		engine.RecordResult(comp, state, "GROUPS", groupB.id, scoreB)
		Local finalFixture:TFixtureState = state.stages[1].fixtures[0]
		AssertTrue(finalFixture.homeTeamId = 1 Or finalFixture.awayTeamId = 1)
		Local finalScore:TResultPayload = New TResultPayload
		finalScore.kind = EResultKind.HeadToHeadScore
		finalScore.scoreHome = 1
		engine.RecordResult(comp, state, "FINAL", finalFixture.id, finalScore)
		AssertEquals(3, state.actions.Length)
		AssertEquals(3, timeline.frames.Length)

		Local invalid:TResultPayload = New TResultPayload
		invalid.kind = EResultKind.HeadToHeadScore
		invalid.scoreHome = -1
		Local rejected:Int
		Try
			engine.CorrectResult(comp, state, "GROUPS", groupA.id, invalid)
		Catch problem:Object
			rejected = True
		End Try

		AssertTrue(rejected)
		AssertEquals(3, state.actions.Length)
		AssertEquals(3, timeline.frames.Length)

		Local correction:TResultPayload = New TResultPayload
		correction.kind = EResultKind.HeadToHeadScore
		If groupA.homeTeamId = 2 Then correction.scoreHome = 1 Else correction.scoreAway = 1

		Local randomBefore:Int = RndSeed()
		Local revised:TResultCorrection = engine.CorrectResult(comp, state, "GROUPS", groupA.id, correction)
		AssertEquals(randomBefore, RndSeed())
		AssertEquals(1, revised.invalidated.Length)
		AssertEquals("FINAL", revised.invalidated[0].action.stageId)
		AssertEquals(2, revised.state.actions.Length)
		AssertEquals(2, timeline.frames.Length)
		AssertEquals(EStageStatus.Running.Ordinal(), revised.state.stages[1].status.Ordinal())
		Local revisedFinal:TFixtureState = revised.state.stages[1].fixtures[0]
		AssertTrue(revisedFinal.homeTeamId = 2 Or revisedFinal.awayTeamId = 2)
		AssertTrue(revisedFinal.homeTeamId = 3 Or revisedFinal.awayTeamId = 3)
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[1].status.Ordinal())
		AssertEquals(3, state.actions.Length)

		Local json:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local restored:TCompetitionState = TCompetitionState(json.FromJson(json.ToJson(revised.state), "TCompetitionState"))
		AssertEquals(2, restored.actions.Length)
		AssertTrue(restored.replayBaseJson <> "")
	End Method

	Method testCorrectionReplaysLaterSeriesResultsAfterStateRoundTrip() { test }
		Local builder:TCompetitionBuilder = New TCompetitionBuilder("Series correction")
		For Local id:Int = 1 To 2
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.kind = EParticipantKind.Individual
			builder.AddParticipant(participant)
		Next

		Local scoring:TScoringSystem = TTourneyAuthoring.PositionScoring(["10", "5"])
		builder.AddSeries("SERIES", [TTourneyAuthoring.Event("E1", ["RACE"]), TTourneyAuthoring.Event("E2", ["RACE"])], scoring)
		Local comp:TCompetition = builder.BuildChecked()
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Series, New TSeriesScheduler)
		engine.RegisterScorer(EStageType.Series, New TSeriesScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local first:TResultPayload = New TResultPayload
		first.kind = EResultKind.Classification
		first.order = [1, 2]
		engine.RecordResult(comp, state, "SERIES", state.stages[0].fixtures[0].id, first)
		first.order[0] = 2 ' caller mutation must not change the replay journal
		Local second:TResultPayload = New TResultPayload
		second.kind = EResultKind.Classification
		second.order = [1, 2]
		engine.RecordResult(comp, state, "SERIES", state.stages[0].fixtures[1].id, second)
		Local json:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local restored:TCompetitionState = TCompetitionState(json.FromJson(json.ToJson(state), "TCompetitionState"))
		Local correction:TResultPayload = New TResultPayload
		correction.kind = EResultKind.Classification
		correction.order = [2, 1]
		Local revised:TResultCorrection = engine.CorrectResult(comp, restored, "SERIES", state.stages[0].fixtures[0].id, correction)
		AssertEquals(0, revised.invalidated.Length)
		AssertEquals(2, revised.state.actions.Length)
		AssertEquals(2, revised.state.stages[0].fixtures[0].classificationOrder[0])
		AssertEquals(1, revised.state.stages[0].fixtures[1].classificationOrder[0])
		For Local row:TLeaderboardRow = EachIn revised.state.stages[0].leaderboard.rows
			AssertEquals(15, row.points)
		Next
	End Method

	Method testGroupWinnersFeedFinal() { test }
		Local builder:TCompetitionBuilder = MakeBuilder()
		Local groups:TGroupConfig = New TGroupConfig
		groups.groups = 2
		groups.groupSize = 2
		groups.roundRobinPerOpponent = 1
		builder.AddStage("GROUPS", EStageType.Group, groups)
		Local finalConfig:TBracketConfig = New TBracketConfig
		finalConfig.size = 2
		builder.AddStage("FINAL", EStageType.Bracket, finalConfig)
		Local top:TFilterRule = New TFilterRule
		top.kind = EFilterKind.TopN
		top.n = 1
		top.scope = EFilterScope.PerGroup
		builder.Connect("GROUPS", "FINAL", top)
		Local comp:TCompetition = builder.Build()
		AssertEquals("GROUPS", comp.stages[1].input.fromStageIds[0])
		AssertEquals(False, comp.stages[1].independent)
		AssertEquals("FINAL", comp.stages[0].advancement[0].toStageId)
		Local path:String = AppDir + "/builder_competition.json"
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local output:TStream = WriteStream(path)
		jconv.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		comp = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Group, New TGroupScheduler)
		engine.RegisterScorer(EStageType.Group, New TGroupScorer)
		engine.RegisterAdvancer(EStageType.Group, New TGroupAdvancer)
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(2, state.stages[0].fixtures.Length)
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
			engine.RecordResultAndAdvance(comp, state, "GROUPS", fixture.id, 1, 0)
		Next

		AssertEquals(EStageStatus.Running.Ordinal(), state.stages[1].status.Ordinal())
		AssertEquals(1, state.stages[1].fixtures.Length)
	End Method

	Method testIndependentRootsAndMergedDependency() { test }
		Local builder:TCompetitionBuilder = MakeBuilder()
		builder.AddStage("A", EStageType.Bracket, New TBracketConfig)
		builder.AddStage("B", EStageType.Bracket, New TBracketConfig)
		builder.AddStage("JOIN", EStageType.Bracket, New TBracketConfig)
		builder.Connect("A", "JOIN", Null, EAdvancementOutcome.Winner)
		builder.Connect("B", "JOIN", Null, EAdvancementOutcome.Winner)
		Local comp:TCompetition = builder.Build()
		AssertEquals(True, comp.stages[0].independent)
		AssertEquals(True, comp.stages[1].independent)
		AssertEquals(2, comp.stages[2].input.fromStageIds.Length)
		AssertEquals("A", comp.stages[2].input.fromStageIds[0])
		AssertEquals("B", comp.stages[2].input.fromStageIds[1])
	End Method

	Method testPresetGroupsAndCombinedRouteSerialize() { test }
		Local builder:TCompetitionBuilder = MakeBuilder()
		Local first:TPresetGroup = New TPresetGroup
		first.code = "A"
		first.participantIds = [1, 2]
		Local second:TPresetGroup = New TPresetGroup
		second.code = "B"
		second.participantIds = [3, 4]
		Local config:TGroupConfig = New TGroupConfig
		config.groups = 2
		config.groupSize = 2
		config.roundRobinPerOpponent = 1
		config.presetGroups = [first, second]
		builder.AddStage("GROUPS", EStageType.Group, config)
		Local finalConfig:TBracketConfig = New TBracketConfig
		finalConfig.size = 2
		builder.AddStage("FINAL", EStageType.Bracket, finalConfig)
		Local winners:TFilterRule = New TFilterRule
		winners.kind = EFilterKind.TopN
		winners.n = 1
		winners.scope = EFilterScope.PerGroup
		Local extras:TFilterRule = New TFilterRule
		extras.kind = EFilterKind.BestXAcrossGroups
		extras.n = 0
		extras.startRank = 2
		builder.ConnectRules("GROUPS", "FINAL", [winners, extras])
		Local comp:TCompetition = builder.Build()
		Local path:String = AppDir + "/builder_preset_groups.json"
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local output:TStream = WriteStream(path)
		jconv.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		comp = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		AssertEquals("B", TGroupConfig(comp.stages[0].config).presetGroups[1].code)
		AssertEquals(4, TGroupConfig(comp.stages[0].config).presetGroups[1].participantIds[1])
		AssertEquals(2, comp.stages[0].advancement[0].rules.Length)
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Group, New TGroupScheduler)
		engine.RegisterScorer(EStageType.Group, New TGroupScorer)
		engine.RegisterAdvancer(EStageType.Group, New TGroupAdvancer)
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals("A", state.stages[0].fixtures[0].groupKey)
		AssertEquals("B", state.stages[0].fixtures[1].groupKey)
	End Method

	Method testRejectsDuplicateConnectionsAndCycles() { test }
		Local builder:TCompetitionBuilder = MakeBuilder()
		builder.AddStage("A", EStageType.Bracket, New TBracketConfig)
		builder.AddStage("B", EStageType.Bracket, New TBracketConfig)
		builder.Connect("A", "B", Null, EAdvancementOutcome.Winner)
		Local duplicateRejected:Int
		Try
			builder.Connect("A", "B", Null, EAdvancementOutcome.Winner)
		Catch error:Object
			duplicateRejected = True
		End Try

		AssertTrue(duplicateRejected)
		builder.Connect("B", "A", Null, EAdvancementOutcome.Winner)
		Local cycleRejected:Int
		Try
			builder.Build()
		Catch error:Object
			cycleRejected = True
		End Try

		AssertTrue(cycleRejected)
	End Method
End Type

Type TResultObserverProbe Implements ICompetitionResultObserver
	Field calls:Int
	Field stageId:String
	Field fixtureId:String
	Field leaderId:Int
	Field leaderPoints:Int
	Field stageStatus:Int

	Method OnResultRecorded(comp:TCompetition, state:TCompetitionState, updatedStageId:String, updatedFixtureId:String, result:TResultPayload)
		calls :+ 1
		stageId = updatedStageId
		fixtureId = updatedFixtureId
		leaderId = state.stages[0].leaderboard.rows[0].participantId
		leaderPoints = state.stages[0].leaderboard.rows[0].points
		stageStatus = state.stages[0].status.Ordinal()
	End Method
End Type

Type TResultObserverTest Extends TTest
	Method testObserverSeesCompletedUpdate() { test }
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 2
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.kind = EParticipantKind.Individual
			comp.participants :+ [participant]
		Next

		Local stage:TStage = New TStage
		stage.id = "SEASON"
		stage.stageType = EStageType.Series
		Local cfg:TSeriesConfig = New TSeriesConfig
		cfg.scoring = New TScoringSystem
		cfg.scoring.mode = EScoringMode.PositionTable
		Local points:TPointsTableEntry = New TPointsTableEntry
		points.position = 1
		points.points = 10
		cfg.scoring.table = [points]
		For Local number:Int = 1 To 2
			Local event:TSeriesEvent = New TSeriesEvent
			event.id = "R" + number
			cfg.events :+ [event]
		Next

		stage.config = cfg
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Series, New TSeriesScheduler)
		engine.RegisterScorer(EStageType.Series, New TSeriesScorer)
		Local probe:TResultObserverProbe = New TResultObserverProbe
		engine.AddResultObserver(probe)
		Local timeline:TCompetitionTimeline = New TCompetitionTimeline
		engine.AddResultObserver(timeline)
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(0, probe.calls)
		Local firstFixture:String = state.stages[0].fixtures[0].id
		engine.RecordSeriesClassificationAndAdvance(comp, state, stage.id, firstFixture, [1, 2])
		AssertEquals(1, probe.calls)
		AssertEquals("SEASON", probe.stageId)
		AssertEquals(firstFixture, probe.fixtureId)
		AssertEquals(1, probe.leaderId)
		AssertEquals(10, probe.leaderPoints)
		AssertEquals(EStageStatus.Running.Ordinal(), probe.stageStatus)
		AssertEquals(1, timeline.frames.Length)
		AssertEquals("R1", timeline.frames[0].eventId)
		AssertEquals(10, timeline.frames[0].Board().rows[0].points)
		Try
			engine.RecordSeriesClassificationAndAdvance(comp, state, stage.id, firstFixture, [1, 2])
		Catch error:Object
		End Try

		AssertEquals(1, probe.calls)
		engine.RecordSeriesClassificationAndAdvance(comp, state, stage.id, state.stages[0].fixtures[1].id, [1, 2])
		AssertEquals(2, probe.calls)
		AssertEquals(20, probe.leaderPoints)
		AssertEquals(EStageStatus.Complete.Ordinal(), probe.stageStatus)
		AssertEquals(2, timeline.frames.Length)
		AssertEquals(10, timeline.frames[0].Board().rows[0].points)
		AssertEquals(20, timeline.frames[1].Board().rows[0].points)
		state.stages[0].leaderboard.rows[0].points = 99
		AssertEquals(20, timeline.frames[1].Board().rows[0].points)
	End Method
End Type

Type TCyclingStageRaceTest Extends TTest
	Function Rider:TCyclingRiderResult(id:Int, place:Int, seconds:Long, expectedBonus:Int, recorded:Int = True)
		Local result:TCyclingRiderResult = New TCyclingRiderResult
		result.participantId = id
		result.place = place
		result.elapsedSeconds = seconds
		result.bonusSeconds = expectedBonus
		result.bonusRecorded = recorded
		Return result
	End Function

	Method testRecordedBonusWithPointsOnlyCheckpoint() { test }
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 2
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.kind = EParticipantKind.Individual
			comp.participants :+ [participant]
		Next

		Local stage:TStage = New TStage
		stage.id = "BONUS"
		stage.stageType = EStageType.Series
		stage.formatCode = "cycling-stage-race"
		Local cfg:TCyclingConfig = New TCyclingConfig
		cfg.sprintPoints = [2, 1]
		Local rule:TCyclingStageRule = New TCyclingStageRule
		rule.id = "S1"
		Local checkpoint:TCyclingCheckpointRule = New TCyclingCheckpointRule
		checkpoint.code = "SPRINT"
		checkpoint.classification = "POINTS"
		rule.checkpoints = [checkpoint]
		cfg.stages = [rule]
		stage.config = cfg
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterFormat("cycling-stage-race", New TCyclingScheduler, New TCyclingScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.Custom
		result.customCode = "cycling-stage"
		result.cyclingResults = [Rider(1, 1, 100, 7), Rider(2, 2, 110, 0)]
		Local crossing:TCyclingCheckpointResult = New TCyclingCheckpointResult
		crossing.code = "SPRINT"
		crossing.order = [2, 1]
		result.cyclingCheckpoints = [crossing]
		engine.RecordResult(comp, state, stage.id, state.stages[0].fixtures[0].id, result)
		AssertEquals(93, Int(state.stages[0].leaderboard.rows[0].timeSeconds))
		AssertEquals(7, state.stages[0].cyclingStandings[0].bonusSeconds)
	End Method

	Method testCheckpointBonusesTeamsWithdrawalAndResume() { test }
		Local comp:TCompetition = New TCompetition
		For Local teamId:Int = 101 To 102
			Local team:TParticipant = New TParticipant
			team.id = teamId
			team.kind = EParticipantKind.Team
			comp.participants :+ [team]
		Next

		For Local id:Int = 1 To 4
			Local rider:TParticipant = New TParticipant
			rider.id = id
			rider.kind = EParticipantKind.Individual
			rider.parentTeamId = 101 + (id - 1) / 2
			comp.participants :+ [rider]
		Next

		Local stage:TStage = New TStage
		stage.id = "MINI_TOUR"
		stage.stageType = EStageType.Series
		stage.formatCode = "cycling-stage-race"
		Local cfg:TCyclingConfig = New TCyclingConfig
		cfg.ridersPerTeam = 2
		cfg.youngRiderIds = [3]
		cfg.sprintPoints = [5, 3]
		Local climb:TCyclingClimbRule = New TCyclingClimbRule
		climb.category = "HILL"
		climb.points = [2, 1]
		cfg.climbPoints = [climb]
		For Local i:Int = 1 To 2
			Local rule:TCyclingStageRule = New TCyclingStageRule
			rule.id = "S" + i
			rule.finishPoints = [10, 5, 3, 1]
			rule.finishBonusSeconds = [10, 6, 4]
			If i = 1 Then
				Local sprint:TCyclingCheckpointRule = New TCyclingCheckpointRule
				sprint.code = "SPRINT"; sprint.classification = "POINTS"
				Local hill:TCyclingCheckpointRule = New TCyclingCheckpointRule
				hill.code = "HILL"; hill.classification = "CLIMBER"; hill.category = "HILL"
				Local bonus:TCyclingCheckpointRule = New TCyclingCheckpointRule
				bonus.code = "BONUS"; bonus.classification = "BONUS"; bonus.bonusSeconds = [2]
				rule.checkpoints = [sprint, hill, bonus]
			End If

			cfg.stages :+ [rule]
		Next

		stage.config = cfg
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterFormat("cycling-stage-race", New TCyclingScheduler, New TCyclingScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local first:TResultPayload = New TResultPayload
		first.kind = EResultKind.Custom
		first.customCode = "cycling-stage"
		first.cyclingResults = [Rider(1, 1, 100, 12), Rider(2, 4, 130, 0), Rider(3, 2, 110, 6), Rider(4, 3, 120, 4)]
		Local sprintResult:TCyclingCheckpointResult = New TCyclingCheckpointResult
		sprintResult.code = "SPRINT"; sprintResult.order = [3, 1]
		Local hillResult:TCyclingCheckpointResult = New TCyclingCheckpointResult
		hillResult.code = "HILL"; hillResult.order = [1, 3]
		Local bonusResult:TCyclingCheckpointResult = New TCyclingCheckpointResult
		bonusResult.code = "BONUS"; bonusResult.order = [1]
		first.cyclingCheckpoints = [sprintResult, hillResult, bonusResult]
		engine.RecordResult(comp, state, stage.id, state.stages[0].fixtures[0].id, first)
		AssertEquals(230, Int(state.stages[0].cyclingTeamStandings[0].totalSeconds))
		AssertEquals(101, state.stages[0].cyclingTeamStandings[0].teamId)
		AssertEquals(1, state.stages[0].cyclingTeamStandings[0].stageWins)
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local output:TStream = WriteStream("rt_cycling_comp.json")
		jconv.ToJson(comp, output); output.Close()
		output = WriteStream("rt_cycling_state.json")
		jconv.ToJson(state, output); output.Close()
		Local input:TStream = ReadStream("rt_cycling_comp.json")
		comp = TCompetition(jconv.FromJson(input, "TCompetition")); input.Close()
		input = ReadStream("rt_cycling_state.json")
		state = TCompetitionState(jconv.FromJson(input, "TCompetitionState")); input.Close()
		DeleteFile("rt_cycling_comp.json"); DeleteFile("rt_cycling_state.json")
		AssertEquals(3, TCyclingConfig(comp.stages[0].config).stages[0].checkpoints.Length)
		AssertEquals(12, state.stages[0].cyclingStandings[0].bonusSeconds)
		Local second:TResultPayload = New TResultPayload
		second.kind = EResultKind.Custom
		second.customCode = "cycling-stage"
		Local withdrawn:TCyclingRiderResult = New TCyclingRiderResult
		withdrawn.participantId = 2
		withdrawn.status = ECyclingRiderStatus.Withdrawn
		second.cyclingResults = [Rider(1, 1, 100, 10), withdrawn, Rider(3, 2, 105, 6), Rider(4, 3, 106, 4)]
		engine.RecordResult(comp, state, stage.id, state.stages[0].fixtures[1].id, second)
		AssertEquals(EStageStatus.Complete, state.stages[0].status)
		AssertEquals(178, Int(state.stages[0].leaderboard.rows[0].timeSeconds))
		AssertEquals(1, state.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(23 * cfg.pointsScale, state.stages[0].championships[0].leaderboard.rows[0].points)
		AssertEquals(3, state.stages[0].championships[2].leaderboard.rows[0].participantId)
		AssertEquals(102, state.stages[0].championships[3].leaderboard.rows[0].participantId)
		AssertEquals(441, Int(state.stages[0].championships[3].leaderboard.rows[0].timeSeconds))
	End Method
End Type

Type TTableTieDecisionTest Extends TTest
	Function Engine:TCompetitionEngine()
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Group, New TGroupScheduler)
		engine.RegisterScorer(EStageType.Group, New TGroupScorer)
		engine.RegisterAdvancer(EStageType.Group, New TGroupAdvancer)
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		Return engine
	End Function

	Method testRecordedDrawDecisionStartsFinalAndInvalidatesOnCorrection() { test }
		Local builder:TCompetitionBuilder = New TCompetitionBuilder("Tie decision")
		For Local id:Int = 1 To 4
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.kind = EParticipantKind.Team
			builder.AddParticipant(participant)
		Next

		Local config:TGroupConfig = TTourneyAuthoring.Groups(2, 2)
		config.tiebreakers = [ETiebreaker.Points, ETiebreaker.GoalDifference, ETiebreaker.GoalsFor, ETiebreaker.RandomDraw]
		Local a:TPresetGroup = New TPresetGroup
		a.code = "A"; a.participantIds = [1, 2]
		Local b:TPresetGroup = New TPresetGroup
		b.code = "B"; b.participantIds = [3, 4]
		config.presetGroups = [a, b]
		builder.AddStage("GROUPS", EStageType.Group, config)
		builder.AddBracket("FINAL", 2)
		builder.ConnectTop("GROUPS", "FINAL", 1, EFilterScope.PerGroup)
		Local comp:TCompetition = builder.BuildChecked()
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local aFixture:TFixtureState
		Local bFixture:TFixtureState
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
			If fixture.groupKey = "A" Then aFixture = fixture Else bFixture = fixture
		Next

		Local draw:TResultPayload = New TResultPayload
		draw.kind = EResultKind.HeadToHeadScore
		draw.scoreHome = 1; draw.scoreAway = 1
		engine.RecordResult(comp, state, "GROUPS", aFixture.id, draw)
		Local win:TResultPayload = New TResultPayload
		win.kind = EResultKind.HeadToHeadScore
		If bFixture.homeTeamId = 3 Then win.scoreHome = 1 Else win.scoreAway = 1

		engine.RecordResult(comp, state, "GROUPS", bFixture.id, win)
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(EStageStatus.Pending.Ordinal(), state.stages[1].status.Ordinal())
		AssertEquals(1, state.stages[0].groups[0].rows[0].sportingRank)
		AssertEquals(1, state.stages[0].groups[0].rows[1].sportingRank)
		Local ties:TUnresolvedTableTie[] = engine.UnresolvedTableTies(comp, state, "GROUPS")
		Local groupTie:Int
		For Local tie:TUnresolvedTableTie = EachIn ties
			If tie.scopeKey = "A" Then
				groupTie :+ 1
				AssertEquals("GROUPS", tie.stageId)
				AssertEquals(2, tie.participantIds.Length)
				AssertEquals(1, tie.participantIds[0])
				AssertEquals(2, tie.participantIds[1])
			End If
		Next

		AssertEquals(1, groupTie)
		AssertEquals(2, state.actions.Length)
		Local rejected:Int
		Try
			engine.RecordTableTieDecision(comp, state, "GROUPS", "A", [2, 3], "Invalid draw")
		Catch problem:Object
			rejected = True
		End Try

		AssertTrue(rejected, "A decision must cover exactly the tied group members")
		AssertEquals(2, state.actions.Length)
		Local revised:TCompetitionState = engine.RecordTableTieDecision(comp, state, "GROUPS", "A", [2, 1], "Drawing of lots")
		AssertEquals(EStageStatus.Pending.Ordinal(), state.stages[1].status.Ordinal())
		AssertEquals(EStageStatus.Running.Ordinal(), revised.stages[1].status.Ordinal())
		AssertEquals(3, revised.actions.Length)
		Local finalFixture:TFixtureState = revised.stages[1].fixtures[0]
		AssertTrue(finalFixture.homeTeamId = 2 Or finalFixture.awayTeamId = 2)
		AssertTrue(finalFixture.homeTeamId = 3 Or finalFixture.awayTeamId = 3)
		Local json:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local restored:TCompetitionState = TCompetitionState(json.FromJson(json.ToJson(revised), "TCompetitionState"))
		Local correction:TResultPayload = New TResultPayload
		correction.kind = EResultKind.HeadToHeadScore
		If aFixture.homeTeamId = 1 Then correction.scoreHome = 1 Else correction.scoreAway = 1

		Local replay:TResultCorrection = engine.CorrectResult(comp, restored, "GROUPS", aFixture.id, correction)
		AssertEquals(1, replay.invalidated.Length)
		AssertEquals(ERecordedActionType.TableTieDecision.Ordinal(), replay.invalidated[0].action.actionType.Ordinal())
		AssertEquals(2, replay.state.actions.Length)
		finalFixture = replay.state.stages[1].fixtures[0]
		AssertTrue(finalFixture.homeTeamId = 1 Or finalFixture.awayTeamId = 1)
	End Method

	Method testFairPlayPenaltySeparatesEqualScores() { test }
		Local builder:TCompetitionBuilder = New TCompetitionBuilder("Fair play")
		For Local id:Int = 1 To 2
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.kind = EParticipantKind.Team
			builder.AddParticipant(participant)
		Next

		Local config:TGroupConfig = TTourneyAuthoring.Groups(1, 2)
		config.tiebreakers = [ETiebreaker.Points, ETiebreaker.FairPlay, ETiebreaker.RandomDraw]
		builder.AddStage("GROUP", EStageType.Group, config)
		Local comp:TCompetition = builder.BuildChecked()
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local fixture:TFixtureState = state.stages[0].fixtures[0]
		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.HeadToHeadScore
		result.scoreHome = 1; result.scoreAway = 1
		result.fairPlayHome = 3; result.fairPlayAway = 1
		engine.RecordResult(comp, state, "GROUP", fixture.id, result)
		AssertEquals(fixture.awayTeamId, state.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(1, state.stages[0].leaderboard.rows[0].sportingRank)
		AssertEquals(2, state.stages[0].leaderboard.rows[1].sportingRank)
	End Method

	Method testCrossGroupCutoffNeedsExactDecision() { test }
		Local builder:TCompetitionBuilder = New TCompetitionBuilder("Cross-group tie")
		For Local id:Int = 1 To 6
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.kind = EParticipantKind.Team
			builder.AddParticipant(participant)
		Next

		Local config:TGroupConfig = TTourneyAuthoring.Groups(3, 2)
		Local a:TPresetGroup = New TPresetGroup
		a.code = "A"; a.participantIds = [1, 2]
		Local b:TPresetGroup = New TPresetGroup
		b.code = "B"; b.participantIds = [3, 4]
		Local c:TPresetGroup = New TPresetGroup
		c.code = "C"; c.participantIds = [5, 6]
		config.presetGroups = [a, b, c]
		Local stage:TStage = builder.AddStage("GROUPS", EStageType.Group, config)
		Local route:TAdvancement = New TAdvancement
		route.toStageId = "UNUSED"
		route.rule = TTourneyAuthoring.BestAtRankAcrossGroups(1, 1)
		Local comp:TCompetition = builder.BuildChecked()
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
			Local result:TResultPayload = New TResultPayload
			result.kind = EResultKind.HeadToHeadScore
			result.scoreHome = 1
			engine.RecordResult(comp, state, "GROUPS", fixture.id, result)
		Next

		stage.advancement = [route] ' exercise selection without starting a destination stage
		Local advancer:TGroupAdvancer = New TGroupAdvancer
		AssertTrue(advancer.ProduceAdvancements(comp, stage, state.stages[0]) = Null)
		Local first:Int = state.stages[0].groups[0].rows[0].participantId
		Local second:Int = state.stages[0].groups[1].rows[0].participantId
		Local third:Int = state.stages[0].groups[2].rows[0].participantId
		Local ties:TUnresolvedTableTie[] = engine.UnresolvedTableTies(comp, state, "GROUPS")
		Local crossTie:Int
		For Local tie:TUnresolvedTableTie = EachIn ties
			If tie.scopeKey = "bestAcross" Then
				crossTie :+ 1
				AssertEquals(3, tie.participantIds.Length)
				AssertEquals(first, tie.participantIds[0])
				AssertEquals(second, tie.participantIds[1])
				AssertEquals(third, tie.participantIds[2])
			End If
		Next

		AssertEquals(1, crossTie)
		Local rejected:Int
		Try
			engine.RecordTableTieDecision(comp, state, "GROUPS", "bestAcross", [first, second], "Incomplete set")
		Catch problem:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Cross-group decision must match the blocking cutoff")
		AssertEquals(3, state.actions.Length)
		Local revised:TCompetitionState = engine.RecordTableTieDecision(comp, state, "GROUPS", "bestAcross", [second, first, third], "Drawing of lots")
		For Local tie:TUnresolvedTableTie = EachIn engine.UnresolvedTableTies(comp, revised, "GROUPS")
			AssertTrue(tie.scopeKey <> "bestAcross", "The cutoff decision has resolved the tie")
		Next

		Local selected:TParticipant[] = advancer.ProduceAdvancements(comp, stage, revised.stages[0])
		AssertEquals(1, selected.Length)
		AssertEquals(second, selected[0].id)
	End Method

	Method testLeagueSeasonMovementWaitsForTieDecision() { test }
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 2
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.kind = EParticipantKind.Team
			comp.participants :+ [participant]
		Next

		Local fixture:TFixture = New TFixture
		fixture.homeTeamId = 1; fixture.awayTeamId = 2; fixture.round = 1
		Local config:TLeagueConfig = New TLeagueConfig
		config.schedule = New TLeagueScheduleConfig
		config.schedule.fixedFixtures = [fixture]
		config.tiebreakers = [ETiebreaker.Points, ETiebreaker.GoalDifference, ETiebreaker.GoalsFor, ETiebreaker.RandomDraw]
		Local stage:TStage = New TStage
		stage.id = "LEAGUE"; stage.stageType = EStageType.League; stage.independent = True; stage.config = config
		comp.stages = [stage]
		Local movement:TSeasonTransitionRule = New TSeasonTransitionRule
		movement.fromStageId = "LEAGUE"; movement.destinationDivisionId = "UP"
		movement.selection = New TFilterRule
		movement.selection.kind = EFilterKind.TopN
		movement.selection.n = 1
		comp.seasonTransitions = [movement]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		engine.RegisterScorer(EStageType.League, New TLeagueScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local draw:TResultPayload = New TResultPayload
		draw.kind = EResultKind.HeadToHeadScore
		draw.scoreHome = 1; draw.scoreAway = 1
		engine.RecordResult(comp, state, "LEAGUE", state.stages[0].fixtures[0].id, draw)
		Local rejected:Int
		Try
			engine.ResolveSeasonMovements(comp, state)
		Catch problem:Object
			rejected = True
		End Try

		AssertTrue(rejected, "A tied league place cannot determine promotion")
		Local revised:TCompetitionState = engine.RecordTableTieDecision(comp, state, "LEAGUE", "", [2, 1], "Drawing of lots")
		Local moves:TSeasonMovement[] = engine.ResolveSeasonMovements(comp, revised)
		AssertEquals(1, moves.Length)
		AssertEquals(2, moves[0].participantId)
	End Method
End Type

Type TSeriesTableTieDecisionTest Extends TTest
	Function Builder:TCompetitionBuilder(name:String)
		Local builder:TCompetitionBuilder = New TCompetitionBuilder(name)
		For Local id:Int = 1 To 2
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.kind = EParticipantKind.Individual
			builder.AddParticipant(participant)
		Next

		Return builder
	End Function

	Function Engine:TCompetitionEngine()
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Series, New TSeriesScheduler)
		engine.RegisterScorer(EStageType.Series, New TSeriesScorer)
		engine.RegisterAdvancer(EStageType.Series, New TSeriesAdvancer)
		Return engine
	End Function

	Function Transition:TSeasonTransitionRule(code:String)
		Local transition:TSeasonTransitionRule = New TSeasonTransitionRule
		transition.fromStageId = "SERIES"
		transition.championshipCode = code
		transition.destinationDivisionId = "WINNERS"
		transition.selection = New TFilterRule
		transition.selection.kind = EFilterKind.TopN
		transition.selection.n = 1
		Return transition
	End Function

	Function Classification:TResultPayload(first:Int, second:Int)
		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.Classification
		result.order = [first, second]
		Return result
	End Function

	Method testMainSeriesTieDecisionReplaysAfterCorrection() { test }
		Local builder:TCompetitionBuilder = Builder("Series tie")
		Local config:TSeriesConfig = New TSeriesConfig
		config.events = [TTourneyAuthoring.Event("E1", ["RACE"]), TTourneyAuthoring.Event("E2", ["RACE"])]
		config.scoring = TTourneyAuthoring.PositionScoring(["10", "5"])
		config.tiebreakers = [ETiebreaker.Points, ETiebreaker.Wins]
		builder.AddStage("SERIES", EStageType.Series, config)
		Local comp:TCompetition = builder.BuildChecked()
		comp.seasonTransitions = [Transition("")]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local firstId:String = state.stages[0].fixtures[0].id
		engine.RecordResult(comp, state, "SERIES", firstId, Classification(1, 2))
		engine.RecordResult(comp, state, "SERIES", state.stages[0].fixtures[1].id, Classification(2, 1))
		AssertEquals(1, state.stages[0].leaderboard.rows[0].sportingRank)
		AssertEquals(1, state.stages[0].leaderboard.rows[1].sportingRank)
		AssertEquals(EQualificationStatus.Possible.Ordinal(), engine.AnalyzeQualification(comp, state, "SERIES", 2, 1).status.Ordinal())
		Local rejected:Int
		Try
			engine.ResolveSeasonMovements(comp, state)
		Catch problem:Object
			rejected = True
		End Try

		AssertTrue(rejected)
		Local decided:TCompetitionState = engine.RecordTableTieDecision(comp, state, "SERIES", "", [2, 1], "Championship tie decision")
		AssertEquals(2, decided.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(2, engine.ResolveSeasonMovements(comp, decided)[0].participantId)
		AssertEquals(EQualificationStatus.Guaranteed.Ordinal(), engine.AnalyzeQualification(comp, decided, "SERIES", 2, 1).status.Ordinal())
		Local json:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local restored:TCompetitionState = TCompetitionState(json.FromJson(json.ToJson(decided), "TCompetitionState"))
		Local correction:TResultCorrection = engine.CorrectResult(comp, restored, "SERIES", firstId, Classification(2, 1))
		AssertEquals(1, correction.invalidated.Length)
		AssertEquals(ERecordedActionType.TableTieDecision.Ordinal(), correction.invalidated[0].action.actionType.Ordinal())
		AssertEquals(2, correction.state.stages[0].leaderboard.rows[0].participantId)
	End Method

	Method testNamedChampionshipTieDecisionSelectsWinner() { test }
		Local builder:TCompetitionBuilder = Builder("Named board tie")
		Local config:TSeriesConfig = New TSeriesConfig
		config.events = [TTourneyAuthoring.Event("E1", ["RACE"])]
		config.scoring = TTourneyAuthoring.PositionScoring(["10", "5"])
		Local named:TChampionshipConfig = New TChampionshipConfig
		named.code = "ALT"
		named.sessionCodes = ["RACE"]
		named.scoringOverride = TTourneyAuthoring.PositionScoring(["1", "1"])
		named.tiebreakers = [ETiebreaker.Points]
		config.championships = [named]
		Local stage:TStage = builder.AddStage("SERIES", EStageType.Series, config)
		Local comp:TCompetition = builder.BuildChecked()
		comp.seasonTransitions = [Transition("ALT")]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "SERIES", state.stages[0].fixtures[0].id, Classification(1, 2))
		AssertEquals(1, state.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(1, state.stages[0].championships[0].leaderboard.rows[0].sportingRank)
		Local namedTies:TUnresolvedTableTie[] = engine.UnresolvedTableTies(comp, state, "SERIES")
		Local namedTie:Int
		For Local tie:TUnresolvedTableTie = EachIn namedTies
			If tie.scopeKey = "ALT" Then
				namedTie :+ 1
				AssertEquals(2, tie.participantIds.Length)
				AssertEquals(1, tie.participantIds[0])
				AssertEquals(2, tie.participantIds[1])
			End If
		Next

		AssertEquals(1, namedTie)
		AssertEquals(EQualificationStatus.Possible.Ordinal(), engine.AnalyzeQualification(comp, state, "SERIES", 2, 1, "", 100000, "ALT").status.Ordinal())
		Local route:TAdvancement = New TAdvancement
		route.championshipCode = "ALT"
		route.rule = New TFilterRule
		route.rule.kind = EFilterKind.TopN
		route.rule.n = 1
		stage.advancement = [route]
		Local advancer:TSeriesAdvancer = New TSeriesAdvancer
		AssertTrue(advancer.ProduceAdvancements(comp, stage, state.stages[0]) = Null)
		Local decided:TCompetitionState = engine.RecordTableTieDecision(comp, state, "SERIES", "ALT", [2, 1], "Named title decision")
		For Local tie:TUnresolvedTableTie = EachIn engine.UnresolvedTableTies(comp, decided, "SERIES")
			AssertTrue(tie.scopeKey <> "ALT", "The named title decision has resolved its tie")
		Next

		AssertEquals(1, decided.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(2, decided.stages[0].championships[0].leaderboard.rows[0].participantId)
		AssertEquals(EQualificationStatus.Guaranteed.Ordinal(), engine.AnalyzeQualification(comp, decided, "SERIES", 2, 1, "", 100000, "ALT").status.Ordinal())
		AssertEquals(2, engine.ResolveSeasonMovements(comp, decided)[0].participantId)
		AssertEquals(2, advancer.ProduceAdvancements(comp, stage, decided.stages[0])[0].id)
	End Method

	Method testAdjustmentCanCreateAResolvableSeriesTie() { test }
		Local builder:TCompetitionBuilder = Builder("Adjusted series tie")
		Local config:TSeriesConfig = New TSeriesConfig
		config.events = [TTourneyAuthoring.Event("E1", ["RACE"])]
		config.scoring = TTourneyAuthoring.PositionScoring(["10", "5"])
		builder.AddStage("SERIES", EStageType.Series, config)
		Local comp:TCompetition = builder.BuildChecked()
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "SERIES", state.stages[0].fixtures[0].id, Classification(1, 2))
		Local adjustment:TPointAdjustment = New TPointAdjustment
		adjustment.participantId = 2
		adjustment.pointsDelta = 5
		Local payload:TResultPayload = New TResultPayload
		payload.kind = EResultKind.AdminAdjustment
		payload.adjustments = [adjustment]
		engine.RecordResult(comp, state, "SERIES", "", payload)
		AssertEquals(10, state.stages[0].leaderboard.rows[0].points)
		AssertEquals(10, state.stages[0].leaderboard.rows[1].points)
		AssertEquals(1, state.stages[0].leaderboard.rows[0].sportingRank)
		AssertEquals(1, state.stages[0].leaderboard.rows[1].sportingRank)
		Local decided:TCompetitionState = engine.RecordTableTieDecision(comp, state, "SERIES", "", [2, 1], "Adjusted points tie")
		AssertEquals(2, decided.stages[0].leaderboard.rows[0].participantId)
	End Method
End Type

Type TParis2024MensDinghyReplayTest Extends TTest
	Method testCompleteRegattaAndOfficialClassification() { test }
		AssertEquals(43, TParis2024MensDinghyReplay.Run(AppDir + "/../examples/paris_2024_mens_dinghy.tsv"))
	End Method
End Type

Type TRegattaRulesTest Extends TTest
	Function Score:TRegattaRaceScore(id:Int, place:Int, code:String = "")
		Local score:TRegattaRaceScore = New TRegattaRaceScore
		score.participantId = id
		score.place = place
		score.code = code
		Return score
	End Function

	Method testNonDiscardablePenaltyAndUnknownAdjustedCode() { test }
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 3
			Local participant:TParticipant = New TParticipant
			participant.id = id
			comp.participants :+ [participant]
		Next

		Local stage:TStage = New TStage
		stage.id = "FLEET"
		stage.stageType = EStageType.Qualifying
		stage.formatCode = "regatta"
		Local cfg:TRegattaConfig = New TRegattaConfig
		cfg.scheduledRaces = 3
		cfg.discardAfterRaces = 3
		stage.config = cfg
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterFormat("regatta", New TRegattaScheduler, New TRegattaScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local races:TRegattaRaceScore[][] = [[Score(1, 0, "DNE"), Score(2, 1), Score(3, 2)], [Score(1, 3), Score(2, 2), Score(3, 1)], [Score(1, 2), Score(2, 1), Score(3, 3)]]
		For Local round:Int = 1 To 3
			Local result:TResultPayload = New TResultPayload
			result.kind = EResultKind.Custom
			result.customCode = "regatta-race"
			result.regattaScores = races[round - 1]
			engine.RecordResult(comp, state, stage.id, state.stages[0].fixtures[round - 1].id, result)
			If round = 1 Then
				Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
				Local output:TStream = WriteStream("rt_regatta_comp.json")
				jconv.ToJson(comp, output)
				output.Close()
				output = WriteStream("rt_regatta_state.json")
				jconv.ToJson(state, output)
				output.Close()
				Local input:TStream = ReadStream("rt_regatta_comp.json")
				comp = TCompetition(jconv.FromJson(input, "TCompetition"))
				input.Close()
				input = ReadStream("rt_regatta_state.json")
				state = TCompetitionState(jconv.FromJson(input, "TCompetitionState"))
				input.Close()
				DeleteFile("rt_regatta_comp.json")
				DeleteFile("rt_regatta_state.json")
				AssertEquals(3, TRegattaConfig(comp.stages[0].config).scheduledRaces)
				AssertEquals("DNE", state.stages[0].fixtures[0].regattaScores[0].code)
			End If
		Next

		AssertEquals(EStageStatus.Complete, state.stages[0].status)
		Local standing:TRegattaStanding = state.stages[0].regattaStandings[2]
		AssertEquals(1, standing.participantId)
		AssertEquals(6, standing.totalUnits)
		AssertFalse(standing.scores[0].discarded)
		AssertTrue(standing.scores[1].discarded)
		Local adjusted:TRegattaRaceScore = Score(1, 0, "DPI")
		Local rejected:Int
		Try
			TRegattaRules.ScoreUnits(cfg, adjusted, 3)
		Catch failure:Object
			rejected = True
		End Try

		AssertTrue(rejected)
	End Method
End Type

Type TParis2024Mens800mReplayTest Extends TTest
	Method testAllRoundsAndFinalOrder() { test }
		AssertEquals(987, TParis800Replay.Run(AppDir + "/../examples/paris_2024_mens_800m.tsv"))
	End Method
End Type

Type TMasters2024ReplayTest Extends TTest
	Method testCompleteFieldCutAndFinalStandings() { test }
		AssertEquals(60, TMasters2024Replay.Run(AppDir + "/../examples/masters_2024_scores.txt"))
	End Method
End Type

Type TCompetitionCalendarTest Extends TTest
	Method testJointPlannerDetectsSharedVenueCapacityAcrossStages() { test }
		Local comp:TCompetition = New TCompetition
		Local state:TCompetitionState = New TCompetitionState
		For Local index:Int = 0 Until 2
			Local stage:TStage = New TStage
			stage.id = "STAGE" + index
			stage.stageType = EStageType.League
			stage.schedule = New TSchedulePolicy
			stage.schedule.calendar = New TCalendar
			stage.schedule.calendar.slots = [Slot("slot" + index, "2026-10-22T12:00:00Z", "shared")]
			comp.stages :+ [stage]
			Local ss:TStageState = New TStageState
			ss.stageId = stage.id
			Local fixture:TFixtureState = New TFixtureState
			fixture.id = "F" + index
			fixture.homeTeamId = index * 2 + 1
			fixture.awayTeamId = index * 2 + 2
			ss.fixtures = [fixture]
			state.stages :+ [ss]
		Next

		Local engine:TCompetitionEngine = New TCompetitionEngine
		Local rejected:Int
		Try
			engine.PlanCalendar(comp, state, False, 1)
		Catch problem:Object
			rejected = True
		End Try

		AssertTrue(rejected)
		AssertTrue(engine.lastScheduleFailure.capacityConflict)
		AssertEquals("venue", engine.lastScheduleFailure.capacityKind)
		AssertEquals("shared", engine.lastScheduleFailure.capacityResource)
		AssertEquals(2, engine.lastScheduleFailure.requiredFixtures)
		AssertEquals(1, engine.lastScheduleFailure.availableResources)
		AssertEquals(1, engine.lastScheduleSearchNodes)
		AssertEquals("", state.stages[0].fixtures[0].slotId)
		AssertEquals("", state.stages[1].fixtures[0].slotId)
		Local laterCalendar:TCalendar = comp.stages[1].schedule.calendar
		laterCalendar.slots :+ [Slot("later", "2026-10-22T16:00:00Z", "shared")]
		AssertEquals(2, engine.PlanCalendar(comp, state, False, 10))
		AssertEquals("later", state.stages[1].fixtures[0].slotId)
	End Method

	Method testJointPlannerDetectsLargeParticipantWeekShortage() { test }
		Local comp:TCompetition = New TCompetition
		Local stage:TStage = New TStage
		stage.id = "LONG"
		stage.stageType = EStageType.League
		stage.config = New TLeagueConfig
		TLeagueConfig(stage.config).schedule = New TLeagueScheduleConfig
		TLeagueConfig(stage.config).schedule.weeks = 33
		stage.schedule = New TSchedulePolicy
		stage.schedule.calendar = New TCalendar
		For Local week:Int = 1 To 33
			Local slot:TSlot = Slot("W" + week, "2026-10-" + week, "venue")
			slot.round = week
			stage.schedule.calendar.slots :+ [slot]
		Next

		comp.stages = [stage]
		Local ss:TStageState = New TStageState
		ss.stageId = "LONG"
		For Local index:Int = 0 Until 34
			Local fixture:TFixtureState = New TFixtureState
			fixture.id = "F" + index
			fixture.homeTeamId = 1
			fixture.awayTeamId = index + 2
			ss.fixtures :+ [fixture]
		Next

		Local state:TCompetitionState = New TCompetitionState
		state.stages = [ss]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		Local rejected:Int
		Try
			engine.PlanSchedule(comp, state, False, 1)
		Catch problem:Object
			rejected = True
		End Try

		AssertTrue(rejected)
		AssertTrue(engine.lastScheduleFailure.capacityConflict)
		AssertEquals("weeks for participant", engine.lastScheduleFailure.capacityKind)
		AssertEquals("1", engine.lastScheduleFailure.capacityResource)
		AssertEquals(34, engine.lastScheduleFailure.requiredFixtures)
		AssertEquals(33, engine.lastScheduleFailure.availableResources)
		AssertEquals(1, engine.lastScheduleSearchNodes)
		AssertEquals(0, ss.fixtures[0].round)
		AssertEquals("", ss.fixtures[0].slotId)
	End Method

	Method testJointPlannerDetectsHallSlotCapacityBeforeSearch() { test }
		Local comp:TCompetition = New TCompetition
		Local stage:TStage = New TStage
		stage.id = "CROWDED"
		stage.stageType = EStageType.League
		stage.schedule = New TSchedulePolicy
		stage.schedule.calendar = New TCalendar
		Local calendar:TCalendar = stage.schedule.calendar
		calendar.slots = [Slot("a", "2026-10-22T12:00:00Z", "a"), Slot("b", "2026-10-22T16:00:00Z", "b"), Slot("c", "2026-10-22T20:00:00Z", "c")]
		For Local teamId:Int = 1 To 3 Step 2
			For Local slotId:String = EachIn ["b", "c"]
				Local blackout:TTeamBlackout = New TTeamBlackout
				blackout.teamId = teamId
				blackout.slotId = slotId
				calendar.blackouts :+ [blackout]
			Next
		Next

		comp.stages = [stage]
		Local ss:TStageState = New TStageState
		ss.stageId = "CROWDED"
		For Local index:Int = 0 Until 3
			Local fixture:TFixtureState = New TFixtureState
			fixture.id = "F" + index
			fixture.homeTeamId = index * 2 + 1
			fixture.awayTeamId = index * 2 + 2
			ss.fixtures :+ [fixture]
		Next

		Local state:TCompetitionState = New TCompetitionState
		state.stages = [ss]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		Local rejected:Int
		Try
			engine.PlanCalendar(comp, state, False, 1)
		Catch problem:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Two fixtures sharing one usable slot cannot both be placed")
		AssertTrue(engine.lastScheduleFailure <> Null)
		AssertTrue(engine.lastScheduleFailure.capacityConflict)
		AssertTrue(Not engine.lastScheduleFailure.searchLimitReached)
		AssertEquals(1, engine.lastScheduleSearchNodes)
		For Local fixture:TFixtureState = EachIn ss.fixtures
			AssertEquals("", fixture.slotId)
		Next

		calendar.blackouts = calendar.blackouts[..3]
		AssertEquals(3, engine.PlanCalendar(comp, state, False, 100))
		AssertTrue(ss.fixtures[0].slotId <> ss.fixtures[1].slotId)
	End Method

	Function Slot:TSlot(id:String, dateTime:String, venue:String)
		Local slot:TSlot = New TSlot
		slot.id = id; slot.dateTime = dateTime; slot.venueId = venue
		Return slot
	End Function

	Function Stage:TStage(id:String, home:Int, away:Int, calendar:TCalendar)
		Local stage:TStage = New TStage
		stage.id = id
		stage.stageType = EStageType.League
		stage.independent = True
		stage.config = New TLeagueConfig
		Local fixture:TFixture = New TFixture
		fixture.round = 1
		fixture.homeTeamId = home
		fixture.awayTeamId = away
		TLeagueConfig(stage.config).schedule = New TLeagueScheduleConfig
		TLeagueConfig(stage.config).schedule.fixedFixtures = [fixture]
		stage.schedule = New TSchedulePolicy
		stage.schedule.calendar = calendar
		Return stage
	End Function

	Function Teams:TCompetition()
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 4
			Local participant:TParticipant = New TParticipant
			participant.id = id
			If id = 1 Or id = 2 Then
				participant.homeVenueId = "shared"
			End If

			comp.participants :+ [participant]
		Next

		Return comp
	End Function

	Method testSharedVenueAcrossIndependentStages() { test }
		Local comp:TCompetition = Teams()
		Local calendar:TCalendar = New TCalendar
		calendar.slots = [Slot("early", "2026-10-22T12:00:00Z", "shared"), Slot("late", "2026-10-22T16:00:00Z", "shared")]
		comp.stages = [Stage("JETS", 1, 3, calendar), Stage("GIANTS", 2, 4, calendar)]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals("early", state.stages[0].fixtures[0].slotId)
		AssertEquals("late", state.stages[1].fixtures[0].slotId)
	End Method

	Method testLiveScheduleRevisionSurvivesResultCorrection() { test }
		Local comp:TCompetition = Teams()
		Local calendar:TCalendar = New TCalendar
		calendar.slots = [Slot("early", "2026-10-22T12:00:00Z", "shared"), Slot("late", "2026-10-22T16:00:00Z", "shared"), Slot("extra", "2026-10-23T12:00:00Z", "shared")]
		comp.stages = [Stage("JETS", 1, 3, calendar), Stage("GIANTS", 2, 4, calendar)]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		engine.RegisterScorer(EStageType.League, New TLeagueScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local completedId:String = state.stages[0].fixtures[0].id
		Local openId:String = state.stages[1].fixtures[0].id
		Local first:TResultPayload = New TResultPayload
		first.kind = EResultKind.HeadToHeadScore
		first.scoreHome = 1
		engine.RecordResult(comp, state, "JETS", completedId, first)
		Local revised:TCompetitionState = engine.ReviseFixtureSchedule(comp, state, "GIANTS", openId, "extra")
		AssertEquals("late", state.stages[1].fixtures[0].slotId)
		AssertEquals("extra", revised.stages[1].fixtures[0].slotId)
		AssertEquals("early", revised.stages[0].fixtures[0].slotId)
		AssertEquals(EFixtureStatus.Completed.Ordinal(), revised.stages[0].fixtures[0].status.Ordinal())
		AssertEquals(2, revised.actions.Length)

		Local rejected:Int
		Try
			engine.ReviseFixtureSchedule(comp, revised, "GIANTS", openId, "early")
		Catch problem:Object
			rejected = True
		End Try

		AssertTrue(rejected, "The completed fixture keeps its shared stadium slot")
		AssertEquals("extra", revised.stages[1].fixtures[0].slotId)
		AssertEquals(2, revised.actions.Length)

		Local json:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local restored:TCompetitionState = TCompetitionState(json.FromJson(json.ToJson(revised), "TCompetitionState"))
		Local replacement:TResultPayload = New TResultPayload
		replacement.kind = EResultKind.HeadToHeadScore
		replacement.scoreAway = 2
		Local correction:TResultCorrection = engine.CorrectResult(comp, restored, "JETS", completedId, replacement)
		AssertEquals(0, correction.invalidated.Length)
		AssertEquals(2, correction.state.actions.Length)
		AssertEquals("early", correction.state.stages[0].fixtures[0].slotId)
		AssertEquals("extra", correction.state.stages[1].fixtures[0].slotId)
		AssertEquals(2, correction.state.stages[0].fixtures[0].scoreAway)
	End Method

	Method testRevisionCanReplanOtherUnplayedFixtures() { test }
		Local comp:TCompetition = Teams()
		Local calendar:TCalendar = New TCalendar
		calendar.slots = [Slot("early", "2026-10-22T12:00:00Z", "shared"), Slot("late", "2026-10-22T16:00:00Z", "shared")]
		comp.stages = [Stage("JETS", 1, 3, calendar), Stage("GIANTS", 2, 4, calendar)]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		engine.RegisterScorer(EStageType.League, New TLeagueScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		state.stages[1].fixtures[0].status = EFixtureStatus.Postponed
		Local revised:TCompetitionState = engine.ReviseFixtureSchedule(comp, state, "GIANTS", "GIANTS_F1", "early", 0, True)
		AssertEquals("late", revised.stages[0].fixtures[0].slotId)
		AssertEquals("early", revised.stages[1].fixtures[0].slotId)
		AssertEquals(EFixtureStatus.Scheduled.Ordinal(), revised.stages[1].fixtures[0].status.Ordinal())
		AssertTrue(revised.replayBaseJson <> "")
		AssertEquals(1, revised.actions.Length)
		AssertEquals("early", state.stages[0].fixtures[0].slotId)
		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.HeadToHeadScore
		result.scoreHome = 1
		engine.RecordResult(comp, revised, "JETS", "JETS_F1", result)
		Local replacement:TResultPayload = New TResultPayload
		replacement.kind = EResultKind.HeadToHeadScore
		replacement.scoreAway = 1
		Local correction:TResultCorrection = engine.CorrectResult(comp, revised, "JETS", "JETS_F1", replacement)
		AssertEquals(0, correction.invalidated.Length)
		AssertEquals("late", correction.state.stages[0].fixtures[0].slotId)
		AssertEquals("early", correction.state.stages[1].fixtures[0].slotId)
	End Method

	Method testJointPlannerMovesEarlierStageForScarceSharedVenueSlot() { test }
		Local comp:TCompetition = Teams()
		Local flexible:TCalendar = New TCalendar
		flexible.slots = [Slot("early", "2026-10-22T12:00:00Z", "shared"), Slot("late", "2026-10-22T16:00:00Z", "shared")]
		Local restricted:TCalendar = New TCalendar
		restricted.slots = [Slot("early", "2026-10-22T12:00:00Z", "shared")]
		comp.stages = [Stage("JETS", 1, 3, flexible), Stage("GIANTS", 2, 4, restricted)]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local sequentialFailed:Int
		Try
			engine.Initialize(comp)
		Catch problem:Object
			sequentialFailed = True
		End Try

		AssertTrue(sequentialFailed, "Stage-by-stage assignment consumes the Giants' only slot")
		Local state:TCompetitionState = engine.Initialize(comp, True)
		AssertEquals("late", state.stages[0].fixtures[0].slotId)
		AssertEquals("early", state.stages[1].fixtures[0].slotId)
	End Method

	Method testJointPlannerAvoidsParticipantOverlapAcrossStages() { test }
		Local comp:TCompetition = Teams()
		Local home:TCalendar = New TCalendar
		home.slots = [Slot("early-home", "2026-10-22T12:00:00Z", "shared"), Slot("late-home", "2026-10-22T16:00:00Z", "shared")]
		Local away:TCalendar = New TCalendar
		away.slots = [Slot("early-away", "2026-10-22T12:00:00Z", "other")]
		comp.stages = [Stage("HOME", 1, 3, home), Stage("AWAY", 4, 1, away)]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp, True)
		AssertEquals("late-home", state.stages[0].fixtures[0].slotId)
		AssertEquals("early-away", state.stages[1].fixtures[0].slotId)
	End Method

	Method testJointPlannerCanReassignAndRestoresStateAfterFailure() { test }
		Local comp:TCompetition = Teams()
		Local flexible:TCalendar = New TCalendar
		flexible.slots = [Slot("early", "2026-10-22T12:00:00Z", "shared"), Slot("late", "2026-10-22T16:00:00Z", "shared")]
		Local restricted:TCalendar = New TCalendar
		restricted.slots = [Slot("early", "2026-10-22T12:00:00Z", "shared"), Slot("late", "2026-10-22T16:00:00Z", "shared")]
		comp.stages = [Stage("JETS", 1, 3, flexible), Stage("GIANTS", 2, 4, restricted)]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals("early", state.stages[0].fixtures[0].slotId)
		AssertEquals("late", state.stages[1].fixtures[0].slotId)
		restricted.slots = restricted.slots[..1]
		AssertEquals(2, engine.PlanCalendar(comp, state, True))
		AssertEquals("late", state.stages[0].fixtures[0].slotId)
		AssertEquals("early", state.stages[1].fixtures[0].slotId)
		AssertTrue(engine.lastScheduleFailure = Null)
		flexible.slots = flexible.slots[..1]
		Local rejected:Int
		Local failure:String
		Try
			engine.PlanCalendar(comp, state, True)
		Catch problem:Object
			rejected = True
			failure = String(problem)
		End Try

		AssertTrue(rejected, "Two hosts cannot use the shared stadium at the same time")
		AssertTrue(failure.Find("venue shared") >= 0, "The failure should identify shared-venue capacity")
		AssertTrue(engine.lastScheduleFailure <> Null)
		AssertTrue(engine.lastScheduleFailure.capacityConflict)
		AssertEquals("venue", engine.lastScheduleFailure.capacityKind)
		AssertEquals("shared", engine.lastScheduleFailure.capacityResource)
		AssertEquals(2, engine.lastScheduleFailure.requiredFixtures)
		AssertEquals(1, engine.lastScheduleFailure.availableResources)
		AssertTrue(Not engine.lastScheduleFailure.searchLimitReached)
		AssertEquals(engine.lastScheduleSearchNodes, engine.lastScheduleFailure.nodes)
		AssertEquals("late", state.stages[0].fixtures[0].slotId)
		AssertEquals("early", state.stages[1].fixtures[0].slotId)
	End Method

	Method testJointPlannerReportsSearchLimitSeparatelyFromDeadEnd() { test }
		Local comp:TCompetition = Teams()
		For Local id:Int = 5 To 6
			Local participant:TParticipant = New TParticipant
			participant.id = id
			comp.participants :+ [participant]
		Next

		Local calendar:TCalendar = New TCalendar
		calendar.slots = [Slot("early", "2026-10-22T12:00:00Z", "shared"), Slot("late", "2026-10-22T16:00:00Z", "shared"), Slot("later", "2026-10-22T20:00:00Z", "shared")]
		Local first:TStage = Stage("FIRST", 1, 3, Null)
		Local second:TStage = Stage("SECOND", 2, 4, Null)
		Local third:TStage = Stage("THIRD", 5, 6, Null)
		comp.stages = [first, second, third]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp)
		first.schedule.calendar = calendar
		second.schedule.calendar = calendar
		third.schedule.calendar = calendar
		Local failure:String
		Try
			engine.PlanCalendar(comp, state, False, 3)
		Catch problem:Object
			failure = String(problem)
		End Try

		AssertTrue(failure.Find("search limit") >= 0)
		AssertTrue(engine.lastScheduleFailure = Null)
		AssertEquals(4, engine.lastScheduleSearchNodes)
		AssertEquals("", state.stages[0].fixtures[0].slotId)
		AssertEquals("", state.stages[1].fixtures[0].slotId)
		AssertEquals("", state.stages[2].fixtures[0].slotId)
	End Method

	Method testJointScheduleChoosesWeeksWithSlots() { test }
		Local comp:TCompetition = Teams()
		Local calendar:TCalendar = New TCalendar
		Local first:TSlot = Slot("week-one", "2026-10-22T12:00:00Z", "shared")
		first.round = 1
		Local second:TSlot = Slot("week-two", "2026-10-29T12:00:00Z", "shared")
		second.round = 2
		calendar.slots = [first, second]
		Local blackout:TTeamBlackout = New TTeamBlackout
		blackout.teamId = 1
		blackout.slotId = "week-one"
		calendar.blackouts = [blackout]
		Local stage:TStage = Stage("LEAGUE", 1, 3, calendar)
		Local schedule:TLeagueScheduleConfig = TLeagueConfig(stage.config).schedule
		schedule.fixedFixtures[0].round = 0
		Local other:TFixture = New TFixture
		other.homeTeamId = 2
		other.awayTeamId = 4
		schedule.fixedFixtures :+ [other]
		schedule.weeks = 2
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local sequentialFailed:Int
		Try
			engine.Initialize(comp)
		Catch problem:Object
			sequentialFailed = True
		End Try

		AssertTrue(sequentialFailed, "Week-first allocation cannot recover from the blackout")
		Local state:TCompetitionState = engine.Initialize(comp, True)
		AssertEquals(2, state.stages[0].fixtures[0].round)
		AssertEquals("week-two", state.stages[0].fixtures[0].slotId)
		AssertEquals(1, state.stages[0].fixtures[1].round)
		AssertEquals("week-one", state.stages[0].fixtures[1].slotId)
	End Method

	Method testJointScheduleChoosesWeeksAcrossStages() { test }
		Local comp:TCompetition = Teams()
		Local flexible:TCalendar = New TCalendar
		Local early:TSlot = Slot("week-one", "2026-10-22T12:00:00Z", "shared")
		early.round = 1
		Local late:TSlot = Slot("week-two", "2026-10-29T12:00:00Z", "shared")
		late.round = 2
		flexible.slots = [early, late]
		Local restricted:TCalendar = New TCalendar
		restricted.slots = [early]
		Local jets:TStage = Stage("JETS", 1, 3, flexible)
		Local giants:TStage = Stage("GIANTS", 2, 4, restricted)
		TLeagueConfig(jets.config).schedule.weeks = 2
		TLeagueConfig(giants.config).schedule.weeks = 2
		TLeagueConfig(jets.config).schedule.fixedFixtures[0].round = 0
		TLeagueConfig(giants.config).schedule.fixedFixtures[0].round = 0
		comp.stages = [jets, giants]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp, True)
		AssertEquals(2, state.stages[0].fixtures[0].round)
		AssertEquals("week-two", state.stages[0].fixtures[0].slotId)
		AssertEquals(1, state.stages[1].fixtures[0].round)
		AssertEquals("week-one", state.stages[1].fixtures[0].slotId)
	End Method

	Method testJointScheduleUsesNumberedSlotsForOpenEndedLeague() { test }
		Local comp:TCompetition = Teams()
		Local calendar:TCalendar = New TCalendar
		Local first:TSlot = Slot("week-one", "2026-10-22T12:00:00Z", "shared")
		first.round = 1
		Local second:TSlot = Slot("week-two", "2026-10-29T12:00:00Z", "shared")
		second.round = 2
		calendar.slots = [first, second]
		Local blackout:TTeamBlackout = New TTeamBlackout
		blackout.teamId = 1
		blackout.slotId = "week-one"
		calendar.blackouts = [blackout]
		Local stage:TStage = Stage("OPEN", 1, 3, calendar)
		Local schedule:TLeagueScheduleConfig = TLeagueConfig(stage.config).schedule
		schedule.fixedFixtures[0].round = 0
		Local other:TFixture = New TFixture
		other.homeTeamId = 2
		other.awayTeamId = 4
		schedule.fixedFixtures :+ [other]
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp, True)
		AssertEquals(2, state.stages[0].fixtures[0].round)
		AssertEquals("week-two", state.stages[0].fixtures[0].slotId)
		AssertEquals(1, state.stages[0].fixtures[1].round)
		AssertEquals("week-one", state.stages[0].fixtures[1].slotId)
	End Method

	Method testJointScheduleKeepsWeekAllocatorForUnnumberedOpenCalendar() { test }
		Local comp:TCompetition = Teams()
		Local calendar:TCalendar = New TCalendar
		calendar.slots = [Slot("first", "2026-10-22T12:00:00Z", "shared"), Slot("second", "2026-10-22T16:00:00Z", "shared")]
		Local stage:TStage = Stage("OPEN", 1, 3, calendar)
		TLeagueConfig(stage.config).schedule.fixedFixtures[0].round = 0
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp, True)
		AssertEquals(1, state.stages[0].fixtures[0].round)
		AssertEquals("first", state.stages[0].fixtures[0].slotId)
	End Method

	Method testJointSchedulePrefersShortestOpenEndedSeason() { test }
		Local comp:TCompetition = Teams()
		Local calendar:TCalendar = New TCalendar
		Local first:TSlot = Slot("week-one-a", "2026-10-22T12:00:00Z", "shared")
		first.round = 1
		Local second:TSlot = Slot("week-one-b", "2026-10-23T12:00:00Z", "shared")
		second.round = 1
		Local later:TSlot = Slot("week-two", "2026-10-29T12:00:00Z", "shared")
		later.round = 2
		calendar.slots = [first, second, later]
		Local stage:TStage = Stage("OPEN", 1, 3, calendar)
		Local schedule:TLeagueScheduleConfig = TLeagueConfig(stage.config).schedule
		schedule.fixedFixtures[0].round = 0
		Local other:TFixture = New TFixture
		other.homeTeamId = 2
		other.awayTeamId = 4
		schedule.fixedFixtures :+ [other]
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp, True)
		AssertEquals(1, state.stages[0].fixtures[0].round)
		AssertEquals(1, state.stages[0].fixtures[1].round)
	End Method

	Method testJointSchedulePrefersRestWeeks() { test }
		Local comp:TCompetition = Teams()
		Local calendar:TCalendar = New TCalendar
		Local slots:TSlot[]
		For Local week:Int = 1 To 3
			Local slot:TSlot = Slot("week-" + week, "2026-11-0" + week + "T12:00:00Z", "shared")
			slot.round = week
			slots :+ [slot]
		Next

		calendar.slots = slots
		Local stage:TStage = Stage("REST", 1, 3, calendar)
		Local schedule:TLeagueScheduleConfig = TLeagueConfig(stage.config).schedule
		schedule.fixedFixtures[0].round = 0
		Local other:TFixture = New TFixture
		other.homeTeamId = 1
		other.awayTeamId = 4
		schedule.fixedFixtures :+ [other]
		schedule.weeks = 3
		stage.schedule.preferences = New TSchedulePreferences
		stage.schedule.preferences.minRestWeeks = 1
		stage.schedule.preferences.restShortfallWeight = 5
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp, True)
		AssertEquals(1, state.stages[0].fixtures[0].round)
		AssertEquals(3, state.stages[0].fixtures[1].round)
		AssertEquals(0, engine.lastSchedulePreferenceScore)
		AssertTrue(engine.lastSchedulePreferenceOptimal)
		AssertEquals(2, engine.PlanSchedule(comp, state, True, 1))
		AssertEquals(0, engine.lastSchedulePreferenceScore)
		AssertTrue(engine.lastSchedulePreferenceOptimal)
		AssertEquals(1, engine.lastScheduleSearchNodes)
		AssertEquals(1, engine.lastSchedulePrunedNodes)
		AssertEquals(3, state.stages[0].fixtures[1].round)
		Local bounded:TCompetitionState = engine.Initialize(comp)
		AssertEquals(2, engine.PlanSchedule(comp, bounded, True, 1))
		AssertEquals(5, engine.lastSchedulePreferenceScore)
		AssertTrue(Not engine.lastSchedulePreferenceOptimal)
		AssertEquals(2, bounded.stages[0].fixtures[1].round)
		AssertEquals(2, engine.PlanSchedule(comp, bounded, True, 3))
		AssertEquals(5, engine.lastSchedulePreferenceScore)
		AssertTrue(Not engine.lastSchedulePreferenceOptimal, "A bounded preference search reports that optimality is unproven")
		Local blackout:TTeamBlackout = New TTeamBlackout
		blackout.teamId = 1
		blackout.slotId = "week-3"
		calendar.blackouts = [blackout]
		AssertEquals(2, engine.PlanSchedule(comp, state, True))
		AssertEquals(2, state.stages[0].fixtures[1].round)
		AssertEquals(5, engine.lastSchedulePreferenceScore)
	End Method

	Method testRestLowerBoundProvesUnavoidableCost() { test }
		Local comp:TCompetition = Teams()
		Local calendar:TCalendar = New TCalendar
		Local first:TSlot = Slot("first", "2026-11-01T12:00:00Z", "shared")
		first.round = 1
		Local second:TSlot = Slot("second", "2026-11-08T12:00:00Z", "shared")
		second.round = 2
		calendar.slots = [first, second]
		Local stage:TStage = Stage("REST", 1, 3, calendar)
		Local schedule:TLeagueScheduleConfig = TLeagueConfig(stage.config).schedule
		schedule.fixedFixtures[0].round = 0
		Local other:TFixture = New TFixture
		other.homeTeamId = 1
		other.awayTeamId = 4
		schedule.fixedFixtures :+ [other]
		schedule.weeks = 2
		stage.schedule.preferences = New TSchedulePreferences
		stage.schedule.preferences.minRestWeeks = 1
		stage.schedule.preferences.restShortfallWeight = 5
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp, True)
		AssertEquals(5, engine.lastSchedulePreferenceScore)
		AssertEquals(2, engine.PlanSchedule(comp, state, True, 1))
		AssertEquals(5, engine.lastSchedulePreferenceScore)
		AssertTrue(engine.lastSchedulePreferenceOptimal)
		AssertEquals(1, engine.lastSchedulePrunedNodes)
	End Method

	Method testEightTeamCalendarPrunesFromExistingSchedule() { test }
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 8
			Local team:TParticipant = New TParticipant
			team.id = id
			comp.participants :+ [team]
		Next

		Local stage:TStage = New TStage
		stage.id = "LEAGUE"
		stage.stageType = EStageType.League
		stage.config = New TLeagueConfig
		Local schedule:TLeagueScheduleConfig = New TLeagueScheduleConfig
		schedule.weeks = 2
		TLeagueConfig(stage.config).schedule = schedule
		For Local pair:Int = 0 Until 4
			Local first:TFixture = New TFixture
			first.homeTeamId = pair * 2 + 1
			first.awayTeamId = pair * 2 + 2
			schedule.fixedFixtures :+ [first]
		Next

		For Local pair:Int = 0 Until 4
			Local second:TFixture = New TFixture
			second.homeTeamId = pair * 2 + 2
			second.awayTeamId = pair * 2 + 1
			schedule.fixedFixtures :+ [second]
		Next

		stage.schedule = New TSchedulePolicy
		stage.schedule.calendar = New TCalendar
		For Local week:Int = 1 To 2
			For Local venue:Int = 1 To 4
				Local slot:TSlot = Slot("W" + week + "V" + venue, "2026-11-0" + week + "T12:00:00Z", "V" + venue)
				slot.round = week
				stage.schedule.calendar.slots :+ [slot]
			Next
		Next

		stage.schedule.preferences = New TSchedulePreferences
		stage.schedule.preferences.minRestWeeks = 1
		stage.schedule.preferences.restShortfallWeight = 1
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(8, engine.PlanSchedule(comp, state, True, 1))
		AssertEquals(8, engine.lastSchedulePreferenceScore)
		AssertTrue(engine.lastSchedulePreferenceOptimal)
		AssertEquals(1, engine.lastScheduleSearchNodes)
		AssertEquals(1, engine.lastSchedulePrunedNodes)
	End Method

	Method testJointSchedulePrefersAlternatingHomeAway() { test }
		Local comp:TCompetition = Teams()
		Local calendar:TCalendar = New TCalendar
		Local slots:TSlot[]
		For Local week:Int = 1 To 3
			Local slot:TSlot = Slot("week-" + week, "2026-11-0" + week + "T12:00:00Z", "shared")
			slot.round = week
			slots :+ [slot]
		Next

		calendar.slots = slots
		Local stage:TStage = Stage("STREAK", 1, 3, calendar)
		Local schedule:TLeagueScheduleConfig = TLeagueConfig(stage.config).schedule
		schedule.fixedFixtures[0].round = 0
		Local home:TFixture = New TFixture
		home.homeTeamId = 1
		home.awayTeamId = 4
		Local away:TFixture = New TFixture
		away.homeTeamId = 2
		away.awayTeamId = 1
		schedule.fixedFixtures :+ [home, away]
		schedule.weeks = 3
		stage.schedule.preferences = New TSchedulePreferences
		stage.schedule.preferences.maxHomeStreak = 1
		stage.schedule.preferences.streakExcessWeight = 7
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp, True)
		AssertEquals(1, state.stages[0].fixtures[0].round)
		AssertEquals(3, state.stages[0].fixtures[1].round)
		AssertEquals(2, state.stages[0].fixtures[2].round)
		AssertEquals(0, engine.lastSchedulePreferenceScore)
	End Method

	Method testJointSchedulePrefersConfiguredVenueTravel() { test }
		Local comp:TCompetition = Teams()
		comp.participants[2].homeVenueId = "B"
		comp.participants[3].homeVenueId = "C"
		Local calendar:TCalendar = New TCalendar
		Local home:TSlot = Slot("home-one", "2026-11-01T12:00:00Z", "shared")
		home.round = 1
		Local bTwo:TSlot = Slot("B-two", "2026-11-08T12:00:00Z", "B")
		bTwo.round = 2
		Local cTwo:TSlot = Slot("C-two", "2026-11-08T12:00:00Z", "C")
		cTwo.round = 2
		Local bThree:TSlot = Slot("B-three", "2026-11-15T12:00:00Z", "B")
		bThree.round = 3
		Local cThree:TSlot = Slot("C-three", "2026-11-15T12:00:00Z", "C")
		cThree.round = 3
		calendar.slots = [home, bTwo, cTwo, bThree, cThree]
		Local stage:TStage = Stage("TRAVEL", 1, 2, calendar)
		Local schedule:TLeagueScheduleConfig = TLeagueConfig(stage.config).schedule
		Local atB:TFixture = New TFixture
		atB.homeTeamId = 3
		atB.awayTeamId = 1
		Local atC:TFixture = New TFixture
		atC.homeTeamId = 4
		atC.awayTeamId = 1
		schedule.fixedFixtures :+ [atB, atC]
		schedule.weeks = 3
		stage.schedule.preferences = New TSchedulePreferences
		stage.schedule.preferences.venueTransitionWeight = 1
		Local expensive:TVenueTransitionCost = New TVenueTransitionCost
		expensive.fromVenueId = "B"
		expensive.toVenueId = "C"
		expensive.cost = 9
		stage.schedule.preferences.venueTransitions = [expensive]
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp, True)
		AssertEquals(1, state.stages[0].fixtures[0].round)
		AssertEquals(3, state.stages[0].fixtures[1].round)
		AssertEquals(2, state.stages[0].fixtures[2].round)
		AssertEquals(0, engine.lastSchedulePreferenceScore)
	End Method

	Method testSchedulePreferencesRoundTrip() { test }
		Local comp:TCompetition = New TCompetition
		Local stage:TStage = New TStage
		stage.id = "PREFERENCES"
		stage.schedule = New TSchedulePolicy
		stage.schedule.preferences = New TSchedulePreferences
		stage.schedule.preferences.minRestWeeks = 2
		stage.schedule.preferences.restShortfallWeight = 4
		stage.schedule.preferences.maxAwayStreak = 3
		stage.schedule.preferences.streakExcessWeight = 5
		stage.schedule.preferences.venueTransitionWeight = 2
		Local cost:TVenueTransitionCost = New TVenueTransitionCost
		cost.fromVenueId = "A"
		cost.toVenueId = "B"
		cost.cost = 7
		stage.schedule.preferences.venueTransitions = [cost]
		comp.stages = [stage]
		Local jconv:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local path:String = "/private/tmp/tourney_schedule_preferences.json"
		Local output:TStream = WriteStream(path)
		jconv.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		Local restored:TCompetition = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		Local preferences:TSchedulePreferences = restored.stages[0].schedule.preferences
		AssertEquals(2, preferences.minRestWeeks)
		AssertEquals(4, preferences.restShortfallWeight)
		AssertEquals(3, preferences.maxAwayStreak)
		AssertEquals(5, preferences.streakExcessWeight)
		AssertEquals(2, preferences.venueTransitionWeight)
		AssertEquals(7, preferences.venueTransitions[0].cost)
	End Method

	Method testJointScheduleReplanRestoresWeeksOnFailure() { test }
		Local comp:TCompetition = Teams()
		Local calendar:TCalendar = New TCalendar
		Local first:TSlot = Slot("week-one", "2026-10-22T12:00:00Z", "shared")
		first.round = 1
		Local second:TSlot = Slot("week-two", "2026-10-29T12:00:00Z", "shared")
		second.round = 2
		calendar.slots = [first, second]
		Local stage:TStage = Stage("LEAGUE", 1, 3, calendar)
		stage.schedule.preferences = New TSchedulePreferences
		stage.schedule.preferences.minRestWeeks = 1
		stage.schedule.preferences.restShortfallWeight = 5
		Local schedule:TLeagueScheduleConfig = TLeagueConfig(stage.config).schedule
		schedule.fixedFixtures[0].round = 0
		schedule.weeks = 2
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp, True)
		AssertEquals(1, state.stages[0].fixtures[0].round)
		Local one:TTeamBlackout = New TTeamBlackout
		one.teamId = 1
		one.slotId = "week-one"
		Local two:TTeamBlackout = New TTeamBlackout
		two.teamId = 1
		two.slotId = "week-two"
		calendar.blackouts = [one, two]
		Local failed:Int
		Try
			engine.PlanSchedule(comp, state, True)
		Catch problem:Object
			failed = True
		End Try

		AssertTrue(failed, "All candidate weeks are blocked")
		AssertEquals(1, state.stages[0].fixtures[0].round)
		AssertEquals("week-one", state.stages[0].fixtures[0].slotId)
	End Method

	Method testJointScheduleHonoursPinnedWeekAndBye() { test }
		Local comp:TCompetition = Teams()
		Local calendar:TCalendar = New TCalendar
		Local first:TSlot = Slot("week-one", "2026-10-22T12:00:00Z", "shared")
		first.round = 1
		Local second:TSlot = Slot("week-two", "2026-10-29T12:00:00Z", "shared")
		second.round = 2
		calendar.slots = [first, second]
		Local stage:TStage = Stage("LEAGUE", 1, 3, calendar)
		Local schedule:TLeagueScheduleConfig = TLeagueConfig(stage.config).schedule
		schedule.weeks = 2
		Local other:TFixture = New TFixture
		other.homeTeamId = 2
		other.awayTeamId = 4
		schedule.fixedFixtures :+ [other]
		Local bye:TParticipantByeWeek = New TParticipantByeWeek
		bye.participantId = 2
		bye.week = 1
		schedule.byeWeeks = [bye]
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp, True)
		AssertEquals(1, state.stages[0].fixtures[0].round)
		AssertEquals(2, state.stages[0].fixtures[1].round)
		AssertEquals(2, engine.PlanSchedule(comp, state, True))
		AssertEquals(1, state.stages[0].fixtures[0].round)
		AssertEquals(2, state.stages[0].fixtures[1].round)
		state.stages[0].fixtures[0].round = 2
		AssertEquals(2, engine.PlanSchedule(comp, state, True))
		AssertEquals(1, state.stages[0].fixtures[0].round)
	End Method

	Method testParticipantCannotPlayInTwoStagesAtOnce() { test }
		Local comp:TCompetition = Teams()
		Local first:TCalendar = New TCalendar
		first.slots = [Slot("a-noon", "2026-10-22T12:00:00Z", "shared")]
		Local second:TCalendar = New TCalendar
		second.slots = [Slot("b-noon", "2026-10-22T12:00:00Z", "other"), Slot("b-evening", "2026-10-22T19:00:00Z", "other")]
		comp.stages = [Stage("FIRST", 1, 3, first), Stage("SECOND", 4, 1, second)]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals("b-evening", state.stages[1].fixtures[0].slotId)
	End Method

	Method testConstraintSearchReservesScarceSlot() { test }
		Local comp:TCompetition = Teams()
		Local stage:TStage = New TStage
		stage.schedule = New TSchedulePolicy
		stage.schedule.calendar = New TCalendar
		stage.schedule.calendar.slots = [Slot("a", "2026-10-22T12:00:00Z", "shared"), Slot("b", "2026-10-22T12:00:00Z", "other")]
		Local flexible:TFixtureState = New TFixtureState
		flexible.id = "flexible"; flexible.homeTeamId = 3; flexible.awayTeamId = 4
		Local restricted:TFixtureState = New TFixtureState
		restricted.id = "restricted"; restricted.homeTeamId = 1; restricted.awayTeamId = 2
		Local allocator:TCalendarSlotAllocator = New TCalendarSlotAllocator
		allocator.Assign(comp, stage, [flexible, restricted])
		AssertEquals("b", flexible.slotId)
		AssertEquals("a", restricted.slotId)
	End Method

	Method testConstraintSearchBacktracksAfterDeadEnd() { test }
		Local comp:TCompetition = New TCompetition
		Local stage:TStage = New TStage
		stage.schedule = New TSchedulePolicy
		stage.schedule.calendar = New TCalendar
		Local calendar:TCalendar = stage.schedule.calendar
		calendar.slots = [Slot("a", "2026-10-22T12:00:00Z", "a"), Slot("b", "2026-10-22T12:00:00Z", "b"), Slot("c", "2026-10-22T12:00:00Z", "c")]
		Local noC:TTeamBlackout = New TTeamBlackout
		noC.teamId = 1; noC.slotId = "c"
		Local noB3:TTeamBlackout = New TTeamBlackout
		noB3.teamId = 3; noB3.slotId = "b"
		Local noB5:TTeamBlackout = New TTeamBlackout
		noB5.teamId = 5; noB5.slotId = "b"
		calendar.blackouts = [noC, noB3, noB5]
		Local first:TFixtureState = New TFixtureState
		first.id = "first"; first.homeTeamId = 1; first.awayTeamId = 2
		Local second:TFixtureState = New TFixtureState
		second.id = "second"; second.homeTeamId = 3; second.awayTeamId = 4
		Local third:TFixtureState = New TFixtureState
		third.id = "third"; third.homeTeamId = 5; third.awayTeamId = 6
		(New TCalendarSlotAllocator).Assign(comp, stage, [first, second, third])
		AssertEquals("b", first.slotId)
		AssertTrue(second.slotId = "a" Or second.slotId = "c")
		AssertTrue(third.slotId = "a" Or third.slotId = "c")
		AssertTrue(second.slotId <> third.slotId)
	End Method

	Method testImpossibleCalendarLeavesNoPartialAssignments() { test }
		Local comp:TCompetition = Teams()
		Local stage:TStage = New TStage
		stage.id = "CONFLICT"
		stage.schedule = New TSchedulePolicy
		stage.schedule.calendar = New TCalendar
		stage.schedule.calendar.slots = [Slot("only", "2026-10-22T12:00:00Z", "shared")]
		Local a:TFixtureState = New TFixtureState
		a.id = "a"; a.homeTeamId = 1; a.awayTeamId = 3
		Local b:TFixtureState = New TFixtureState
		b.id = "b"; b.homeTeamId = 2; b.awayTeamId = 4
		Local rejected:Int
		Try
			(New TCalendarSlotAllocator).Assign(comp, stage, [a, b])
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Shared venue must reject simultaneous hosts")
		AssertEquals("", a.slotId)
		AssertEquals("", b.slotId)
	End Method
End Type

Type TLeagueOpponentFormulaTest Extends TTest
	Function AddRule:TMatchupRule(schedule:TLeagueScheduleConfig, sources:String[], targets:String[], mode:EMatchupMode, games:Int = 1)
		Local rule:TMatchupRule = New TMatchupRule
		rule.sourceDivisionIds = sources
		rule.targetDivisionIds = targets
		rule.mode = mode
		rule.gamesPerPair = games
		schedule.matchupRules :+ [rule]
		Return rule
	End Function

	Method testOpponentRuleOptionsRoundTrip() { test }
		Local schedule:TLeagueScheduleConfig = New TLeagueScheduleConfig
		schedule.balanceHomeAway = True
		schedule.minWeeksBetweenMeetings = 2
		Local rule:TMatchupRule = AddRule(schedule, ["A"], ["B", "C"], EMatchupMode.RotatingDivision)
		rule.sameRankOnly = True
		rule.excludeAlreadyScheduled = True
		rule.rotationOffset = 2
		AddRule(schedule, ["A", "B", "C", "D"], Null, EMatchupMode.RotatingDivisionPairs)
		Local jconv:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local path:String = "rt_league_opponent_formula.json"
		Local output:TStream = WriteStream(path)
		jconv.ToJson(schedule, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		Local loaded:TLeagueScheduleConfig = TLeagueScheduleConfig(jconv.FromJson(input, "TLeagueScheduleConfig"))
		input.Close()
		DeleteFile(path)
		AssertTrue(loaded.balanceHomeAway)
		AssertEquals(2, loaded.minWeeksBetweenMeetings)
		AssertTrue(loaded.matchupRules[0].sameRankOnly)
		AssertTrue(loaded.matchupRules[0].excludeAlreadyScheduled)
		AssertEquals(2, loaded.matchupRules[0].rotationOffset)
		AssertEquals(EMatchupMode.RotatingDivisionPairs.Ordinal(), loaded.matchupRules[1].mode.Ordinal())
	End Method

	Method testSixDivisionRotationCycleAndValidation() { test }
		Local comp:TCompetition = New TCompetition
		Local divisions:String[] = ["D0", "D1", "D2", "D3", "D4", "D5"]
		For Local i:Int = 0 Until divisions.Length
			Local participant:TParticipant = New TParticipant
			participant.id = i + 1
			participant.divisionId = divisions[i]
			comp.participants :+ [participant]
		Next

		Local schedule:TLeagueScheduleConfig = New TLeagueScheduleConfig
		Local rule:TMatchupRule = AddRule(schedule, divisions, Null, EMatchupMode.RotatingDivisionPairs)
		Local scheduler:TLeagueScheduler = New TLeagueScheduler
		Local stage:TStage = New TStage
		stage.id = "ROTATION"
		Local pairs:TStringMap = New TStringMap
		Local distinct:Int
		For Local season:Int = 0 Until 5
			schedule.rotationSeed = season
			Local fixtures:TFixtureState[] = scheduler.BuildRuleFixtures(comp, stage, schedule)
			AssertEquals(3, fixtures.Length)
			Local appearances:Int[] = New Int[7]
			For Local fixture:TFixtureState = EachIn fixtures
				appearances[fixture.homeTeamId] :+ 1
				appearances[fixture.awayTeamId] :+ 1
				Local low:Int = Min(fixture.homeTeamId, fixture.awayTeamId)
				Local high:Int = Max(fixture.homeTeamId, fixture.awayTeamId)
				Local key:String = low + "-" + high
				If Not pairs.Contains(key) Then
					distinct :+ 1
				End If

				pairs.Insert(key, "1")
			Next

			For Local id:Int = 1 To 6
				AssertEquals(1, appearances[id])
			Next
		Next

		AssertEquals(15, distinct)
		rule.sourceDivisionIds = ["D0", "D1", "D2"]
		Local rejected:Int
		Try
			scheduler.BuildRuleFixtures(comp, stage, schedule)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "An odd division pool cannot form complete pairs")
	End Method

	Method testRotatingAndRankMatchedOpponentFormula() { test }
		Local comp:TCompetition = New TCompetition
		Local schedule:TLeagueScheduleConfig = New TLeagueScheduleConfig
		Local stage:TStage = New TStage
		stage.id = "FORMULA"
		Local allA:String[] = ["A0", "A1", "A2", "A3"]
		Local allB:String[] = ["B0", "B1", "B2", "B3"]
		For Local division:Int = 0 Until 8
			Local name:String = "A" + division
			If division >= 4 Then
				name = "B" + (division - 4)
			End If

			Local entry:TDivision = New TDivision
			entry.id = name
			schedule.divisions :+ [entry]
			For Local rank:Int = 1 To 4
				Local participant:TParticipant = New TParticipant
				participant.id = division * 4 + rank
				participant.divisionId = name
				participant.previousRank = rank
				comp.participants :+ [participant]
			Next

			AddRule(schedule, [name], [name], EMatchupMode.AllPairs, 2)
		Next

		AddRule(schedule, allA, Null, EMatchupMode.RotatingDivisionPairs)
		AddRule(schedule, allB, Null, EMatchupMode.RotatingDivisionPairs)
		AddRule(schedule, allA, allB, EMatchupMode.RotatingDivision)
		Local aRank:TMatchupRule = AddRule(schedule, allA, allA, EMatchupMode.SameRank)
		aRank.excludeAlreadyScheduled = True
		Local bRank:TMatchupRule = AddRule(schedule, allB, allB, EMatchupMode.SameRank)
		bRank.excludeAlreadyScheduled = True
		Local crossRank:TMatchupRule = AddRule(schedule, allA, allB, EMatchupMode.RotatingDivision)
		crossRank.rotationOffset = 1
		crossRank.sameRankOnly = True
		crossRank.excludeAlreadyScheduled = True
		schedule.totalGamesPerTeam = 17
		schedule.balanceHomeAway = True
		Local scheduler:TLeagueScheduler = New TLeagueScheduler
		Local fixtures:TFixtureState[] = scheduler.BuildRuleFixtures(comp, stage, schedule)
		scheduler.ValidateGameCounts(comp, schedule, fixtures)
		AssertEquals(272, fixtures.Length)
		For Local participant:TParticipant = EachIn comp.participants
			Local games:Int
			Local homeGames:Int
			Local opponents:TStringMap = New TStringMap
			Local distinct:Int
			Local crossConference:Int
			For Local fixture:TFixtureState = EachIn fixtures
				Local opponent:Int
				If fixture.homeTeamId = participant.id Then
					opponent = fixture.awayTeamId
				End If

				If fixture.awayTeamId = participant.id Then
					opponent = fixture.homeTeamId
				End If

				If opponent = 0 Then
					Continue
				End If

				games :+ 1
				If fixture.homeTeamId = participant.id Then
					homeGames :+ 1
				End If

				If Not opponents.Contains(String(opponent)) Then
					distinct :+ 1
				End If

				opponents.Insert(String(opponent), "1")
				If (participant.id <= 16 And opponent > 16) Or (participant.id > 16 And opponent <= 16) Then
					crossConference :+ 1
				End If
			Next

			AssertEquals(17, games)
			AssertTrue(homeGames = 8 Or homeGames = 9, "Generated games should balance home assignments")
			AssertEquals(14, distinct)
			AssertEquals(5, crossConference)
			Local ownDivision:Int = (participant.id - 1) / 4
			For Local opponentRank:Int = 1 To 4
				Local opponentId:Int = ownDivision * 4 + opponentRank
				If opponentId = participant.id Then
					Continue
				End If

				Local hosted:Int
				Local visited:Int
				For Local fixture:TFixtureState = EachIn fixtures
					If fixture.homeTeamId = participant.id And fixture.awayTeamId = opponentId Then
						hosted :+ 1
					End If

					If fixture.homeTeamId = opponentId And fixture.awayTeamId = participant.id Then
						visited :+ 1
					End If
				Next

				AssertEquals(1, hosted)
				AssertEquals(1, visited)
			Next
		Next

		Local firstYear:String
		For Local fixture:TFixtureState = EachIn fixtures
			If fixture.homeTeamId = 1 And fixture.awayTeamId > 16 Then
				firstYear :+ fixture.awayTeamId + ","
			End If

			If fixture.awayTeamId = 1 And fixture.homeTeamId > 16 Then
				firstYear :+ fixture.homeTeamId + ","
			End If
		Next

		schedule.rotationSeed = 1
		Local rotated:TFixtureState[] = scheduler.BuildRuleFixtures(comp, stage, schedule)
		scheduler.ValidateGameCounts(comp, schedule, rotated)
		Local secondYear:String
		For Local fixture:TFixtureState = EachIn rotated
			If fixture.homeTeamId = 1 And fixture.awayTeamId > 16 Then
				secondYear :+ fixture.awayTeamId + ","
			End If

			If fixture.awayTeamId = 1 And fixture.homeTeamId > 16 Then
				secondYear :+ fixture.homeTeamId + ","
			End If
		Next

		AssertTrue(firstYear <> secondYear, "Rotation should change cross-conference opponents")
		Local fullDivisionSeen:Int[] = New Int[4]
		For Local season:Int = 0 Until 3
			schedule.rotationSeed = season
			Local seasonFixtures:TFixtureState[] = scheduler.BuildRuleFixtures(comp, stage, schedule)
			scheduler.ValidateGameCounts(comp, schedule, seasonFixtures)
			Local divisionGames:Int[] = New Int[4]
			For Local fixture:TFixtureState = EachIn seasonFixtures
				Local opponent:Int
				If fixture.homeTeamId = 1 Then
					opponent = fixture.awayTeamId
				End If

				If fixture.awayTeamId = 1 Then
					opponent = fixture.homeTeamId
				End If

				If opponent >= 5 And opponent <= 16 Then
					divisionGames[(opponent - 1) / 4] :+ 1
				End If
			Next

			For Local division:Int = 1 To 3
				If divisionGames[division] = 4 Then
					fullDivisionSeen[division] :+ 1
				End If

				AssertTrue(divisionGames[division] = 1 Or divisionGames[division] = 4)
			Next
		Next

		For Local division:Int = 1 To 3
			AssertEquals(1, fullDivisionSeen[division])
		Next
	End Method
End Type

Type TLeagueRematchSpacingTest Extends TTest
	Method testFixedLengthRequiresAnInterveningWeek() { test }
		Local schedule:TLeagueScheduleConfig = New TLeagueScheduleConfig
		schedule.weeks = 3
		schedule.minWeeksBetweenMeetings = 1
		Local first:TFixtureState = New TFixtureState
		first.id = "first"; first.homeTeamId = 1; first.awayTeamId = 2; first.round = 1
		Local second:TFixtureState = New TFixtureState
		second.id = "second"; second.homeTeamId = 2; second.awayTeamId = 1
		Local allocator:TLeagueWeekAllocator = New TLeagueWeekAllocator
		allocator.Assign(New TCompetition, schedule, [first, second])
		AssertEquals(3, second.round)
		schedule.weeks = 2
		second.round = 0
		Local rejected:Int
		Try
			allocator.Assign(New TCompetition, schedule, [first, second])
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Two meetings need at least three weeks")
		AssertEquals(0, second.round)
		second.round = 2
		rejected = False
		Try
			allocator.Assign(New TCompetition, schedule, [first, second])
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Pinned consecutive meetings must be rejected")
	End Method

	Method testOpenEndedAllocatorStillChecksGapAndBye() { test }
		Local schedule:TLeagueScheduleConfig = New TLeagueScheduleConfig
		schedule.minWeeksBetweenMeetings = 1
		Local bye:TParticipantByeWeek = New TParticipantByeWeek
		bye.participantId = 1; bye.week = 3
		schedule.byeWeeks = [bye]
		Local first:TFixtureState = New TFixtureState
		first.homeTeamId = 1; first.awayTeamId = 2; first.round = 1
		Local second:TFixtureState = New TFixtureState
		second.homeTeamId = 2; second.awayTeamId = 1
		(New TLeagueWeekAllocator).Assign(New TCompetition, schedule, [first, second])
		AssertEquals(4, second.round)
	End Method
End Type

Type TSwissProgressionTest Extends TTest
	Function Competition:TCompetition(count:Int, rounds:Int)
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To count
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.seedRank = id
			comp.participants :+ [participant]
		Next

		Local stage:TStage = New TStage
		stage.id = "SWISS"
		stage.stageType = EStageType.Swiss
		stage.config = New TSwissConfig
		TSwissConfig(stage.config).rounds = rounds
		comp.stages = [stage]
		Return comp
	End Function

	Function Engine:TCompetitionEngine()
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Swiss, New TSwissScheduler)
		engine.RegisterScorer(EStageType.Swiss, New TSwissScorer)
		Return engine
	End Function

	Method testRoundsUseResultsAndSurviveStateRoundTrip() { test }
		Local comp:TCompetition = Competition(4, 3)
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(2, state.stages[0].fixtures.Length)
		AssertEquals(1, state.stages[0].fixtures[0].round)
		engine.RecordResultAndAdvance(comp, state, "SWISS", state.stages[0].fixtures[0].id, 1, 0)
		engine.RecordResultAndAdvance(comp, state, "SWISS", state.stages[0].fixtures[1].id, 1, 0)
		AssertEquals(4, state.stages[0].fixtures.Length)
		AssertEquals(2, state.stages[0].fixtures[2].round)
		Local winnerPair:TFixtureState = state.stages[0].fixtures[2]
		AssertEquals(1, Min(winnerPair.homeTeamId, winnerPair.awayTeamId))
		AssertEquals(3, Max(winnerPair.homeTeamId, winnerPair.awayTeamId))
		Local jconv:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local path:String = "rt_swiss_state.json"
		Local output:TStream = WriteStream(path)
		jconv.ToJson(state, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		state = TCompetitionState(jconv.FromJson(input, "TCompetitionState"))
		input.Close()
		DeleteFile(path)
		AssertEquals("buchholz", state.stages[0].leaderboard.rows[0].metrics[0].code)
		For Local i:Int = 2 To 3
			engine.RecordResultAndAdvance(comp, state, "SWISS", state.stages[0].fixtures[i].id, 1, 0)
		Next

		AssertEquals(6, state.stages[0].fixtures.Length)
		For Local i:Int = 4 To 5
			engine.RecordResultAndAdvance(comp, state, "SWISS", state.stages[0].fixtures[i].id, 1, 0)
		Next

		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		Local pairings:TStringMap = New TStringMap
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
			Local low:Int = Min(fixture.homeTeamId, fixture.awayTeamId)
			Local high:Int = Max(fixture.homeTeamId, fixture.awayTeamId)
			Local key:String = low + "-" + high
			AssertTrue(Not pairings.Contains(key), "Swiss should avoid rematches")
			pairings.Insert(key, "1")
		Next
	End Method

	Method testOddFieldRotatesPairingByes() { test }
		Local comp:TCompetition = Competition(5, 3)
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local byeRecipients:TStringMap = New TStringMap
		For Local round:Int = 1 To 3
			Local byeCount:Int
			Local games:Int
			Local playable:String[]
			For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
				If fixture.round <> round Then
					Continue
				End If

				If fixture.awayTeamId = 0 Then
					byeCount :+ 1
					AssertTrue(Not byeRecipients.Contains(String(fixture.homeTeamId)))
					byeRecipients.Insert(String(fixture.homeTeamId), "1")
					Local byePoints:Int = -1
					For Local row:TLeaderboardRow = EachIn state.stages[0].leaderboard.rows
						If row.participantId = fixture.homeTeamId Then
							byePoints = row.points
						End If
					Next

					AssertTrue(byePoints >= 2, "A pairing bye should award the configured point")
				Else
					games :+ 1
					playable :+ [fixture.id]
				End If
			Next

			AssertEquals(1, byeCount)
			AssertEquals(2, games)
			For Local id:String = EachIn playable
				engine.RecordResultAndAdvance(comp, state, "SWISS", id, 1, 0)
			Next
		Next

		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
	End Method

	Method testPairingFailureCanBeRetriedAfterChangingRule() { test }
		Local comp:TCompetition = Competition(2, 2)
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local rejected:Int
		Try
			engine.RecordResultAndAdvance(comp, state, "SWISS", state.stages[0].fixtures[0].id, 1, 0)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "A second round cannot avoid a rematch with only two entrants")
		AssertEquals(EFixtureStatus.Completed.Ordinal(), state.stages[0].fixtures[0].status.Ordinal())
		AssertEquals(1, state.stages[0].fixtures.Length)
		TSwissConfig(comp.stages[0].config).avoidRematches = False
		AssertTrue(engine.GenerateNextRound(comp, state, "SWISS"))
		AssertEquals(2, state.stages[0].fixtures.Length)
		engine.RecordResultAndAdvance(comp, state, "SWISS", state.stages[0].fixtures[1].id, 0, 0)
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(3, state.stages[0].leaderboard.rows[0].points)
	End Method

	Method testByesDoNotConsumeCalendarSlots() { test }
		Local comp:TCompetition = Competition(5, 2)
		Local stage:TStage = comp.stages[0]
		stage.schedule = New TSchedulePolicy
		stage.schedule.calendar = New TCalendar
		For Local round:Int = 1 To 2
			For Local game:Int = 1 To 2
				Local slot:TSlot = New TSlot
				slot.id = "R" + round + "G" + game
				slot.round = round
				slot.dateTime = "2026-11-" + (round * 2 + game) + "T12:00:00Z"
				stage.schedule.calendar.slots :+ [slot]
			Next
		Next

		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local firstRoundGames:String[]
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
			If fixture.awayTeamId = 0 Then
				AssertEquals("", fixture.slotId)
			Else
				AssertTrue(fixture.slotId <> "")
				firstRoundGames :+ [fixture.id]
			End If
		Next

		For Local id:String = EachIn firstRoundGames
			engine.RecordResultAndAdvance(comp, state, "SWISS", id, 1, 0)
		Next

		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
			If fixture.round <> 2 Then
				Continue
			End If

			If fixture.awayTeamId = 0 Then
				AssertEquals("", fixture.slotId)
			Else
				AssertTrue(fixture.slotId <> "")
			End If
		Next
	End Method

	Method testSwissConfigRoundTrip() { test }
		Local comp:TCompetition = Competition(5, 3)
		Local cfg:TSwissConfig = TSwissConfig(comp.stages[0].config)
		cfg.pointsScale = 4
		cfg.pointsDraw = 0.25
		cfg.byePoints = 0.75
		cfg.pointsDrawExact = "0.25"
		cfg.byePointsExact = "0.75"
		cfg.tiebreaks = [ESwissTieBreak.Buchholz, ESwissTieBreak.BuchholzCut1]
		cfg.pairingPolicy = New TSwissPairingPolicy
		cfg.pairingPolicy.system = ESwissPairingSystem.DutchStyle
		cfg.pairingPolicy.initialColour = -1
		Local planned:TSwissPlannedUnplayed = New TSwissPlannedUnplayed
		planned.participantId = 2
		planned.round = 2
		planned.kind = ESwissUnplayedKind.RequestedBye
		planned.awardedPoints = 0.25
		planned.awardedPointsExact = "0.25"
		cfg.plannedUnplayed = [planned]
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local path:String = "rt_swiss_competition.json"
		Local output:TStream = WriteStream(path)
		jconv.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		Local loaded:TCompetition = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		Local restored:TSwissConfig = TSwissConfig(loaded.stages[0].config)
		AssertEquals(3, restored.rounds)
		AssertEquals(4, restored.pointsScale)
		AssertEquals(1, SwissUnits(restored.pointsDraw, restored.pointsScale))
		AssertEquals(3, SwissUnits(restored.byePoints, restored.pointsScale))
		AssertEquals("0.25", restored.pointsDrawExact)
		AssertEquals(1, SwissDrawUnits(restored))
		AssertEquals(3, SwissByeUnits(restored))
		AssertEquals(ESwissTieBreak.Buchholz.Ordinal(), restored.tiebreaks[0].Ordinal())
		AssertEquals(ESwissPairingSystem.DutchStyle.Ordinal(), restored.pairingPolicy.system.Ordinal())
		AssertEquals(-1, restored.pairingPolicy.initialColour)
		AssertEquals(1, restored.plannedUnplayed.Length)
		AssertEquals(2, restored.plannedUnplayed[0].participantId)
		AssertEquals("0.25", restored.plannedUnplayed[0].awardedPointsExact)
		AssertEquals(1, SwissPlannedUnits(restored.plannedUnplayed[0], restored))
		AssertEquals(ESwissUnplayedKind.RequestedBye.Ordinal(), restored.plannedUnplayed[0].kind.Ordinal())
	End Method

	Method testPlannedByeExcludesEntrantAndPersistsAward() { test }
		Local comp:TCompetition = Competition(5, 1)
		Local cfg:TSwissConfig = TSwissConfig(comp.stages[0].config)
		Local planned:TSwissPlannedUnplayed = New TSwissPlannedUnplayed
		planned.participantId = 1
		planned.round = 1
		planned.kind = ESwissUnplayedKind.RequestedBye
		planned.awardedPoints = cfg.pointsDraw
		cfg.plannedUnplayed = [planned]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(3, state.stages[0].fixtures.Length)
		Local bye:TFixtureState = state.stages[0].fixtures[0]
		AssertEquals(1, bye.homeTeamId)
		AssertEquals(0, bye.awayTeamId)
		AssertEquals(ESwissUnplayedKind.RequestedBye.Ordinal(), bye.swissUnplayedKind.Ordinal())
		AssertEquals(1, bye.swissAwardedUnits)
		AssertEquals(1, TSwissBuchholzTest.Row(state.stages[0], 1).points)
		Local jconv:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local path:String = "rt_swiss_unplayed.json"
		Local output:TStream = WriteStream(path)
		jconv.ToJson(state, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		state = TCompetitionState(jconv.FromJson(input, "TCompetitionState"))
		input.Close()
		DeleteFile(path)
		AssertEquals(ESwissUnplayedKind.RequestedBye.Ordinal(), state.stages[0].fixtures[0].swissUnplayedKind.Ordinal())
		AssertEquals(1, state.stages[0].fixtures[0].swissAwardedUnits)
	End Method

	Method testWithdrawalCarriesIntoLaterRounds() { test }
		Local comp:TCompetition = Competition(4, 3)
		Local cfg:TSwissConfig = TSwissConfig(comp.stages[0].config)
		cfg.avoidRematches = False
		Local planned:TSwissPlannedUnplayed = New TSwissPlannedUnplayed
		planned.participantId = 4
		planned.round = 2
		planned.kind = ESwissUnplayedKind.Withdrawal
		cfg.plannedUnplayed = [planned]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		For Local round:Int = 1 To 2
			Local games:String[]
			For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
				If fixture.round = round And fixture.awayTeamId <> 0 Then
					games :+ [fixture.id]
				End If
			Next

			For Local id:String = EachIn games
				engine.RecordResultAndAdvance(comp, state, "SWISS", id, 1, 0)
			Next
		Next

		Local withdrawalCount:Int
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
			If fixture.homeTeamId = 4 And fixture.awayTeamId = 0 And fixture.swissUnplayedKind = ESwissUnplayedKind.Withdrawal Then
				withdrawalCount :+ 1
			End If
		Next

		AssertEquals(2, withdrawalCount)
	End Method

	Method testDutchStyleStartsWithHalfSplitAndAlternatingInitialColours() { test }
		Local comp:TCompetition = Competition(8, 3)
		Local cfg:TSwissConfig = TSwissConfig(comp.stages[0].config)
		cfg.pairingPolicy = New TSwissPairingPolicy
		cfg.pairingPolicy.system = ESwissPairingSystem.DutchStyle
		cfg.pairingPolicy.initialColour = 1
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(4, state.stages[0].fixtures.Length)
		For Local i:Int = 0 Until 4
			Local fixture:TFixtureState = state.stages[0].fixtures[i]
			AssertEquals(i + 1, Min(fixture.homeTeamId, fixture.awayTeamId))
			AssertEquals(i + 5, Max(fixture.homeTeamId, fixture.awayTeamId))
			If i Mod 2 = 0 Then
				AssertEquals(i + 1, fixture.homeTeamId)
			Else
				AssertEquals(i + 1, fixture.awayTeamId)
			End If
		Next
	End Method

	Method testDutchStyleTransposesToAvoidRematch() { test }
		Local comp:TCompetition = Competition(4, 2)
		Local cfg:TSwissConfig = TSwissConfig(comp.stages[0].config)
		cfg.pairingPolicy = New TSwissPairingPolicy
		cfg.pairingPolicy.system = ESwissPairingSystem.DutchStyle
		cfg.avoidRematches = False
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures[..]
			engine.RecordResultAndAdvance(comp, state, "SWISS", fixture.id, 0, 0)
		Next

		AssertEquals(4, state.stages[0].fixtures.Length)
		AssertEquals(1, Min(state.stages[0].fixtures[2].homeTeamId, state.stages[0].fixtures[2].awayTeamId))
		AssertEquals(4, Max(state.stages[0].fixtures[2].homeTeamId, state.stages[0].fixtures[2].awayTeamId))
		AssertEquals(2, Min(state.stages[0].fixtures[3].homeTeamId, state.stages[0].fixtures[3].awayTeamId))
		AssertEquals(3, Max(state.stages[0].fixtures[3].homeTeamId, state.stages[0].fixtures[3].awayTeamId))
	End Method

	Method testDutchStyleRejectsMatchingAbsoluteColourPreferences() { test }
		Local scheduler:TSwissScheduler = New TSwissScheduler
		Local cfg:TSwissConfig = New TSwissConfig
		cfg.rounds = 4
		Local state:TStageState = New TStageState
		state.fixtures = [TSwissBuchholzTest.Fixture(1, 1, 3, 1, 0), TSwissBuchholzTest.Fixture(1, 2, 4, 1, 0), TSwissBuchholzTest.Fixture(2, 1, 4, 1, 0), TSwissBuchholzTest.Fixture(2, 2, 3, 1, 0)]
		AssertEquals(-1, scheduler.AbsoluteColourPreference(state, 1))
		AssertEquals(-1, scheduler.AbsoluteColourPreference(state, 2))
		AssertTrue(Not scheduler.DutchColourCompatible(state, 1, 2, cfg, 3))
	End Method

	Method testDutchStyleByePrefersLowestScoreAndSeedNumberSetsColour() { test }
		Local comp:TCompetition = Competition(5, 2)
		Local cfg:TSwissConfig = TSwissConfig(comp.stages[0].config)
		cfg.pairingPolicy = New TSwissPairingPolicy
		cfg.pairingPolicy.system = ESwissPairingSystem.DutchStyle
		Local state:TCompetitionState = Engine().Initialize(comp)
		Local byeId:Int
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
			If fixture.awayTeamId = 0 Then
				byeId = fixture.homeTeamId
			End If
		Next

		AssertEquals(5, byeId)
		Local requested:TSwissPlannedUnplayed = New TSwissPlannedUnplayed
		requested.participantId = 1
		requested.round = 1
		requested.kind = ESwissUnplayedKind.RequestedBye
		cfg.plannedUnplayed = [requested]
		state = Engine().Initialize(comp)
		Local first:TFixtureState = state.stages[0].fixtures[1]
		AssertEquals(2, first.awayTeamId)
	End Method
End Type

Type TSwissBuchholzTest Extends TTest
	Function Fixture:TFixtureState(round:Int, home:Int, away:Int, homeScore:Int, awayScore:Int)
		Local fixture:TFixtureState = New TFixtureState
		fixture.round = round
		fixture.homeTeamId = home
		fixture.awayTeamId = away
		fixture.scoreHome = homeScore
		fixture.scoreAway = awayScore
		fixture.status = EFixtureStatus.Completed
		Return fixture
	End Function

	Function Row:TLeaderboardRow(state:TStageState, id:Int)
		For Local row:TLeaderboardRow = EachIn state.leaderboard.rows
			If row.participantId = id Then
				Return row
			End If
		Next

		Return Null
	End Function

	Function Unplayed:TFixtureState(round:Int, id:Int, kind:ESwissUnplayedKind, units:Int)
		Local fixture:TFixtureState = Fixture(round, id, 0, 0, 0)
		fixture.swissUnplayedKind = kind
		fixture.swissAwardedUnits = units
		Return fixture
	End Function

	Function Forfeit:TFixtureState(round:Int, home:Int, away:Int, homeScore:Int, awayScore:Int)
		Local fixture:TFixtureState = Fixture(round, home, away, homeScore, awayScore)
		Local result:TResultPayload = New TResultPayload
		result.forfeit = True
		fixture.resultLog = [result]
		Return fixture
	End Function

	Method testOpponentsScoresBreakEqualPoints() { test }
		Local stage:TStage = New TStage
		stage.config = New TSwissConfig
		Local cfg:TSwissConfig = TSwissConfig(stage.config)
		cfg.rounds = 3
		cfg.tiebreaks = [ESwissTieBreak.Buchholz]
		Local state:TStageState = New TStageState
		state.entrants = [1, 2, 3, 4, 5, 6]
		state.leaderboard = New TLeaderboard
		state.fixtures = [Fixture(1, 1, 2, 1, 0), Fixture(1, 3, 4, 1, 0), Fixture(1, 5, 6, 1, 0), Fixture(2, 1, 3, 1, 0), Fixture(2, 2, 5, 1, 0), Fixture(2, 4, 6, 1, 0), Fixture(3, 1, 4, 1, 0), Fixture(3, 3, 5, 1, 0), Fixture(3, 2, 6, 1, 0)]
		Local scorer:TSwissScorer = New TSwissScorer
		scorer.ComputeStandings(New TCompetition, stage, state)
		AssertEquals(2, Row(state, 4).points)
		AssertEquals(2, Row(state, 5).points)
		AssertEquals(10, scorer.Metric(Row(state, 4), "buchholz"))
		AssertEquals(8, scorer.Metric(Row(state, 5), "buchholz"))
		AssertEquals(4, Row(state, 3).points)
		AssertEquals(4, Row(state, 2).points)
		AssertEquals(3, state.leaderboard.rows[1].participantId)
		AssertEquals(2, state.leaderboard.rows[2].participantId)
	End Method

	Method testPairingByeUsesCappedDummyScore() { test }
		Local stage:TStage = New TStage
		stage.config = New TSwissConfig
		Local cfg:TSwissConfig = TSwissConfig(stage.config)
		cfg.rounds = 2
		cfg.tiebreaks = [ESwissTieBreak.Buchholz, ESwissTieBreak.BuchholzCut1]
		Local state:TStageState = New TStageState
		state.entrants = [1, 2, 3]
		state.leaderboard = New TLeaderboard
		state.fixtures = [Fixture(1, 1, 0, 0, 0), Fixture(1, 2, 3, 1, 0), Fixture(2, 1, 2, 1, 0), Fixture(2, 3, 0, 0, 0)]
		Local scorer:TSwissScorer = New TSwissScorer
		scorer.ComputeStandings(New TCompetition, stage, state)
		AssertEquals(4, Row(state, 1).points)
		AssertEquals(4, scorer.Metric(Row(state, 1), "buchholz"))
		AssertEquals(2, scorer.Metric(Row(state, 1), "buchholzCut1"))
		AssertEquals(6, scorer.Metric(Row(state, 2), "buchholz"))
	End Method

	Method testFinalRequestedByeAdjustsOpponentScoreAndCutOne() { test }
		Local stage:TStage = New TStage
		stage.config = New TSwissConfig
		Local cfg:TSwissConfig = TSwissConfig(stage.config)
		cfg.rounds = 3
		Local state:TStageState = New TStageState
		state.entrants = [1, 2, 3, 4]
		state.leaderboard = New TLeaderboard
		state.fixtures = [Fixture(1, 1, 2, 1, 0), Fixture(1, 3, 4, 1, 0), Fixture(2, 1, 3, 1, 0), Fixture(2, 2, 4, 1, 0), Unplayed(3, 2, ESwissUnplayedKind.RequestedBye, 0), Fixture(3, 1, 4, 1, 0), Unplayed(3, 3, ESwissUnplayedKind.Withdrawal, 0)]
		Local scorer:TSwissScorer = New TSwissScorer
		scorer.ComputeStandings(New TCompetition, stage, state)
		AssertEquals(2, Row(state, 2).points)
		AssertEquals(3, scorer.AdjustedScore(state.leaderboard.rows, state.fixtures, 2, cfg))
		AssertEquals(6, scorer.Metric(Row(state, 1), "buchholz"))
		AssertEquals(6, scorer.Metric(Row(state, 2), "buchholzCut1"))
	End Method

	Method testEarlierRequestedByeKeepsAwardedScoreAfterPlay() { test }
		Local stage:TStage = New TStage
		stage.config = New TSwissConfig
		Local cfg:TSwissConfig = TSwissConfig(stage.config)
		cfg.rounds = 2
		Local state:TStageState = New TStageState
		state.entrants = [1, 2]
		state.leaderboard = New TLeaderboard
		state.fixtures = [Unplayed(1, 1, ESwissUnplayedKind.RequestedBye, 1), Fixture(2, 1, 2, 1, 0)]
		Local scorer:TSwissScorer = New TSwissScorer
		scorer.ComputeStandings(New TCompetition, stage, state)
		AssertEquals(3, scorer.AdjustedScore(state.leaderboard.rows, state.fixtures, 1, cfg))
	End Method

	Method testForfeitContributionIsCappedAndCutOnePrefersForfeitLoss() { test }
		Local stage:TStage = New TStage
		stage.config = New TSwissConfig
		Local cfg:TSwissConfig = TSwissConfig(stage.config)
		cfg.rounds = 2
		Local state:TStageState = New TStageState
		state.entrants = [1, 2, 3]
		state.leaderboard = New TLeaderboard
		state.fixtures = [Forfeit(1, 1, 2, 1, 0), Fixture(1, 3, 2, 1, 0), Fixture(2, 1, 3, 1, 0)]
		Local scorer:TSwissScorer = New TSwissScorer
		scorer.ComputeStandings(New TCompetition, stage, state)
		AssertEquals(2, scorer.Metric(Row(state, 1), "buchholzCut1"))
		AssertEquals(2, scorer.Metric(Row(state, 2), "buchholzCut1"))
	End Method
End Type

Type TStrokePlayTest Extends TTest
	Method testAggregateGrossRoundTotalSurvivesSerialization() { test }
		Local comp:TCompetition = SmallCompetition(2, 18)
		Local first:TStrokeScorecard = New TStrokeScorecard
		first.participantId = 1
		first.roundStrokes = 72
		Local second:TStrokeScorecard = New TStrokeScorecard
		second.participantId = 2
		second.roundStrokes = 69
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Result([first, second]))
		AssertEquals(2, state.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(69, state.stages[0].strokeStandings[0].strokes)
		AssertEquals(18, TStrokePlayConfig(comp.stages[0].config).rounds[0].holeCount)
		AssertEquals(69, state.stages[0].strokeStandings[0].roundValues[0].roundStrokes)
		AssertTrue(state.stages[0].strokeStandings[0].roundValues[0].holes = Null)
		Local serialized:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local path:String = "rt_stroke_round_total_state.json"
		Local output:TStream = WriteStream(path)
		serialized.ToJson(state, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		state = TCompetitionState(serialized.FromJson(input, "TCompetitionState"))
		input.Close()
		DeleteFile(path)
		AssertEquals(72, state.stages[0].fixtures[0].strokeCards[0].roundStrokes)
		AssertEquals(69, state.stages[0].strokeStandings[0].roundValues[0].roundStrokes)
	End Method

	Method testAggregateRoundRejectsMissingHoleDetailForCountback() { test }
		Local comp:TCompetition = SmallCompetition(2, 18)
		Local cfg:TStrokePlayConfig = TStrokePlayConfig(comp.stages[0].config)
		Local segment:TStrokeCountbackSegment = New TStrokeCountbackSegment
		segment.lastHoles = 9
		cfg.countback = [segment]
		Local first:TStrokeScorecard = New TStrokeScorecard
		first.participantId = 1
		first.roundStrokes = 72
		Local second:TStrokeScorecard = New TStrokeScorecard
		second.participantId = 2
		second.roundStrokes = 69
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local rejected:Int
		Try
			engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Result([first, second]))
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected)
		AssertEquals(EFixtureStatus.Scheduled.Ordinal(), state.stages[0].fixtures[0].status.Ordinal())
	End Method

	Function SmallCompetition:TCompetition(players:Int, holeCount:Int)
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To players
			Local participant:TParticipant = New TParticipant
			participant.id = id
			comp.participants :+ [participant]
		Next

		Local stage:TStage = New TStage
		stage.id = "GOLF"
		stage.stageType = EStageType.Qualifying
		stage.formatCode = "stroke-play"
		Local cfg:TStrokePlayConfig = New TStrokePlayConfig
		Local round:TStrokePlayRoundConfig = New TStrokePlayRoundConfig
		round.holeCount = holeCount
		For Local i:Int = 0 Until holeCount
			round.pars :+ [4]
		Next

		cfg.rounds = [round]
		stage.config = cfg
		comp.stages = [stage]
		Return comp
	End Function

	Function Card:TStrokeScorecard(id:Int, holes:Int[])
		Local card:TStrokeScorecard = New TStrokeScorecard
		card.participantId = id
		card.holes = holes
		Return card
	End Function

	Function Result:TResultPayload(cards:TStrokeScorecard[])
		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.Custom
		result.customCode = "stroke-play-card"
		result.strokeCards = cards
		Return result
	End Function

	Method testNetHandicapChangesGrossOrder() { test }
		Local comp:TCompetition = SmallCompetition(2, 2)
		Local cfg:TStrokePlayConfig = TStrokePlayConfig(comp.stages[0].config)
		cfg.scoring = EStrokeScoringMode.Net
		Local handicap:TStrokeHandicap = New TStrokeHandicap
		handicap.participantId = 2
		handicap.received = [2, 0]
		cfg.rounds[0].handicaps = [handicap]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Result([Card(1, [4, 4]), Card(2, [5, 4])]))
		AssertEquals(2, state.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(9, state.stages[0].strokeStandings[0].strokes)
		AssertEquals(7, state.stages[0].strokeStandings[0].netStrokes)
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
	End Method

	Method testPlayingHandicapFollowsStrokeIndexes() { test }
		Local comp:TCompetition = SmallCompetition(3, 2)
		Local cfg:TStrokePlayConfig = TStrokePlayConfig(comp.stages[0].config)
		cfg.scoring = EStrokeScoringMode.Net
		cfg.rounds[0].strokeIndexes = [2, 1]
		Local receiving:TStrokeHandicap = New TStrokeHandicap
		receiving.participantId = 2
		receiving.playingHandicap = 1
		Local giving:TStrokeHandicap = New TStrokeHandicap
		giving.participantId = 3
		giving.playingHandicap = -1
		cfg.rounds[0].handicaps = [receiving, giving]
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local path:String = "rt_stroke_handicap_comp.json"
		Local output:TStream = WriteStream(path)
		jconv.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		comp = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		cfg = TStrokePlayConfig(comp.stages[0].config)
		AssertEquals(EStrokeScoringMode.Net.Ordinal(), cfg.scoring.Ordinal())
		AssertEquals(1, cfg.rounds[0].handicaps[0].playingHandicap)
		AssertEquals(2, cfg.rounds[0].strokeIndexes[0])
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Result([Card(1, [5, 5]), Card(2, [4, 5]), Card(3, [3, 5])]))
		AssertEquals(2, state.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(8, state.stages[0].strokeStandings[0].netStrokes)
		AssertEquals(9, state.stages[0].strokeStandings[1].netStrokes)
	End Method

	Method testStablefordCountsPickupAsZeroPoints() { test }
		Local comp:TCompetition = SmallCompetition(2, 2)
		TStrokePlayConfig(comp.stages[0].config).scoring = EStrokeScoringMode.Stableford
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Result([Card(1, [3, 4]), Card(2, [3, 0])]))
		AssertEquals(1, state.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(5, state.stages[0].strokeStandings[0].points)
		AssertEquals(3, state.stages[0].strokeStandings[1].points)
	End Method

	Method testStablefordBandsAndPlayoffPoints() { test }
		Local comp:TCompetition = SmallCompetition(2, 2)
		Local cfg:TStrokePlayConfig = TStrokePlayConfig(comp.stages[0].config)
		cfg.scoring = EStrokeScoringMode.Stableford
		Local birdie:TStrokePointBand = New TStrokePointBand
		birdie.maxRelativeToPar = -1
		birdie.points = 3
		Local par:TStrokePointBand = New TStrokePointBand
		par.maxRelativeToPar = 0
		par.points = 2
		Local bogey:TStrokePointBand = New TStrokePointBand
		bogey.maxRelativeToPar = 1
		bogey.points = 1
		cfg.stablefordBands = [birdie, par, bogey]
		cfg.playoffRound = New TStrokePlayRoundConfig
		cfg.playoffRound.holeCount = 1
		cfg.playoffRound.pars = [4]
		cfg.playoffScoring = EStrokeScoringMode.Stableford
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Result([Card(1, [4, 4]), Card(2, [3, 5])]))
		AssertEquals(4, state.stages[0].strokeStandings[0].points)
		AssertEquals(2, state.stages[0].fixtures[1].participantIds.Length)
		engine.RecordResult(comp, state, "GOLF", "GOLF_PLAYOFF_1", Result([Card(1, [4]), Card(2, [3])]))
		AssertEquals(2, state.stages[0].strokePlayWinnerId)
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
	End Method

	Method testNetPlayoffUsesConfiguredHoleAllowance() { test }
		Local comp:TCompetition = SmallCompetition(2, 2)
		Local cfg:TStrokePlayConfig = TStrokePlayConfig(comp.stages[0].config)
		cfg.scoring = EStrokeScoringMode.Net
		Local regular:TStrokeHandicap = New TStrokeHandicap
		regular.participantId = 2
		regular.received = [1, 0]
		cfg.rounds[0].handicaps = [regular]
		cfg.playoffRound = New TStrokePlayRoundConfig
		cfg.playoffRound.holeCount = 1
		cfg.playoffRound.pars = [4]
		Local extra:TStrokeHandicap = New TStrokeHandicap
		extra.participantId = 2
		extra.received = [1]
		cfg.playoffRound.handicaps = [extra]
		cfg.playoffScoring = EStrokeScoringMode.Net
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Result([Card(1, [4, 4]), Card(2, [5, 4])]))
		AssertEquals(2, state.stages[0].fixtures[1].participantIds.Length)
		engine.RecordResult(comp, state, "GOLF", "GOLF_PLAYOFF_1", Result([Card(1, [4]), Card(2, [4])]))
		AssertEquals(2, state.stages[0].strokePlayWinnerId)
	End Method

	Method testBestBallTeamUsesDifferentMemberOnEachHole() { test }
		Local comp:TCompetition = SmallCompetition(4, 2)
		For Local id:Int = 100 To 200 Step 100
			Local teamParticipant:TParticipant = New TParticipant
			teamParticipant.id = id
			comp.participants :+ [teamParticipant]
		Next

		Local cfg:TStrokePlayConfig = TStrokePlayConfig(comp.stages[0].config)
		Local a:TStrokeTeam = New TStrokeTeam
		a.teamId = 100
		a.memberIds = [1, 2]
		Local b:TStrokeTeam = New TStrokeTeam
		b.teamId = 200
		b.memberIds = [3, 4]
		cfg.teams = [a, b]
		cfg.teamBestPerHole = 1
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(4, state.stages[0].fixtures[0].participantIds.Length)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Result([Card(1, [4, 0]), Card(2, [0, 4]), Card(3, [5, 5]), Card(4, [5, 5])]))
		AssertEquals(100, state.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(8, state.stages[0].strokeStandings[0].strokes)
		AssertEquals(10, state.stages[0].strokeStandings[1].strokes)
	End Method

	Method testTeamCutAndPlayoffAdvanceTeamsThroughMemberCards() { test }
		Local comp:TCompetition = SmallCompetition(6, 2)
		Local cfg:TStrokePlayConfig = TStrokePlayConfig(comp.stages[0].config)
		Local second:TStrokePlayRoundConfig = New TStrokePlayRoundConfig
		second.holeCount = 2
		second.pars = [4, 4]
		cfg.rounds :+ [second]
		cfg.cutAfterRound = 1
		cfg.cutPlaces = 1
		cfg.playoffHoleCount = 1
		cfg.teamBestPerHole = 1
		For Local teamIndex:Int = 1 To 3
			Local team:TStrokeTeam = New TStrokeTeam
			team.teamId = teamIndex * 100
			team.memberIds = [teamIndex * 2 - 1, teamIndex * 2]
			cfg.teams :+ [team]
			Local participant:TParticipant = New TParticipant
			participant.id = team.teamId
			comp.participants :+ [participant]
		Next

		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Result([Card(1, [4, 4]), Card(2, [6, 6]), Card(3, [4, 4]), Card(4, [5, 5]), Card(5, [5, 5]), Card(6, [6, 6])]))
		AssertEquals(4, state.stages[0].fixtures[1].participantIds.Length)
		AssertTrue(Not TStrokePlayRules.HasId(state.stages[0].fixtures[1].participantIds, 5))
		AssertEquals("cut", state.stages[0].strokeStandings[2].status)
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local path:String = "rt_stroke_team_comp.json"
		Local output:TStream = WriteStream(path)
		jconv.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		comp = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		AssertEquals(3, TStrokePlayConfig(comp.stages[0].config).teams.Length)
		AssertEquals(1, TStrokePlayConfig(comp.stages[0].config).teamBestPerHole)
		path = "rt_stroke_team_state.json"
		output = WriteStream(path)
		jconv.ToJson(state, output)
		output.Close()
		input = ReadStream(path)
		state = TCompetitionState(jconv.FromJson(input, "TCompetitionState"))
		input.Close()
		DeleteFile(path)
		AssertEquals(2, state.stages[0].strokeStandings[0].roundValues[0].holes.Length)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_2", Result([Card(1, [4, 4]), Card(2, [6, 6]), Card(3, [4, 4]), Card(4, [6, 6])]))
		AssertEquals(4, state.stages[0].fixtures[2].participantIds.Length)
		engine.RecordResult(comp, state, "GOLF", "GOLF_PLAYOFF_1", Result([Card(1, [4]), Card(2, [6]), Card(3, [3]), Card(4, [6])]))
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(200, state.stages[0].strokePlayWinnerId)
		AssertEquals(200, state.stages[0].leaderboard.rows[0].participantId)
	End Method

	Method testCountbackResolvesEqualGrossTotals() { test }
		Local comp:TCompetition = SmallCompetition(2, 4)
		Local segment:TStrokeCountbackSegment = New TStrokeCountbackSegment
		segment.roundsFromEnd = 0
		segment.lastHoles = 1
		TStrokePlayConfig(comp.stages[0].config).countback = [segment]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Result([Card(1, [4, 4, 4, 4]), Card(2, [3, 5, 5, 3])]))
		AssertEquals(2, state.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(16, state.stages[0].strokeStandings[0].strokes)
		AssertEquals(16, state.stages[0].strokeStandings[1].strokes)
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
	End Method

	Method testCountbackCanResolveCutPlace() { test }
		Local comp:TCompetition = SmallCompetition(3, 2)
		Local cfg:TStrokePlayConfig = TStrokePlayConfig(comp.stages[0].config)
		Local second:TStrokePlayRoundConfig = New TStrokePlayRoundConfig
		second.holeCount = 2
		second.pars = [4, 4]
		cfg.rounds :+ [second]
		cfg.cutAfterRound = 1
		cfg.cutPlaces = 1
		cfg.cutUsesCountback = True
		Local segment:TStrokeCountbackSegment = New TStrokeCountbackSegment
		segment.roundsFromEnd = 1
		segment.lastHoles = 1
		cfg.countback = [segment]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Result([Card(1, [4, 4]), Card(2, [5, 3]), Card(3, [5, 5])]))
		AssertEquals(1, state.stages[0].fixtures[1].participantIds.Length)
		AssertEquals(2, state.stages[0].fixtures[1].participantIds[0])
	End Method

	Method testNetBestBallChoosesLowestAdjustedHoleScore() { test }
		Local comp:TCompetition = SmallCompetition(4, 2)
		Local cfg:TStrokePlayConfig = TStrokePlayConfig(comp.stages[0].config)
		cfg.scoring = EStrokeScoringMode.Net
		cfg.teamBestPerHole = 1
		Local handicap:TStrokeHandicap = New TStrokeHandicap
		handicap.participantId = 1
		handicap.received = [2, 0]
		cfg.rounds[0].handicaps = [handicap]
		For Local teamIndex:Int = 1 To 2
			Local team:TStrokeTeam = New TStrokeTeam
			team.teamId = teamIndex * 100
			team.memberIds = [teamIndex * 2 - 1, teamIndex * 2]
			cfg.teams :+ [team]
			Local participant:TParticipant = New TParticipant
			participant.id = team.teamId
			comp.participants :+ [participant]
		Next

		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Result([Card(1, [5, 5]), Card(2, [4, 4]), Card(3, [4, 4]), Card(4, [5, 5])]))
		AssertEquals(100, state.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(7, state.stages[0].strokeStandings[0].netStrokes)
		AssertEquals(8, state.stages[0].strokeStandings[1].netStrokes)
	End Method

	Function Competition:TCompetition()
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 6
			Local player:TParticipant = New TParticipant
			player.id = id
			comp.participants :+ [player]
		Next

		Local stage:TStage = New TStage
		stage.id = "GOLF"
		stage.stageType = EStageType.Qualifying
		stage.formatCode = "stroke-play"
		Local cfg:TStrokePlayConfig = New TStrokePlayConfig
		For Local round:Int = 1 To 3
			Local definition:TStrokePlayRoundConfig = New TStrokePlayRoundConfig
			definition.holeCount = 2
			definition.pars = [4, 4]
			cfg.rounds :+ [definition]
		Next

		cfg.cutAfterRound = 2
		cfg.cutPlaces = 2
		stage.config = cfg
		comp.stages = [stage]
		Return comp
	End Function

	Function Engine:TCompetitionEngine()
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterFormat("stroke-play", New TStrokePlayScheduler, New TStrokePlayScorer)
		Return engine
	End Function

	Function Cards:TResultPayload(fixture:TFixtureState, totals:Int[])
		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.Custom
		result.customCode = "stroke-play-card"
		For Local id:Int = EachIn fixture.participantIds
			Local card:TStrokeScorecard = New TStrokeScorecard
			card.participantId = id
			card.holes = [4, totals[id - 1] - 4]
			result.strokeCards :+ [card]
		Next

		Return result
	End Function

	Function PlayoffCards:TResultPayload(fixture:TFixtureState, totals:Int[])
		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.Custom
		result.customCode = "stroke-play-card"
		For Local id:Int = EachIn fixture.participantIds
			Local card:TStrokeScorecard = New TStrokeScorecard
			card.participantId = id
			card.holes = [totals[id - 1]]
			result.strokeCards :+ [card]
		Next

		Return result
	End Function

	Method testCumulativeScoringCutTiesAndRoundTrip() { test }
		Local comp:TCompetition = Competition()
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(6, state.stages[0].fixtures[0].participantIds.Length)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Cards(state.stages[0].fixtures[0], [8, 9, 10, 11, 12, 13]))
		AssertEquals(2, state.stages[0].fixtures.Length)
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local path:String = "rt_stroke_comp.json"
		Local output:TStream = WriteStream(path)
		jconv.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		comp = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		AssertEquals(2, TStrokePlayConfig(comp.stages[0].config).rounds[0].holeCount)
		path = "rt_stroke_state.json"
		output = WriteStream(path)
		jconv.ToJson(state, output)
		output.Close()
		input = ReadStream(path)
		state = TCompetitionState(jconv.FromJson(input, "TCompetitionState"))
		input.Close()
		DeleteFile(path)
		AssertEquals(8, state.stages[0].fixtures[0].strokeCards[0].holes[0] + state.stages[0].fixtures[0].strokeCards[0].holes[1])
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_2", Cards(state.stages[0].fixtures[1], [9, 9, 8, 8, 8, 8]))
		AssertEquals(3, state.stages[0].fixtures.Length)
		AssertEquals(3, state.stages[0].fixtures[2].participantIds.Length)
		AssertEquals(1, state.stages[0].fixtures[2].participantIds[0])
		AssertEquals(2, state.stages[0].fixtures[2].participantIds[1])
		AssertEquals(3, state.stages[0].fixtures[2].participantIds[2])
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_3", Cards(state.stages[0].fixtures[2], [8, 6, 9, 8, 8, 8]))
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(2, state.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(24, state.stages[0].strokeStandings[0].strokes)
		AssertEquals("cut", state.stages[0].strokeStandings[3].status)
	End Method

	Method testTiedLeadNeedsExplicitResolution() { test }
		Local comp:TCompetition = Competition()
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Cards(state.stages[0].fixtures[0], [8, 9, 10, 11, 12, 13]))
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_2", Cards(state.stages[0].fixtures[1], [9, 9, 8, 8, 8, 8]))
		Local rejected:Int
		Try
			engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_3", Cards(state.stages[0].fixtures[2], [8, 7, 9, 8, 8, 8]))
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected)
		AssertEquals(EStageStatus.Running.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(EFixtureStatus.Completed.Ordinal(), state.stages[0].fixtures[2].status.Ordinal())
		TStrokePlayConfig(comp.stages[0].config).playoffHoleCount = 1
		AssertTrue(engine.GenerateNextRound(comp, state, "GOLF"))
		AssertEquals(2, state.stages[0].fixtures[3].participantIds.Length)
	End Method

	Method testTiedLeadRunsRepeatedHolePlayoff() { test }
		Local comp:TCompetition = Competition()
		TStrokePlayConfig(comp.stages[0].config).playoffHoleCount = 1
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", Cards(state.stages[0].fixtures[0], [8, 9, 10, 11, 12, 13]))
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_2", Cards(state.stages[0].fixtures[1], [9, 9, 8, 8, 8, 8]))
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_3", Cards(state.stages[0].fixtures[2], [8, 7, 9, 8, 8, 8]))
		AssertEquals(4, state.stages[0].fixtures.Length)
		AssertEquals(2, state.stages[0].fixtures[3].participantIds.Length)
		engine.RecordResult(comp, state, "GOLF", "GOLF_PLAYOFF_1", PlayoffCards(state.stages[0].fixtures[3], [4, 4, 4, 4, 4, 4]))
		AssertEquals(5, state.stages[0].fixtures.Length)
		engine.RecordResult(comp, state, "GOLF", "GOLF_PLAYOFF_2", PlayoffCards(state.stages[0].fixtures[4], [5, 3, 4, 4, 4, 4]))
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(2, state.stages[0].strokePlayWinnerId)
		AssertEquals(2, state.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(25, state.stages[0].strokeStandings[0].strokes)
	End Method

	Method testInvalidCardIsRejectedAndWithdrawalLeavesNextRound() { test }
		Local comp:TCompetition = Competition()
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local result:TResultPayload = Cards(state.stages[0].fixtures[0], [8, 9, 10, 11, 12, 13])
		result.strokeCards[5].holes = [4]
		Local rejected:Int
		Try
			engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", result)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected)
		AssertEquals(EFixtureStatus.Scheduled.Ordinal(), state.stages[0].fixtures[0].status.Ordinal())
		result.strokeCards[5].holes = Null
		result.strokeCards[5].status = EStrokeCardStatus.Withdrawn
		engine.RecordResult(comp, state, "GOLF", "GOLF_ROUND_1", result)
		AssertEquals(5, state.stages[0].fixtures[1].participantIds.Length)
		AssertEquals("withdrawn", state.stages[0].strokeStandings[5].status)
	End Method
End Type

Type THeatsProgressionTest Extends TTest
	Method testPublishedLaneMapSurvivesSerializationAndRejectsCollisions() { test }
		Local comp:TCompetition = Competition(0)
		Local policy:THeatLanePolicy = New THeatLanePolicy
		policy.laneCount = 4
		For Local id:Int = 1 To 8
			Local assignment:THeatLaneAssignment = New THeatLaneAssignment
			assignment.participantId = id
			Select id
				Case 1, 2
					assignment.lane = 4
				Case 3, 4
					assignment.lane = 2
				Case 5, 6
					assignment.lane = 3
				Case 7, 8
					assignment.lane = 1
			End Select

			policy.fixedAssignments :+ [assignment]
		Next

		THeatsConfig(comp.stages[0].config).lanes = policy
		Local serialized:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local path:String = "rt_fixed_lanes_comp.json"
		Local output:TStream = WriteStream(path)
		serialized.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		comp = TCompetition(serialized.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		policy = THeatsConfig(comp.stages[0].config).lanes
		AssertEquals(8, policy.fixedAssignments.Length)
		Local state:TCompetitionState = Engine().Initialize(comp)
		AssertEquals(4, state.stages[0].fixtures[0].heatLanes[0].lane)
		AssertEquals(2, state.stages[0].fixtures[0].heatLanes[1].lane)
		policy.fixedAssignments[3].lane = 4
		Local rejected:Int
		Try
			Engine().Initialize(comp)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Published lane map cannot reuse a lane in one heat")
	End Method

	Method testFixedHeatGroupsValidateAndRoundTrip() { test }
		Local comp:TCompetition = Competition(0)
		Local rule:THeatRoundConfig = New THeatRoundConfig
		rule.heatCount = 2
		rule.automaticPlaces = 2
		Local first:THeatGroup = New THeatGroup
		first.participantIds = [3, 1, 7, 5]
		Local second:THeatGroup = New THeatGroup
		second.participantIds = [4, 2, 8, 6]
		rule.fixedGroups = [first, second]
		THeatsConfig(comp.stages[0].config).qualifyingRounds = [rule]
		Local serialized:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local path:String = "rt_fixed_heats_comp.json"
		Local output:TStream = WriteStream(path)
		serialized.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		comp = TCompetition(serialized.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		rule = THeatsConfig(comp.stages[0].config).qualifyingRounds[0]
		AssertEquals(2, rule.fixedGroups.Length)
		AssertEquals(7, rule.fixedGroups[0].participantIds[2])
		Local state:TCompetitionState = Engine().Initialize(comp)
		AssertEquals(3, state.stages[0].fixtures[0].heatEntrants[0])
		AssertEquals(4, state.stages[0].fixtures[1].heatEntrants[0])
		rule.fixedGroups[1].participantIds = [4, 2, 8, 3]
		Local rejected:Int
		Try
			Engine().Initialize(comp)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Fixed groups cannot duplicate or omit an entrant")
	End Method

	Function Competition:TCompetition(fastest:Int, policy:EHeatCutoffTiePolicy = EHeatCutoffTiePolicy.AdvanceAll)
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 8
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.seedRank = id
			comp.participants :+ [participant]
		Next

		Local stage:TStage = New TStage
		stage.id = "TRACK"
		stage.stageType = EStageType.Qualifying
		stage.formatCode = "timed-heats"
		Local cfg:THeatsConfig = New THeatsConfig
		cfg.heatCount = 2
		cfg.automaticPlaces = 2
		cfg.fastestRemaining = fastest
		cfg.cutoffTiePolicy = policy
		stage.config = cfg
		comp.stages = [stage]
		Return comp
	End Function

	Function Engine:TCompetitionEngine()
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterFormat("timed-heats", New THeatsScheduler, New THeatsScorer)
		Return engine
	End Function

	Function TimedResult:TResultPayload(fixture:TFixtureState, times:Long[])
		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.TimeBased
		For Local i:Int = 0 Until fixture.heatEntrants.Length
			Local athlete:TParticipantTime = New TParticipantTime
			athlete.participantId = fixture.heatEntrants[i]
			athlete.millis = times[i]
			result.times :+ [athlete]
		Next

		Return result
	End Function

	Method testPlaceAndFastestQualifiersReachFinal() { test }
		Local comp:TCompetition = Competition(2)
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(2, state.stages[0].fixtures.Length)
		AssertEquals(1, state.stages[0].fixtures[0].heatEntrants[0])
		AssertEquals(4, state.stages[0].fixtures[0].heatEntrants[1])
		AssertEquals(2, state.stages[0].fixtures[1].heatEntrants[0])
		engine.RecordResult(comp, state, "TRACK", "TRACK_HEAT_1", TimedResult(state.stages[0].fixtures[0], [10000:Long, 10200:Long, 10300:Long, 10400:Long]))
		AssertEquals(2, state.stages[0].fixtures.Length)
		engine.RecordResult(comp, state, "TRACK", "TRACK_HEAT_2", TimedResult(state.stages[0].fixtures[1], [9900:Long, 10100:Long, 10250:Long, 10500:Long]))
		AssertEquals(3, state.stages[0].fixtures.Length)
		Local finalFixture:TFixtureState = state.stages[0].fixtures[2]
		AssertEquals(6, finalFixture.heatEntrants.Length)
		AssertTrue(Contains(finalFixture.heatEntrants, 5))
		AssertTrue(Contains(finalFixture.heatEntrants, 6))
		AssertTrue(Not Contains(finalFixture.heatEntrants, 7))
		Local finalTimes:Long[]
		For Local id:Int = EachIn finalFixture.heatEntrants
			If id = 6 Then finalTimes :+ [9500:Long] Else finalTimes :+ [11000:Long + id]
		Next

		engine.RecordResult(comp, state, "TRACK", finalFixture.id, TimedResult(finalFixture, finalTimes))
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(6, state.stages[0].leaderboard.rows[0].participantId)
	End Method

	Method testPlaceTieReducesTimeSlotsAndCutoffTiePolicy() { test }
		Local comp:TCompetition = Competition(2)
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "TRACK", "TRACK_HEAT_1", TimedResult(state.stages[0].fixtures[0], [10000:Long, 10200:Long, 10200:Long, 10400:Long]))
		engine.RecordResult(comp, state, "TRACK", "TRACK_HEAT_2", TimedResult(state.stages[0].fixtures[1], [9900:Long, 10100:Long, 10250:Long, 10500:Long]))
		Local selected:Int[] = state.stages[0].fixtures[2].heatEntrants
		AssertEquals(6, selected.Length)
		AssertTrue(Contains(selected, 5))
		AssertTrue(Contains(selected, 6))
		comp = Competition(1, EHeatCutoffTiePolicy.RequireResolution)
		state = Engine().Initialize(comp)
		engine.RecordResult(comp, state, "TRACK", "TRACK_HEAT_1", TimedResult(state.stages[0].fixtures[0], [10000:Long, 10200:Long, 10300:Long, 10400:Long]))
		Local rejected:Int
		Try
			engine.RecordResult(comp, state, "TRACK", "TRACK_HEAT_2", TimedResult(state.stages[0].fixtures[1], [9900:Long, 10100:Long, 10300:Long, 10500:Long]))
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Equal fastest remaining times need a resolution policy")
		AssertEquals(EFixtureStatus.Completed.Ordinal(), state.stages[0].fixtures[1].status.Ordinal())
		THeatsConfig(comp.stages[0].config).cutoffTiePolicy = EHeatCutoffTiePolicy.AdvanceAll
		AssertTrue(engine.GenerateNextRound(comp, state, "TRACK"))
		AssertEquals(6, state.stages[0].fixtures[2].heatEntrants.Length)
	End Method

	Method testHeatsConfigAndAssignedEntrantsRoundTrip() { test }
		Local comp:TCompetition = Competition(2, EHeatCutoffTiePolicy.RequireResolution)
		Local lanes:THeatLanePolicy = New THeatLanePolicy
		lanes.laneCount = 4
		lanes.preference = [2, 3, 1, 4]
		THeatsConfig(comp.stages[0].config).lanes = lanes
		THeatsConfig(comp.stages[0].config).finalLanes = lanes
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local path:String = "rt_heats_competition.json"
		Local output:TStream = WriteStream(path)
		jconv.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		comp = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		Local cfg:THeatsConfig = THeatsConfig(comp.stages[0].config)
		AssertEquals(2, cfg.heatCount)
		AssertEquals(2, cfg.fastestRemaining)
		AssertEquals(EHeatCutoffTiePolicy.RequireResolution.Ordinal(), cfg.cutoffTiePolicy.Ordinal())
		AssertEquals(4, cfg.lanes.laneCount)
		AssertEquals(2, cfg.lanes.preference[0])
		Local state:TCompetitionState = Engine().Initialize(comp)
		path = "rt_heats_state.json"
		output = WriteStream(path)
		jconv.ToJson(state, output)
		output.Close()
		input = ReadStream(path)
		state = TCompetitionState(jconv.FromJson(input, "TCompetitionState"))
		input.Close()
		DeleteFile(path)
		AssertEquals(4, state.stages[0].fixtures[0].heatEntrants.Length)
		AssertEquals(1, state.stages[0].fixtures[0].heatEntrants[0])
		AssertEquals(4, state.stages[0].fixtures[0].heatLanes.Length)
		AssertEquals(1, state.stages[0].fixtures[0].heatLanes[0].participantId)
		AssertEquals(2, state.stages[0].fixtures[0].heatLanes[0].lane)
		AssertEquals(4, state.stages[0].fixtures[0].heatLanes[1].participantId)
		AssertEquals(3, state.stages[0].fixtures[0].heatLanes[1].lane)
	End Method

	Method testFinalLaneCapacityCanBeReconfiguredAfterQualification() { test }
		Local comp:TCompetition = Competition(2)
		Local cfg:THeatsConfig = THeatsConfig(comp.stages[0].config)
		cfg.finalLanes = New THeatLanePolicy
		cfg.finalLanes.laneCount = 4
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordResult(comp, state, "TRACK", "TRACK_HEAT_1", TimedResult(state.stages[0].fixtures[0], [10000:Long, 10200:Long, 10300:Long, 10400:Long]))
		Local rejected:Int
		Try
			engine.RecordResult(comp, state, "TRACK", "TRACK_HEAT_2", TimedResult(state.stages[0].fixtures[1], [9900:Long, 10100:Long, 10250:Long, 10500:Long]))
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Final needs enough lanes for all qualifiers")
		AssertEquals(2, state.stages[0].fixtures.Length)
		AssertEquals(EFixtureStatus.Completed.Ordinal(), state.stages[0].fixtures[1].status.Ordinal())
		cfg.finalLanes.laneCount = 6
		cfg.finalLanes.preference = [3, 4, 2, 5, 1, 6]
		AssertTrue(engine.GenerateNextRound(comp, state, "TRACK"))
		Local finalFixture:TFixtureState = state.stages[0].fixtures[2]
		AssertEquals(6, finalFixture.heatLanes.Length)
		AssertEquals(finalFixture.heatEntrants[0], finalFixture.heatLanes[0].participantId)
		AssertEquals(3, finalFixture.heatLanes[0].lane)
	End Method

	Method testInvalidLanePreferenceIsRejected() { test }
		Local comp:TCompetition = Competition(0)
		Local lanes:THeatLanePolicy = New THeatLanePolicy
		lanes.laneCount = 4
		lanes.preference = [2, 2, 1, 4]
		THeatsConfig(comp.stages[0].config).lanes = lanes
		Local rejected:Int
		Try
			Engine().Initialize(comp)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "A lane may only be assigned once")
	End Method

	Method testSeededRandomLaneDrawIsRepeatableAndSerialized() { test }
		Local comp:TCompetition = Competition(0)
		Local lanes:THeatLanePolicy = New THeatLanePolicy
		lanes.laneCount = 4
		lanes.allocation = EHeatLaneAllocation.Random
		lanes.drawSeed = 42
		THeatsConfig(comp.stages[0].config).lanes = lanes
		Local first:TCompetitionState = Engine().Initialize(comp)
		Local again:TCompetitionState = Engine().Initialize(comp)
		For Local h:Int = 0 Until 2
			Local seen:Int[]
			For Local i:Int = 0 Until 4
				Local original:THeatLaneAssignment = first.stages[0].fixtures[h].heatLanes[i]
				AssertEquals(first.stages[0].fixtures[h].heatEntrants[i], original.participantId)
				AssertEquals(original.lane, again.stages[0].fixtures[h].heatLanes[i].lane)
				AssertTrue(original.lane >= 1 And original.lane <= 4)
				AssertTrue(Not Contains(seen, original.lane), "Each lane is drawn once")
				seen :+ [original.lane]
			Next
		Next

		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local path:String = "rt_random_lanes_comp.json"
		Local output:TStream = WriteStream(path)
		jconv.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		comp = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		lanes = THeatsConfig(comp.stages[0].config).lanes
		AssertEquals(EHeatLaneAllocation.Random.Ordinal(), lanes.allocation.Ordinal())
		AssertEquals(42, lanes.drawSeed)
		Local restored:TCompetitionState = Engine().Initialize(comp)
		For Local h:Int = 0 Until 2
			For Local i:Int = 0 Until 4
				AssertEquals(first.stages[0].fixtures[h].heatLanes[i].lane, restored.stages[0].fixtures[h].heatLanes[i].lane)
			Next
		Next

		lanes.drawSeed = 43
		Local changed:TCompetitionState = Engine().Initialize(comp)
		Local differs:Int
		For Local h:Int = 0 Until 2
			For Local i:Int = 0 Until 4
				If first.stages[0].fixtures[h].heatLanes[i].lane <> changed.stages[0].fixtures[h].heatLanes[i].lane Then
					differs = True
				End If
			Next
		Next

		AssertTrue(differs, "Changing the draw seed should change the fixture draw")
	End Method

	Method testHeatResultRejectsWrongEntrantAndDoesNotAdvanceDNF() { test }
		Local comp:TCompetition = Competition(1)
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local bad:TResultPayload = TimedResult(state.stages[0].fixtures[0], [10000:Long, 10200:Long, 10300:Long, 10400:Long])
		bad.times[0].participantId = 2
		Local rejected:Int
		Try
			engine.RecordResult(comp, state, "TRACK", "TRACK_HEAT_1", bad)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected)
		AssertEquals(EFixtureStatus.Scheduled.Ordinal(), state.stages[0].fixtures[0].status.Ordinal())
		Local good:TResultPayload = TimedResult(state.stages[0].fixtures[0], [10000:Long, 10200:Long, 10300:Long, 10400:Long])
		good.times[2].status = ETimeStatus.DNF
		engine.RecordResult(comp, state, "TRACK", "TRACK_HEAT_1", good)
		engine.RecordResult(comp, state, "TRACK", "TRACK_HEAT_2", TimedResult(state.stages[0].fixtures[1], [9900:Long, 10100:Long, 10250:Long, 10500:Long]))
		AssertTrue(Not Contains(state.stages[0].fixtures[2].heatEntrants, 5))
	End Method

	Method testThreeStageHeatSemiFinalReplaySurvivesRoundTrip() { test }
		Local comp:TCompetition = Competition(0)
		For Local id:Int = 9 To 12
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.seedRank = id
			comp.participants :+ [participant]
		Next

		Local cfg:THeatsConfig = THeatsConfig(comp.stages[0].config)
		Local heats:THeatRoundConfig = New THeatRoundConfig
		heats.heatCount = 3
		heats.automaticPlaces = 2
		heats.fastestRemaining = 2
		Local semis:THeatRoundConfig = New THeatRoundConfig
		semis.heatCount = 2
		semis.automaticPlaces = 2
		cfg.qualifyingRounds = [heats, semis]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(3, state.stages[0].fixtures.Length)
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures[..]
			Local times:Long[]
			For Local id:Int = EachIn fixture.heatEntrants
				times :+ [10000:Long + id * 10]
			Next

			engine.RecordResult(comp, state, "TRACK", fixture.id, TimedResult(fixture, times))
		Next

		AssertEquals(5, state.stages[0].fixtures.Length)
		AssertEquals(2, state.stages[0].fixtures[3].round)
		Local serialized:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local path:String = "rt_multiround_heats_comp.json"
		Local output:TStream = WriteStream(path)
		serialized.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		comp = TCompetition(serialized.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		AssertEquals(2, THeatsConfig(comp.stages[0].config).qualifyingRounds.Length)
		path = "rt_multiround_heats_state.json"
		output = WriteStream(path)
		serialized.ToJson(state, output)
		output.Close()
		input = ReadStream(path)
		state = TCompetitionState(serialized.FromJson(input, "TCompetitionState"))
		input.Close()
		DeleteFile(path)
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures[..]
			If fixture.round <> 2 Then
				Continue
			End If

			Local times:Long[]
			For Local id:Int = EachIn fixture.heatEntrants
				times :+ [10000:Long + id * 10]
			Next

			engine.RecordResult(comp, state, "TRACK", fixture.id, TimedResult(fixture, times))
		Next

		AssertEquals(6, state.stages[0].fixtures.Length)
		Local finalFixture:TFixtureState = state.stages[0].fixtures[5]
		AssertEquals(3, finalFixture.round)
		AssertEquals(4, finalFixture.heatEntrants.Length)
		For Local id:Int = 1 To 4
			AssertTrue(Contains(finalFixture.heatEntrants, id))
		Next

		Local finalTimes:Long[]
		For Local id:Int = EachIn finalFixture.heatEntrants
			If id = 4 Then finalTimes :+ [9000:Long] Else finalTimes :+ [10000:Long + id * 10]
		Next

		engine.RecordResult(comp, state, "TRACK", finalFixture.id, TimedResult(finalFixture, finalTimes))
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(4, state.stages[0].leaderboard.rows[0].participantId)
	End Method

	Method testOfficialPlacesResolveEqualTimesWithinHeat() { test }
		Local comp:TCompetition = Competition(0)
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local result:TResultPayload = TimedResult(state.stages[0].fixtures[0], [10000:Long, 10200:Long, 10200:Long, 10400:Long])
		For Local i:Int = 0 Until result.times.Length
			result.times[i].place = i + 1
		Next

		engine.RecordResult(comp, state, "TRACK", "TRACK_HEAT_1", result)
		engine.RecordResult(comp, state, "TRACK", "TRACK_HEAT_2", TimedResult(state.stages[0].fixtures[1], [9900:Long, 10100:Long, 10250:Long, 10500:Long]))
		AssertEquals(4, state.stages[0].fixtures[2].heatEntrants.Length)
		AssertTrue(Contains(state.stages[0].fixtures[2].heatEntrants, 4))
		AssertTrue(Not Contains(state.stages[0].fixtures[2].heatEntrants, 5))
		comp = Competition(0)
		state = Engine().Initialize(comp)
		result = TimedResult(state.stages[0].fixtures[0], [10000:Long, 10200:Long, 10200:Long, 10400:Long])
		For Local i:Int = 0 Until result.times.Length
			result.times[i].place = 4 - i
		Next

		Local rejected:Int
		Try
			engine.RecordResult(comp, state, "TRACK", "TRACK_HEAT_1", result)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Official places must agree with distinct times")
	End Method

	Method testRepechageMergesWithDirectQualifiersBeforeSemiFinal() { test }
		Local comp:TCompetition = Competition(0)
		For Local id:Int = 9 To 12
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.seedRank = id
			comp.participants :+ [participant]
		Next

		Local first:THeatRoundConfig = New THeatRoundConfig
		first.heatCount = 3
		first.automaticPlaces = 2
		first.lanes = New THeatLanePolicy
		first.lanes.laneCount = 4
		first.lanes.preference = [2, 3, 1, 4]
		first.repechage = New THeatRoundConfig
		first.repechage.heatCount = 2
		first.repechage.automaticPlaces = 1
		first.repechage.fastestRemaining = 1
		first.repechage.lanes = New THeatLanePolicy
		first.repechage.lanes.laneCount = 3
		first.repechage.lanes.preference = [2, 1, 3]
		Local semi:THeatRoundConfig = New THeatRoundConfig
		semi.heatCount = 2
		semi.automaticPlaces = 2
		semi.lanes = New THeatLanePolicy
		semi.lanes.laneCount = 5
		semi.lanes.preference = [3, 2, 4, 1, 5]
		THeatsConfig(comp.stages[0].config).qualifyingRounds = [first, semi]
		THeatsConfig(comp.stages[0].config).finalLanes = New THeatLanePolicy
		THeatsConfig(comp.stages[0].config).finalLanes.laneCount = 4
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(2, state.stages[0].fixtures[0].heatLanes[0].lane)
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures[..]
			Local times:Long[]
			For Local id:Int = EachIn fixture.heatEntrants
				times :+ [10000:Long + id * 10]
			Next

			Local result:TResultPayload = TimedResult(fixture, times)
			For Local athlete:TParticipantTime = EachIn result.times
				If athlete.participantId = 12 Then
					athlete.status = ETimeStatus.DNF
				End If
			Next

			engine.RecordResult(comp, state, "TRACK", fixture.id, result)
		Next

		AssertEquals(5, state.stages[0].fixtures.Length)
		Local repEntrants:Int[]
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
			If fixture.round <> 2 Then
				Continue
			End If

			AssertEquals(EHeatPhase.Repechage.Ordinal(), fixture.heatPhase.Ordinal())
			AssertEquals(2, fixture.heatLanes[0].lane)
			repEntrants :+ fixture.heatEntrants
		Next

		AssertEquals(5, repEntrants.Length)
		AssertTrue(Contains(repEntrants, 7))
		AssertTrue(Not Contains(repEntrants, 1))
		AssertTrue(Not Contains(repEntrants, 12))
		AssertEquals(1, state.stages[0].leaderboard.rows[0].participantId)
		Local serialized:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local path:String = "rt_repechage_comp.json"
		Local output:TStream = WriteStream(path)
		serialized.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		comp = TCompetition(serialized.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		AssertEquals(2, THeatsConfig(comp.stages[0].config).qualifyingRounds[0].repechage.heatCount)
		AssertEquals(3, THeatsConfig(comp.stages[0].config).qualifyingRounds[0].repechage.lanes.laneCount)
		path = "rt_repechage_state.json"
		output = WriteStream(path)
		serialized.ToJson(state, output)
		output.Close()
		input = ReadStream(path)
		state = TCompetitionState(serialized.FromJson(input, "TCompetitionState"))
		input.Close()
		DeleteFile(path)
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures[..]
			If fixture.round <> 2 Then
				Continue
			End If

			Local times:Long[]
			For Local id:Int = EachIn fixture.heatEntrants
				times :+ [10000:Long + id * 10]
			Next

			engine.RecordResult(comp, state, "TRACK", fixture.id, TimedResult(fixture, times))
		Next

		AssertEquals(7, state.stages[0].fixtures.Length)
		Local semiEntrants:Int[]
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
			If fixture.round <> 3 Then
				Continue
			End If

			AssertEquals(EHeatPhase.Main.Ordinal(), fixture.heatPhase.Ordinal())
			AssertEquals(3, fixture.heatLanes[0].lane)
			semiEntrants :+ fixture.heatEntrants
		Next

		AssertEquals(9, semiEntrants.Length)
		For Local id:Int = 1 To 9
			AssertTrue(Contains(semiEntrants, id))
		Next

		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures[..]
			If fixture.round <> 3 Then
				Continue
			End If

			Local times:Long[]
			For Local id:Int = EachIn fixture.heatEntrants
				times :+ [10000:Long + id * 10]
			Next

			engine.RecordResult(comp, state, "TRACK", fixture.id, TimedResult(fixture, times))
		Next

		AssertEquals(8, state.stages[0].fixtures.Length)
		Local finalFixture:TFixtureState = state.stages[0].fixtures[7]
		AssertEquals(EHeatPhase.Final.Ordinal(), finalFixture.heatPhase.Ordinal())
		AssertEquals(4, finalFixture.round)
		AssertEquals(4, finalFixture.heatEntrants.Length)
		AssertEquals(4, finalFixture.heatLanes.Length)
		AssertEquals(1, finalFixture.heatLanes[0].lane)
		Local finalTimes:Long[]
		For Local id:Int = EachIn finalFixture.heatEntrants
			If id = 4 Then finalTimes :+ [9000:Long] Else finalTimes :+ [10000:Long + id * 10]
		Next

		engine.RecordResult(comp, state, "TRACK", finalFixture.id, TimedResult(finalFixture, finalTimes))
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(4, state.stages[0].leaderboard.rows[0].participantId)
	End Method

	Method testEmptyRepechageIsSkipped() { test }
		Local comp:TCompetition = Competition(0)
		Local cfg:THeatsConfig = THeatsConfig(comp.stages[0].config)
		cfg.automaticPlaces = 4
		cfg.repechage = New THeatRoundConfig
		cfg.repechage.heatCount = 2
		cfg.repechage.automaticPlaces = 1
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures[..]
			Local times:Long[]
			For Local id:Int = EachIn fixture.heatEntrants
				times :+ [10000:Long + id * 10]
			Next

			engine.RecordResult(comp, state, "TRACK", fixture.id, TimedResult(fixture, times))
		Next

		AssertEquals(3, state.stages[0].fixtures.Length)
		AssertEquals(EHeatPhase.Final.Ordinal(), state.stages[0].fixtures[2].heatPhase.Ordinal())
		AssertEquals(2, state.stages[0].fixtures[2].round)
	End Method

	Function Contains:Int(ids:Int[], id:Int)
		For Local value:Int = EachIn ids
			If value = id Then
				Return True
			End If
		Next

		Return False
	End Function
End Type

Type THistoricalCricket2011ReplayTest Extends TTest
	Method testCompleteCricketWorldCup() { test }
		AssertEquals(49, TCricket2011Replay.Run(AppDir + "/../examples/cricket_2011_replay.tsv"))
	End Method

	Method testCricketResultAndRulesRoundTrip() { test }
		Local comp:TCompetition = New TCompetition
		Local stage:TStage = New TStage
		stage.id = "CRICKET"
		stage.config = New TCricketConfig
		TCricketConfig(stage.config).pointsNoResult = 2
		comp.stages = [stage]
		Local serial:TConfigSerializer = New TConfigSerializer
		serial.RegisterConfig("cricket", New TCricketConfigFactory)
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", serial).WithEmptyArrays().Build()
		Local path:String = "/private/tmp/tourney_cricket_config.json"
		Local output:TStream = WriteStream(path)
		jconv.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		Local restored:TCompetition = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		AssertEquals(2, TCricketConfig(restored.stages[0].config).pointsNoResult)
		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.Custom
		result.customCode = "cricket"
		result.cricket = New TCricketMatchResult
		result.cricket.outcome = ECricketOutcome.Win
		result.cricket.winnerId = 1
		result.cricket.revisedTarget = 162
		result.cricket.first = New TCricketInnings
		result.cricket.first.teamId = 2
		result.cricket.first.creditedRuns = 161
		result.cricket.first.creditedBalls = 228
		Local output2:TStream = WriteStream(path)
		jconv.ToJson(result, output2)
		output2.Close()
		Local input2:TStream = ReadStream(path)
		Local saved:TResultPayload = TResultPayload(jconv.FromJson(input2, "TResultPayload"))
		input2.Close()
		DeleteFile(path)
		AssertEquals(162, saved.cricket.revisedTarget)
		AssertEquals(161, saved.cricket.first.creditedRuns)
	End Method

	Method testCricketRejectsContradictoryWinner() { test }
		Local comp:TCompetition = New TCompetition
		Local stage:TStage = New TStage
		stage.id = "MATCH"
		stage.stageType = EStageType.League
		stage.config = New TCricketConfig
		Local fixture:TFixtureState = New TFixtureState
		fixture.id = "M1"
		fixture.homeTeamId = 1
		fixture.awayTeamId = 2
		fixture.status = EFixtureStatus.Scheduled
		Local state:TStageState = New TStageState
		state.fixtures = [fixture]
		Local payload:TResultPayload = New TResultPayload
		payload.kind = EResultKind.Custom
		payload.customCode = "cricket"
		payload.cricket = New TCricketMatchResult
		payload.cricket.outcome = ECricketOutcome.Win
		payload.cricket.winnerId = 1
		payload.cricket.first = New TCricketInnings
		payload.cricket.first.teamId = 1
		payload.cricket.first.runs = 100
		payload.cricket.first.legalBalls = 300
		payload.cricket.first.allocatedBalls = 300
		payload.cricket.second = New TCricketInnings
		payload.cricket.second.teamId = 2
		payload.cricket.second.runs = 101
		payload.cricket.second.legalBalls = 200
		payload.cricket.second.allocatedBalls = 300
		Local rejected:Int
		Try
			(New TCricketScorer).ApplyResult(comp, stage, state, fixture.id, payload)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "A chase winner must match the innings totals")
		AssertEquals(EFixtureStatus.Scheduled.Ordinal(), fixture.status.Ordinal())
	End Method
End Type

Type THistoricalMLB2024ReplayTest Extends TTest
	Method testCompleteMLBSeason() { test }
		AssertEquals(2472, TMLB2024Replay.Run(AppDir + "/../examples/mlb_2024_replay.tsv"))
	End Method

	Method testSaveAndRestoreMidseason() { test }
		AssertEquals(2472, TMLB2024Replay.Run(AppDir + "/../examples/mlb_2024_replay.tsv", Null, 1215))
	End Method

	Method testViewerSnapshotsCoverEveryGame() { test }
		Local path:String = "rt_mlb_2024_snapshots.tsv"
		AssertEquals(2472, TMLB2024SnapshotExport.Export(AppDir + "/../examples/mlb_2024_replay.tsv", path))
		Local input:TStream = ReadStream(path)
		AssertTrue(input <> Null)
		Local teams:Int, games:Int, rows:Int
		Local lastGame:String
		While Not input.Eof()
			Local line:String = input.ReadLine()
			If line.StartsWith("T|") Then
				teams :+ 1
			End If

			If line.StartsWith("E|") Then games :+ 1; lastGame = line

			If line.StartsWith("R|") Then
				rows :+ 1
			End If
		Wend

		input.Close()
		DeleteFile(path)
		AssertEquals(30, teams)
		AssertEquals(2472, games)
		AssertEquals(2472 * 30, rows)
		AssertEquals("E|2472|WORLD_SERIES|1|147|119|6|7", lastGame)
	End Method

	Method testFinalCanUseEarlierStandingsForHomeSeed() { test }
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 2
			Local participant:TParticipant = New TParticipant
			participant.id = id
			comp.participants :+ [participant]
		Next

		Local regular:TStage = New TStage
		regular.id = "REG"
		Local championship:TStage = New TStage
		championship.id = "FINAL"
		championship.stageType = EStageType.Bracket
		championship.input = New TEntrySource
		championship.input.seeding = New TSeedingPolicy
		championship.input.seeding.seedingMethod = ESeedingMethod.Ranking
		championship.input.seeding.rankingStageId = "REG"
		championship.config = New TBracketConfig
		TBracketConfig(championship.config).size = 2
		comp.stages = [regular, championship]
		Local standing:TStageState = New TStageState
		standing.stageId = "REG"
		standing.status = EStageStatus.Complete
		standing.leaderboard = New TLeaderboard
		Local first:TLeaderboardRow = New TLeaderboardRow
		first.participantId = 2
		Local second:TLeaderboardRow = New TLeaderboardRow
		second.participantId = 1
		standing.leaderboard.rows = [first, second]
		Local playoff:TStageState = New TStageState
		playoff.stageId = "FINAL"
		Local state:TCompetitionState = New TCompetitionState
		state.stages = [standing, playoff]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.StartStage(comp, state, 1, comp.participants)
		AssertEquals(2, playoff.fixtures[0].homeTeamId)
	End Method
End Type

Type THistoricalNFL2024ReplayTest Extends TTest
	Method testCompleteNFLSeason() { test }
		AssertEquals(285, TNFL2024Replay.Run(AppDir + "/../examples/nfl_2024_replay.tsv"))
	End Method
End Type

Type TPostseasonSelectionTest Extends TTest
	Function Fixture:TFixtureState(home:Int, away:Int, homeScore:Int, awayScore:Int)
		Local fixture:TFixtureState = New TFixtureState
		fixture.homeTeamId = home
		fixture.awayTeamId = away
		fixture.scoreHome = homeScore
		fixture.scoreAway = awayScore
		fixture.status = EFixtureStatus.Completed
		Return fixture
	End Function

	Function Competition:TCompetition()
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 3
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.divisionId = "EAST"
			comp.participants :+ [participant]
		Next

		Return comp
	End Function

	Function Config:TPostseasonConfig()
		Local cfg:TPostseasonConfig = New TPostseasonConfig
		Local pool:TPostseasonPool = New TPostseasonPool
		pool.code = "CONFERENCE"
		pool.divisionIds = ["EAST"]
		cfg.pools = [pool]
		cfg.divisionWinnersPerDivision = 1
		cfg.divisionTie = New TPostseasonTieRules
		cfg.divisionTie.twoTeams = [EPostseasonCriterion.HeadToHead, EPostseasonCriterion.NetPoints]
		cfg.divisionTie.manyTeams = [EPostseasonCriterion.HeadToHead, EPostseasonCriterion.NetPoints]
		cfg.atLargeTie = cfg.divisionTie
		cfg.seedTie = cfg.divisionTie
		Return cfg
	End Function

	Method testThreeWayTieAndRecordedDecision() { test }
		Local comp:TCompetition = Competition()
		Local cfg:TPostseasonConfig = Config()
		Local state:TStageState = New TStageState
		state.status = EStageStatus.Complete
		state.fixtures = [Fixture(1, 2, 20, 10), Fixture(2, 3, 20, 13), Fixture(3, 1, 20, 19)]
		AssertEquals(1, TPostseasonSelector.Select(comp, state, cfg, "CONFERENCE").entrantIds[0])
		state.fixtures = [Fixture(1, 2, 20, 10), Fixture(2, 3, 20, 10), Fixture(3, 1, 20, 10)]
		Local rejected:Int
		Try
			TPostseasonSelector.Select(comp, state, cfg, "CONFERENCE")
		Catch problem:Object
			rejected = True
		End Try

		AssertTrue(rejected, "A sporting tie must not silently use participant ID")
		Local decision:TPostseasonTieDecision = New TPostseasonTieDecision
		decision.poolCode = "CONFERENCE"
		decision.participantIds = [3, 1, 2]
		decision.winnerId = 2
		decision.reason = "Recorded drawing of lots"
		cfg.tieDecisions = [decision]
		AssertEquals(2, TPostseasonSelector.Select(comp, state, cfg, "CONFERENCE").entrantIds[0])
	End Method

	Method testPostseasonRulesRoundTrip() { test }
		Local comp:TCompetition = Competition()
		Local stage:TStage = New TStage
		stage.id = "REG"
		stage.stageType = EStageType.League
		stage.config = New TLeagueConfig
		TLeagueConfig(stage.config).postseason = Config()
		comp.stages = [stage]
		Local path:String = "/private/tmp/tourney_postseason_config.json"
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local output:TStream = WriteStream(path)
		jconv.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		Local restored:TCompetition = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		Local saved:TPostseasonConfig = TLeagueConfig(restored.stages[0].config).postseason
		AssertEquals("CONFERENCE", saved.pools[0].code)
		AssertEquals(EPostseasonCriterion.HeadToHead.Ordinal(), saved.divisionTie.manyTeams[0].Ordinal())
	End Method
End Type

Type THistoricalF12021ReplayTest Extends TTest
	Method testFullSeasonAndHalfPoints() { test }
		Local timeline:TCompetitionTimeline = New TCompetitionTimeline
		AssertEquals(31, TF12021Replay.Run(AppDir + "/../examples/f1_2021_replay.tsv", timeline))
		AssertEquals(25, timeline.frames.Length)
		AssertEquals(31, timeline.participants.Length)
		AssertEquals("SPRINT", timeline.frames[9].sessionCode)
		AssertEquals("RACE", timeline.frames[10].sessionCode)
		AssertEquals("R10", timeline.frames[9].eventId)
		AssertEquals("R10", timeline.frames[10].eventId)
		AssertEquals(9, timeline.frames[9].classificationOrder[0])
		AssertEquals(9, timeline.frames[24].Board("DRIVERS").rows[0].participantId)
		AssertEquals(791, timeline.frames[24].Board("DRIVERS").rows[0].points)
		AssertEquals(108, timeline.frames[24].Board("CONSTRUCTORS").rows[0].participantId)
		AssertEquals(1227, timeline.frames[24].Board("CONSTRUCTORS").rows[0].points)
		AssertEquals("Max Verstappen", timeline.Participant(9).name)
		Local firstPoints:Int = timeline.frames[0].Board("DRIVERS").rows[0].points
		timeline.frames[24].Board("DRIVERS").rows[0].points = 0
		AssertEquals(firstPoints, timeline.frames[0].Board("DRIVERS").rows[0].points)
	End Method

	Method testExactPointConfigurationRoundTrips() { test }
		Local comp:TCompetition = New TCompetition
		Local stage:TStage = New TStage
		stage.id = "F1"
		stage.stageType = EStageType.Series
		Local cfg:TSeriesConfig = New TSeriesConfig
		cfg.pointsScale = 2
		cfg.scoring = New TScoringSystem
		Local tableEntry:TPointsTableEntry = New TPointsTableEntry
		tableEntry.position = 1
		tableEntry.pointsExact = "1.25"
		cfg.scoring.table = [tableEntry]
		Local bonus:TBonusRule = New TBonusRule
		bonus.code = "BONUS"
		bonus.pointsExact = "0.25"
		bonus.maxPointsPerAwardExact = "0.5"
		cfg.scoring.bonuses = [bonus]
		Local event:TSeriesEvent = New TSeriesEvent
		event.id = "BELGIUM"
		event.pointsMultiplierExact = "0.5"
		cfg.events = [event]
		stage.config = cfg
		comp.stages = [stage]
		Local path:String = "/private/tmp/tourney_f1_points_config.json"
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local output:TStream = WriteStream(path)
		jconv.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		Local restored:TCompetition = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		Local saved:TSeriesConfig = TSeriesConfig(restored.stages[0].config)
		AssertEquals(2, saved.pointsScale)
		AssertEquals("0.5", saved.events[0].pointsMultiplierExact)
		AssertEquals("1.25", saved.scoring.table[0].pointsExact)
		AssertEquals("0.25", saved.scoring.bonuses[0].pointsExact)
		AssertEquals("0.5", saved.scoring.bonuses[0].maxPointsPerAwardExact)
		AssertEquals(25, TSeriesScorer.EventPoints(restored.stages[0], "BELGIUM", 25))
	End Method
End Type

New TTestSuite.run()

Type TRoundRobinTest Extends TTest

	Method testRoundRobinCreatesCorrectNumberOfMatches() { test }
		Local ids:Int[] = [1, 2, 3, 4]
		Local fixtures:TFixture[] = GenerateRoundRobinFixturesN("test", ids, 1, 1)
		' For 4 teams, single round robin = 6 matches
		AssertEquals(6, fixtures.Length, "Expected 6 matches for 4 teams in single RR")
	End Method

	Method testDoubleRoundRobinHasTwiceMatches() { test }
		Local ids:Int[] = [1, 2, 3, 4]
		Local rrSingle:TFixture[] = GenerateRoundRobinFixturesN("test", ids, 1, 1)
		Local rrDouble:TFixture[] = GenerateRoundRobinFixturesN("test", ids, 2, 1)
		AssertEquals(rrSingle.Length * 2, rrDouble.Length, "Double round robin should double matches")
	End Method

	Method testAllPairsAppearExactlyOnceInSingleRR() { test }
		Local ids:Int[] = [1, 2, 3, 4]
		Local fixtures:TFixture[] = GenerateRoundRobinFixturesN("test", ids, 1, 1)
		Local pairSeen:Int[5, 5]
		For Local f:TFixture = EachIn fixtures
			pairSeen[f.homeTeamId, f.awayTeamId] :+ 1
			pairSeen[f.awayTeamId, f.homeTeamId] :+ 1
		Next
		' Every unordered pair should appear exactly once
		For Local i:Int = 1 To 4
			For Local j:Int = i + 1 To 4
				AssertEquals(1, pairSeen[i, j], "Teams " + i + " & " + j + " must meet once")
			Next
		Next
	End Method

End Type

Type TAutoBalancedGroupsTest Extends TTest

	Field groupScheduler:TGroupScheduler

	Method setup() { before }
		groupScheduler = New TGroupScheduler
	End Method

	Method testExactMultiple() { test }
		Local sizes:Int[] = groupScheduler.ComputeGroupSizes(32, 0, 8) ' 32 entrants, target 8
		' Expect 4 groups of 8
		AssertEquals(4, sizes.Length, "Should produce 4 groups")
		For Local s:Int = EachIn sizes
			AssertEquals(8, s, "Each group should have size 8")
		Next
	End Method

	Method testWithRemainder() { test }
		Local sizes:Int[] = groupScheduler.ComputeGroupSizes(130, 0, 8)
		' Sum must equal 130, sizes differ by at most 1, largest first
		Local sum:Int = 0, minS:Int = 999, maxS:Int = -999
		For Local i:Int = 0 Until sizes.Length
			sum :+ sizes[i]
			If sizes[i] < minS Then
				minS = sizes[i]
			End If

			If sizes[i] > maxS Then
				maxS = sizes[i]
			End If

			If i > 0 Then
				AssertTrue(sizes[i] <= sizes[i - 1], "Larger groups should appear first")
			End If
		Next

		AssertEquals(130, sum, "Sizes should sum to entrants")
		AssertTrue(maxS - minS <= 1, "Group sizes should differ by at most 1")
	End Method

	Method testExplicitGroupsIgnoresTargetSize() { test }
		Local sizes:Int[] = groupScheduler.ComputeGroupSizes(19, 5, 8) ' explicit 5 groups
		AssertEquals(5, sizes.Length, "Should honour explicit group count")
		Local sum:Int = 0
		For Local s:Int = EachIn sizes; sum :+ s; Next

		AssertEquals(19, sum, "Sizes should sum to entrants")
	End Method

End Type

Type TPlaceWithConstraintsTest Extends TTest

	Field groupScheduler:TGroupScheduler
	Field comp:TCompetition

	Method before() { before }
		comp = New TCompetition
		groupScheduler = New TGroupScheduler
	End Method

	' ---------- Infeasible: disallowSameRegion with too few groups ----------
	Method test_DisallowSameRegion_Infeasible_Throws() { test }
		' 8 entrants, 2 groups of 4, only 2 regions A/B each with 4 entrants
		Local parts:TParticipant[] = [..
            MakePart(1, "A", "D1"), MakePart(2, "A", "D1"), MakePart(3, "A", "D2"), MakePart(4, "A", "D2"), ..
            MakePart(5, "B", "D1"), MakePart(6, "B", "D1"), MakePart(7, "B", "D2"), MakePart(8, "B", "D2")..
        ]
		comp.participants = parts
		Local ids:Int[] = [1, 2, 3, 4, 5, 6, 7, 8]
		Local sizes:Int[] = [4, 4]
		Local c:TDrawConstraints = New TDrawConstraints
		c.disallowSameRegion = True
		c.maxFromRegion = 0
		c.disallowSameGroup = False
		c.avoidPairs = []

		Local idx:TDrawIndex = groupScheduler.BuildDrawIndex(parts, c.avoidPairs)

		Try
			groupScheduler.PlaceWithConstraints(comp, ids, sizes, c, idx)
			AssertTrue(False, "disallowSameRegion with A×4/B×4 over 2 groups must be infeasible")
		Catch o:Object
			' expected
		End Try
	End Method

	' ---------- Feasible: disallowSameRegion with 4 regions ----------
	Method test_DisallowSameRegion_Feasible_Succeeds() { test }
		' 8 entrants, 2 groups of 4, regions A/B/C/D (two of each overall)
		Local parts:TParticipant[] = [..
            MakePart(1, "A", "D1"), MakePart(2, "B", "D1"), MakePart(3, "C", "D2"), MakePart(4, "D", "D2"), ..
            MakePart(5, "A", "D1"), MakePart(6, "B", "D1"), MakePart(7, "C", "D2"), MakePart(8, "D", "D2")..
        ]
		comp.participants = parts
		Local ids:Int[] = [1, 2, 3, 4, 5, 6, 7, 8]
		Local sizes:Int[] = [4, 4]
		Local c:TDrawConstraints = New TDrawConstraints
		c.disallowSameRegion = True
		c.maxFromRegion = 0
		c.disallowSameGroup = False
		c.avoidPairs = []

		Local idx:TDrawIndex = groupScheduler.BuildDrawIndex(parts, c.avoidPairs)
		Local groups:Int[][] = groupScheduler.PlaceWithConstraints(comp, ids, sizes, c, idx)

		' Verify each group has 4 distinct regions
		For Local g:Int = 0 Until groups.Length
			Local seen:String[] = []
			For Local pid:Int = EachIn groups[g]
				Local r:String = ById(parts, pid).region

				Local found:Int
				For Local i:Int = 0 Until seen.Length
					if seen[i] = r Then
						found = True
						Exit
					End If
				Next

				AssertTrue(found = 0, "Duplicate region " + r + " in group " + g)
				seen :+ [r]
			Next

			AssertEquals(4, seen.Length, "Each group should end with 4 unique regions")
		Next
	End Method

	' ---------- Infeasible: disallowSameGroup (division) with only 2 groups ----------
	Method test_DisallowSameDivision_Infeasible_Throws() { test }
		' 8 entrants: D1×4 and D2×4, 2 groups, disallowSameGroup => impossible
		Local parts:TParticipant[] = [..
            MakePart(1, "A", "D1"), MakePart(2, "A", "D1"), MakePart(3, "A", "D1"), MakePart(4, "A", "D1"), ..
            MakePart(5, "B", "D2"), MakePart(6, "B", "D2"), MakePart(7, "B", "D2"), MakePart(8, "B", "D2")..
        ]
		comp.participants = parts
		Local ids:Int[] = [1, 2, 3, 4, 5, 6, 7, 8]
		Local sizes:Int[] = [4, 4]
		Local c:TDrawConstraints = New TDrawConstraints
		c.disallowSameRegion = False
		c.maxFromRegion = 0
		c.disallowSameGroup = True
		c.avoidPairs = []

		Local idx:TDrawIndex = groupScheduler.BuildDrawIndex(parts, c.avoidPairs)

		Try
			groupScheduler.PlaceWithConstraints(comp, ids, sizes, c, idx)
			AssertTrue(False, "disallowSameGroup with D1×4/D2×4 over 2 groups must be infeasible")
		Catch o:Object
			' expected
		End Try
	End Method

	' ---------- Feasible: disallowSameGroup with 4 divisions ----------
	Method test_DisallowSameDivision_Feasible_Succeeds() { test }
		' Divisions D1..D4 (two of each overall), 2 groups
		Local parts:TParticipant[] = [..
            MakePart(1, "A", "D1"), MakePart(2, "B", "D2"), MakePart(3, "A", "D3"), MakePart(4, "B", "D4"), ..
            MakePart(5, "A", "D1"), MakePart(6, "B", "D2"), MakePart(7, "A", "D3"), MakePart(8, "B", "D4")..
        ]
		comp.participants = parts
		Local ids:Int[] = [1, 2, 3, 4, 5, 6, 7, 8]
		Local sizes:Int[] = [4, 4]
		Local c:TDrawConstraints = New TDrawConstraints
		c.disallowSameRegion = False
		c.maxFromRegion = 0
		c.disallowSameGroup = True
		c.avoidPairs = []

		Local idx:TDrawIndex = groupScheduler.BuildDrawIndex(parts, c.avoidPairs)
		Local groups:Int[][] = groupScheduler.PlaceWithConstraints(comp, ids, sizes, c, idx)

		' Verify each group has 4 distinct divisions
		For Local g:Int = 0 Until groups.Length
			Local seen:String[] = []
			For Local pid:Int = EachIn groups[g]
				Local d:String = ById(parts, pid).divisionId

				Local found:Int
				For Local i:Int = 0 Until seen.Length
					if seen[i] = d Then
						found = True
						Exit
					End If
				Next

				AssertTrue(found = 0, "Duplicate division " + d + " in group " + g)
				seen :+ [d]
			Next

			AssertEquals(4, seen.Length, "Each group should end with 4 unique divisions")
		Next
	End Method

	' ---------- Feasible: maxFromRegion ----------
	Method test_MaxFromRegion_LimitsPerGroup() { test }
		' A×4, B×4 across 2 groups of 4; maxFromRegion=2 is feasible
		Local parts:TParticipant[] = [..
			MakePart(1, "A", "D1"), MakePart(2, "A", "D2"), MakePart(3, "A", "D1"), MakePart(4, "A", "D2"), ..
			MakePart(5, "B", "D1"), MakePart(6, "B", "D2"), MakePart(7, "B", "D1"), MakePart(8, "B", "D2")..
		]
		comp.participants = parts
		Local ids:Int[] = [1, 2, 3, 4, 5, 6, 7, 8]
		Local sizes:Int[] = [4, 4]
		Local c:TDrawConstraints = New TDrawConstraints
		c.disallowSameRegion = False
		c.maxFromRegion = 2
		c.disallowSameGroup = False
		c.avoidPairs = []

		' (Optional) sanity: assert feasibility for the test setup
		' AssertTrue(CheckFeasible(sizes, BuildDrawIndex(parts, c.avoidPairs), c), "Test setup should be feasible")

		Local idx:TDrawIndex = groupScheduler.BuildDrawIndex(parts, c.avoidPairs)
		Local groups:Int[][] = groupScheduler.PlaceWithConstraints(comp, ids, sizes, c, idx)

		For Local g:Int = 0 Until groups.Length
			Local a:Int = 0, b:Int = 0
			For Local pid:Int = EachIn groups[g]
				Local r:String = ById(parts, pid).region
				If r = "A" Then a :+ 1 Else b :+ 1
			Next

			AssertTrue(a <= 2, "Group " + g + ": region A should have ≤ 2")
			AssertTrue(b <= 2, "Group " + g + ": region B should have ≤ 2")
		Next
	End Method

	' ---------- Feasible: avoidPairs ----------
	Method test_AvoidPairs_Respected() { test }
		Local parts:TParticipant[] = [..
            MakePart(1, "A", "D1"), MakePart(2, "A", "D1"), MakePart(3, "B", "D2"), MakePart(4, "B", "D2"), ..
            MakePart(5, "C", "D3"), MakePart(6, "C", "D3"), MakePart(7, "D", "D4"), MakePart(8, "D", "D4")..
        ]
		comp.participants = parts
		Local ids:Int[] = [1, 2, 3, 4, 5, 6, 7, 8]
		Local sizes:Int[] = [4, 4]
		Local c:TDrawConstraints = New TDrawConstraints
		c.disallowSameRegion = False
		c.maxFromRegion = 0
		c.disallowSameGroup = False
		c.avoidPairs = [[1, 3], [2, 4], [5, 7], [6, 8]]

		Local idx:TDrawIndex = groupScheduler.BuildDrawIndex(parts, c.avoidPairs)
		Local groups:Int[][] = groupScheduler.PlaceWithConstraints(comp, ids, sizes, c, idx)

		For Local g:Int = 0 Until groups.Length
			Local inGroup:Int[9]
			For Local pid:Int = EachIn groups[g]; inGroup[pid] = 1; Next

			AssertTrue(Not(inGroup[1] = 1 And inGroup[3] = 1), "1 & 3 must not be together")
			AssertTrue(Not(inGroup[2] = 1 And inGroup[4] = 1), "2 & 4 must not be together")
			AssertTrue(Not(inGroup[5] = 1 And inGroup[7] = 1), "5 & 7 must not be together")
			AssertTrue(Not(inGroup[6] = 1 And inGroup[8] = 1), "6 & 8 must not be together")
		Next
	End Method

	' --- helpers ---
	Function MakePart:TParticipant(id:Int, region:String, divId:String)
		Local p:TParticipant = New TParticipant
		p.id = id; p.name = "P" + id; p.region = region; p.divisionId = divId
		Return p
	End Function

	Function ById:TParticipant(parts:TParticipant[], id:Int)
		For Local p:TParticipant = EachIn parts
			If p.id = id Then
				Return p
			End If
		Next

		Return Null
	End Function
End Type

Type TGroupSetBasedScorerTest Extends TTest

	Method testSetBasedScoringAndTiebreaks() { test }
		' Participants
		Local p1:TParticipant = MakeP(1, "", "")
		Local p2:TParticipant = MakeP(2, "", "")
		Local p3:TParticipant = MakeP(3, "", "")
		Local p4:TParticipant = MakeP(4, "", "")

		Local comp:TCompetition = New TCompetition
		comp.participants = [p1, p2, p3, p4]

		' Stage config (Group, 1 group, single RR, 1 point per win)
		Local stg:TStage = New TStage
		stg.id = "G"
		stg.stageType = EStageType.Group
		stg.input = New TEntrySource
		stg.input.seeding = New TSeedingPolicy
		stg.input.seeding.seedingMethod = ESeedingMethod.Random
		stg.input.constraints = New TDrawConstraints
		stg.config = New TGroupConfig
		TGroupConfig(stg.config).groups = 1
		TGroupConfig(stg.config).groupSize = 4
		TGroupConfig(stg.config).roundRobinPerOpponent = 1
		TGroupConfig(stg.config).pointsWin = 1
		TGroupConfig(stg.config).pointsDraw = 0
		TGroupConfig(stg.config).pointsLoss = 0
		TGroupConfig(stg.config).tiebreakers = [ETiebreaker.Points, ETiebreaker.GoalDifference, ETiebreaker.GoalsFor]

		' Fixtures (G1 round-robin)
		Local fx:TFixtureState[] = []
		fx :+ [ F("G_G1_R1_1v4", 1, 0, 1, 4, EFixtureStatus.Scheduled) ]
		fx :+ [ F("G_G1_R1_2v3", 1, 0, 2, 3, EFixtureStatus.Scheduled) ]
		fx :+ [ F("G_G1_R2_1v3", 2, 0, 1, 3, EFixtureStatus.Scheduled) ]
		fx :+ [ F("G_G1_R2_4v2", 2, 0, 4, 2, EFixtureStatus.Scheduled) ]
		fx :+ [ F("G_G1_R3_1v2", 3, 0, 1, 2, EFixtureStatus.Scheduled) ]
		fx :+ [ F("G_G1_R3_3v4", 3, 0, 3, 4, EFixtureStatus.Scheduled) ]
		For Local f:TFixtureState = EachIn fx; f.groupKey = "G1"; Next

		Local ss:TStageState = New TStageState
		ss.stageId = stg.id
		ss.fixtures = fx
		ss.leaderboard = New TLeaderboard; ss.leaderboard.rows = []
		ss.status = EStageStatus.Running
		ss.entrants = [1, 2, 3, 4]

		Local scorer:TSetBasedScorer = New TSetBasedScorer

		' Record 3 matches (best-of-3 sets as “games”):
		' 1 beats 4, 2–0
		scorer.ApplyResult(comp, stg, ss, "G_G1_R1_1v4", MakeResult([ S(1, 0), S(1, 0) ]))
		' 2 beats 3, 2–1
		scorer.ApplyResult(comp, stg, ss, "G_G1_R1_2v3", MakeResult([ S(1, 0), S(0, 1), S(1, 0) ]))
		' 1 beats 3, 2–1
		scorer.ApplyResult(comp, stg, ss, "G_G1_R2_1v3", MakeResult([ S(1, 0), S(0, 1), S(1, 0) ]))

		scorer.ComputeStandings(comp, stg, ss)

		' Expectations:
		' P1: 2W, points=2; sets GF= (2+2)=4, GA= (0+1)=1 → GD=+3
		' P2: 1W, points=1; sets GF= (2)=2, GA= (1)=1 → GD=+1
		' P3: 0W, points=0; sets GF= (1+1)=2, GA= (2+2)=4 → GD=-2
		' P4: 0W, points=0; sets GF=0, GA=2 → GD=-2

		Local r1:TLeaderboardRow = RowFor(ss, 1)
		Local r2:TLeaderboardRow = RowFor(ss, 2)
		Local r3:TLeaderboardRow = RowFor(ss, 3)
		Local r4:TLeaderboardRow = RowFor(ss, 4)

		AssertEquals(2, r1.points, "P1 points")
		AssertEquals(1, r2.points, "P2 points")
		AssertEquals(0, r3.points, "P3 points")
		AssertEquals(0, r4.points, "P4 points")

		AssertEquals(4, r1.gf, "P1 sets for")
		AssertEquals(1, r1.ga, "P1 sets against")

		' And check ordering (P1 > P2 > P3/P4 by GD then GF)
		AssertEquals(1, ss.leaderboard.rows[0].participantId, "Row 1 should be P1")
		AssertEquals(2, ss.leaderboard.rows[1].participantId, "Row 2 should be P2")
	End Method

	Function MakeResult:TResultPayload(sets:TSetScore[])
		Local r:TResultPayload = New TResultPayload
		r.kind = EResultKind.SetBased
		r.sets = sets
		Return r
	End Function

	Function MakeP:TParticipant(id:Int, r:String, d:String)
		Local p:TParticipant = New TParticipant
		p.id = id; p.name = "P" + id; p.region = r; p.divisionId = d
		Return p
	End Function

	Function F:TFixtureState(fid:String, round:Int, leg:Int, h:Int, a:Int, st:EFixtureStatus)
		Local f:TFixtureState = New TFixtureState
		f.id = fid; f.round = round; f.leg = leg; f.homeTeamId = h; f.awayTeamId = a; f.status = st
		Return f
	End Function

	Function S:TSetScore(h:Int, a:Int)
		Local s:TSetScore = New TSetScore
		s.home = h; s.away = a
		Return s
	End Function

	Function RowFor:TLeaderboardRow(ss:TStageState, pid:Int)
		For Local r:TLeaderboardRow = EachIn ss.leaderboard.rows
			If r.participantId = pid Then
				Return r
			End If
		Next

		Return Null
	End Function
End Type

Type TGroupAdvancerTopNTest Extends TTest

	Method testTop2PerGroupProducesFourQualifiers() { test }
		Local comp:TCompetition = New TCompetition
		comp.participants = [P(1), P(2), P(3), P(4), P(5), P(6)]

		Local stg:TStage = New TStage
		stg.id = "groups"
		stg.stageType = EStageType.Group
		stg.config = New TGroupConfig

		Local ss:TStageState = New TStageState
		ss.stageId = stg.id
		ss.leaderboard = New TLeaderboard

		' Provide per-group standings directly
		Local g1:TGroupTable = New TGroupTable
		g1.key = "G1"
		g1.rows = Rows([2, 1, 3], [3, 2, 1])   ' already sorted

		Local g2:TGroupTable = New TGroupTable
		g2.key = "G2"
		g2.rows = Rows([6, 5, 4], [3, 2, 1])

		ss.groups = [g1, g2]

		stg.advancement = [..
			RuleTo("next", EFilterKind.TopN, 2, EFilterScope.PerGroup)..
		]

		Local adv:TGroupAdvancer = New TGroupAdvancer
		Local q:TParticipant[] = adv.ProduceAdvancements(comp, stg, ss)

		AssertEquals(4, q.Length, "Should advance 2× per group = 4")
		AssertEquals(2, q[0].id, "G1 #1")
		AssertEquals(1, q[1].id, "G1 #2")
		AssertEquals(6, q[2].id, "G2 #1")
		AssertEquals(5, q[3].id, "G2 #2")
	End Method

	Function P:TParticipant(id:Int)
		Local p:TParticipant = New TParticipant
		p.id = id; p.name = "P" + id
		Return p
	End Function

	Function Rows:TLeaderboardRow[](ids:Int[], pts:Int[])
		Local out:TLeaderboardRow[] = []
		For Local i:Int = 0 Until ids.Length
			Local r:TLeaderboardRow = New TLeaderboardRow
			r.participantId = ids[i]
			r.points = pts[i]
			out :+ [r]
		Next

		Return out
	End Function

	Function RuleTo:TAdvancement(toId:String, kind:EFilterKind, n:Int, scope:EFilterScope)
		Local a:TAdvancement = New TAdvancement
		a.toStageId = toId
		a.rule = New TFilterRule
		a.rule.kind = kind
		a.rule.n = n
		a.rule.scope = scope
		Return a
	End Function
End Type

Type TAdminAndStatusTest Extends TTest

	Field engine:TCompetitionEngine = New TCompetitionEngine

	Method testAdminAdjustmentOverlaysAfterRecompute() { test }
		' Build a mini stage with a table
		Local comp:TCompetition = New TCompetition
		comp.participants = [P(1), P(2)]
		Local stg:TStage = New TStage; stg.id = "G"; stg.stageType = EStageType.Group
		stg.config = New TGroupConfig
		Local ss:TStageState = New TStageState
		ss.stageId = "G"; ss.leaderboard = New TLeaderboard
		ss.leaderboard.rows = [Row(1, 3), Row(2, 1)]

		' Apply a -2 adjustment to P1
		Local adj:TPointAdjustment = New TPointAdjustment
		adj.participantId = 1; adj.pointsDelta = -2; adj.reason = "sanction"

		engine.ApplyAdjustmentsToState(ss, [adj])

		' Overlay should be reflected
		AssertEquals(1, ss.leaderboard.rows[0].participantId, "Row order unchanged here")
		AssertEquals(1, ss.leaderboard.rows[0].points, "P1 points after -2 should be 1")

		' Simulate recompute (overwrite points), overlay reapplied
		ss.leaderboard.rows[0].points = 3
		ss.leaderboard.rows[1].points = 1
		engine.ApplyAdjustmentsOverlayToLeaderboard(ss)
		AssertEquals(1, ss.leaderboard.rows[0].points, "Overlay reapplied after recompute")
	End Method

	Method testStatusOnlyMarksFixture() { test }
		Local ss:TStageState = New TStageState
		ss.fixtures = [ FX("f1", EFixtureStatus.Scheduled), FX("f2", EFixtureStatus.Scheduled) ]
		engine.MarkFixtureStatus(ss, "f2", EFixtureStatus.Postponed)
		AssertEquals(EFixtureStatus.Postponed.Ordinal(), ss.fixtures[1].status.Ordinal(), "Fixture f2 should be postponed")
		AssertEquals(EFixtureStatus.Scheduled.Ordinal(), ss.fixtures[0].status.Ordinal(), "Fixture f1 untouched")
	End Method

	Function P:TParticipant(id:Int)
		Local p:TParticipant = New TParticipant; p.id = id; p.name = "P" + id; Return p
	End Function

	Function Row:TLeaderboardRow(pid:Int, pts:Int)
		Local r:TLeaderboardRow = New TLeaderboardRow; r.participantId = pid; r.points = pts; Return r
	End Function

	Function FX:TFixtureState(id:String, st:EFixtureStatus)
		Local f:TFixtureState = New TFixtureState; f.id = id; f.status = st; Return f
	End Function
End Type

Type TTimeScorerQualifyingTest Extends TTest

	Method testRanksByTimeAscendingWithPenalties() { test }
		' Participants 1..5
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 5
			Local p:TParticipant = New TParticipant
			p.id = i; p.name = "P" + i
			comp.participants :+ [p]
		Next

		' Series stage with NO points table (qualifying mode)
		Local stg:TStage = New TStage
		stg.id = "Q1"
		stg.stageType = EStageType.Series
		stg.config = New TSeriesConfig
		TSeriesConfig(stg.config).events = [ New TSeriesEvent ]
		TSeriesConfig(stg.config).scoring = New TScoringSystem
		TSeriesConfig(stg.config).scoring.mode = EScoringMode.TimeBased
		TSeriesConfig(stg.config).scoring.table = [] ' empty ⇒ qualifying mode

		' State: one "fixture" for the session; entrants are 1..5
		Local fx:TFixtureState = New TFixtureState
		fx.id = "Q1_SESSION"; fx.status = EFixtureStatus.Scheduled
		Local ss:TStageState = New TStageState
		ss.stageId = stg.id
		ss.fixtures = [fx]
		ss.leaderboard = New TLeaderboard; ss.leaderboard.rows = []
		ss.status = EStageStatus.Running
		ss.entrants = [1, 2, 3, 4, 5]

		Local scorer:TTimeScorer = New TTimeScorer

		' Times (ms): smaller is faster; include a penalty on P2 to push him behind P3
		Local times:TParticipantTime[] = [..
            PT(1, 92500, 0),  ' P1
            PT(2, 92300, 500), ' P2 raw faster but +0.5s penalty -> 92800
            PT(3, 92600, 0),  ' P3
            PT(4, 93000, 0), ..
            PT(5, 94000, 0)..
        ]

		scorer.ApplyResult(comp, stg, ss, "Q1_SESSION", MakeResult(times))

		' mark final so scorer picks it as the “last finalized event”
		ss.fixtures[0].status = EFixtureStatus.Completed

		scorer.ComputeStandings(comp, stg, ss)

		' Expected order by adjusted time: P1 (92.500), P3 (92.600), P2 (92.800), P4, P5
		AssertEquals(1, ss.leaderboard.rows[0].participantId, "Row 1 should be P1")
		AssertEquals(3, ss.leaderboard.rows[1].participantId, "Row 2 should be P3")
		AssertEquals(2, ss.leaderboard.rows[2].participantId, "Row 3 should be P2")
		AssertEquals(4, ss.leaderboard.rows[3].participantId, "Row 4 should be P4")
		AssertEquals(5, ss.leaderboard.rows[4].participantId, "Row 5 should be P5")

		' No points are awarded in qualifying mode
		For Local r:TLeaderboardRow = EachIn ss.leaderboard.rows
			AssertEquals(0, r.points, "Qualifying rows should have 0 points")
		Next
	End Method

	Function MakeResult:TResultPayload(times:TParticipantTime[])
		Local r:TResultPayload = New TResultPayload
		r.kind = EResultKind.TimeBased
		r.times = times
		Return r
	End Function

	Function PT:TParticipantTime(pid:Int, ms:Long, pen:Long)
		Local t:TParticipantTime = New TParticipantTime
		t.participantId = pid; t.millis = ms; t.penaltyMillis = pen
		Return t
	End Function
End Type

Type TTimeScorerSumTimesTest Extends TTest

	' --- Helpers ---
	Function P:TParticipant(id:Int)
		Local p:TParticipant = New TParticipant
		p.id = id; p.name = "P" + id
		Return p
	End Function

	Function PT:TParticipantTime(pid:Int, ms:Long, pen:Long)
		Local t:TParticipantTime = New TParticipantTime
		t.participantId = pid
		t.millis = ms
		t.penaltyMillis = pen
		Return t
	End Function

	' ========== Test 1: Sum across finalized sessions ==========
	Method testSumOfTimesAcrossSessions() { test }
		' Participants 1..3
		Local comp:TCompetition = New TCompetition
		comp.participants = [ P(1), P(2), P(3) ]

		' Stage config: Time-based + sumTimes
		Local stg:TStage = New TStage
		stg.id = "RALLY"
		stg.stageType = EStageType.Series
		stg.config = New TSeriesConfig
		TSeriesConfig(stg.config).scoring = New TScoringSystem
		TSeriesConfig(stg.config).scoring.mode = EScoringMode.TimeBased
		TSeriesConfig(stg.config).scoring.table = [] ' no position points
		TSeriesConfig(stg.config).scoring.aggregation = New TAggregation
		TSeriesConfig(stg.config).scoring.aggregation.sumTimes = True

		' Two sessions/fixtures
		Local ss:TStageState = New TStageState
		ss.stageId = stg.id
		ss.fixtures = []
		ss.leaderboard = New TLeaderboard; ss.leaderboard.rows = []
		ss.entrants = [1, 2, 3]
		ss.status = EStageStatus.Running

		Local fx1:TFixtureState = New TFixtureState; fx1.id = "SS1"; fx1.status = EFixtureStatus.Scheduled
		Local fx2:TFixtureState = New TFixtureState; fx2.id = "SS2"; fx2.status = EFixtureStatus.Scheduled
		ss.fixtures :+ [fx1, fx2]

		Local scorer:TTimeScorer = New TTimeScorer

		' SS1 times (ms)
		scorer.ApplyResult(comp, stg, ss, "SS1", MakeResult([..
            PT(1, 30000, 0), PT(2, 31000, 0), PT(3, 32000, 0)..
        ]))
		' SS2 times with a penalty on P1 that flips order vs P2:
		scorer.ApplyResult(comp, stg, ss, "SS2", MakeResult([..
            PT(1, 30000, 1500),  ' 30.000 + 1.500 = 31.500
            PT(2, 31000, 0),     ' 31.000
            PT(3, 33000, 0)..      ' 33.000
        ]))
		' ApplyTimes marks fixtures final

		scorer.ComputeStandings(comp, stg, ss)

		' Totals (ms):
		' P1 = 30,000 + 31,500 = 61,500
		' P2 = 31,000 + 31,000 = 62,000
		' P3 = 32,000 + 33,000 = 65,000
		' Order: P1, P2, P3
		AssertEquals(3, ss.leaderboard.rows.Length, "Should rank all entrants")
		AssertEquals(1, ss.leaderboard.rows[0].participantId, "Leader should be P1")
		AssertEquals(2, ss.leaderboard.rows[1].participantId, "Second should be P2")
		AssertEquals(3, ss.leaderboard.rows[2].participantId, "Third should be P3")

		' No points in sumTimes mode unless a points table is present
		For Local r:TLeaderboardRow = EachIn ss.leaderboard.rows
			AssertEquals(0, r.points, "No points expected in pure sumTimes mode")
		Next
	End Method

	' ========== Test 2: Non-final sessions ignored + entrants filter ==========
	Method testIgnoresNonFinalAndFiltersEntrants() { test }
		' Participants 1..4, but entrants only 1..3
		Local comp:TCompetition = New TCompetition
		comp.participants = [ P(1), P(2), P(3), P(4) ]

		Local stg:TStage = New TStage
		stg.id = "STAGE"
		stg.stageType = EStageType.Series
		stg.config = New TSeriesConfig
		TSeriesConfig(stg.config).scoring = New TScoringSystem
		TSeriesConfig(stg.config).scoring.mode = EScoringMode.TimeBased
		TSeriesConfig(stg.config).scoring.table = []
		TSeriesConfig(stg.config).scoring.aggregation = New TAggregation
		TSeriesConfig(stg.config).scoring.aggregation.sumTimes = True

		Local ss:TStageState = New TStageState
		ss.stageId = stg.id
		ss.leaderboard = New TLeaderboard
		ss.leaderboard.rows = []
		ss.status = EStageStatus.Running
		ss.entrants = [1, 2, 3]

		' Three fixtures: one scheduled (ignored), two final (counted)
		Local fA:TFixtureState = New TFixtureState; fA.id = "A"; fA.status = EFixtureStatus.Scheduled
		Local fB:TFixtureState = New TFixtureState; fB.id = "B"; fB.status = EFixtureStatus.Scheduled
		Local fC:TFixtureState = New TFixtureState; fC.id = "C"; fC.status = EFixtureStatus.Scheduled
		ss.fixtures = [fA, fB, fC]

		Local scorer:TTimeScorer = New TTimeScorer

		' A (scheduled) – should be ignored even if times exist
		scorer.ApplyResult(comp, stg, ss, "A", MakeResult([..
            PT(1, 10000, 0), PT(2, 10000, 0), PT(3, 10000, 0), PT(4, 1, 0)..
        ]))
		' Flip A back to scheduled to mimic a not-finalized session
		ss.fixtures[0].status = EFixtureStatus.Scheduled

		' B (final)
		scorer.ApplyResult(comp, stg, ss, "B", MakeResult([..
            PT(1, 12000, 0), PT(2, 11000, 0), PT(3, 13000, 0), PT(4, 9000, 0).. ' P4 should be ignored (not an entrant)
        ]))

		' C (final)
		scorer.ApplyResult(comp, stg, ss, "C", MakeResult([..
            PT(1, 11000, 0), PT(2, 11000, 500), PT(3, 11500, 0)..
        ]))

		scorer.ComputeStandings(comp, stg, ss)

		' Totals over B and C (A ignored, P4 ignored):
		' B: P1=12000, P2=11000, P3=13000
		' C: P1=11000, P2=11500 (11000+500), P3=11500
		' P1 total = 23000
		' P2 total = 22500
		' P3 total = 24500
		' Order: P2 (22.5s), P1 (23.0s), P3 (24.5s)
		AssertEquals(3, ss.leaderboard.rows.Length, "Only entrants should be ranked")
		AssertEquals(2, ss.leaderboard.rows[0].participantId, "Leader should be P2")
		AssertEquals(1, ss.leaderboard.rows[1].participantId, "Second should be P1")
		AssertEquals(3, ss.leaderboard.rows[2].participantId, "Third should be P3")
	End Method

	' ========== Test 3 (optional): deterministic tie-break ==========
	Method testTiesBreakByParticipantId() { test }
		' Ensure stable ordering when totals tie: lower participantId first
		Local comp:TCompetition = New TCompetition
		comp.participants = [ P(1), P(2) ]

		Local stg:TStage = New TStage
		stg.id = "TIE"
		stg.stageType = EStageType.Series
		stg.config = New TSeriesConfig
		TSeriesConfig(stg.config).scoring = New TScoringSystem
		TSeriesConfig(stg.config).scoring.mode = EScoringMode.TimeBased
		TSeriesConfig(stg.config).scoring.table = []
		TSeriesConfig(stg.config).scoring.aggregation = New TAggregation
		TSeriesConfig(stg.config).scoring.aggregation.sumTimes = True

		Local ss:TStageState = New TStageState
		ss.stageId = stg.id
		ss.leaderboard = New TLeaderboard; ss.leaderboard.rows = []
		ss.status = EStageStatus.Running
		ss.entrants = [1, 2]

		Local f1:TFixtureState = New TFixtureState; f1.id = "S1"; f1.status = EFixtureStatus.Scheduled
		Local f2:TFixtureState = New TFixtureState; f2.id = "S2"; f2.status = EFixtureStatus.Scheduled
		ss.fixtures = [f1, f2]

		Local scorer:TTimeScorer = New TTimeScorer

		' Build exact tie on totals: (1: 10k + 12k) vs (2: 11k + 11k)
		scorer.ApplyResult(comp, stg, ss, "S1", MakeResult([ PT(1, 10000, 0), PT(2, 11000, 0) ]))
		scorer.ApplyResult(comp, stg, ss, "S2", MakeResult([ PT(1, 12000, 0), PT(2, 11000, 0) ]))

		scorer.ComputeStandings(comp, stg, ss)

		' Tie-breaker rule (as implemented earlier): lower participantId first
		AssertEquals(1, ss.leaderboard.rows[0].participantId, "Tie: lower participantId first")
		AssertEquals(2, ss.leaderboard.rows[1].participantId, "Tie: higher participantId second")
	End Method

	Function MakeResult:TResultPayload(times:TParticipantTime[])
		Local r:TResultPayload = New TResultPayload
		r.kind = EResultKind.TimeBased
		r.times = times
		Return r
	End Function
End Type

Type TTimeScorerDnfDsqTest Extends TTest

	Function P:TParticipant(id:Int)
		Local p:TParticipant = New TParticipant
		p.id = id; p.name = "P" + id
		Return p
	End Function

	Function PT:TParticipantTime(pid:Int, ms:Long, pen:Long, st:ETimeStatus)
		Local t:TParticipantTime = New TParticipantTime
		t.participantId = pid; t.millis = ms; t.penaltyMillis = pen; t.status = st
		Return t
	End Function

	' ========== 1) Qualifying: finishers first by time, then DNF, then DSQ ==========
	Method testQualifyingDnfDsqOrdering() { test }
		Local comp:TCompetition = New TCompetition
		comp.participants = [P(1), P(2), P(3), P(4), P(5)]

		Local stg:TStage = New TStage
		stg.id = "Q"
		stg.stageType = EStageType.Series
		stg.config = New TSeriesConfig
		TSeriesConfig(stg.config).scoring = New TScoringSystem
		TSeriesConfig(stg.config).scoring.mode = EScoringMode.TimeBased
		TSeriesConfig(stg.config).scoring.table = [] ' qualifying mode
		TSeriesConfig(stg.config).scoring.aggregation = New TAggregation ' default false

		Local ss:TStageState = New TStageState
		ss.stageId = stg.id
		ss.fixtures = [ New TFixtureState ]
		ss.fixtures[0].id = "QF"; ss.fixtures[0].status = EFixtureStatus.Scheduled
		ss.leaderboard = New TLeaderboard; ss.leaderboard.rows = []
		ss.entrants = [1, 2, 3, 4, 5]

		Local scorer:TTimeScorer = New TTimeScorer

		' P1 finishes 92.5, P2 finishes 92.8 (penalty), P3 DNF, P4 DSQ, P5 finishes 93.0
		scorer.ApplyResult(comp, stg, ss, "QF", MakeResult([..
            PT(1, 92500, 0, ETimeStatus.Finished), ..
            PT(2, 92300, 500, ETimeStatus.Finished), ..
            PT(3, 0, 0, ETimeStatus.DNF), ..
            PT(4, 0, 0, ETimeStatus.DSQ), ..
            PT(5, 93000, 0, ETimeStatus.Finished)..
        ]))

		scorer.ComputeStandings(comp, stg, ss)

		' Expected order: P1 (92.5), P2 (92.8), P5 (93.0), then P3 (DNF), then P4 (DSQ)
		AssertEquals(1, ss.leaderboard.rows[0].participantId, "P1 first")
		AssertEquals(2, ss.leaderboard.rows[1].participantId, "P2 second")
		AssertEquals(5, ss.leaderboard.rows[2].participantId, "P5 third")
		AssertEquals(3, ss.leaderboard.rows[3].participantId, "P3 DNF fourth")
		AssertEquals(4, ss.leaderboard.rows[4].participantId, "P4 DSQ last")
	End Method

	' ========== 2) SumTimes: any non-finish puts you behind all finishers ==========
	Method testSumTimesDNFFallsBehindFinishers() { test }
		Local comp:TCompetition = New TCompetition
		comp.participants = [P(1), P(2), P(3)]

		Local stg:TStage = New TStage
		stg.id = "RALLY"
		stg.stageType = EStageType.Series
		stg.config = New TSeriesConfig
		TSeriesConfig(stg.config).scoring = New TScoringSystem
		TSeriesConfig(stg.config).scoring.mode = EScoringMode.TimeBased
		TSeriesConfig(stg.config).scoring.table = []
		TSeriesConfig(stg.config).scoring.aggregation = New TAggregation
		TSeriesConfig(stg.config).scoring.aggregation.sumTimes = True

		Local ss:TStageState = New TStageState
		ss.stageId = stg.id
		ss.fixtures = [ New TFixtureState, New TFixtureState ]
		ss.fixtures[0].id = "SS1"; ss.fixtures[0].status = EFixtureStatus.Scheduled
		ss.fixtures[1].id = "SS2"; ss.fixtures[1].status = EFixtureStatus.Scheduled
		ss.leaderboard = New TLeaderboard; ss.leaderboard.rows = []
		ss.entrants = [1, 2, 3]

		Local scorer:TTimeScorer = New TTimeScorer

		' SS1: all finish
		scorer.ApplyResult(comp, stg, ss, "SS1", MakeResult([..
            PT(1, 30000, 0, ETimeStatus.Finished), ..
            PT(2, 30500, 0, ETimeStatus.Finished), ..
            PT(3, 31000, 0, ETimeStatus.Finished)..
        ]))
		' SS2: P1 DNF, others finish
		scorer.ApplyResult(comp, stg, ss, "SS2", MakeResult([..
            PT(1, 0, 0, ETimeStatus.DNF), ..
            PT(2, 30000, 0, ETimeStatus.Finished), ..
            PT(3, 29500, 0, ETimeStatus.Finished)..
        ]))

		scorer.ComputeStandings(comp, stg, ss)

		' Even though P1 led after SS1, the DNF puts P1 behind all finishers overall:
		' Finishers: P2 total = 60500; P3 total = 60500 (tie → lower id first => P2)
		' DNF: P1 goes after both
		AssertEquals(2, ss.leaderboard.rows[0].participantId, "P2 first (tie broken by id)")
		AssertEquals(3, ss.leaderboard.rows[1].participantId, "P3 second")
		AssertEquals(1, ss.leaderboard.rows[2].participantId, "P1 (DNF) last among these")
	End Method

	' ========== 3) Points table: only finishers earn points ==========
	Method testPointsAwardedOnlyToFinishers() { test }
		Local comp:TCompetition = New TCompetition
		comp.participants = [P(1), P(2), P(3), P(4)]

		Local stg:TStage = New TStage
		stg.id = "RACE"
		stg.stageType = EStageType.Series
		stg.config = New TSeriesConfig
		TSeriesConfig(stg.config).scoring = New TScoringSystem
		TSeriesConfig(stg.config).scoring.mode = EScoringMode.TimeBased
		TSeriesConfig(stg.config).scoring.table = [..
            NewPoints(1, 10), NewPoints(2, 6), NewPoints(3, 4), NewPoints(4, 3)..
        ]
		TSeriesConfig(stg.config).scoring.aggregation = New TAggregation ' not sumTimes here

		Local ss:TStageState = New TStageState
		ss.stageId = stg.id
		ss.fixtures = [ New TFixtureState ]
		ss.fixtures[0].id = "R1"; ss.fixtures[0].status = EFixtureStatus.Scheduled
		ss.leaderboard = New TLeaderboard; ss.leaderboard.rows = []
		ss.entrants = [1, 2, 3, 4]

		Local scorer:TTimeScorer = New TTimeScorer

		' P1 finishes, P2 DNF, P3 finishes, P4 DSQ
		scorer.ApplyResult(comp, stg, ss, "R1", MakeResult([..
            PT(1, 60000, 0, ETimeStatus.Finished), ..
            PT(2, 0, 0, ETimeStatus.DNF), ..
            PT(3, 61000, 0, ETimeStatus.Finished), ..
            PT(4, 0, 0, ETimeStatus.DSQ)..
        ]))

		scorer.ComputeStandings(comp, stg, ss)

		' Points: only finishers (P1, P3) get points -> 10 and 6
		Local r1:TLeaderboardRow = Row(ss, 1)
		Local r2:TLeaderboardRow = Row(ss, 2)
		Local r3:TLeaderboardRow = Row(ss, 3)
		Local r4:TLeaderboardRow = Row(ss, 4)

		AssertEquals(10, r1.points, "P1 should get winner points")
		AssertEquals(6, r3.points, "P3 should get second-place points")
		AssertEquals(0, r2.points, "P2 DNF no points")
		AssertEquals(0, r4.points, "P4 DSQ no points")

		' Order should be P1, P3, then P2 (DNF), then P4 (DSQ)
		AssertEquals(1, ss.leaderboard.rows[0].participantId, "P1 first")
		AssertEquals(3, ss.leaderboard.rows[1].participantId, "P3 second")
		AssertEquals(2, ss.leaderboard.rows[2].participantId, "P2 DNF third")
		AssertEquals(4, ss.leaderboard.rows[3].participantId, "P4 DSQ last")
	End Method

	Function NewPoints:TPointsTableEntry(pos:Int, pts:Int)
		Local e:TPointsTableEntry = New TPointsTableEntry
		e.position = pos; e.points = pts
		Return e
	End Function

	Function Row:TLeaderboardRow(ss:TStageState, pid:Int)
		For Local r:TLeaderboardRow = EachIn ss.leaderboard.rows
			If r.participantId = pid Then
				Return r
			End If
		Next

		Return Null
	End Function

	Function MakeResult:TResultPayload(times:TParticipantTime[])
		Local r:TResultPayload = New TResultPayload
		r.kind = EResultKind.TimeBased
		r.times = times
		Return r
	End Function
End Type

Type TBracketSeedingTest Extends TTest

	Method testSeededQuarterfinalPairs() { test }
		Local comp:TCompetition = New TCompetition
		comp.participants = []
		For Local s:Int = 1 To 8
			comp.participants :+ [ P(s, s) ] ' id=seed
		Next

		Local stg:TStage = New TStage
		stg.id = "BR"
		stg.stageType = EStageType.Bracket
		stg.input = New TEntrySource
		stg.input.seeding = New TSeedingPolicy
		stg.input.seeding.seedingMethod = ESeedingMethod.Ranking  ' use seed (rank) from meta
		stg.config = New TBracketConfig
		TBracketConfig(stg.config).size = 8
		TBracketConfig(stg.config).format = EBracketFormat.SingleElim
		TBracketConfig(stg.config).reseedEachRound = False
		TBracketConfig(stg.config).byes = 0
		TBracketConfig(stg.config).matchFormat = New TMatchFormat
		TBracketConfig(stg.config).matchFormat.legs = 1
		TBracketConfig(stg.config).policy = New TSchedulePolicy
		TBracketConfig(stg.config).policy.venuePolicy = New TVenuePolicy
		TBracketConfig(stg.config).policy.venuePolicy.venueType = EVenue.HigherSeedHome

		Local sched:TBracketScheduler = New TBracketScheduler
		Local fx:TFixtureState[] = sched.BuildFixtures(comp, stg)

		' Pull QF round (round=1)
		Local qf:TFixtureState[] = FilterRound(fx, 1)
		AssertEquals(4, qf.Length, "Expect 4 quarterfinals")

		' Normalize pairs as unordered sets to check matching
		AssertTrue(HasPair(qf, 1, 8), "QF must include 1 vs 8")
		AssertTrue(HasPair(qf, 4, 5), "QF must include 4 vs 5")
		AssertTrue(HasPair(qf, 3, 6), "QF must include 3 vs 6")
		AssertTrue(HasPair(qf, 2, 7), "QF must include 2 vs 7")

		' Check legs=1 for each QF
		For Local f:TFixtureState = EachIn qf
			AssertEquals(1, f.leg, "QF should be single-leg")
		Next
	End Method

	Function P:TParticipant(id:Int, seed:Int)
		Local p:TParticipant = New TParticipant
		p.id = id; p.name = "Seed" + seed
		' Store rank in meta if your seeding reads from there; otherwise, your ESeedingMethod.Ranking can just use id.
		' If you do require meta["rank"], set it here.
		Return p
	End Function

	Function FilterRound:TFixtureState[](f:TFixtureState[], rnd:Int)
		Local out:TFixtureState[]
		For Local x:TFixtureState = EachIn f
			If x.round = rnd Then
				out :+ [x]
			End If
		Next

		Return out
	End Function

	Function HasPair:Int(f:TFixtureState[], a:Int, b:Int) {asBool}
		For Local x:TFixtureState = EachIn f
			Local h:Int = x.homeTeamId, aw:Int = x.awayTeamId
			If (h = a And aw = b) Or (h = b And aw = a) Then
				Return True
			End If
		Next

		Return False
	End Function

End Type

Type TBracketTwoLegTest Extends TTest

	Method testTwoLegTiesEmittedInRound1() { test }
		Local comp:TCompetition = New TCompetition
		comp.participants = []
		For Local s:Int = 1 To 4
			comp.participants :+ [ P(s) ]
		Next

		Local stg:TStage = New TStage
		stg.id = "BR_2L"
		stg.stageType = EStageType.Bracket
		stg.input = New TEntrySource
		stg.input.seeding = New TSeedingPolicy
		stg.input.seeding.seedingMethod = ESeedingMethod.Ranking
		stg.config = New TBracketConfig
		TBracketConfig(stg.config).size = 4
		TBracketConfig(stg.config).format = EBracketFormat.SingleElim
		TBracketConfig(stg.config).reseedEachRound = False
		TBracketConfig(stg.config).byes = 0
		TBracketConfig(stg.config).matchFormat = New TMatchFormat
		TBracketConfig(stg.config).matchFormat.legs = 2
		TBracketConfig(stg.config).matchFormat.aggregateScores = True

		Local sched:TBracketScheduler = New TBracketScheduler
		Local fx:TFixtureState[] = sched.BuildFixtures(comp, stg)

		' Round 1 should have 2 ties x 2 legs = 4 fixtures
		Local r1:TFixtureState[] = FilterRound(fx, 1)
		AssertEquals(4, r1.Length, "Round 1 should emit two-leg fixtures for two ties")

		' Check that for each unordered pair, we have leg=1 and leg=2
		AssertTrue(HasTwoLegs(r1), "Each pairing should have leg 1 and leg 2")
	End Method

	Function P:TParticipant(id:Int)
		Local p:TParticipant = New TParticipant
		p.id = id; p.name = "Seed" + id
		Return p
	End Function

	Function FilterRound:TFixtureState[](f:TFixtureState[], rnd:Int)
		Local out:TFixtureState[]
		For Local x:TFixtureState = EachIn f
			If x.round = rnd Then
				out :+ [x]
			End If
		Next

		Return out
	End Function

	Function HasTwoLegs:Int(fixtures:TFixtureState[])
		' Build signatures per pairing: minId-maxId -> legs seen
		Local seen:TStringMap = New TStringMap
		For Local f:TFixtureState = EachIn fixtures
			Local a:Int = Min(f.homeTeamId, f.awayTeamId)
			Local b:Int = Max(f.homeTeamId, f.awayTeamId)
			Local key:String = a + "-" + b
			Local val:String = String(seen.ValueForKey(key))
			If val = "" Then
				val = "0,0"
			End If
			' parse
			Local l1:Int = Int(val.Split(",")[0])
			Local l2:Int = Int(val.Split(",")[1])
			If f.leg = 1 Then
				l1 = 1
			End If

			If f.leg = 2 Then
				l2 = 1
			End If

			seen.Insert(key, l1 + "," + l2)
		Next

		For Local it:String = EachIn seen.Keys()
			Local val:String = String(seen.ValueForKey(it))
			Local parts:String[] = val.Split(",")
			If parts.Length <> 2 Then
				Return False
			End If

			If Int(parts[0]) <> 1 Or Int(parts[1]) <> 1 Then
				Return False
			End If
		Next

		Return True
	End Function

End Type

Type TBracketByesTest Extends TTest

	Method testTopSeedsReceiveByes() { test }
		Local comp:TCompetition = New TCompetition
		comp.participants = []
		For Local s:Int = 1 To 6
			comp.participants :+ [ P(s) ]
		Next

		Local stg:TStage = New TStage
		stg.id = "BR_BYE"
		stg.stageType = EStageType.Bracket
		stg.input = New TEntrySource
		stg.input.seeding = New TSeedingPolicy
		stg.input.seeding.seedingMethod = ESeedingMethod.Ranking
		stg.config = New TBracketConfig
		TBracketConfig(stg.config).size = 8
		TBracketConfig(stg.config).format = EBracketFormat.SingleElim
		TBracketConfig(stg.config).reseedEachRound = False
		TBracketConfig(stg.config).byes = 2
		TBracketConfig(stg.config).matchFormat = New TMatchFormat
		TBracketConfig(stg.config).matchFormat.legs = 1

		Local sched:TBracketScheduler = New TBracketScheduler
		Local fx:TFixtureState[] = sched.BuildFixtures(comp, stg)

		Local r1:TFixtureState[] = FilterRound(fx, 1)
		AssertEquals(2, r1.Length, "With 2 byes in an 8-slot bracket and 6 entrants, round 1 should have 2 matches")

		' Optional: check that seeds 1 and 2 do not appear in round 1, i.e., they received byes.
		For Local f:TFixtureState = EachIn r1
			AssertTrue(f.homeTeamId <> 1 And f.awayTeamId <> 1, "Seed 1 should have a bye in R1")
			AssertTrue(f.homeTeamId <> 2 And f.awayTeamId <> 2, "Seed 2 should have a bye in R1")
		Next
	End Method

	Function P:TParticipant(id:Int)
		Local p:TParticipant = New TParticipant
		p.id = id; p.name = "Seed" + id
		Return p
	End Function

	Function FilterRound:TFixtureState[](f:TFixtureState[], rnd:Int)
		Local out:TFixtureState[] = []
		For Local x:TFixtureState = EachIn f
			If x.round = rnd Then
				out :+ [x]
			End If
		Next

		Return out
	End Function

End Type

' --- helpers ---
Function BrStage:TStage(id:String, size:Int, reseed:Int)
	Local stg:TStage = New TStage
	stg.id = id
	stg.stageType = EStageType.Bracket
	stg.input = New TEntrySource
	stg.input.seeding = New TSeedingPolicy
	stg.input.seeding.seedingMethod = ESeedingMethod.Ranking
	stg.config = New TBracketConfig
	TBracketConfig(stg.config).size = size
	TBracketConfig(stg.config).format = EBracketFormat.SingleElim
	TBracketConfig(stg.config).reseedEachRound = reseed
	TBracketConfig(stg.config).byes = 0
	TBracketConfig(stg.config).matchFormat = New TMatchFormat
	TBracketConfig(stg.config).matchFormat.legs = 1
	TBracketConfig(stg.config).policy = New TSchedulePolicy
	TBracketConfig(stg.config).policy.venuePolicy = New TVenuePolicy
	TBracketConfig(stg.config).policy.venuePolicy.venueType = EVenue.HigherSeedHome
	Return stg
End Function

Function CountRound:Int(fx:TFixtureState[], rnd:Int)
	Local n:Int = 0
	For Local f:TFixtureState = EachIn fx; If f.round = rnd Then n :+ 1
	Next

	Return n
End Function

Function HasPair:Int(fx:TFixtureState[], a:Int, b:Int)
	For Local f:TFixtureState = EachIn fx
		If (f.homeTeamId = a And f.awayTeamId = b) Or (f.homeTeamId = b And f.awayTeamId = a) Then
			Return True
		End If
	Next

	Return False
End Function

Function Sc(engine:TCompetitionEngine, comp:TCompetition, state:TCompetitionState, stageId:String, fid:String, h:Int, a:Int)
	Local res:TResultPayload = New TResultPayload
	res.kind = EResultKind.HeadToHeadScore
	res.scoreHome = h; res.scoreAway = a
	engine.RecordResult(comp, state, stageId, fid, res)
End Function

Type TBracketPipelineFixedTest Extends TTest

	Method testQFtoSFtoFinal_FixedBracket() { test }
		' --- Build competition with 3 bracket stages ---
		Local comp:TCompetition = New TCompetition
		comp.name = "Playoffs (Fixed)"
		For Local s:Int = 1 To 8
			Local p:TParticipant = New TParticipant
			p.id = s; p.name = "Seed" + s
			comp.participants :+ [p]
		Next

		' QF: size 8, fixed
		Local qf:TStage = BrStage("QF", 8, False)
		' SF: size 4, fixed
		Local sf:TStage = BrStage("SF", 4, False)
		' Final: size 2, fixed
		Local fin:TStage = BrStage("F", 2, False)

		comp.stages = [qf, sf, fin]

		' --- Init engine state: should schedule QF fixtures (R1) ---
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)

		Local state:TCompetitionState = engine.Initialize(comp)

		' Sanity: have 4 QF matches
		Local qfSS:TStageState = state.stages[0]
		AssertEquals(4, CountRound(qfSS.fixtures, 1), "QF should schedule 4 matches")

		' --- Play all QF results (winners: 1,5,3,2) ---
		Sc(engine, comp, state, "QF", "QF_R1_M1_L1", 3, 0) ' 1 beats 8
		Sc(engine, comp, state, "QF", "QF_R1_M2_L1", 1, 2) ' 5 beats 4
		Sc(engine, comp, state, "QF", "QF_R1_M3_L1", 2, 0) ' 3 beats 6
		Sc(engine, comp, state, "QF", "QF_R1_M4_L1", 1, 0) ' 2 beats 7

		' Engine should have advanced pipeline: SF now running with 2 matches
		Local sfSS:TStageState = state.stages[1]
		AssertEquals(EStageStatus.Running.Ordinal(), sfSS.status.Ordinal(), "SF should be initialized")
		AssertEquals(2, CountRound(sfSS.fixtures, 1), "SF should have 2 matches")

		' Fixed bracket layout expects SF pairs: (M1 vs M2) and (M3 vs M4) winners -> (1 vs 5) and (3 vs 2)
		AssertTrue(HasPair(sfSS.fixtures, 1, 5), "SF must include 1 vs 5")
		AssertTrue(HasPair(sfSS.fixtures, 3, 2), "SF must include 3 vs 2")

		' --- Play SF winners (1,3) ---
		Sc(engine, comp, state, "SF", "SF_R1_M1_L1", 2, 1) ' 1 beats 5
		Sc(engine, comp, state, "SF", "SF_R1_M2_L1", 0, 1) ' 3 beats 2

		' Engine should have advanced pipeline: Final now running with 1 match
		Local fSS:TStageState = state.stages[2]
		AssertEquals(EStageStatus.Running.Ordinal(), fSS.status.Ordinal(), "Final should be initialized")
		AssertEquals(1, CountRound(fSS.fixtures, 1), "Final should have 1 match")
		AssertTrue(HasPair(fSS.fixtures, 1, 3), "Final must be 1 vs 3")
	End Method

End Type

Type TBracketPipelineReseedTest Extends TTest

	Method testQFtoSFtoFinal_ReseedEachRound() { test }
		Local comp:TCompetition = New TCompetition
		For Local s:Int = 1 To 8
			Local p:TParticipant = New TParticipant; p.id = s; p.name = "Seed" + s
			comp.participants :+ [p]
		Next

		' QF reseed flag is irrelevant (only one round); SF & Final set reseed=True
		Local qf:TStage = BrStage("QF", 8, True)
		Local sf:TStage = BrStage("SF", 4, True)
		Local fin:TStage = BrStage("F", 2, True)
		comp.stages = [qf, sf, fin]

		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)

		Local state:TCompetitionState = engine.Initialize(comp)

		' QF winners: 1,5,3,2
		Sc(engine, comp, state, "QF", "QF_R1_M1_L1", 3, 0)
		Sc(engine, comp, state, "QF", "QF_R1_M2_L1", 1, 2)
		Sc(engine, comp, state, "QF", "QF_R1_M3_L1", 2, 0)
		Sc(engine, comp, state, "QF", "QF_R1_M4_L1", 1, 0)

		' SF should pair highest vs lowest → 1 vs 5, and 2 vs 3
		Local sfSS:TStageState = state.stages[1]
		AssertTrue(HasPair(sfSS.fixtures, 1, 5), "Reseed SF must include 1 vs 5")
		AssertTrue(HasPair(sfSS.fixtures, 2, 3), "Reseed SF must include 2 vs 3")

		' Play SF winners (1,2) so final will be 1 vs 2
		Sc(engine, comp, state, "SF", "SF_R1_M1_L1", 2, 1) ' 1 beats 5
		Sc(engine, comp, state, "SF", "SF_R1_M2_L1", 1, 0) ' 2 beats 3
		Local fSS:TStageState = state.stages[2]
		AssertTrue(HasPair(fSS.fixtures, 1, 2), "Final should be 1 vs 2 under reseed")
	End Method

End Type

Type TBracketPipelineAggregateTest Extends TTest

	Method testAggregateSemisToFinal() { test }
		Local comp:TCompetition = New TCompetition
		For Local s:Int = 1 To 4
			Local p:TParticipant = New TParticipant; p.id = s; p.name = "Seed" + s
			comp.participants :+ [p]
		Next

		' SF stage: size 4, legs=2 aggregate; Final size 2, legs=1
		Local sf:TStage = BrStage("SF", 4, False)
		TBracketConfig(sf.config).matchFormat.legs = 2
		TBracketConfig(sf.config).matchFormat.aggregateScores = True

		Local fin:TStage = BrStage("F", 2, False)

		Local compObj:TCompetition = comp
		compObj.stages = [sf, fin]

		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)

		Local state:TCompetitionState = engine.Initialize(comp)

		' Two ties x 2 legs:
		' Tie A (1 vs 4): 2-1, then 1-1 → seed 1 advances
		Sc(engine, compObj, state, "SF", "SF_R1_M1_L1", 2, 1)
		Sc(engine, compObj, state, "SF", "SF_R1_M1_L2", 1, 1)
		' Tie B (2 vs 3): 0-1, then 1-1 → seed 3 advances
		Sc(engine, compObj, state, "SF", "SF_R1_M2_L1", 0, 1)
		Sc(engine, compObj, state, "SF", "SF_R1_M2_L2", 1, 1)

		' Final initialized: 1 vs 3
		Local fSS:TStageState = state.stages[1]
		AssertEquals(1, CountRound(fSS.fixtures, 1), "Final should have one tie")
		AssertTrue(HasPair(fSS.fixtures, 1, 3), "Final must be seed 1 vs seed 3")
	End Method
End Type

Type TBracketVenueNeutralTest Extends TTest

	Method testNeutralVenue_QFtoSF() { test }
		Local comp:TCompetition = New TCompetition
		For Local s:Int = 1 To 8
			Local p:TParticipant = New TParticipant; p.id = s; p.name = "Seed" + s
			comp.participants :+ [p]
		Next

		' QF (neutral), SF (neutral)
		Local qf:TStage = BrStageNeutral("QF", 8)
		Local sf:TStage = BrStageNeutral("SF", 4)
		comp.stages = [qf, sf]

		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)

		Local state:TCompetitionState = engine.Initialize(comp)

		' Play QFs – winners: 1,5,3,2 (same as before)
		Sc(engine, comp, state, "QF", "QF_R1_M1_L1", 3, 0) ' 1>8
		Sc(engine, comp, state, "QF", "QF_R1_M2_L1", 1, 2) ' 5>4
		Sc(engine, comp, state, "QF", "QF_R1_M3_L1", 2, 0) ' 3>6
		Sc(engine, comp, state, "QF", "QF_R1_M4_L1", 1, 0) ' 2>7

		' SF initialized under neutral venue; pairs must be valid regardless of home/away
		Local sfSS:TStageState = state.stages[1]
		AssertEquals(2, CountRound(sfSS.fixtures, 1), "SF should have 2 matches")
		AssertTrue(HasUnorderedPair(sfSS.fixtures, 1, 5), "SF includes 1 vs 5")
		AssertTrue(HasUnorderedPair(sfSS.fixtures, 3, 2), "SF includes 3 vs 2")
	End Method

	Function BrStageNeutral:TStage(id:String, size:Int)
		Local stg:TStage = New TStage
		stg.id = id
		stg.stageType = EStageType.Bracket
		stg.input = New TEntrySource
		stg.input.seeding = New TSeedingPolicy
		stg.input.seeding.seedingMethod = ESeedingMethod.Ranking
		stg.config = New TBracketConfig
		TBracketConfig(stg.config).size = size
		TBracketConfig(stg.config).format = EBracketFormat.SingleElim
		TBracketConfig(stg.config).reseedEachRound = False
		TBracketConfig(stg.config).byes = 0
		TBracketConfig(stg.config).matchFormat = New TMatchFormat
		TBracketConfig(stg.config).matchFormat.legs = 1
		TBracketConfig(stg.config).policy = New TSchedulePolicy
		TBracketConfig(stg.config).policy.venuePolicy = New TVenuePolicy
		TBracketConfig(stg.config).policy.venuePolicy.venueType = EVenue.Neutral
		Return stg
	End Function

	Function CountRound:Int(fx:TFixtureState[], rnd:Int)
		Local n:Int
		For Local f:TFixtureState = EachIn fx
			If f.round = rnd Then
				n :+ 1
			End If
		Next

		Return n
	End Function

	Function HasUnorderedPair:Int(fx:TFixtureState[], a:Int, b:Int) {asBool}
		For Local f:TFixtureState = EachIn fx
			If (f.homeTeamId = a And f.awayTeamId = b) Or (f.homeTeamId = b And f.awayTeamId = a) Then
				Return True
			End If
		Next

		Return False
	End Function

	Function Sc(engine:TCompetitionEngine, comp:TCompetition, state:TCompetitionState, stageId:String, fid:String, h:Int, a:Int)
		Local res:TResultPayload = New TResultPayload
		res.kind = EResultKind.HeadToHeadScore
		res.scoreHome = h; res.scoreAway = a
		engine.RecordResult(comp, state, stageId, fid, res)
	End Function

End Type

Type TBracketAwayGoalsTest Extends TTest

	Method testAggregateWithAwayGoalsRule() { test }
		Local comp:TCompetition = New TCompetition
		' Seeds 1..4
		For Local s:Int = 1 To 4
			Local p:TParticipant = New TParticipant; p.id = s; p.name = "Seed" + s
			comp.participants :+ [p]
		Next

		' Single stage (semis) with two-legs + away-goals
		Local sf:TStage = BrStageTwoLeg("SF", 4, True)
		comp.stages = [sf]

		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)

		Local state:TCompetitionState = engine.Initialize(comp)

		' Tie A: 1 vs 4
		' Leg 1 (home=1): 1–0
		Sc(engine, comp, state, "SF", "SF_R1_M1_L1", 1, 0)
		' Leg 2 (home=4): 1–2  (aggregate 2–2; away goals → team 1 has 1 away goal, team 4 has 0 away goals) => seed 1 advances
		Sc(engine, comp, state, "SF", "SF_R1_M1_L2", 1, 2)

		' Tie B: 2 vs 3 (keep simple aggregate win for 3)
		Sc(engine, comp, state, "SF", "SF_R1_M2_L1", 0, 1)
		Sc(engine, comp, state, "SF", "SF_R1_M2_L2", 1, 0)

		' Stage complete; no next stage here, but winners should be determinable
		' (If you want, attach a final stage and assert it’s 1 vs 3.)
		' We’ll assert winners via the advancer
		Local adv:TBracketAdvancer = New TBracketAdvancer
		Local winners:TParticipant[] = adv.ProduceAdvancements(comp, sf, state.stages[0])

		AssertEquals(2, winners.Length, "Should produce two winners from semis")
		AssertEquals(1, winners[0].id, "Seed 1 should advance by away goals")
		AssertEquals(3, winners[1].id, "Seed 3 should advance on aggregate")
	End Method

	Function BrStageTwoLeg:TStage(id:String, size:Int, awayGoals:Int)
		Local stg:TStage = New TStage
		stg.id = id
		stg.stageType = EStageType.Bracket
		stg.input = New TEntrySource
		stg.input.seeding = New TSeedingPolicy
		stg.input.seeding.seedingMethod = ESeedingMethod.Ranking
		stg.config = New TBracketConfig
		TBracketConfig(stg.config).size = size
		TBracketConfig(stg.config).format = EBracketFormat.SingleElim
		TBracketConfig(stg.config).reseedEachRound = False
		TBracketConfig(stg.config).byes = 0
		TBracketConfig(stg.config).matchFormat = New TMatchFormat
		TBracketConfig(stg.config).matchFormat.legs = 2
		TBracketConfig(stg.config).matchFormat.aggregateScores = True
		TBracketConfig(stg.config).matchFormat.awayGoalsRule = awayGoals
		' neutral or two-leg venue works; scheduler already flips leg homes
		Return stg
	End Function

	Function Sc(engine:TCompetitionEngine, comp:TCompetition, state:TCompetitionState, stageId:String, fid:String, h:Int, a:Int)
		Local res:TResultPayload = New TResultPayload
		res.kind = EResultKind.HeadToHeadScore
		res.scoreHome = h; res.scoreAway = a
		engine.RecordResult(comp, state, stageId, fid, res)
	End Function

End Type

Type TProtectedTopNSeedingTest Extends TTest

	Method testTopNPreservedRestShuffled() { test }
		Local comp:TCompetition = New TCompetition
		comp.name = "ProtectedTopN Demo"
		' 8 entrants with IDs 1..8; since GetRank returns 999999 unless provided,
		' initial order acts as seeding, so 1 and 2 are the "top seeds".  [oai_citation:8‡tourney.bmx](file-service://file-8t5cHASzU57UtReioWDcdr)
		For Local i:Int = 1 To 8
			Local p:TParticipant = New TParticipant
			p.id = i
			p.name = "Seed " + i
			comp.participants :+ [p]
		Next

		' A bracket stage whose seeding policy is ProtectedTopN=2
		Local st:TStage = New TStage
		st.id = "BR"
		st.stageType = EStageType.Bracket
		st.input = New TEntrySource
		st.input.mode = EEntryMode.Direct
		st.input.seeding = New TSeedingPolicy
		st.input.seeding.seedingMethod = ESeedingMethod.ProtectedTopN
		st.input.seeding.protectedTopN = 2
		st.input.constraints = New TDrawConstraints

		st.config = New TBracketConfig
		TBracketConfig(st.config).configType = EConfigType.Bracket
		TBracketConfig(st.config).size = 8
		TBracketConfig(st.config).format = EBracketFormat.SingleElim
		TBracketConfig(st.config).matchFormat = New TMatchFormat

		comp.stages = [st]

		' We can call the orderer via the Bracket scheduler (it inherits TEntrantsOrderer).  [oai_citation:9‡tourney.bmx](file-service://file-8t5cHASzU57UtReioWDcdr)
		Local sched:TBracketScheduler = New TBracketScheduler
		Local ids:Int[] = sched.OrderEntrantsByPolicy(comp, st)

		' Check first two preserved
		AssertEqualsI(1, ids[0], "seed #1 must remain first")
		AssertEqualsI(2, ids[1], "seed #2 must remain second")

		' Remaining 6 are a permutation of 3..8
		Local remaining:Int[] = ids[2..]
		AssertEqualsI(6, remaining.Length, "there must be 6 remaining entrants")
		Local seen:Int[9]
		For Local v:Int = EachIn remaining
			AssertTrue(v >= 3 And v <= 8, "only seeds 3..8 allowed in the tail")
			seen[v] :+ 1
		Next

		For Local k:Int = 3 To 8
			AssertEqualsI(1, seen[k], "seed " + k + " must appear exactly once")
		Next
	End Method

End Type

' Type TProtectedTopNSeedingTest Extends TTest

' 	Field groupScheduler:TGroupScheduler

'     Method testTop4ProtectedStayAtFrontInOrder() { test }
'         ' Build 12 participants with an explicit ranking 1..12 (id == rank for simplicity)
'         Local comp:TCompetition = New TCompetition
'         For Local r:Int = 1 To 12
'             Local p:TParticipant = New TParticipant
'             p.id = r; p.name = "P"+r
'             comp.participants :+ [p]
'         Next

'         ' Bracket stage with ProtectedTopN=4
'         Local stg:TStage = New TStage
'         stg.id = "BR"
'         stg.stageType = EStageType.Bracket
'         stg.input = New TEntrySource
'         stg.input.seeding = New TSeedingPolicy
'         stg.input.seeding.seedingMethod = ESeedingMethod.ProtectedTopN
'         stg.input.seeding.protectedTopN = 4
'         stg.config = New TBracketConfig
'         TBracketConfig(stg.config).size = 12
'         TBracketConfig(stg.config).format = EBracketFormat.SingleElim
'         TBracketConfig(stg.config).matchFormat = New TMatchFormat

' 		groupScheduler = New TGroupScheduler
'         Local order:Int[] = groupScheduler.OrderEntrantsByPolicy(comp, stg)

'         ' Assert top-4 are 1,2,3,4 in that order
'         AssertEquals(12, order.Length, "Should seed all 12 entrants")
'         AssertEquals(1, order[0], "Seed 1 locked at position 1")
'         AssertEquals(2, order[1], "Seed 2 locked at position 2")
'         AssertEquals(3, order[2], "Seed 3 locked at position 3")
'         AssertEquals(4, order[3], "Seed 4 locked at position 4")

'         ' The remaining seeds are a permutation of 5..12
'         Local seen:Int[] = []
'         For Local i:Int = 4 Until order.Length
'             seen :+ [order[i]]
'         Next
'         AssertEquals(8, seen.Length, "Tail length must be 8")
'         For Local v:Int = 5 To 12
'             AssertTrue(Contains(seen, v), "Tail must contain "+v)
'         Next
'     End Method

'     Function Contains:Int(a:Int[], v:Int) {asBool}
'         For Local x:Int = EachIn a; If x = v Then Return True
'         Next
'         Return False
'     End Function

' End Type

Type TBracketDrawProgressionTest Extends TTest
	Method MakeStage:TStage(id:String, size:Int)
		Local stage:TStage = New TStage
		stage.id = id
		stage.stageType = EStageType.Bracket
		stage.input = New TEntrySource
		stage.input.seeding = New TSeedingPolicy
		stage.input.seeding.seedingMethod = ESeedingMethod.Ranking
		stage.config = New TBracketConfig
		TBracketConfig(stage.config).size = size
		TBracketConfig(stage.config).matchFormat = New TMatchFormat
		TBracketConfig(stage.config).matchFormat.legs = 1
		Return stage
	End Method

	Method HasPair:Int(fixtures:TFixtureState[], a:Int, b:Int)
		For Local fixture:TFixtureState = EachIn fixtures
			If (fixture.homeTeamId = a And fixture.awayTeamId = b) Or (fixture.homeTeamId = b And fixture.awayTeamId = a) Then
				Return True
			End If
		Next

		Return False
	End Method

	Method testExplicitRanksProtectOppositeHalves() { test }
		Local comp:TCompetition = New TCompetition
		For Local seed:Int = 8 To 1 Step -1
			Local p:TParticipant = New TParticipant
			p.id = seed * 10
			p.seedRank = seed
			comp.participants :+ [p]
		Next

		Local stage:TStage = MakeStage("R8", 8)
		comp.stages = [stage]
		Local fixtures:TFixtureState[] = (New TBracketScheduler).BuildFixtures(comp, stage)
		AssertTrue(HasPair(fixtures, 10, 80))
		AssertTrue(HasPair(fixtures, 20, 70))
		Local topPosition:Int = 0
		Local secondPosition:Int = 0
		For Local fixture:TFixtureState = EachIn fixtures
			If fixture.homeTeamId = 10 Or fixture.awayTeamId = 10 Then
				topPosition = fixture.bracketPosition
			End If

			If fixture.homeTeamId = 20 Or fixture.awayTeamId = 20 Then
				secondPosition = fixture.bracketPosition
			End If
		Next

		AssertTrue(topPosition <= 2 And secondPosition > 2)
	End Method

	Method testByesAdvanceIntoFixedLanes() { test }
		Local comp:TCompetition = New TCompetition
		For Local seed:Int = 1 To 6
			Local p:TParticipant = New TParticipant
			p.id = seed
			p.seedRank = seed
			comp.participants :+ [p]
		Next

		comp.stages = [MakeStage("QF", 8), MakeStage("SF", 4)]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(2, state.stages[0].bracketByeEntrants.Length)
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
			engine.RecordResultAndAdvance(comp, state, "QF", fixture.id, 1, 0)
		Next

		AssertEquals(EStageStatus.Running.Ordinal(), state.stages[1].status.Ordinal())
		AssertTrue(HasPair(state.stages[1].fixtures, 1, 4))
		AssertTrue(HasPair(state.stages[1].fixtures, 2, 3))
	End Method

	Method testSeedBandsRandomizeOnlyWithinBands() { test }
		Local comp:TCompetition = New TCompetition
		For Local seed:Int = 1 To 8
			Local p:TParticipant = New TParticipant
			p.id = seed
			p.seedRank = seed
			comp.participants :+ [p]
		Next

		Local stage:TStage = MakeStage("R8", 8)
		stage.input.seeding.seedBands = [1, 1, 2, 4]
		stage.schedule = New TSchedulePolicy
		comp.stages = [stage]
		Local seenLeft:Int = False
		Local seenRight:Int = False
		SeedRnd(17)
		For Local drawIndex:Int = 1 To 40
			Local fixtures:TFixtureState[] = (New TBracketScheduler).BuildFixtures(comp, stage)
			For Local fixture:TFixtureState = EachIn fixtures
				If fixture.homeTeamId = 1 Or fixture.awayTeamId = 1 Then
					AssertTrue(fixture.bracketPosition <= 2)
				End If

				If fixture.homeTeamId = 2 Or fixture.awayTeamId = 2 Then
					AssertTrue(fixture.bracketPosition > 2)
				End If

				If fixture.homeTeamId = 3 Or fixture.awayTeamId = 3 Then
					If fixture.bracketPosition <= 2 Then seenLeft = True Else seenRight = True
				End If
			Next
		Next

		AssertTrue(seenLeft And seenRight, "Seeds in a band may swap pathways")
	End Method
End Type

Type TKnockoutOutcomeTest Extends TTest
	Method MakeCompetition:TCompetition(format:TMatchFormat)
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 2
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.seedRank = id
			comp.participants :+ [participant]
		Next

		Local stage:TStage = New TStage
		stage.id = "F"
		stage.stageType = EStageType.Bracket
		stage.input = New TEntrySource
		stage.input.seeding = New TSeedingPolicy
		stage.input.seeding.seedingMethod = ESeedingMethod.Ranking
		stage.config = New TBracketConfig
		TBracketConfig(stage.config).size = 2
		TBracketConfig(stage.config).matchFormat = format
		comp.stages = [stage]
		Return comp
	End Method

	Method MakeEngine:TCompetitionEngine()
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)
		Return engine
	End Method

	Method testBestOfFiveClinchAndHomePattern() { test }
		Local format:TMatchFormat = New TMatchFormat
		format.bestOfMatches = 5
		Local comp:TCompetition = MakeCompetition(format)
		Local policy:TSchedulePolicy = New TSchedulePolicy
		policy.venuePolicy = New TVenuePolicy
		policy.venuePolicy.venueType = EVenue.HigherSeedHome
		policy.venuePolicy.seriesTemplate = New THomeCourtSeries
		policy.venuePolicy.seriesTemplate.bestOf = 5
		policy.venuePolicy.seriesTemplate.pattern = [2, 2, 1]
		TBracketConfig(comp.stages[0].config).policy = policy
		Local engine:TCompetitionEngine = MakeEngine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local games:TFixtureState[] = state.stages[0].fixtures
		AssertEquals(5, games.Length)
		AssertEquals(1, games[0].homeTeamId)
		AssertEquals(1, games[1].homeTeamId)
		AssertEquals(2, games[2].homeTeamId)
		AssertEquals(2, games[3].homeTeamId)
		AssertEquals(1, games[4].homeTeamId)
		For Local i:Int = 0 To 2
			If games[i].homeTeamId = 1 Then
				engine.RecordResultAndAdvance(comp, state, "F", games[i].id, 1, 0)
			Else
				engine.RecordResultAndAdvance(comp, state, "F", games[i].id, 0, 1)
			End If
		Next

		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(EFixtureStatus.Cancelled.Ordinal(), games[3].status.Ordinal())
		AssertEquals(EFixtureStatus.Cancelled.Ordinal(), games[4].status.Ordinal())
		AssertEquals(1, state.stages[0].leaderboard.rows[0].participantId)
	End Method

	Method testBestOfFiveCanReachDecidingGame() { test }
		Local format:TMatchFormat = New TMatchFormat
		format.bestOfMatches = 5
		Local comp:TCompetition = MakeCompetition(format)
		Local engine:TCompetitionEngine = MakeEngine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local games:TFixtureState[] = state.stages[0].fixtures
		Local rejected:Int = False
		Try
			engine.RecordResultAndAdvance(comp, state, "F", games[1].id, 1, 0)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Series games must be recorded in order")
		Local winners:Int[] = [1, 2, 1, 2, 2]
		For Local i:Int = 0 Until games.Length
			Local homeScore:Int = 0, awayScore:Int = 1
			If games[i].homeTeamId = winners[i] Then homeScore = 1; awayScore = 0

			engine.RecordResultAndAdvance(comp, state, "F", games[i].id, homeScore, awayScore)
			If i < 4 Then
				AssertEquals(EStageStatus.Running.Ordinal(), state.stages[0].status.Ordinal())
			End If
		Next

		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(2, state.stages[0].leaderboard.rows[0].participantId)
	End Method

	Method testSingleMatchNeedsConfiguredDecider() { test }
		Local format:TMatchFormat = New TMatchFormat
		format.legs = 1
		format.penalties = True
		Local comp:TCompetition = MakeCompetition(format)
		Local engine:TCompetitionEngine = MakeEngine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local fixture:TFixtureState = state.stages[0].fixtures[0]
		Local tied:TResultPayload = New TResultPayload
		tied.kind = EResultKind.HeadToHeadScore
		tied.scoreHome = 1
		tied.scoreAway = 1
		Local rejected:Int = False
		Try
			engine.RecordResult(comp, state, "F", fixture.id, tied)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected)
		AssertEquals(EFixtureStatus.Scheduled.Ordinal(), fixture.status.Ordinal())
		tied.penaltiesHome = 5
		tied.penaltiesAway = 4
		engine.RecordResult(comp, state, "F", fixture.id, tied)
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(fixture.homeTeamId, state.stages[0].leaderboard.rows[0].participantId)
	End Method

	Method testTwoLegAggregateNeedsDecider() { test }
		Local format:TMatchFormat = New TMatchFormat
		format.legs = 2
		format.aggregateScores = True
		format.penalties = True
		Local comp:TCompetition = MakeCompetition(format)
		Local engine:TCompetitionEngine = MakeEngine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local first:TFixtureState = state.stages[0].fixtures[0]
		Local second:TFixtureState = state.stages[0].fixtures[1]
		engine.RecordResultAndAdvance(comp, state, "F", first.id, 1, 0)
		Local tied:TResultPayload = New TResultPayload
		tied.kind = EResultKind.HeadToHeadScore
		tied.scoreHome = 1
		tied.scoreAway = 0
		Local rejected:Int = False
		Try
			engine.RecordResult(comp, state, "F", second.id, tied)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected)
		AssertEquals(EFixtureStatus.Scheduled.Ordinal(), second.status.Ordinal())
		tied.penaltiesHome = 4
		tied.penaltiesAway = 3
		engine.RecordResult(comp, state, "F", second.id, tied)
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(second.homeTeamId, state.stages[0].leaderboard.rows[0].participantId)
	End Method

	Method testSetMatchNeedsCompletedWinningSets() { test }
		Local format:TMatchFormat = New TMatchFormat
		format.legs = 1
		format.setRules = New TSetRules
		format.setRules.usesSets = True
		format.setRules.setsBestOf = 3
		format.setRules.gamesPerSetTarget = 6
		format.setRules.gamesMargin = 2
		format.setRules.tiebreakAtGames = 6
		Local comp:TCompetition = MakeCompetition(format)
		Local engine:TCompetitionEngine = MakeEngine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local fixture:TFixtureState = state.stages[0].fixtures[0]
		Local first:TSetScore = New TSetScore
		first.home = 6
		first.away = 4
		Local second:TSetScore = New TSetScore
		second.home = 6
		second.away = 7
		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.SetBased
		result.sets = [first, second]
		Local rejected:Int = False
		Try
			engine.RecordResult(comp, state, "F", fixture.id, result)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "One set each is not a completed match")
		AssertEquals(EFixtureStatus.Scheduled.Ordinal(), fixture.status.Ordinal())
		Local third:TSetScore = New TSetScore
		third.home = 7
		third.away = 6
		result.sets = [first, second, third]
		engine.RecordResult(comp, state, "F", fixture.id, result)
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(fixture.homeTeamId, state.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(3, fixture.setResults.Length)
	End Method

	Method testBestOfSeriesResumesAfterStateRoundTrip() { test }
		Local format:TMatchFormat = New TMatchFormat
		format.bestOfMatches = 3
		Local comp:TCompetition = MakeCompetition(format)
		Local engine:TCompetitionEngine = MakeEngine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local first:TFixtureState = state.stages[0].fixtures[0]
		If first.homeTeamId = 1 Then
			engine.RecordResultAndAdvance(comp, state, "F", first.id, 1, 0)
		Else
			engine.RecordResultAndAdvance(comp, state, "F", first.id, 0, 1)
		End If

		Local path:String = "rt_best_of_state.json"
		Local jconv:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local output:TStream = WriteStream(path)
		jconv.ToJson(state, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		state = TCompetitionState(jconv.FromJson(input, "TCompetitionState"))
		input.Close()
		DeleteFile(path)
		AssertEquals(EFixtureStatus.Completed.Ordinal(), state.stages[0].fixtures[0].status.Ordinal())
		Local second:TFixtureState = state.stages[0].fixtures[1]
		If second.homeTeamId = 1 Then
			engine.RecordResultAndAdvance(comp, state, "F", second.id, 1, 0)
		Else
			engine.RecordResultAndAdvance(comp, state, "F", second.id, 0, 1)
		End If

		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(EFixtureStatus.Cancelled.Ordinal(), state.stages[0].fixtures[2].status.Ordinal())
	End Method
End Type

Type TAdvancementRoutesTest Extends TTest
	Method Bracket:TStage(id:String, size:Int)
		Local stage:TStage = New TStage
		stage.id = id
		stage.stageType = EStageType.Bracket
		stage.input = New TEntrySource
		stage.input.seeding = New TSeedingPolicy
		stage.input.seeding.seedingMethod = ESeedingMethod.Ranking
		stage.config = New TBracketConfig
		TBracketConfig(stage.config).size = size
		TBracketConfig(stage.config).matchFormat = New TMatchFormat
		TBracketConfig(stage.config).matchFormat.legs = 1
		Return stage
	End Method

	Method Route:TAdvancement(destination:String, outcome:EAdvancementOutcome, slots:String[])
		Local route:TAdvancement = New TAdvancement
		route.toStageId = destination
		route.outcome = outcome
		route.mapping = New TAdvancementMapping
		route.mapping.mode = EAdvMappingMode.FixedSlots
		route.mapping.toSlots = slots
		Return route
	End Method

	Method Engine:TCompetitionEngine()
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)
		Return engine
	End Method

	Method Players:TCompetition()
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 4
			Local p:TParticipant = New TParticipant
			p.id = id
			p.seedRank = id
			comp.participants :+ [p]
		Next

		Return comp
	End Method

	Method ScoreWinner(engine:TCompetitionEngine, comp:TCompetition, state:TCompetitionState, stageId:String, fixture:TFixtureState, winnerId:Int)
		If fixture.homeTeamId = winnerId Then
			engine.RecordResultAndAdvance(comp, state, stageId, fixture.id, 1, 0)
		Else
			engine.RecordResultAndAdvance(comp, state, stageId, fixture.id, 0, 1)
		End If
	End Method

	Method HasPair:Int(fixtures:TFixtureState[], a:Int, b:Int)
		For Local fixture:TFixtureState = EachIn fixtures
			If (fixture.homeTeamId = a And fixture.awayTeamId = b) Or (fixture.homeTeamId = b And fixture.awayTeamId = a) Then
				Return True
			End If
		Next

		Return False
	End Method

	Method testWinnersAndLosersReachDifferentMatches() { test }
		Local comp:TCompetition = Players()
		Local semi:TStage = Bracket("SF", 4)
		Local finalStage:TStage = Bracket("F", 2)
		finalStage.input.fromStageId = "SF"
		Local third:TStage = Bracket("THIRD", 2)
		third.input.fromStageId = "SF"
		semi.advancement = [Route("F", EAdvancementOutcome.Winner, ["1", "2"]), Route("THIRD", EAdvancementOutcome.Loser, ["1", "2"])]
		comp.stages = [semi, finalStage, third]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		ScoreWinner(engine, comp, state, "SF", state.stages[0].fixtures[0], 1)
		ScoreWinner(engine, comp, state, "SF", state.stages[0].fixtures[1], 3)
		AssertEquals(EStageStatus.Running.Ordinal(), state.stages[1].status.Ordinal())
		AssertEquals(EStageStatus.Running.Ordinal(), state.stages[2].status.Ordinal())
		AssertTrue(HasPair(state.stages[1].fixtures, 1, 3))
		AssertTrue(HasPair(state.stages[2].fixtures, 4, 2))
		AssertEquals("1", state.stages[2].inputs[0].slotIds[0])
		AssertEquals("2", state.stages[2].inputs[0].slotIds[1])
	End Method

	Method testTwoSourcesFillNamedSlotsAfterReload() { test }
		Local comp:TCompetition = Players()
		Local a:TStage = Bracket("A", 4)
		Local b:TStage = Bracket("B", 4)
		b.independent = True
		Local joined:TStage = Bracket("JOIN", 4)
		joined.input.fromStageIds = ["A", "B"]
		a.advancement = [Route("JOIN", EAdvancementOutcome.Winner, ["1", "3"])]
		b.advancement = [Route("JOIN", EAdvancementOutcome.Winner, ["2", "4"])]
		comp.stages = [a, b, joined]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		ScoreWinner(engine, comp, state, "A", state.stages[0].fixtures[0], 1)
		ScoreWinner(engine, comp, state, "A", state.stages[0].fixtures[1], 2)
		AssertEquals(EStageStatus.Pending.Ordinal(), state.stages[2].status.Ordinal())
		Local path:String = "rt_advancement_slots.json"
		Local jconv:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local output:TStream = WriteStream(path)
		jconv.ToJson(state, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		state = TCompetitionState(jconv.FromJson(input, "TCompetitionState"))
		input.Close()
		DeleteFile(path)
		AssertEquals("3", state.stages[2].inputs[0].slotIds[1])
		ScoreWinner(engine, comp, state, "B", state.stages[1].fixtures[0], 4)
		ScoreWinner(engine, comp, state, "B", state.stages[1].fixtures[1], 3)
		AssertEquals(EStageStatus.Running.Ordinal(), state.stages[2].status.Ordinal())
		AssertTrue(HasPair(state.stages[2].fixtures, 1, 4))
		AssertTrue(HasPair(state.stages[2].fixtures, 2, 3))
	End Method

	Method testSeededRouteReseedsSurvivors() { test }
		Local comp:TCompetition = Players()
		For Local id:Int = 5 To 8
			Local p:TParticipant = New TParticipant
			p.id = id
			p.seedRank = id
			comp.participants :+ [p]
		Next

		Local first:TStage = Bracket("R8", 8)
		Local nextStage:TStage = Bracket("R4", 4)
		nextStage.input.fromStageId = "R8"
		Local route:TAdvancement = New TAdvancement
		route.toStageId = "R4"
		route.outcome = EAdvancementOutcome.Winner
		route.mapping = New TAdvancementMapping
		route.mapping.mode = EAdvMappingMode.Seeded
		first.advancement = [route]
		comp.stages = [first, nextStage]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local winners:Int[] = [1, 5, 7, 3]
		For Local i:Int = 0 Until winners.Length
			ScoreWinner(engine, comp, state, "R8", state.stages[0].fixtures[i], winners[i])
		Next

		AssertEquals(EStageStatus.Running.Ordinal(), state.stages[1].status.Ordinal())
		AssertTrue(HasPair(state.stages[1].fixtures, 1, 7))
		AssertTrue(HasPair(state.stages[1].fixtures, 3, 5))
	End Method

	Method testPartitionRoutesKeepSourcesInSeparateHalves() { test }
		Local comp:TCompetition = Players()
		Local a:TStage = Bracket("A", 4)
		Local b:TStage = Bracket("B", 4)
		b.independent = True
		Local joined:TStage = Bracket("JOIN", 4)
		joined.input.fromStageIds = ["A", "B"]
		Local left:TAdvancement = New TAdvancement
		left.toStageId = "JOIN"
		left.outcome = EAdvancementOutcome.Winner
		left.mapping = New TAdvancementMapping
		left.mapping.mode = EAdvMappingMode.Partition
		left.mapping.partitionKey = "left"
		Local right:TAdvancement = New TAdvancement
		right.toStageId = "JOIN"
		right.outcome = EAdvancementOutcome.Winner
		right.mapping = New TAdvancementMapping
		right.mapping.mode = EAdvMappingMode.Partition
		right.mapping.partitionKey = "right"
		a.advancement = [left]
		b.advancement = [right]
		comp.stages = [a, b, joined]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		ScoreWinner(engine, comp, state, "A", state.stages[0].fixtures[0], 1)
		ScoreWinner(engine, comp, state, "A", state.stages[0].fixtures[1], 2)
		ScoreWinner(engine, comp, state, "B", state.stages[1].fixtures[0], 4)
		ScoreWinner(engine, comp, state, "B", state.stages[1].fixtures[1], 3)
		AssertTrue(HasPair(state.stages[2].fixtures, 1, 2))
		AssertTrue(HasPair(state.stages[2].fixtures, 4, 3))
	End Method

	Method GroupTable:TGroupTable(key:String, first:Int, second:Int)
		Local group:TGroupTable = New TGroupTable
		group.key = key
		For Local id:Int = EachIn [first, second]
			Local row:TLeaderboardRow = New TLeaderboardRow
			row.participantId = id
			group.rows :+ [row]
		Next

		Return group
	End Method

	Method GroupSlot:TGroupRankSlot(key:String, rank:Int, slot:Int)
		Local assignment:TGroupRankSlot = New TGroupRankSlot
		assignment.groupKey = key
		assignment.rank = rank
		assignment.slotId = String(slot)
		Return assignment
	End Method

	Method ConditionalCase:TConditionalSlotCase(group:String, runnerSlot:Int, otherSlot:Int)
		Local choice:TConditionalSlotCase = New TConditionalSlotCase
		choice.qualifyingGroupKeys = [group]
		choice.assignments = [GroupSlot("A", 1, 1), GroupSlot("B", 1, 3), GroupSlot("C", 1, otherSlot), GroupSlot(group, 2, runnerSlot)]
		Return choice
	End Method

	Method testConditionalSlotsSelectByQualifiedGroupAndSurviveRoundTrip() { test }
		Local source:TStageState = New TStageState
		source.groups = [GroupTable("A", 1, 2), GroupTable("B", 3, 4), GroupTable("C", 5, 6)]
		Local mapping:TAdvancementMapping = New TAdvancementMapping
		mapping.mode = EAdvMappingMode.ConditionalSlots
		mapping.qualifyingRank = 2
		mapping.conditionalCases = [ConditionalCase("B", 4, 2), ConditionalCase("C", 2, 4)]
		Local target:TStage = Bracket("NEXT", 4)
		Local engine:TCompetitionEngine = Engine()
		Local slots:String[] = engine.RoutedSlots(mapping, [1, 3, 5, 6], source, target)
		AssertEquals("1", slots[0])
		AssertEquals("3", slots[1])
		AssertEquals("4", slots[2])
		AssertEquals("2", slots[3])

		Local path:String = "rt_conditional_mapping.json"
		Local jconv:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local output:TStream = WriteStream(path)
		jconv.ToJson(mapping, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		mapping = TAdvancementMapping(jconv.FromJson(input, "TAdvancementMapping"))
		input.Close()
		DeleteFile(path)
		slots = engine.RoutedSlots(mapping, [1, 3, 5, 4], source, target)
		AssertEquals("1", slots[0])
		AssertEquals("3", slots[1])
		AssertEquals("2", slots[2])
		AssertEquals("4", slots[3])
	End Method

	Method testConditionalSlotsRejectMissingAndAmbiguousCases() { test }
		Local source:TStageState = New TStageState
		source.groups = [GroupTable("A", 1, 2), GroupTable("B", 3, 4), GroupTable("C", 5, 6)]
		Local mapping:TAdvancementMapping = New TAdvancementMapping
		mapping.mode = EAdvMappingMode.ConditionalSlots
		mapping.qualifyingRank = 2
		mapping.conditionalCases = [ConditionalCase("B", 4, 2)]
		Local engine:TCompetitionEngine = Engine()
		Local target:TStage = Bracket("NEXT", 4)
		Local rejected:Int = False
		Try
			engine.RoutedSlots(mapping, [1, 3, 5, 6], source, target)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "An unmatched qualifying combination must fail")
		mapping.conditionalCases = [ConditionalCase("C", 2, 4), ConditionalCase("C", 4, 2)]
		rejected = False
		Try
			engine.RoutedSlots(mapping, [1, 3, 5, 6], source, target)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Ambiguous qualifying combinations must fail")
	End Method

	Method testConditionalSlotsRejectDuplicateSlotAndUnqualifiedEntrant() { test }
		Local source:TStageState = New TStageState
		source.groups = [GroupTable("A", 1, 2), GroupTable("B", 3, 4), GroupTable("C", 5, 6)]
		Local mapping:TAdvancementMapping = New TAdvancementMapping
		mapping.mode = EAdvMappingMode.ConditionalSlots
		mapping.qualifyingRank = 2
		mapping.conditionalCases = [ConditionalCase("C", 2, 2)]
		Local engine:TCompetitionEngine = Engine()
		Local target:TStage = Bracket("NEXT", 4)
		Local rejected:Int = False
		Try
			engine.RoutedSlots(mapping, [1, 3, 5, 6], source, target)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Two entrants cannot occupy one bracket slot")
		mapping.conditionalCases[0] = ConditionalCase("C", 2, 4)
		mapping.conditionalCases[0].assignments[3] = GroupSlot("A", 2, 2)
		rejected = False
		Try
			engine.RoutedSlots(mapping, [1, 3, 5, 6], source, target)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "A conditional assignment cannot place an unqualified entrant")
	End Method
End Type

Type TEliminationTreeTest Extends TTest
	Method Competition:TCompetition(size:Int)
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To size
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.seedRank = id
			comp.participants :+ [participant]
		Next

		Return comp
	End Method

	Method Options:TEliminationTreeOptions(size:Int, kind:EEliminationTreeKind)
		Local options:TEliminationTreeOptions = New TEliminationTreeOptions
		options.idPrefix = "CUP"
		options.size = size
		options.kind = kind
		options.seeding = New TSeedingPolicy
		options.seeding.seedingMethod = ESeedingMethod.Ranking
		Return options
	End Method

	Method Engine:TCompetitionEngine()
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)
		Return engine
	End Method

	Method PlayAll:Int(engine:TCompetitionEngine, comp:TCompetition, state:TCompetitionState, skipStageId:String = "")
		Local played:Int = 0
		For Local pass:Int = 1 To 20
			Local progressed:Int = False
			For Local index:Int = 0 Until comp.stages.Length
				If comp.stages[index].id = skipStageId Then
					Continue
				End If

				If state.stages[index].status <> EStageStatus.Running Then
					Continue
				End If

				For Local fixture:TFixtureState = EachIn state.stages[index].fixtures
					If fixture.status <> EFixtureStatus.Scheduled Then
						Continue
					End If

					engine.RecordResultAndAdvance(comp, state, comp.stages[index].id, fixture.id, 1, 0)
					played :+ 1
					progressed = True
				Next
			Next

			If Not progressed Then
				Exit
			End If
		Next

		Return played
	End Method

	Method Contains:Int(values:Int[], value:Int)
		For Local item:Int = EachIn values
			If item = value Then
				Return True
			End If
		Next

		Return False
	End Method

	Method testSingleEliminationWithThirdPlace() { test }
		Local comp:TCompetition = Competition(8)
		Local options:TEliminationTreeOptions = Options(8, EEliminationTreeKind.SingleElimination)
		options.thirdPlace = True
		Local tree:TEliminationTree = New TEliminationTreeBuilder.Append(comp, options)
		AssertEquals(3, tree.winnerRounds.Length)
		AssertEquals("CUP_W3", tree.finalStageId)
		AssertEquals("CUP_THIRD", tree.thirdPlaceStageId)
		AssertEquals(4, comp.stages.Length)
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(8, PlayAll(engine, comp, state))
		For Local stage:TStageState = EachIn state.stages
			AssertEquals(EStageStatus.Complete.Ordinal(), stage.status.Ordinal())
		Next

		AssertEquals(2, state.stages[3].entrants.Length)
		AssertTrue(tree.ChampionId(comp, state) > 0)
	End Method

	Method testFullClassificationPlacesEveryEntrant() { test }
		Local comp:TCompetition = Competition(8)
		Local options:TEliminationTreeOptions = Options(8, EEliminationTreeKind.SingleElimination)
		options.placementThroughRank = 8
		Local tree:TEliminationTree = New TEliminationTreeBuilder.Append(comp, options)
		AssertEquals(4, tree.classificationStages.Length)
		AssertEquals(7, comp.stages.Length)
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(12, PlayAll(engine, comp, state))
		Local placements:Int[] = tree.Placements(comp, state)
		AssertEquals(8, placements.Length)
		For Local rank:Int = 0 Until placements.Length
			AssertTrue(placements[rank] > 0)
			For Local previous:Int = 0 Until rank
				AssertTrue(placements[rank] <> placements[previous])
			Next
		Next
	End Method

	Method testPartialClassificationLeavesLowerPlacesUnranked() { test }
		Local comp:TCompetition = Competition(8)
		Local options:TEliminationTreeOptions = Options(8, EEliminationTreeKind.SingleElimination)
		options.placementThroughRank = 6
		Local tree:TEliminationTree = New TEliminationTreeBuilder.Append(comp, options)
		AssertEquals(3, tree.classificationStages.Length)
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(11, PlayAll(engine, comp, state))
		For Local rank:Int = 1 To 6
			AssertTrue(tree.PlacementId(comp, state, rank) > 0)
		Next

		AssertEquals(0, tree.PlacementId(comp, state, 7))
		AssertEquals(0, tree.PlacementId(comp, state, 8))
	End Method

	Method testSixteenEntrantClassificationAndManifestReload() { test }
		Local comp:TCompetition = Competition(16)
		Local options:TEliminationTreeOptions = Options(16, EEliminationTreeKind.SingleElimination)
		options.placementThroughRank = 16
		Local tree:TEliminationTree = New TEliminationTreeBuilder.Append(comp, options)
		Local jconv:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local path:String = "/private/tmp/tourney_placement_tree.json"
		Local output:TStream = WriteStream(path)
		jconv.ToJson(tree, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		tree = TEliminationTree(jconv.FromJson(input, "TEliminationTree"))
		input.Close()
		DeleteFile(path)
		AssertEquals(11, tree.classificationStages.Length)
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(32, PlayAll(engine, comp, state))
		For Local rank:Int = 1 To 16
			Local participantId:Int = tree.PlacementId(comp, state, rank)
			AssertTrue(participantId > 0)
			For Local previous:Int = 1 Until rank
				AssertTrue(participantId <> tree.PlacementId(comp, state, previous))
			Next
		Next
	End Method

	Method testEightEntrantDoubleEliminationTree() { test }
		Local comp:TCompetition = Competition(8)
		Local options:TEliminationTreeOptions = Options(8, EEliminationTreeKind.DoubleElimination)
		options.grandFinalReset = False
		Local tree:TEliminationTree = New TEliminationTreeBuilder.Append(comp, options)
		AssertEquals(3, tree.winnerRounds.Length)
		AssertEquals(4, tree.loserRounds.Length)
		AssertEquals("CUP_GF", tree.finalStageId)
		AssertEquals(8, comp.stages.Length)
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(14, PlayAll(engine, comp, state))
		For Local stage:TStageState = EachIn state.stages
			AssertEquals(EStageStatus.Complete.Ordinal(), stage.status.Ordinal())
		Next

		For Local index:Int = 4 To 6 Step 2
			Local lower:TStageState = state.stages[index]
			AssertEquals(2, lower.inputs.Length)
			For Local fixture:TFixtureState = EachIn lower.fixtures
				Local first:Int = Contains(lower.inputs[0].entrantIds, fixture.homeTeamId) Or Contains(lower.inputs[0].entrantIds, fixture.awayTeamId)
				Local second:Int = Contains(lower.inputs[1].entrantIds, fixture.homeTeamId) Or Contains(lower.inputs[1].entrantIds, fixture.awayTeamId)
				AssertTrue(first And second)
			Next
		Next

		AssertTrue(tree.ChampionId(comp, state) > 0)
	End Method

	Method testGrandFinalResetOnlyWhenWinnerBracketEntrantLoses() { test }
		Local comp:TCompetition = Competition(8)
		Local options:TEliminationTreeOptions = Options(8, EEliminationTreeKind.DoubleElimination)
		Local tree:TEliminationTree = New TEliminationTreeBuilder.Append(comp, options)
		AssertEquals("CUP_RESET", tree.resetStageId)
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(14, PlayAll(engine, comp, state))
		AssertEquals(EStageStatus.Skipped.Ordinal(), state.stages[8].status.Ordinal())
		AssertTrue(tree.ChampionId(comp, state) > 0)

		comp = Competition(8)
		tree = New TEliminationTreeBuilder.Append(comp, options)
		state = engine.Initialize(comp)
		AssertEquals(13, PlayAll(engine, comp, state, tree.finalStageId))
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local compPath:String = "/private/tmp/tourney_elimination_comp.json"
		Local statePath:String = "/private/tmp/tourney_elimination_state.json"
		Local output:TStream = WriteStream(compPath)
		jconv.ToJson(comp, output)
		output.Close()
		output = WriteStream(statePath)
		jconv.ToJson(state, output)
		output.Close()
		Local input:TStream = ReadStream(compPath)
		comp = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		input = ReadStream(statePath)
		state = TCompetitionState(jconv.FromJson(input, "TCompetitionState"))
		input.Close()
		DeleteFile(compPath)
		DeleteFile(statePath)
		Local finalState:TStageState = state.stages[7]
		AssertEquals(EStageStatus.Running.Ordinal(), finalState.status.Ordinal())
		Local lowerChampion:Int = 0
		For Local input:TStageInputState = EachIn finalState.inputs
			If input.sourceStageId = tree.loserRounds[tree.loserRounds.Length - 1] Then
				lowerChampion = input.entrantIds[0]
			End If
		Next

		AssertTrue(lowerChampion > 0)
		Local fixture:TFixtureState = finalState.fixtures[0]
		If fixture.homeTeamId = lowerChampion Then
			engine.RecordResultAndAdvance(comp, state, tree.finalStageId, fixture.id, 1, 0)
		Else
			engine.RecordResultAndAdvance(comp, state, tree.finalStageId, fixture.id, 0, 1)
		End If

		AssertEquals(EStageStatus.Running.Ordinal(), state.stages[8].status.Ordinal())
		AssertEquals(0, tree.ChampionId(comp, state))
		Local resetWinner:Int = state.stages[8].fixtures[0].homeTeamId
		AssertEquals(1, PlayAll(engine, comp, state))
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[8].status.Ordinal())
		AssertEquals(resetWinner, tree.ChampionId(comp, state))
	End Method

	Method testDoubleEliminationTreeScalesToFourAndSixteenEntrants() { test }
		For Local size:Int = EachIn [4, 16]
			Local comp:TCompetition = Competition(size)
			Local options:TEliminationTreeOptions = Options(size, EEliminationTreeKind.DoubleElimination)
			Local tree:TEliminationTree = New TEliminationTreeBuilder.Append(comp, options)
			Local engine:TCompetitionEngine = Engine()
			Local state:TCompetitionState = engine.Initialize(comp)
			AssertEquals(2 * size - 2, PlayAll(engine, comp, state))
			AssertTrue(tree.ChampionId(comp, state) > 0)
			For Local index:Int = 0 Until state.stages.Length - 1
				AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[index].status.Ordinal())
			Next

			AssertEquals(EStageStatus.Skipped.Ordinal(), state.stages[state.stages.Length - 1].status.Ordinal())
		Next
	End Method
End Type

Type TClinchingTest Extends TTest
	Method Series:TCompetition(eventCount:Int)
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 3
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.kind = EParticipantKind.Individual
			comp.participants :+ [participant]
		Next

		Local stage:TStage = New TStage
		stage.id = "SEASON"
		stage.stageType = EStageType.Series
		stage.config = New TSeriesConfig
		Local config:TSeriesConfig = TSeriesConfig(stage.config)
		config.scoring = New TScoringSystem
		config.scoring.mode = EScoringMode.PositionTable
		For Local position:Int = 1 To 3
			Local entry:TPointsTableEntry = New TPointsTableEntry
			entry.position = position
			Select position
				Case 1 entry.points = 10
				Case 2 entry.points = 5
			End Select

			config.scoring.table :+ [entry]
		Next

		For Local n:Int = 1 To eventCount
			Local event:TSeriesEvent = New TSeriesEvent
			event.id = "E" + n
			config.events :+ [event]
		Next

		Local championship:TChampionshipConfig = New TChampionshipConfig
		championship.code = "DRIVERS"
		championship.filterByKind = True
		championship.participantKind = EParticipantKind.Individual
		config.championships = [championship]
		comp.stages = [stage]
		Return comp
	End Method

	Method Engine:TCompetitionEngine()
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Series, New TSeriesScheduler)
		engine.RegisterScorer(EStageType.Series, New TSeriesScorer)
		Return engine
	End Method

	Method Projection:TProjectedPoints(id:Int, points:Int)
		Local projected:TProjectedPoints = New TProjectedPoints
		projected.participantId = id
		projected.points = points
		Return projected
	End Method

	Method testSeriesCanClinchWithRaceRemaining() { test }
		Local comp:TCompetition = Series(4)
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		For Local n:Int = 0 To 1
			engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[n].id, [1, 2, 3])
		Next

		Local analysis:TClinchAnalysis = engine.AnalyzeClinching(comp, state, "SEASON", "DRIVERS")
		AssertEquals(EClinchStatus.NotCertified.Ordinal(), analysis.status.Ordinal())
		AssertEquals("E3", analysis.nextWindowId)
		AssertEquals(20, Int(analysis.BoundFor(1).currentPoints))
		AssertEquals(20, Int(analysis.BoundFor(2).maximumAdditional))
		AssertEquals(10, Int(analysis.BoundFor(2).maximumAfterNext))
		AssertTrue(analysis.ClinchesAfterNext(1, [Projection(1, 30), Projection(2, 15), Projection(3, 0)]))
		AssertTrue(Not analysis.ClinchesAfterNext(1, [Projection(1, 25), Projection(2, 20), Projection(3, 0)]))
		Local impossible:Int = False
		Try
			analysis.ClinchesAfterNext(1, [Projection(1, 100), Projection(2, 15), Projection(3, 0)])
		Catch error:Object
			impossible = True
		End Try

		AssertTrue(impossible)
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[2].id, [1, 2, 3])
		analysis = engine.AnalyzeClinching(comp, state, "SEASON", "DRIVERS")
		AssertEquals(EClinchStatus.Clinched.Ordinal(), analysis.status.Ordinal())
		AssertEquals(1, analysis.clinchedParticipantId)
		AssertEquals(25, Int(analysis.BoundFor(2).MaximumFinal()))
		Local path:String = "/private/tmp/tourney_clinching_analysis.json"
		Local jconv:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local output:TStream = WriteStream(path)
		jconv.ToJson(analysis, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		analysis = TClinchAnalysis(jconv.FromJson(input, "TClinchAnalysis"))
		input.Close()
		DeleteFile(path)
		AssertEquals(EClinchStatus.Clinched.Ordinal(), analysis.status.Ordinal())
		AssertEquals(25, Int(analysis.BoundFor(2).MaximumFinal()))
	End Method

	Method testTeamChampionshipUsesDriverCountInBounds() { test }
		Local comp:TCompetition = Series(4)
		Local team1:TParticipant = New TParticipant
		team1.id = 10
		team1.kind = EParticipantKind.Team
		Local team2:TParticipant = New TParticipant
		team2.id = 20
		team2.kind = EParticipantKind.Team
		comp.participants :+ [team1, team2]
		Local driver4:TParticipant = New TParticipant
		driver4.id = 4
		driver4.kind = EParticipantKind.Individual
		comp.participants :+ [driver4]
		comp.participants[0].parentTeamId = 10
		comp.participants[1].parentTeamId = 10
		comp.participants[2].parentTeamId = 20
		driver4.parentTeamId = 20
		Local config:TSeriesConfig = TSeriesConfig(comp.stages[0].config)
		config.scoring.table[1].points = 6
		config.scoring.table[2].points = 4
		Local fourth:TPointsTableEntry = New TPointsTableEntry
		fourth.position = 4
		fourth.points = 2
		config.scoring.table :+ [fourth]
		Local teams:TChampionshipConfig = New TChampionshipConfig
		teams.code = "TEAMS"
		teams.parentTeamPoints = True
		config.championships :+ [teams]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		For Local n:Int = 0 To 2
			engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[n].id, [1, 2, 3, 4])
		Next

		Local analysis:TClinchAnalysis = engine.AnalyzeClinching(comp, state, "SEASON", "TEAMS")
		AssertEquals(EClinchStatus.Clinched.Ordinal(), analysis.status.Ordinal())
		AssertEquals(10, analysis.clinchedParticipantId)
		AssertEquals(16, Int(analysis.BoundFor(20).maximumAdditional))
	End Method

	Method testNamedChampionshipUsesItsSessionsAndEventMultiplier() { test }
		Local comp:TCompetition = Series(2)
		Local config:TSeriesConfig = TSeriesConfig(comp.stages[0].config)
		config.championships[0].sessionCodes = ["RACE"]
		Local qualifying:TSession = New TSession
		qualifying.code = "QUALI"
		Local race:TSession = New TSession
		race.code = "RACE"
		config.events[0].sessions = [qualifying, race]
		Local sprint:TSession = New TSession
		sprint.code = "SPRINT"
		sprint.scoringOverride = New TScoringSystem
		sprint.scoringOverride.mode = EScoringMode.PositionTable
		Local sprintWin:TPointsTableEntry = New TPointsTableEntry
		sprintWin.position = 1
		sprintWin.points = 3
		sprint.scoringOverride.table = [sprintWin]
		Local secondRace:TSession = New TSession
		secondRace.code = "RACE"
		config.events[1].sessions = [sprint, secondRace]
		config.events[1].pointsMultiplier = 2.0
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[0].id, [1, 2, 3])
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[1].id, [1, 2, 3])
		Local drivers:TClinchAnalysis = engine.AnalyzeClinching(comp, state, "SEASON", "DRIVERS")
		Local primary:TClinchAnalysis = engine.AnalyzeClinching(comp, state, "SEASON")
		AssertEquals("E2", drivers.nextWindowId)
		AssertEquals(20, Int(drivers.BoundFor(2).maximumAdditional))
		AssertEquals(26, Int(primary.BoundFor(2).maximumAdditional))
	End Method

	Method testUnboundedBonusPreventsCertification() { test }
		Local comp:TCompetition = Series(2)
		Local config:TSeriesConfig = TSeriesConfig(comp.stages[0].config)
		Local bonus:TBonusRule = New TBonusRule
		bonus.code = "BONUS"
		bonus.points = 1
		bonus.uniquePerSession = True
		config.scoring.bonuses = [bonus]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		Local analysis:TClinchAnalysis = engine.AnalyzeClinching(comp, state, "SEASON", "DRIVERS")
		AssertEquals(EClinchStatus.Indeterminate.Ordinal(), analysis.status.Ordinal())
		bonus.maxPointsPerAward = 1
		analysis = engine.AnalyzeClinching(comp, state, "SEASON", "DRIVERS")
		AssertEquals(EClinchStatus.NotCertified.Ordinal(), analysis.status.Ordinal())
		AssertEquals(22, Int(analysis.BoundFor(1).maximumAdditional))
		Local payload:TResultPayload = New TResultPayload
		payload.kind = EResultKind.Classification
		payload.order = [1, 2, 3]
		Local award:TResultAward = New TResultAward
		award.code = "BONUS"
		award.participantId = 1
		award.pointsOverride = 100
		payload.awards = [award]
		Local rejected:Int = False
		Try
			engine.RecordResult(comp, state, "SEASON", state.stages[0].fixtures[0].id, payload)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected)
		AssertEquals(EFixtureStatus.Scheduled.Ordinal(), state.stages[0].fixtures[0].status.Ordinal())
	End Method

	Method testLeagueLeaderCanClinchBeforeLastMatch() { test }
		Local comp:TCompetition = New TCompetition
		Local stage:TStage = New TStage
		stage.id = "LEAGUE"
		stage.stageType = EStageType.League
		stage.config = New TLeagueConfig
		comp.stages = [stage]
		Local state:TCompetitionState = New TCompetitionState
		Local stageState:TStageState = New TStageState
		stageState.stageId = "LEAGUE"
		stageState.leaderboard = New TLeaderboard
		Local leader:TLeaderboardRow = New TLeaderboardRow
		leader.participantId = 1
		leader.points = 9
		Local rival:TLeaderboardRow = New TLeaderboardRow
		rival.participantId = 2
		stageState.leaderboard.rows = [leader, rival]
		Local fixture:TFixtureState = New TFixtureState
		fixture.homeTeamId = 1
		fixture.awayTeamId = 2
		fixture.round = 4
		fixture.status = EFixtureStatus.Scheduled
		stageState.fixtures = [fixture]
		state.stages = [stageState]
		Local analysis:TClinchAnalysis = New TCompetitionEngine.AnalyzeClinching(comp, state, "LEAGUE")
		AssertEquals(EClinchStatus.Clinched.Ordinal(), analysis.status.Ordinal())
		AssertEquals(1, analysis.clinchedParticipantId)
		AssertEquals("round:4", analysis.nextWindowId)
	End Method
End Type

Type TQualificationAndRankingTest Extends TTest
	Function Row:TLeaderboardRow(id:Int, points:Int)
		Local row:TLeaderboardRow = New TLeaderboardRow
		row.participantId = id
		row.points = points
		Return row
	End Function

	Function Fixture:TFixtureState(id:String, home:Int, away:Int, homeScore:Int = 0, awayScore:Int = 0, complete:Int = False)
		Local fixture:TFixtureState = New TFixtureState
		fixture.id = id
		fixture.homeTeamId = home
		fixture.awayTeamId = away
		fixture.scoreHome = homeScore
		fixture.scoreAway = awayScore
		fixture.status = EFixtureStatus.Scheduled
		If complete Then
			fixture.status = EFixtureStatus.Completed
		End If

		Return fixture
	End Function

	Method testThreeWayHeadToHeadUsesMiniTable() { test }
		Local rows:TLeaderboardRow[] = [Row(1, 3), Row(2, 3), Row(3, 3)]
		Local fixtures:TFixtureState[] = [Fixture("A", 1, 2, 1, 0, True), Fixture("B", 2, 3, 1, 0, True), Fixture("C", 3, 1, 2, 0, True)]
		SortTableByTiebreakers(rows, [ETiebreaker.Points, ETiebreaker.HeadToHeadPoints, ETiebreaker.HeadToHeadGD], fixtures)
		AssertEquals(3, rows[0].participantId)
		AssertEquals(2, rows[1].participantId)
		AssertEquals(1, rows[2].participantId)
	End Method

	Method testHeadToHeadCanBeReappliedToRemainingTie() { test }
		Local rows:TLeaderboardRow[] = [Row(1, 10), Row(2, 10), Row(3, 10), Row(4, 10)]
		Local fixtures:TFixtureState[] = [..
			Fixture("AB", 1, 2, 10, 0, True), Fixture("AC", 1, 3, 1, 0, True), ..
			Fixture("AD", 4, 1, 1, 0, True), Fixture("BC", 2, 3, 10, 0, True), ..
			Fixture("BD", 4, 2, 10, 0, True), Fixture("CD", 3, 4, 1, 0, True)]
		SortTableByTiebreakers(rows, [ETiebreaker.Points, ETiebreaker.HeadToHeadPoints, ETiebreaker.HeadToHeadGD], fixtures, 3, 1, 0, True)
		AssertEquals(4, rows[0].participantId)
		AssertEquals(1, rows[1].participantId)
		AssertEquals(2, rows[2].participantId) ' beats 3 after the head-to-head block is re-applied
		AssertEquals(3, rows[3].participantId)
	End Method

	Method testQualificationAccountsForMutuallyExclusiveWins() { test }
		Local comp:TCompetition = New TCompetition
		Local stage:TStage = New TStage
		stage.id = "L"
		stage.stageType = EStageType.League
		stage.config = New TLeagueConfig
		TLeagueConfig(stage.config).tiebreakers = [ETiebreaker.Points]
		comp.stages = [stage]
		Local state:TCompetitionState = New TCompetitionState
		Local current:TStageState = New TStageState
		current.stageId = "L"
		current.leaderboard = New TLeaderboard
		current.leaderboard.rows = [Row(1, 6), Row(2, 4), Row(3, 4)]
		current.fixtures = [Fixture("rival_match", 2, 3)]
		state.stages = [current]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		Local answer:TQualificationAnalysis = engine.AnalyzeQualification(comp, state, "L", 1, 2)
		AssertEquals(EQualificationStatus.Guaranteed.Ordinal(), answer.status.Ordinal())
		AssertEquals(3, answer.scenariosExamined)
		answer = engine.AnalyzeQualification(comp, state, "L", 3, 1)
		AssertEquals(EQualificationStatus.Possible.Ordinal(), answer.status.Ordinal())
		AssertEquals("rival_match", answer.qualifyingScenario[0].fixtureId)
		answer = engine.AnalyzeQualification(comp, state, "L", 1, 1)
		AssertEquals(EQualificationStatus.Possible.Ordinal(), answer.status.Ordinal())
		answer = engine.AnalyzeQualification(comp, state, "L", 3, 1, "", 1)
		AssertEquals(EQualificationStatus.Indeterminate.Ordinal(), answer.status.Ordinal())
		current.leaderboard.rows[2].points = 0
		answer = engine.AnalyzeQualification(comp, state, "L", 3, 1)
		AssertEquals(EQualificationStatus.Eliminated.Ordinal(), answer.status.Ordinal())
	End Method

	Method testGroupQualificationOnlyUsesItsOwnEntrants() { test }
		Local comp:TCompetition = New TCompetition
		Local stage:TStage = New TStage
		stage.id = "GROUPS"
		stage.stageType = EStageType.Group
		stage.config = New TGroupConfig
		TGroupConfig(stage.config).tiebreakers = [ETiebreaker.Points]
		comp.stages = [stage]
		Local current:TStageState = New TStageState
		current.stageId = "GROUPS"
		current.leaderboard = New TLeaderboard
		current.leaderboard.rows = [Row(1, 2), Row(2, 1), Row(3, 30), Row(4, 20)]
		Local first:TFixtureState = Fixture("G1_last", 1, 2)
		first.groupKey = "G1"
		Local second:TFixtureState = Fixture("G2_last", 3, 4)
		second.groupKey = "G2"
		current.fixtures = [first, second]
		Local state:TCompetitionState = New TCompetitionState
		state.stages = [current]
		Local answer:TQualificationAnalysis = New TCompetitionEngine.AnalyzeQualification(comp, state, "GROUPS", 1, 1, "G1")
		AssertEquals(EQualificationStatus.Possible.Ordinal(), answer.status.Ordinal())
		AssertEquals(3, answer.scenariosExamined)
	End Method
End Type

Type TSeriesQualificationTest Extends TTest
	Method Competition:TCompetition()
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 3
			Local driver:TParticipant = New TParticipant
			driver.id = id
			driver.kind = EParticipantKind.Individual
			driver.parentTeamId = 10
			If id = 3 Then
				driver.parentTeamId = 20
			End If

			comp.participants :+ [driver]
		Next

		For Local id:Int = 10 To 20 Step 10
			Local team:TParticipant = New TParticipant
			team.id = id
			team.kind = EParticipantKind.Team
			comp.participants :+ [team]
		Next

		Local stage:TStage = New TStage
		stage.id = "SEASON"
		stage.stageType = EStageType.Series
		stage.config = New TSeriesConfig
		Local config:TSeriesConfig = TSeriesConfig(stage.config)
		config.scoring = New TScoringSystem
		config.scoring.mode = EScoringMode.PositionTable
		For Local position:Int = 1 To 3
			Local entry:TPointsTableEntry = New TPointsTableEntry
			entry.position = position
			If position = 1 Then
				entry.points = 10
			End If

			If position = 2 Then
				entry.points = 5
			End If

			config.scoring.table :+ [entry]
		Next

		For Local n:Int = 1 To 2
			Local event:TSeriesEvent = New TSeriesEvent
			event.id = "E" + n
			config.events :+ [event]
		Next

		Local drivers:TChampionshipConfig = New TChampionshipConfig
		drivers.code = "DRIVERS"
		drivers.filterByKind = True
		drivers.participantKind = EParticipantKind.Individual
		Local teams:TChampionshipConfig = New TChampionshipConfig
		teams.code = "TEAMS"
		teams.parentTeamPoints = True
		config.championships = [drivers, teams]
		comp.stages = [stage]
		Return comp
	End Method

	Method Engine:TCompetitionEngine()
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Series, New TSeriesScheduler)
		engine.RegisterScorer(EStageType.Series, New TSeriesScorer)
		Return engine
	End Method

	Method testPositionSeriesDriverAndTeamQualification() { test }
		Local comp:TCompetition = Competition()
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		state.stages[0].entrants = [1, 2, 3]
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[0].id, [1, 2, 3])
		Local drivers:TQualificationAnalysis = engine.AnalyzeQualification(comp, state, "SEASON", 1, 1, "", 100000, "DRIVERS")
		AssertEquals(EQualificationStatus.Possible.Ordinal(), drivers.status.Ordinal())
		AssertEquals(1, drivers.qualifyingScenario.Length)
		AssertTrue(drivers.qualifyingScenario[0].classificationOrder.Length > 0)
		AssertEquals(1, drivers.failingScenario.Length)
		Local path:String = "/private/tmp/tourney_series_qualification.json"
		Local jconv:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local output:TStream = WriteStream(path)
		jconv.ToJson(drivers, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		drivers = TQualificationAnalysis(jconv.FromJson(input, "TQualificationAnalysis"))
		input.Close()
		DeleteFile(path)
		AssertEquals(EQualificationStatus.Possible.Ordinal(), drivers.status.Ordinal())
		AssertTrue(drivers.qualifyingScenario[0].classificationOrder.Length > 0)
		Local teams:TQualificationAnalysis = engine.AnalyzeQualification(comp, state, "SEASON", 10, 1, "", 100000, "TEAMS")
		AssertEquals(EQualificationStatus.Guaranteed.Ordinal(), teams.status.Ordinal())
		AssertEquals("TEAMS", teams.championshipCode)
	End Method

	Method testSeriesBonusAndSearchLimitAreIndeterminate() { test }
		Local comp:TCompetition = Competition()
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		state.stages[0].entrants = [1, 2, 3]
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[0].id, [1, 2, 3])
		Local analysis:TQualificationAnalysis = engine.AnalyzeQualification(comp, state, "SEASON", 1, 1, "", 1, "DRIVERS")
		AssertEquals(EQualificationStatus.Indeterminate.Ordinal(), analysis.status.Ordinal())
		Local bonus:TBonusRule = New TBonusRule
		bonus.code = "FASTEST"
		bonus.points = 1
		TSeriesConfig(comp.stages[0].config).scoring.bonuses = [bonus]
		analysis = engine.AnalyzeQualification(comp, state, "SEASON", 1, 1, "", 100000, "DRIVERS")
		AssertEquals(EQualificationStatus.Indeterminate.Ordinal(), analysis.status.Ordinal())
		AssertTrue(analysis.reason <> "")
	End Method

	Method testNamedChampionshipSkipsOtherSessionsAndUsesMultiplier() { test }
		Local comp:TCompetition = Competition()
		Local config:TSeriesConfig = TSeriesConfig(comp.stages[0].config)
		config.championships[0].sessionCodes = ["RACE"]
		config.events[1].pointsMultiplier = 2.0
		Local sprint:TSession = New TSession
		sprint.code = "SPRINT"
		sprint.scoringOverride = New TScoringSystem
		sprint.scoringOverride.mode = EScoringMode.PositionTable
		Local sprintWin:TPointsTableEntry = New TPointsTableEntry
		sprintWin.position = 1
		sprintWin.points = 3
		sprint.scoringOverride.table = [sprintWin]
		Local race:TSession = New TSession
		race.code = "RACE"
		config.events[1].sessions = [sprint, race]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		state.stages[0].entrants = [1, 2, 3]
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[0].id, [1, 2, 3])
		Local analysis:TQualificationAnalysis = engine.AnalyzeQualification(comp, state, "SEASON", 2, 1, "", 100000, "DRIVERS")
		AssertEquals(EQualificationStatus.Possible.Ordinal(), analysis.status.Ordinal())
		AssertEquals(1, analysis.qualifyingScenario.Length)
		AssertEquals("SEASON_E2_RACE", analysis.qualifyingScenario[0].fixtureId)
	End Method

	Method testCountbackSettlesPointsTieInTableAndQualification() { test }
		Local comp:TCompetition = Competition()
		Local config:TSeriesConfig = TSeriesConfig(comp.stages[0].config)
		config.championships[0].tiebreakers = [ETiebreaker.Points, ETiebreaker.FinishCountback]
		Local last:TSeriesEvent = New TSeriesEvent
		last.id = "E3"
		config.events :+ [last]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		state.stages[0].entrants = [1, 2, 3]
		For Local i:Int = 0 To 1
			engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[i].id, [1, 2, 3])
		Next

		Local answer:TQualificationAnalysis = engine.AnalyzeQualification(comp, state, "SEASON", 1, 1, "", 100000, "DRIVERS")
		AssertEquals(EQualificationStatus.Guaranteed.Ordinal(), answer.status.Ordinal())
		AssertEquals(0, answer.scenariosExamined) ' countback bounds prove the title directly
		answer = engine.AnalyzeQualification(comp, state, "SEASON", 2, 1, "", 100000, "DRIVERS")
		AssertEquals(EQualificationStatus.Eliminated.Ordinal(), answer.status.Ordinal())
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[2].id, [2, 3, 1])
		Local drivers:TNamedLeaderboard = state.stages[0].championships[0]
		AssertEquals(20, drivers.leaderboard.rows[0].points)
		AssertEquals(20, drivers.leaderboard.rows[1].points)
		AssertEquals(1, drivers.leaderboard.rows[0].participantId)
		answer = engine.AnalyzeQualification(comp, state, "SEASON", 1, 1, "", 100000, "DRIVERS")
		AssertEquals(EQualificationStatus.Guaranteed.Ordinal(), answer.status.Ordinal())
	End Method

	Method testTeamCountbackAggregatesMemberFinishes() { test }
		Local comp:TCompetition = Competition()
		comp.participants[1].parentTeamId = 20
		Local config:TSeriesConfig = TSeriesConfig(comp.stages[0].config)
		config.tiebreakers = [ETiebreaker.Points, ETiebreaker.FinishCountback]
		config.scoring.table[1].points = 0
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		state.stages[0].entrants = [1, 2, 3]
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[0].id, [1, 2, 3])
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[1].id, [2, 3, 1])
		Local teams:TNamedLeaderboard = state.stages[0].championships[1]
		AssertEquals(10, teams.leaderboard.rows[0].points)
		AssertEquals(10, teams.leaderboard.rows[1].points)
		AssertEquals(20, teams.leaderboard.rows[0].participantId)
		Local answer:TQualificationAnalysis = engine.AnalyzeQualification(comp, state, "SEASON", 20, 1, "", 100000, "TEAMS")
		AssertEquals(EQualificationStatus.Guaranteed.Ordinal(), answer.status.Ordinal())
	End Method

	Method testFutureClassificationUpdatesCountback() { test }
		Local comp:TCompetition = Competition()
		Local config:TSeriesConfig = TSeriesConfig(comp.stages[0].config)
		config.championships[0].tiebreakers = [ETiebreaker.Points, ETiebreaker.FinishCountback]
		config.scoring.table[0].points = 0
		config.scoring.table[1].points = 0
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		state.stages[0].entrants = [1, 2, 3]
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[0].id, [1, 2, 3])
		Local answer:TQualificationAnalysis = engine.AnalyzeQualification(comp, state, "SEASON", 2, 1, "", 100000, "DRIVERS")
		AssertEquals(EQualificationStatus.Possible.Ordinal(), answer.status.Ordinal())
		AssertEquals(2, answer.qualifyingScenario[0].classificationOrder[0])
		AssertEquals(1, answer.failingScenario[0].classificationOrder[0])
	End Method

	Method testCountbackCanSelectSessions() { test }
		Local comp:TCompetition = Competition()
		Local config:TSeriesConfig = TSeriesConfig(comp.stages[0].config)
		config.tiebreakers = [ETiebreaker.Points, ETiebreaker.FinishCountback]
		config.countback = New TSeriesCountbackConfig
		config.countback.sessionCodes = ["RACE"]
		config.countback.positions = [2]
		config.scoring.table[0].points = 0
		config.scoring.table[1].points = 0
		Local sprint:TSession = New TSession
		sprint.code = "SPRINT"
		Local race:TSession = New TSession
		race.code = "RACE"
		config.events = [config.events[0]]
		config.events[0].sessions = [sprint, race]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		state.stages[0].entrants = [1, 2, 3]
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[0].id, [2, 1, 3])
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[1].id, [1, 2, 3])
		AssertEquals(2, state.stages[0].championships[0].leaderboard.rows[0].participantId)
	End Method

	Method testCountbackConfigurationRoundTrips() { test }
		Local comp:TCompetition = Competition()
		Local championship:TChampionshipConfig = TSeriesConfig(comp.stages[0].config).championships[0]
		championship.tiebreakers = [ETiebreaker.Points, ETiebreaker.FinishCountback]
		championship.countback = New TSeriesCountbackConfig
		championship.countback.positions = [1, 2]
		championship.countback.sessionCodes = ["RACE"]
		Local path:String = "/private/tmp/tourney_countback_config.json"
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local output:TStream = WriteStream(path)
		jconv.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		Local restored:TCompetition = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		Local saved:TChampionshipConfig = TSeriesConfig(restored.stages[0].config).championships[0]
		AssertEquals(ETiebreaker.FinishCountback.Ordinal(), saved.tiebreakers[1].Ordinal())
		AssertEquals(2, saved.countback.positions.Length)
		AssertEquals("RACE", saved.countback.sessionCodes[0])
	End Method

	Method testOrderedCountbackUsesFutureFallbackSession() { test }
		Local comp:TCompetition = Competition()
		Local config:TSeriesConfig = TSeriesConfig(comp.stages[0].config)
		Local drivers:TChampionshipConfig = config.championships[0]
		drivers.sessionCodes = ["RACE"]
		drivers.tiebreakers = [ETiebreaker.Points, ETiebreaker.FinishCountback]
		Local raceBlock:TSeriesCountbackConfig = New TSeriesCountbackConfig
		raceBlock.sessionCodes = ["RACE"]
		raceBlock.positions = [1]
		Local qualifyingBlock:TSeriesCountbackConfig = New TSeriesCountbackConfig
		qualifyingBlock.sessionCodes = ["QUALI"]
		qualifyingBlock.positions = [1]
		drivers.countbackSequence = [raceBlock, qualifyingBlock]
		Local race:TSession = New TSession
		race.code = "RACE"
		config.events[0].sessions = [race]
		config.events[1].sessions = [race]
		Local finalEvent:TSeriesEvent = New TSeriesEvent
		finalEvent.id = "E3"
		Local qualifying:TSession = New TSession
		qualifying.code = "QUALI"
		finalEvent.sessions = [qualifying]
		config.events :+ [finalEvent]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		state.stages[0].entrants = [1, 2, 3]
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[0].id, [1, 2, 3])
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[1].id, [2, 1, 3])
		AssertEquals(1, state.stages[0].championships[0].leaderboard.rows[0].participantId)
		Local answer:TQualificationAnalysis = engine.AnalyzeQualification(comp, state, "SEASON", 2, 1, "", 100000, "DRIVERS")
		AssertEquals(EQualificationStatus.Possible.Ordinal(), answer.status.Ordinal())
		AssertEquals("SEASON_E3_QUALI", answer.qualifyingScenario[0].fixtureId)
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[2].id, [2, 1, 3])
		Local table:TLeaderboardRow[] = state.stages[0].championships[0].leaderboard.rows
		AssertEquals(2, table[0].participantId)
		AssertEquals(15, table[0].points)
		AssertEquals(15, table[1].points)
		answer = engine.AnalyzeQualification(comp, state, "SEASON", 2, 1, "", 100000, "DRIVERS")
		AssertEquals(EQualificationStatus.Guaranteed.Ordinal(), answer.status.Ordinal())
	End Method

	Method testOrderedCountbackConfigurationRoundTrips() { test }
		Local comp:TCompetition = Competition()
		Local config:TSeriesConfig = TSeriesConfig(comp.stages[0].config)
		Local first:TSeriesCountbackConfig = New TSeriesCountbackConfig
		first.sessionCodes = ["RACE"]
		first.positions = [1, 2]
		Local second:TSeriesCountbackConfig = New TSeriesCountbackConfig
		second.sessionCodes = ["QUALI"]
		second.positions = [1]
		config.countbackSequence = [first]
		config.championships[0].countbackSequence = [first, second]
		Local path:String = "/private/tmp/tourney_countback_sequence.json"
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
		Local output:TStream = WriteStream(path)
		jconv.ToJson(comp, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		Local restored:TCompetition = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		Local saved:TSeriesConfig = TSeriesConfig(restored.stages[0].config)
		AssertEquals(1, saved.countbackSequence.Length)
		AssertEquals(2, saved.championships[0].countbackSequence.Length)
		AssertEquals("QUALI", saved.championships[0].countbackSequence[1].sessionCodes[0])
	End Method

	Method testPrimaryCountbackBlockPrecedesFallback() { test }
		Local comp:TCompetition = Competition()
		Local config:TSeriesConfig = TSeriesConfig(comp.stages[0].config)
		config.scoring.table[0].points = 0
		config.scoring.table[1].points = 0
		config.championships[0].tiebreakers = [ETiebreaker.Points, ETiebreaker.FinishCountback]
		Local raceBlock:TSeriesCountbackConfig = New TSeriesCountbackConfig
		raceBlock.sessionCodes = ["RACE"]
		raceBlock.positions = [1]
		Local qualifyingBlock:TSeriesCountbackConfig = New TSeriesCountbackConfig
		qualifyingBlock.sessionCodes = ["QUALI"]
		qualifyingBlock.positions = [1]
		config.championships[0].countbackSequence = [raceBlock, qualifyingBlock]
		Local race:TSession = New TSession
		race.code = "RACE"
		config.events[0].sessions = [race]
		Local qualifying:TSession = New TSession
		qualifying.code = "QUALI"
		config.events[1].sessions = [qualifying]
		Local engine:TCompetitionEngine = Engine()
		Local state:TCompetitionState = engine.Initialize(comp)
		state.stages[0].entrants = [1, 2, 3]
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[0].id, [1, 2, 3])
		engine.RecordSeriesClassificationAndAdvance(comp, state, "SEASON", state.stages[0].fixtures[1].id, [2, 1, 3])
		AssertEquals(1, state.stages[0].championships[0].leaderboard.rows[0].participantId)
		Local answer:TQualificationAnalysis = engine.AnalyzeQualification(comp, state, "SEASON", 1, 1, "", 100000, "DRIVERS")
		AssertEquals(EQualificationStatus.Guaranteed.Ordinal(), answer.status.Ordinal())
	End Method
End Type

Type TGroupPotDrawTest Extends TTest
	Method testOnePerPotAndInfeasibleDraw() { test }
		Local comp:TCompetition = New TCompetition
		Local ids:Int[]
		For Local i:Int = 1 To 16
			Local p:TParticipant = New TParticipant
			p.id = i
			p.drawPot = "P" + (((i - 1) / 4) + 1)
			comp.participants :+ [p]
			ids :+ [i]
		Next

		Local constraints:TDrawConstraints = New TDrawConstraints
		constraints.maxFromPot = 1
		Local scheduler:TGroupScheduler = New TGroupScheduler
		Local groups:Int[][] = scheduler.PlaceWithConstraints(comp, ids, [4, 4, 4, 4], constraints, scheduler.BuildDrawIndex(comp.participants, Null))
		For Local group:Int[] = EachIn groups
			AssertEquals(4, group.Length)
			Local seen:Int[] = New Int[4]
			For Local pid:Int = EachIn group
				Local pot:Int = (pid - 1) / 4
				seen[pot] :+ 1
			Next

			For Local count:Int = EachIn seen
				AssertEquals(1, count)
			Next
		Next

		comp.participants[4].drawPot = "P1"
		Local rejected:Int = False
		Try
			scheduler.PlaceWithConstraints(comp, ids, [4, 4, 4, 4], constraints, scheduler.BuildDrawIndex(comp.participants, Null))
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Five entrants from one pot cannot fit four one-per-pot groups")
	End Method
End Type

Type TFlexibleEngineTest Extends TTest
	Method testCustomFormatAndConfigRoundTrip() { test }
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 2
			Local p:TParticipant = New TParticipant
			p.id = i
			comp.participants :+ [p]
		Next

		Local stage:TStage = SeriesStage("custom", "RACE")
		stage.formatCode = "custom-series"
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterFormat("custom-series", New TSeriesScheduler, New TSeriesScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(EStageStatus.Running.Ordinal(), state.stages[0].status.Ordinal())
		engine.RecordResult(comp, state, "custom", state.stages[0].fixtures[0].id, Classification([1, 2]))
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())

		Local serial:TConfigSerializer = New TConfigSerializer
		serial.RegisterConfig("example", New TExampleConfigFactory)
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", serial).WithEmptyArrays().Build()
		Local saved:TCompetition = New TCompetition
		Local customStage:TStage = New TStage
		customStage.id = "extension"
		customStage.config = New TExampleConfig
		TExampleConfig(customStage.config).special = 42
		saved.stages = [customStage]
		Local path:String = "rt_custom_tourney.json"
		Local output:TStream = WriteStream(path)
		jconv.ToJson(saved, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		Local loaded:TCompetition = TCompetition(jconv.FromJson(input, "TCompetition"))
		input.Close()
		DeleteFile(path)
		AssertEquals(42, TExampleConfig(loaded.stages[0].config).special)
	End Method

	Method testMatchupRulesAndByeWeeks() { test }
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 4
			Local p:TParticipant = New TParticipant
			p.id = i
			If i <= 2 Then p.divisionId = "A" Else p.divisionId = "B"

			p.previousRank = ((i - 1) Mod 2) + 1
			comp.participants :+ [p]
		Next

		Local a:TMatchupRule = New TMatchupRule
		a.sourceDivisionIds = ["A"]
		a.targetDivisionIds = ["A"]
		a.mode = EMatchupMode.AllPairs
		a.gamesPerPair = 2
		Local b:TMatchupRule = New TMatchupRule
		b.sourceDivisionIds = ["B"]
		b.targetDivisionIds = ["B"]
		b.mode = EMatchupMode.AllPairs
		b.gamesPerPair = 2
		Local ranked:TMatchupRule = New TMatchupRule
		ranked.sourceDivisionIds = ["A"]
		ranked.targetDivisionIds = ["B"]
		ranked.mode = EMatchupMode.SameRank
		Local schedule:TLeagueScheduleConfig = New TLeagueScheduleConfig
		schedule.matchupRules = [a, b, ranked]
		schedule.weeks = 4
		Local bye:TParticipantByeWeek = New TParticipantByeWeek
		bye.participantId = 1
		bye.week = 2
		schedule.byeWeeks = [bye]
		Local stage:TStage = New TStage
		stage.id = "league"
		stage.config = New TLeagueConfig
		TLeagueConfig(stage.config).schedule = schedule
		Local scheduler:TLeagueScheduler = New TLeagueScheduler
		Local fixtures:TFixtureState[] = scheduler.BuildFixtures(comp, stage)
		AssertEquals(6, fixtures.Length)
		For Local f:TFixtureState = EachIn fixtures
			AssertTrue(f.round >= 1 And f.round <= 4)
			AssertTrue(Not (f.round = 2 And (f.homeTeamId = 1 Or f.awayTeamId = 1)))
			For Local other:TFixtureState = EachIn fixtures
				If other = f Or other.round <> f.round Then
					Continue
				End If

				AssertTrue(f.homeTeamId <> other.homeTeamId And f.homeTeamId <> other.awayTeamId)
				AssertTrue(f.awayTeamId <> other.homeTeamId And f.awayTeamId <> other.awayTeamId)
			Next
		Next
	End Method

	Method testWeekAllocatorFindsFeasibleAssignment() { test }
		Local schedule:TLeagueScheduleConfig = New TLeagueScheduleConfig
		schedule.weeks = 2
		Local fixtures:TFixtureState[]
		Local pairs:Int[][] = [[1, 2], [4, 5], [2, 3], [3, 4]]
		For Local i:Int = 0 Until pairs.Length
			Local f:TFixtureState = New TFixtureState
			f.id = "F" + i
			f.homeTeamId = pairs[i][0]
			f.awayTeamId = pairs[i][1]
			fixtures :+ [f]
		Next

		Local allocator:TLeagueWeekAllocator = New TLeagueWeekAllocator
		allocator.Assign(New TCompetition, schedule, fixtures)
		For Local f:TFixtureState = EachIn fixtures
			AssertTrue(f.round = 1 Or f.round = 2)
			For Local other:TFixtureState = EachIn fixtures
				If f = other Or f.round <> other.round Then
					Continue
				End If

				AssertTrue(f.homeTeamId <> other.homeTeamId And f.homeTeamId <> other.awayTeamId)
				AssertTrue(f.awayTeamId <> other.homeTeamId And f.awayTeamId <> other.awayTeamId)
			Next
		Next

		fixtures[0].round = 1
		fixtures[2].round = 1
		Local rejected:Int = False
		Try
			allocator.Assign(New TCompetition, schedule, fixtures)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Conflicting preassigned weeks must be rejected")
	End Method

	Method testRoundRobinWeeksCanMoveAroundBye() { test }
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 4
			Local p:TParticipant = New TParticipant
			p.id = i
			comp.participants :+ [p]
		Next

		Local schedule:TLeagueScheduleConfig = New TLeagueScheduleConfig
		schedule.weeks = 4
		Local bye:TParticipantByeWeek = New TParticipantByeWeek
		bye.participantId = 1
		bye.week = 1
		schedule.byeWeeks = [bye]
		Local stage:TStage = New TStage
		stage.id = "league"
		stage.config = New TLeagueConfig
		TLeagueConfig(stage.config).schedule = schedule
		Local fixtures:TFixtureState[] = (New TLeagueScheduler).BuildFixtures(comp, stage)
		AssertEquals(6, fixtures.Length)
		For Local fixture:TFixtureState = EachIn fixtures
			AssertTrue(fixture.round >= 1 And fixture.round <= 4)
			If fixture.homeTeamId = 1 Or fixture.awayTeamId = 1 Then
				AssertTrue(fixture.round <> 1)
			End If
		Next
	End Method

	Method testDeductionChangesStandingsOrder() { test }
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 2
			Local p:TParticipant = New TParticipant
			p.id = i
			comp.participants :+ [p]
		Next

		Local stage:TStage = New TStage
		stage.id = "G"
		stage.stageType = EStageType.Group
		stage.config = New TGroupConfig
		TGroupConfig(stage.config).groups = 1
		TGroupConfig(stage.config).roundRobinPerOpponent = 1
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Group, New TGroupScheduler)
		engine.RegisterScorer(EStageType.Group, New TGroupScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.HeadToHeadScore
		Local fixture:TFixtureState = state.stages[0].fixtures[0]
		If fixture.homeTeamId = 1 Then result.scoreHome = 1 Else result.scoreAway = 1

		engine.RecordResult(comp, state, "G", fixture.id, result)
		AssertEquals(1, state.stages[0].leaderboard.rows[0].participantId)
		Local deduction:TResultPayload = New TResultPayload
		deduction.kind = EResultKind.AdminAdjustment
		Local adjustment:TPointAdjustment = New TPointAdjustment
		adjustment.participantId = 1
		adjustment.pointsDelta = -4
		deduction.adjustments = [adjustment]
		engine.RecordResult(comp, state, "G", "", deduction)
		AssertEquals(2, state.stages[0].leaderboard.rows[0].participantId)
		AssertEquals(-1, state.stages[0].leaderboard.rows[1].points)
	End Method

	Method testEventBonusLimitAndFinishRequirement() { test }
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 2
			Local p:TParticipant = New TParticipant
			p.id = i
			comp.participants :+ [p]
		Next

		Local stage:TStage = SeriesStage("season", "SPRINT")
		Local cfg:TSeriesConfig = TSeriesConfig(stage.config)
		Local race:TSession = New TSession
		race.code = "RACE"
		Local sessions:TSession[] = cfg.events[0].sessions
		sessions :+ [race]
		Local race2:TSession = New TSession
		race2.code = "RACE2"
		sessions :+ [race2]
		cfg.events[0].sessions = sessions
		Local bonus:TBonusRule = New TBonusRule
		bonus.code = "BONUS"
		bonus.points = 1
		bonus.uniquePerEvent = True
		bonus.requireFinish = True
		cfg.scoring.bonuses = [bonus]
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Series, New TSeriesScheduler)
		engine.RegisterScorer(EStageType.Series, New TSeriesScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local first:TResultPayload = Classification([1, 2])
		Local award:TResultAward = New TResultAward
		award.code = "BONUS"
		award.participantId = 1
		first.awards = [award]
		Local dnf:TFinishStatus = New TFinishStatus
		dnf.participantId = 1
		dnf.flag = EFinishFlag.DNF
		first.statuses = [dnf]
		engine.RecordResult(comp, state, "season", state.stages[0].fixtures[0].id, first)
		Local second:TResultPayload = Classification([1, 2])
		second.awards = [award]
		engine.RecordResult(comp, state, "season", state.stages[0].fixtures[1].id, second)
		Local third:TResultPayload = Classification([1, 2])
		third.awards = [award]
		engine.RecordResult(comp, state, "season", state.stages[0].fixtures[2].id, third)
		AssertEquals(25, state.stages[0].leaderboard.rows[0].points)
	End Method

	Method testLeagueSeasonMovements() { test }
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 4
			Local p:TParticipant = New TParticipant
			p.id = i
			p.divisionId = "middle"
			comp.participants :+ [p]
		Next

		Local stage:TStage = New TStage
		stage.id = "league"
		stage.stageType = EStageType.League
		stage.config = New TLeagueConfig
		Local cfg:TLeagueConfig = TLeagueConfig(stage.config)
		cfg.schedule = New TLeagueScheduleConfig
		cfg.schedule.vsOwnDivision = 2
		comp.stages = [stage]
		Local promote:TSeasonTransitionRule = New TSeasonTransitionRule
		promote.fromStageId = "league"
		promote.destinationDivisionId = "upper"
		promote.selection = New TFilterRule
		promote.selection.kind = EFilterKind.TopN
		promote.selection.n = 1
		Local relegate:TSeasonTransitionRule = New TSeasonTransitionRule
		relegate.fromStageId = "league"
		relegate.destinationDivisionId = "lower"
		relegate.selection = New TFilterRule
		relegate.selection.kind = EFilterKind.BottomN
		relegate.selection.n = 1
		comp.seasonTransitions = [promote, relegate]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		engine.RegisterScorer(EStageType.League, New TLeagueScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(12, state.stages[0].fixtures.Length)
		For Local f:TFixtureState = EachIn state.stages[0].fixtures
			Local result:TResultPayload = New TResultPayload
			result.kind = EResultKind.HeadToHeadScore
			If f.homeTeamId < f.awayTeamId Then
				result.scoreHome = 1
			Else
				result.scoreAway = 1
			End If

			engine.RecordResult(comp, state, "league", f.id, result)
		Next

		Local moves:TSeasonMovement[] = engine.ResolveSeasonMovements(comp, state)
		AssertEquals(2, moves.Length)
		AssertEquals(1, moves[0].participantId)
		AssertEquals("upper", moves[0].toDivisionId)
		AssertEquals(4, moves[1].participantId)
		AssertEquals("lower", moves[1].toDivisionId)
		AssertEquals("middle", comp.participants[0].divisionId)
	End Method

	Method testPlayoffRanksCanBeSelected() { test }
		Local comp:TCompetition = New TCompetition
		Local state:TStageState = New TStageState
		state.leaderboard = New TLeaderboard
		For Local i:Int = 1 To 6
			Local p:TParticipant = New TParticipant
			p.id = i
			comp.participants :+ [p]
			Local row:TLeaderboardRow = New TLeaderboardRow
			row.participantId = i
			row.points = 7 - i
			state.leaderboard.rows :+ [row]
		Next

		Local stage:TStage = New TStage
		stage.config = New TGroupConfig
		stage.advancement = [New TAdvancement]
		stage.advancement[0].rule = New TFilterRule
		stage.advancement[0].rule.kind = EFilterKind.TopN
		stage.advancement[0].rule.scope = EFilterScope.All
		stage.advancement[0].rule.startRank = 3
		stage.advancement[0].rule.n = 4
		Local adv:TGroupAdvancer = New TGroupAdvancer
		Local selected:TParticipant[] = adv.ProduceAdvancements(comp, stage, state)
		AssertEquals(4, selected.Length)
		AssertEquals(3, selected[0].id)
		AssertEquals(6, selected[3].id)
	End Method

	Method testBranchingAndJoiningStages() { test }
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 4
			Local p:TParticipant = New TParticipant
			p.id = i
			p.name = "P" + i
			comp.participants :+ [p]
		Next

		Local a:TStage = SeriesStage("A", "BOTH")
		Local b:TStage = SeriesStage("B", "BOTH")
		b.independent = True
		a.advancement = [TopOne("C")]
		b.advancement = [TopOne("C")]
		Local c:TStage = New TStage
		c.id = "C"
		c.stageType = EStageType.Bracket
		c.input = New TEntrySource
		c.input.fromStageIds = ["A", "B"]
		c.config = New TBracketConfig
		TBracketConfig(c.config).size = 2
		TBracketConfig(c.config).matchFormat = New TMatchFormat
		TBracketConfig(c.config).matchFormat.legs = 1
		comp.stages = [a, b, c]

		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Series, New TSeriesScheduler)
		engine.RegisterScorer(EStageType.Series, New TSeriesScorer)
		engine.RegisterAdvancer(EStageType.Series, New TSeriesAdvancer)
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(EStageStatus.Running.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(EStageStatus.Running.Ordinal(), state.stages[1].status.Ordinal())
		AssertEquals(EStageStatus.Pending.Ordinal(), state.stages[2].status.Ordinal())

		Local bad:TResultPayload = Classification([1, 1, 3, 4])
		Local rejected:Int = False
		Try
			engine.RecordResult(comp, state, "A", state.stages[0].fixtures[0].id, bad)
		Catch e:Object
			rejected = True
		End Try

		AssertTrue(rejected, "Duplicate classification must be rejected")
		AssertEquals(EFixtureStatus.Scheduled.Ordinal(), state.stages[0].fixtures[0].status.Ordinal())

		engine.RecordResult(comp, state, "A", state.stages[0].fixtures[0].id, Classification([1, 2, 3, 4]))
		AssertEquals(EStageStatus.Pending.Ordinal(), state.stages[2].status.Ordinal())
		engine.RecordResult(comp, state, "B", state.stages[1].fixtures[0].id, Classification([2, 1, 3, 4]))
		AssertEquals(EStageStatus.Running.Ordinal(), state.stages[2].status.Ordinal())
		AssertEquals(1, state.stages[2].fixtures.Length)
		Local final:TFixtureState = state.stages[2].fixtures[0]
		AssertTrue((final.homeTeamId = 1 And final.awayTeamId = 2) Or (final.homeTeamId = 2 And final.awayTeamId = 1))
	End Method

	Method testSharedVenueCannotHostSimultaneously() { test }
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 4
			Local p:TParticipant = New TParticipant
			p.id = i
			If i <= 2 Then
				p.homeVenueId = "shared"
			End If

			comp.participants :+ [p]
		Next

		Local first:TFixtureState = New TFixtureState
		first.id = "jets"
		first.homeTeamId = 1
		first.awayTeamId = 3
		Local second:TFixtureState = New TFixtureState
		second.id = "giants"
		second.homeTeamId = 2
		second.awayTeamId = 4
		Local stage:TStage = New TStage
		stage.schedule = New TSchedulePolicy
		stage.schedule.calendar = New TCalendar
		Local early:TSlot = New TSlot
		early.id = "early"
		early.dateTime = "2026-10-22T12:00:00Z"
		early.venueId = "shared"
		Local late:TSlot = New TSlot
		late.id = "late"
		late.dateTime = "2026-10-22T16:00:00Z"
		late.venueId = "shared"
		stage.schedule.calendar.slots = [early, late]
		Local allocator:TCalendarSlotAllocator = New TCalendarSlotAllocator
		allocator.Assign(comp, stage, [first, second])
		AssertEquals("early", first.slotId)
		AssertEquals("late", second.slotId)
	End Method

	Method testTimedAndClassifiedSessionsProduceTwoChampionships() { test }
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 2
			Local driver:TParticipant = New TParticipant
			driver.id = i
			driver.kind = EParticipantKind.Individual
			driver.parentTeamId = i + 10
			comp.participants :+ [driver]
			Local team:TParticipant = New TParticipant
			team.id = i + 10
			team.kind = EParticipantKind.Team
			comp.participants :+ [team]
		Next

		Local stage:TStage = SeriesStage("season", "RACE")
		Local cfg:TSeriesConfig = TSeriesConfig(stage.config)
		Local quali:TSession = New TSession
		quali.code = "QUALI"
		quali.scoringOverride = New TScoringSystem
		quali.scoringOverride.mode = EScoringMode.TimeBased
		cfg.events[0].sessions = [quali, cfg.events[0].sessions[0]]
		Local drivers:TChampionshipConfig = New TChampionshipConfig
		drivers.code = "drivers"
		drivers.filterByKind = True
		drivers.participantKind = EParticipantKind.Individual
		drivers.sessionCodes = ["RACE"]
		Local teams:TChampionshipConfig = New TChampionshipConfig
		teams.code = "teams"
		teams.parentTeamPoints = True
		teams.sessionCodes = ["RACE"]
		cfg.championships = [drivers, teams]
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Series, New TSeriesScheduler)
		engine.RegisterScorer(EStageType.Series, New TSeriesScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local timed:TResultPayload = New TResultPayload
		timed.kind = EResultKind.TimeBased
		Local t1:TParticipantTime = New TParticipantTime
		t1.participantId = 1
		t1.millis = 90000
		Local t2:TParticipantTime = New TParticipantTime
		t2.participantId = 2
		t2.millis = 91000
		timed.times = [t1, t2]
		engine.RecordResult(comp, state, "season", state.stages[0].fixtures[0].id, timed)
		engine.RecordResult(comp, state, "season", state.stages[0].fixtures[1].id, Classification([2, 1]))
		AssertEquals(2, state.stages[0].championships.Length)
		AssertEquals("drivers", state.stages[0].championships[0].code)
		AssertEquals(2, state.stages[0].championships[0].leaderboard.rows[0].participantId)
		AssertEquals("teams", state.stages[0].championships[1].code)
		AssertEquals(12, state.stages[0].championships[1].leaderboard.rows[0].participantId)
	End Method

	Function SeriesStage:TStage(id:String, code:String)
		Local stage:TStage = New TStage
		stage.id = id
		stage.stageType = EStageType.Series
		stage.config = New TSeriesConfig
		Local cfg:TSeriesConfig = TSeriesConfig(stage.config)
		cfg.scoring = New TScoringSystem
		cfg.scoring.mode = EScoringMode.PositionTable
		Local p1:TPointsTableEntry = New TPointsTableEntry
		p1.position = 1
		p1.points = 8
		Local p2:TPointsTableEntry = New TPointsTableEntry
		p2.position = 2
		p2.points = 6
		cfg.scoring.table = [p1, p2]
		Local event:TSeriesEvent = New TSeriesEvent
		event.id = "event"
		Local session:TSession = New TSession
		session.code = code
		event.sessions = [session]
		cfg.events = [event]
		Return stage
	End Function

	Function TopOne:TAdvancement(destination:String)
		Local route:TAdvancement = New TAdvancement
		route.toStageId = destination
		route.rule = New TFilterRule
		route.rule.kind = EFilterKind.TopN
		route.rule.n = 1
		Return route
	End Function

	Function Classification:TResultPayload(order:Int[])
		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.Classification
		result.order = order
		Return result
	End Function
End Type

Type TExampleConfig Extends TConfig
	Field special:Int
	Method New()
		configCode = "example"
	End Method
End Type

Type TExampleConfigFactory Implements IConfigFactory
	Method Create:TConfig()
		Return New TExampleConfig
	End Method
End Type

Type TPotsSeedingOrderTest Extends TTest

	Field groupScheduler:TGroupScheduler

	Method testPotsOrderYieldsOnePerPotPerGroup() { test }
		' Build 8 entrants in 2 pots (P1 ids 1..4, P2 ids 5..8)
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 4
			comp.participants :+ [ MakePotParticipant(i, "P1") ]
		Next

		For Local i:Int = 5 To 8
			comp.participants :+ [ MakePotParticipant(i, "P2") ]
		Next

		' Group stage: 4 groups of size 2, seeding by Pots
		Local stg:TStage = New TStage
		stg.id = "GRP"
		stg.stageType = EStageType.Group
		stg.input = New TEntrySource
		stg.input.seeding = New TSeedingPolicy
		stg.input.seeding.seedingMethod = ESeedingMethod.Pots
		stg.input.seeding.pots = ["P1", "P2"]

		stg.config = New TGroupConfig
		TGroupConfig(stg.config).groups = 4
		TGroupConfig(stg.config).groupSize = 2
		TGroupConfig(stg.config).roundRobinPerOpponent = 1

		groupScheduler = New TGroupScheduler

		' 1) Get the order produced by the seeding policy
		Local order:Int[] = groupScheduler.OrderEntrantsByPolicy(comp, stg)
		AssertEquals(8, order.Length, "Order must include all entrants")

		' 2) Simulate scheduler's round-robin assignment into groups
		Local groups:Int[][] = DealIntoGroups(order, 4, 2)

		' 3) Assert each group has exactly one from each pot
		For Local gi:Int = 0 Until groups.Length
			Local g:Int[] = groups[gi]
			AssertEquals(2, g.Length, "Each group must have 2 entrants")

			Local pot1:Int = 0, pot2:Int = 0
			For Local pid:Int = EachIn g
				Local pot:String = GetPot(comp, pid)
				If pot = "P1" Then
					pot1 :+ 1
				End If

				If pot = "P2" Then
					pot2 :+ 1
				End If
			Next

			AssertEquals(1, pot1, "Group " + (gi + 1) + " must have exactly one from P1")
			AssertEquals(1, pot2, "Group " + (gi + 1) + " must have exactly one from P2")
		Next
	End Method

	' ---------- helpers ----------
	Function MakePotParticipant:TParticipant(id:Int, pot:String)
		Local p:TParticipant = New TParticipant
		p.id = id
		p.name = pot + "-" + id

		' Store pot label in meta in a way your seeding reads.
		' If you use TMap for meta, do that; otherwise adapt to your meta type.
		Local m:TMap = New TMap
		m.Insert("pot", pot)
		p.meta = m

		Return p
	End Function

	Function GetPot:String(comp:TCompetition, pid:Int)
		For Local p:TParticipant = EachIn comp.participants
			If p.id = pid Then
				Local m:TMap = TMap(p.meta)
				If m <> Null Then
					Return String(m.ValueForKey("pot"))
				End If
			End If
		Next

		Return ""
	End Function

	' Deal entrants into groups G1..Gk, round-robin, stopping once each group hits groupSize
	Function DealIntoGroups:Int[][](order:Int[], groupCount:Int, groupSize:Int)
		Local groups:Int[][]
		groups = groups[..groupCount] ' allocate outer

		' track fill counts
		Local filled:Int[groupCount]
		Local assigned:Int = 0
		Local gi:Int = 0

		For Local idx:Int = 0 Until order.Length
			' find next group that still has room
			Local tries:Int = 0
			While filled[gi] >= groupSize And tries < groupCount
				gi = (gi + 1) Mod groupCount
				tries :+ 1
			Wend

			If filled[gi] >= groupSize Then
				' all full (extra entrants would indicate mismatch in inputs)
				Exit
			End If

			groups[gi] :+ [ order[idx] ]
			filled[gi] :+ 1
			assigned :+ 1

			' move to next group for round-robin effect
			gi = (gi + 1) Mod groupCount
		Next

		' sanity
		For Local g:Int[] = EachIn groups
			AssertTrue(g.Length <= groupSize, "No group should exceed its size")
		Next

		Return groups
	End Function

End Type

Type TGroupAdvancementTest Extends TTest

	' 1) Top-N per group (SUPPORTED by current code)   [oai_citation:0‡tourney.bmx](file-service://file-8t5cHASzU57UtReioWDcdr)
	Method test_Top2_PerGroup() { test }
		Local comp:TCompetition = MakeParticipants(8)

		Local stg:TStage = New TStage
		stg.id = "GROUPS"
		stg.stageType = EStageType.Group
		stg.advancement = [..
			Adv("NEXT", FR_TopN(2, EFilterScope.PerGroup))..
		]

		Local st:TStageState = New TStageState
		st.stageId = stg.id
		st.status = EStageStatus.Complete

		' Group A standings: 1,2,3,4
		' Group B standings: 5,6,7,8 (already sorted best→worst)
		st.groups = [..
			GroupTable("G1", [ Row(1, 9), Row(2, 6), Row(3, 3), Row(4, 0) ]), ..
			GroupTable("G2", [ Row(5, 9), Row(6, 6), Row(7, 3), Row(8, 0) ])..
		]

		Local adv:IStageAdvancer = New TGroupAdvancer
		Local qs:TParticipant[] = adv.ProduceAdvancements(comp, stg, st)
		Local got:Int[] = Ids(qs)

		AssertEqualsI(4, got.Length, "Top2 per group → 4 qualifiers")
		AssertTrue(ContainsAll(got, [1, 2, 5, 6]), "Expected A1,A2,B1,B2")
	End Method


	' 2) Best X across groups (wild cards) – requires small addition to TGroupAdvancer
	Method test_Best2_AcrossGroups() { test }
		Local comp:TCompetition = MakeParticipants(8)

		Local stg:TStage = New TStage
		stg.id = "GROUPS"
		stg.stageType = EStageType.Group
		stg.advancement = [..
			Adv("NEXT", FR_BestXAcross(2))..
		]

		Local st:TStageState = New TStageState
		st.stageId = stg.id
		st.status = EStageStatus.Complete

		' A: 1(10), 2(7), 3(4), 4(1)
		' B: 5(11), 6(6), 7(5), 8(0)
		st.groups = [..
			GroupTable("G1", [ Row(1, 10), Row(2, 7), Row(3, 4), Row(4, 1) ]), ..
			GroupTable("G2", [ Row(5, 11), Row(6, 6), Row(7, 5), Row(8, 0) ])..
		]

		Local adv:IStageAdvancer = New TGroupAdvancer
		Local qs:TParticipant[] = adv.ProduceAdvancements(comp, stg, st)
		Local got:Int[] = Ids(qs)

		' Across all teams, best two by points are 5(11) and 1(10)
		AssertEqualsI(2, got.Length, "Best2 across groups → 2 qualifiers")
		AssertTrue(ContainsAll(got, [5, 1]), "Expected global best two 5 and 1")
	End Method


	' 3) Winners + Best Runners-up – requires same addition to TGroupAdvancer
	Method test_WinnersPlusBestRunnersUp() { test }
		Local comp:TCompetition = MakeParticipants(12)

		Local stg:TStage = New TStage
		stg.id = "GROUPS"
		stg.stageType = EStageType.Group
		stg.advancement = [..
			Adv("NEXT", FR_TopN(1, EFilterScope.PerGroup)),  ' winners A1,B1,C1
			Adv("NEXT", FR_BestXAcross(2))..        ' best two among the rest
		]

		Local st:TStageState = New TStageState
		st.stageId = stg.id
		st.status = EStageStatus.Complete

		' 3 groups (A,B,C), each 4 teams. Distinct points for deterministic picks.
		' A: 1(9),  2(7), 3(4), 4(1)  -> winner 1
		' B: 5(8),  6(7), 7(3), 8(0)  -> winner 5
		' C: 9(10), 10(6),11(5),12(0) -> winner 9
		st.groups = [..
			GroupTable("G1", [ Row(1, 9), Row(2, 7), Row(3, 4), Row(4, 1) ]), ..
			GroupTable("G2", [ Row(5, 8), Row(6, 7), Row(7, 3), Row(8, 0) ]), ..
			GroupTable("G3", [ Row(9, 10), Row(10, 6), Row(11, 5), Row(12, 0) ])..
		]

		Local adv:IStageAdvancer = New TGroupAdvancer
		Local qs:TParticipant[] = adv.ProduceAdvancements(comp, stg, st)
		Local got:Int[] = Ids(qs)

		' Winners are 1,5,9. Remove them, remaining best two by points are 2(7) and 6(7).
		AssertEqualsI(5, got.Length, "Winners (3) + best runners-up (2) → 5 qualifiers")
		AssertTrue(ContainsAll(got, [1, 5, 9, 2, 6]), "Expected {1,5,9} + {2,6}")
	End Method

	Method testBestThirdPlacesExcludeFourthPlacedTeams() { test }
		Local comp:TCompetition = MakeParticipants(8)
		Local stage:TStage = New TStage
		stage.id = "GROUPS"
		stage.stageType = EStageType.Group
		Local top:TFilterRule = FR_TopN(2, EFilterScope.PerGroup)
		Local third:TFilterRule = FR_BestXAcross(1)
		third.startRank = 3
		stage.advancement = [Adv("NEXT", top), Adv("NEXT", third)]
		Local state:TStageState = New TStageState
		state.stageId = stage.id
		state.status = EStageStatus.Complete
		' A4 has more points than B3, but only third-place teams are eligible.
		state.groups = [..
			GroupTable("A", [Row(1, 9), Row(2, 7), Row(3, 5), Row(4, 4)]), ..
			GroupTable("B", [Row(5, 9), Row(6, 7), Row(7, 3), Row(8, 0)])..
		]
		Local selected:TParticipant[] = New TGroupAdvancer.ProduceAdvancements(comp, stage, state)
		Local got:Int[] = Ids(selected)
		AssertEquals(5, got.Length)
		AssertTrue(ContainsAll(got, [1, 2, 5, 6, 3]))
		AssertTrue(Not ContainsAll(got, [4]))
	End Method

	' Helpers
	Function MakeParticipants:TCompetition(n:Int)
		Local c:TCompetition = New TCompetition
		For Local i:Int = 1 To n
			Local p:TParticipant = New TParticipant
			p.id = i; p.name = "T" + i
			c.participants :+ [p]
		Next

		Return c
	End Function

	Function Row:TLeaderboardRow(pid:Int, pts:Int)
		Local r:TLeaderboardRow = New TLeaderboardRow
		r.participantId = pid
		r.points = pts
		Return r
	End Function

	Function GroupTable:TGroupTable(key:String, rows:TLeaderboardRow[])
		Local g:TGroupTable = New TGroupTable
		g.key = key
		g.rows = rows
		Return g
	End Function

	Function Adv:TAdvancement(toId:String, rule:TFilterRule)
		Local a:TAdvancement = New TAdvancement
		a.toStageId = toId
		a.rule = rule
		Return a
	End Function

	Function FR_TopN:TFilterRule(n:Int, scope:EFilterScope)
		Local fr:TFilterRule = New TFilterRule
		fr.kind = EFilterKind.TopN
		fr.n = n
		fr.scope = scope
		Return fr
	End Function

	Function FR_BestXAcross:TFilterRule(n:Int)
		Local fr:TFilterRule = New TFilterRule
		fr.kind = EFilterKind.BestXAcrossGroups
		fr.n = n
		fr.scope = EFilterScope.All
		Return fr
	End Function

	Function Ids:Int[](pp:TParticipant[])
		Local out:Int[]
		For Local p:TParticipant = EachIn pp; out :+ [p.id]; Next

		Return out
	End Function

	Function ContainsAll:Int(have:Int[], want:Int[]) {asBool}
		For Local v:Int = EachIn want
			Local ok:Int
			For Local h:Int = EachIn have
				If h = v Then ok = 1; Exit
			Next

			If Not ok Then
				Return False
			End If
		Next

		Return True
	End Function

End Type

Type THistoricalWorldCupReplayTest Extends TTest
	Method testAllOfficialThirdPlaceCombinationsPlaceEightEntrants() { test }
		Local choices:TConditionalSlotCase[] = TWorldCup2026Replay.ThirdPlaceCases(AppDir + "/../examples/world_cup_2026_third_place.tsv")
		AssertEquals(495, choices.Length)
		Local source:TStageState = New TStageState
		For Local groupIndex:Int = 0 Until 12
			Local group:TGroupTable = New TGroupTable
			group.key = "ABCDEFGHIJKL"[groupIndex..groupIndex + 1]
			For Local rank:Int = 1 To 3
				Local row:TLeaderboardRow = New TLeaderboardRow
				row.participantId = groupIndex * 3 + rank
				group.rows :+ [row]
			Next

			source.groups :+ [group]
		Next

		Local mapping:TAdvancementMapping = New TAdvancementMapping
		mapping.mode = EAdvMappingMode.ConditionalSlots
		mapping.qualifyingRank = 3
		mapping.conditionalCases = choices
		Local target:TStage = New TStage
		target.config = New TBracketConfig
		TBracketConfig(target.config).size = 32
		Local engine:TCompetitionEngine = New TCompetitionEngine
		For Local choice:TConditionalSlotCase = EachIn choices
			Local ids:Int[]
			For Local key:String = EachIn choice.qualifyingGroupKeys
				ids :+ [(key[0] - 65) * 3 + 3]
			Next

			Local slots:String[] = engine.RoutedSlots(mapping, ids, source, target)
			AssertEquals(8, slots.Length)
			For Local i:Int = 0 Until 8
				AssertEquals(choice.assignments[i].slotId, slots[i])
			Next
		Next
	End Method

	Method testComplete2026Tournament() { test }
		Local timeline:TCompetitionTimeline = New TCompetitionTimeline
		Local champion:Int = TWorldCup2026Replay.Run(AppDir + "/../examples/world_cup_2026.tsv", timeline)
		AssertEquals(104, timeline.frames.Length)
		AssertEquals(48, timeline.participants.Length)
		AssertEquals("Spain", timeline.Participant(champion).name)
		AssertEquals("WORLD_CUP_W5", timeline.frames[103].stageId)
		AssertEquals("WORLD_CUP_THIRD", timeline.frames[102].stageId)
		AssertEquals("Colombia", timeline.Participant(timeline.frames[71].groups[10].rows[0].participantId).name)
		AssertEquals(7, timeline.frames[71].groups[10].rows[0].points)
		AssertEquals(12, timeline.frames[71].groups.Length)
		AssertEquals(4, timeline.frames[71].groups[10].rows.Length)
		AssertEquals(0, timeline.frames[0].groups[0].rows[0].losses)
	End Method

	' FIFA World Cup 2026 Group K, six official group results:
	' https://www.fifa.com/en/tournaments/mens/worldcup/canadamexicousa2026/articles/match-schedule-fixtures-results-teams-stadiums
	Method test2026GroupKStandings() { test }
		Local comp:TCompetition = New TCompetition
		Local names:String[] = ["Portugal", "Colombia", "Congo DR", "Uzbekistan"]
		For Local i:Int = 0 Until names.Length
			Local participant:TParticipant = New TParticipant
			participant.id = i + 1
			participant.name = names[i]
			comp.participants :+ [participant]
		Next

		Local stage:TStage = New TStage
		stage.id = "GROUP_K"
		stage.stageType = EStageType.Group
		stage.input = New TEntrySource
		stage.input.seeding = New TSeedingPolicy
		stage.input.seeding.seedingMethod = ESeedingMethod.Ranking
		stage.input.constraints = New TDrawConstraints
		stage.config = New TGroupConfig
		Local config:TGroupConfig = TGroupConfig(stage.config)
		config.groups = 1
		config.groupSize = 4
		config.roundRobinPerOpponent = 1
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Group, New TGroupScheduler)
		engine.RegisterScorer(EStageType.Group, New TGroupScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		AssertEquals(6, state.stages[0].fixtures.Length)
		RecordPair(engine, comp, state, 1, 3, 1, 1)
		RecordPair(engine, comp, state, 4, 2, 1, 3)
		RecordPair(engine, comp, state, 1, 4, 5, 0)
		RecordPair(engine, comp, state, 2, 3, 1, 0)
		RecordPair(engine, comp, state, 2, 1, 0, 0)
		RecordPair(engine, comp, state, 3, 4, 3, 1)
		Local rows:TLeaderboardRow[] = state.stages[0].leaderboard.rows
		AssertEquals(EStageStatus.Complete.Ordinal(), state.stages[0].status.Ordinal())
		AssertEquals(2, rows[0].participantId)
		AssertEquals(7, rows[0].points)
		AssertEquals(1, rows[1].participantId)
		AssertEquals(5, rows[1].points)
		AssertEquals(3, rows[2].participantId)
		AssertEquals(4, rows[2].points)
		AssertEquals(4, rows[3].participantId)
		AssertEquals(0, rows[3].points)
	End Method

	Function RecordPair(engine:TCompetitionEngine, comp:TCompetition, state:TCompetitionState, first:Int, second:Int, firstScore:Int, secondScore:Int)
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
			If fixture.homeTeamId = first And fixture.awayTeamId = second Then
				engine.RecordResultAndAdvance(comp, state, "GROUP_K", fixture.id, firstScore, secondScore)
				Return
			End If

			If fixture.homeTeamId = second And fixture.awayTeamId = first Then
				engine.RecordResultAndAdvance(comp, state, "GROUP_K", fixture.id, secondScore, firstScore)
				Return
			End If
		Next

		Throw "Historical fixture not scheduled"
	End Function
End Type

Type THistoricalWimbledonReplayTest Extends TTest
	Method test2025MensSinglesFullDraw() { test }
		Local champion:Int = TWimbledon2025Replay.Replay(AppDir + "/../examples/wimbledon_2025_mens_singles.tsv")
		AssertEquals(1, champion) ' Jannik Sinner, official draw position 1
	End Method
End Type

Type TSetRetirementTest Extends TTest
	Method testLeaderCanRetireAndWinnerSurvivesStateRoundTrip() { test }
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 2
			Local participant:TParticipant = New TParticipant
			participant.id = id
			comp.participants :+ [participant]
		Next

		Local stage:TStage = New TStage
		stage.id = "TENNIS"
		stage.stageType = EStageType.Bracket
		stage.input = New TEntrySource
		stage.input.seeding = New TSeedingPolicy
		stage.input.seeding.seedingMethod = ESeedingMethod.Ranking
		stage.input.constraints = New TDrawConstraints
		stage.config = New TBracketConfig
		Local config:TBracketConfig = TBracketConfig(stage.config)
		config.size = 2
		config.matchFormat = New TMatchFormat
		config.matchFormat.setRules = New TSetRules
		config.matchFormat.setRules.usesSets = True
		config.matchFormat.setRules.setsBestOf = 5
		config.matchFormat.setRules.gamesPerSetTarget = 6
		config.matchFormat.setRules.gamesMargin = 2
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local fixture:TFixtureState = state.stages[0].fixtures[0]
		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.SetBased
		result.retiredParticipantId = fixture.homeTeamId
		Local complete:TSetScore = New TSetScore
		complete.home = 6; complete.away = 3
		Local partial:TSetScore = New TSetScore
		partial.home = 2; partial.away = 2
		result.sets = [complete, partial]
		engine.RecordResult(comp, state, stage.id, fixture.id, result)
		AssertEquals(fixture.awayTeamId, state.stages[0].leaderboard.rows[0].participantId)
		Local path:String = "/private/tmp/tourney_retirement_state.json"
		Local jconv:TJConv = New TJConvBuilder.WithEmptyArrays().Build()
		Local output:TStream = WriteStream(path)
		jconv.ToJson(state, output)
		output.Close()
		Local input:TStream = ReadStream(path)
		Local restored:TCompetitionState = TCompetitionState(jconv.FromJson(input, "TCompetitionState"))
		input.Close()
		DeleteFile(path)
		AssertEquals(fixture.homeTeamId, restored.stages[0].fixtures[0].retiredParticipantId)
		AssertEquals(fixture.awayTeamId, restored.stages[0].fixtures[0].winnerOverrideId)
		AssertEquals(fixture.awayTeamId, New TBracketAdvancer.ComputePairWinner(config, restored.stages[0].fixtures))
	End Method
End Type

Type TPipeline_GroupToFinalTest Extends TTest

	Method test_GroupWinnersAdvanceToFinal() { test }
		' ---- Competition: 2 groups of 2; winners advance to a 2-team bracket final ----
		Local comp:TCompetition = New TCompetition
		comp.name = "G→F"

		' Four teams (ids 1..4)
		For Local i:Int = 1 To 4
			Local p:TParticipant = New TParticipant
			p.id = i
			p.name = "T" + i
			comp.participants :+ [p]
		Next

		' Stage 1: Groups (2 groups × 2 teams)
		Local grp:TStage = New TStage
		grp.id = "GRP"
		grp.stageType = EStageType.Group
		grp.input = New TEntrySource
		grp.input.mode = EEntryMode.Direct
		grp.input.seeding = New TSeedingPolicy
		grp.input.seeding.seedingMethod = ESeedingMethod.Random

		grp.config = New TGroupConfig
		TGroupConfig(grp.config).configType = EConfigType.Group
		TGroupConfig(grp.config).groups = 2
		TGroupConfig(grp.config).groupSize = 2
		TGroupConfig(grp.config).roundRobinPerOpponent = 1

		' Advancement: Top-1 per group to next stage
		grp.advancement = [ MakeAdv("FIN", MakeTopN(1, EFilterScope.PerGroup)) ]

		' Stage 2: Final (2-team bracket)
		Local fin:TStage = New TStage
		fin.id = "FIN"
		fin.stageType = EStageType.Bracket
		fin.input = New TEntrySource
		fin.input.mode = EEntryMode.FromStage
		fin.input.fromStageId = "GRP"
		fin.input.seeding = New TSeedingPolicy
		fin.input.seeding.seedingMethod = ESeedingMethod.Ranking
		fin.config = New TBracketConfig
		TBracketConfig(fin.config).configType = EConfigType.Bracket
		TBracketConfig(fin.config).size = 2
		TBracketConfig(fin.config).format = EBracketFormat.SingleElim
		TBracketConfig(fin.config).matchFormat = New TMatchFormat
		TBracketConfig(fin.config).matchFormat.legs = 1
		TBracketConfig(fin.config).policy = New TSchedulePolicy
		TBracketConfig(fin.config).policy.venuePolicy = New TVenuePolicy
		TBracketConfig(fin.config).policy.venuePolicy.venueType = EVenue.Neutral

		comp.stages = [grp, fin]

		' ---- Engine wiring ----
		Local eng:TCompetitionEngine = New TCompetitionEngine
		eng.RegisterScheduler(EStageType.Group, New TGroupScheduler)
		eng.RegisterScorer(  EStageType.Group, New TGroupScorer)
		eng.RegisterAdvancer(EStageType.Group, New TGroupAdvancer)

		eng.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		eng.RegisterScorer(  EStageType.Bracket, New TBracketScorer)
		eng.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)

		' ---- Init → schedules group fixtures ----
		Local state:TCompetitionState = eng.Initialize(comp)
		Local gs:TStageState = state.stages[0]
		AssertTrue(gs.fixtures.Length > 0, "Group fixtures should exist")

		' locate the single fixture in each group
		Local g1:TFixtureState, g2:TFixtureState
		For Local f:TFixtureState = EachIn gs.fixtures
			If f.groupKey = "G1" Then
				g1 = f
			End If

			If f.groupKey = "G2" Then
				g2 = f
			End If
		Next

		AssertTrue(g1 <> Null And g2 <> Null, "Expect one match in G1 and one in G2")

		' choose deterministic winners: smallest id in each group
		Local w1:Int = Min(g1.homeTeamId, g1.awayTeamId)
		Local w2:Int = Min(g2.homeTeamId, g2.awayTeamId)

		' score them to win (respect home/away)
		WinById(eng, comp, state, "GRP", g1, w1)
		WinById(eng, comp, state, "GRP", g2, w2)

		' assert final contains those two winners (unordered)
		Local fs:TStageState = state.stages[1]
		AssertEquals(EStageStatus.Running.Ordinal(), fs.status.Ordinal(), "Final stage should be Running")
		AssertEquals(1, fs.fixtures.Length, "Final should have exactly one match")
		Local fFinal:TFixtureState = fs.fixtures[0]
		AssertTrue(HasUnorderedPair(fFinal, w1, w2), "Final must be between the two group winners")

	End Method

	' ---- helpers ----
	Function MakeTopN:TFilterRule(n:Int, scope:EFilterScope)
		Local r:TFilterRule = New TFilterRule
		r.kind = EFilterKind.TopN
		r.n = n
		r.scope = scope
		Return r
	End Function

	Function MakeAdv:TAdvancement(toId:String, rule:TFilterRule)
		Local a:TAdvancement = New TAdvancement
		a.toStageId = toId
		a.rule = rule
		Return a
	End Function

	Function WinById(eng:TCompetitionEngine, comp:TCompetition, state:TCompetitionState, stageId:String, fx:TFixtureState, winnerId:Int)
		Local res:TResultPayload = New TResultPayload
		res.kind = EResultKind.HeadToHeadScore
		If fx.homeTeamId = winnerId Then
			res.scoreHome = 2; res.scoreAway = 0
		Else
			res.scoreHome = 0; res.scoreAway = 2
		End If

		eng.RecordResult(comp, state, stageId, fx.id, res)
	End Function

	Function HasUnorderedPair:Int(f:TFixtureState, a:Int, b:Int) {asBool}
		Return (f.homeTeamId = a And f.awayTeamId = b) Or (f.homeTeamId = b And f.awayTeamId = a)
	End Function

End Type

Type TPipeline_PendingWithoutSchedulerTest Extends TTest

	Method test_NextStageRemainsPending_WithoutScheduler() { test }
		' Same 2×2 → final setup as previous test
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 4
			Local p:TParticipant = New TParticipant
			p.id = i; p.name = "T" + i
			comp.participants :+ [p]
		Next

		Local grp:TStage = New TStage
		grp.id = "GRP"; grp.stageType = EStageType.Group
		grp.input = New TEntrySource; grp.input.mode = EEntryMode.Direct
		grp.input.seeding = New TSeedingPolicy; grp.input.seeding.seedingMethod = ESeedingMethod.Random
		grp.config = New TGroupConfig
		TGroupConfig(grp.config).configType = EConfigType.Group
		TGroupConfig(grp.config).groups = 2
		TGroupConfig(grp.config).groupSize = 2
		TGroupConfig(grp.config).roundRobinPerOpponent = 1
		grp.advancement = [ MakeAdv("FIN", MakeTopN(1, EFilterScope.PerGroup)) ]

		Local fin:TStage = New TStage
		fin.id = "FIN"; fin.stageType = EStageType.Bracket
		fin.input = New TEntrySource; fin.input.mode = EEntryMode.FromStage; fin.input.fromStageId = "GRP"
		fin.input.seeding = New TSeedingPolicy; fin.input.seeding.seedingMethod = ESeedingMethod.Ranking
		fin.config = New TBracketConfig
		TBracketConfig(fin.config).configType = EConfigType.Bracket
		TBracketConfig(fin.config).size = 2
		TBracketConfig(fin.config).format = EBracketFormat.SingleElim
		TBracketConfig(fin.config).matchFormat = New TMatchFormat

		comp.stages = [grp, fin]

		' Register only GROUP pieces; omit BRACKET scheduler on purpose
		Local eng:TCompetitionEngine = New TCompetitionEngine
		eng.RegisterScheduler(EStageType.Group, New TGroupScheduler)
		eng.RegisterScorer(  EStageType.Group, New TGroupScorer)
		eng.RegisterAdvancer(EStageType.Group, New TGroupAdvancer)

		' Initialize → play two group matches
		Local state:TCompetitionState = eng.Initialize(comp)
		Local gs:TStageState = state.stages[0]

		Local g1:TFixtureState, g2:TFixtureState
		For Local f:TFixtureState = EachIn gs.fixtures
			If f.groupKey = "G1" Then
				g1 = f
			End If

			If f.groupKey = "G2" Then
				g2 = f
			End If
		Next

		Score(eng, comp, state, "GRP", g1.id, 1, 0)
		Score(eng, comp, state, "GRP", g2.id, 2, 1)

		' Next stage exists but has no scheduler registered → must stay Pending
		Local fs:TStageState = state.stages[1]
		AssertEquals(EStageStatus.Pending.Ordinal(), fs.status.Ordinal(), "Next stage should remain Pending without a scheduler")
		AssertEquals(0, fs.fixtures.Length, "No fixtures should be built")
	End Method

	' helpers
	Function MakeTopN:TFilterRule(n:Int, scope:EFilterScope)
		Local r:TFilterRule = New TFilterRule
		r.kind = EFilterKind.TopN
		r.n = n
		r.scope = scope
		Return r
	End Function

	Function MakeAdv:TAdvancement(toId:String, rule:TFilterRule)
		Local a:TAdvancement = New TAdvancement
		a.toStageId = toId
		a.rule = rule
		Return a
	End Function

	Function Score(eng:TCompetitionEngine, comp:TCompetition, state:TCompetitionState, stageId:String, fid:String, h:Int, a:Int)
		Local res:TResultPayload = New TResultPayload
		res.kind = EResultKind.HeadToHeadScore
		res.scoreHome = h; res.scoreAway = a
		eng.RecordResult(comp, state, stageId, fid, res)
	End Function

End Type

Type TGroupAdvancerAllTest Extends TTest

	' 1) st.groups populated → All should return everyone from all groups, no duplicates
	Method test_All_FromGroups() { test }
		Local comp:TCompetition = MakeParticipants(8)

		Local stg:TStage = New TStage
		stg.id = "GROUPS"
		stg.stageType = EStageType.Group
		stg.advancement = [ AdvAll("NEXT") ]

		Local st:TStageState = New TStageState
		st.stageId = stg.id
		st.status = EStageStatus.Complete

		' Two groups of four; rows are already ordered
		st.groups = [..
			GroupTable("G1", [ Row(1, 9), Row(2, 6), Row(3, 3), Row(4, 0) ]), ..
			GroupTable("G2", [ Row(5, 9), Row(6, 6), Row(7, 3), Row(8, 0) ])..
		]

		Local adv:IStageAdvancer = New TGroupAdvancer
		Local qs:TParticipant[] = adv.ProduceAdvancements(comp, stg, st)
		Local got:Int[] = Ids(qs)

		AssertEqualsI(8, got.Length, "All → everyone across groups")
		AssertTrue(ContainsAll(got, [1, 2, 3, 4, 5, 6, 7, 8]), "All participants should advance")
	End Method


	' 2) No groups → fallback to global leaderboard rows
	Method test_All_FromLeaderboardFallback() { test }
		Local comp:TCompetition = MakeParticipants(6)

		Local stg:TStage = New TStage
		stg.id = "GROUPS"
		stg.stageType = EStageType.Group
		stg.advancement = [ AdvAll("NEXT") ]

		Local st:TStageState = New TStageState
		st.stageId = stg.id
		st.status = EStageStatus.Complete

		' No st.groups; provide a global leaderboard instead
		st.leaderboard = New TLeaderboard
		st.leaderboard.rows = [ Row(6, 10), Row(2, 9), Row(4, 7), Row(1, 5), Row(3, 3), Row(5, 1) ]

		Local adv:IStageAdvancer = New TGroupAdvancer
		Local qs:TParticipant[] = adv.ProduceAdvancements(comp, stg, st)
		Local got:Int[] = Ids(qs)

		AssertEqualsI(6, got.Length, "All from leaderboard → everyone listed")
		AssertTrue(ContainsAll(got, [1, 2, 3, 4, 5, 6]), "All participants in leaderboard should advance")
	End Method

	Function MakeParticipants:TCompetition(n:Int)
		Local c:TCompetition = New TCompetition
		For Local i:Int = 1 To n
			Local p:TParticipant = New TParticipant
			p.id = i; p.name = "T" + i
			c.participants :+ [p]
		Next

		Return c
	End Function

	Function Row:TLeaderboardRow(pid:Int, pts:Int)
		Local r:TLeaderboardRow = New TLeaderboardRow
		r.participantId = pid
		r.points = pts
		Return r
	End Function

	Function GroupTable:TGroupTable(key:String, rows:TLeaderboardRow[])
		Local g:TGroupTable = New TGroupTable
		g.key = key
		g.rows = rows
		Return g
	End Function

	Function AdvAll:TAdvancement(toId:String)
		Local a:TAdvancement = New TAdvancement
		a.toStageId = toId
		a.rule = New TFilterRule
		a.rule.kind = EFilterKind.All
		a.rule.n = 0
		a.rule.scope = EFilterScope.All
		Return a
	End Function

	Function Ids:Int[](pp:TParticipant[])
		Local out:Int[] = []
		For Local p:TParticipant = EachIn pp; out :+ [p.id]; Next

		Return out
	End Function

	Function ContainsAll:Int(have:Int[], want:Int[]) {asBool}
		For Local v:Int = EachIn want
			Local ok:Int
			For Local h:Int = EachIn have
				If h = v Then ok = 1; Exit
			Next

			If Not ok Then
				Return False
			End If
		Next

		Return True
	End Function
End Type

Type TBracketTwoLegPipelineTest Extends TTest

	' A) Aggregate without away-goals: winners decided by total goals
	Method test_SemisTwoLeg_AdvanceWinners_NoAwayGoals() { test }

		Local comp:TCompetition = MakeParticipants(4)

		Local semis:TStage = BracketStageTwoLeg("SF", 4, False)
		Local finalStage:TStage = FinalStageSingleLeg("F")
		finalStage.input.fromStageId = "SF"

		Local eng:TCompetitionEngine = New TCompetitionEngine
		eng.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		eng.RegisterScorer(  EStageType.Bracket, New TBracketScorer)
		eng.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)

		comp.stages = [semis, finalStage]
		Local state:TCompetitionState = eng.Initialize(comp)

		Local sfSS:TStageState = state.stages[0]
		Local pairs:Int[][] = Round1Pairs(sfSS.fixtures)
		AssertEqualsI(2, pairs.Length, "Should detect 2 semi-final pairs")

		' For each tie, choose a deterministic winner and set legs so that winner wins BOTH legs
		Local winners:Int[] = []
		For Local pindex:Int = 0 Until pairs.Length
			Local a:Int = pairs[pindex][0]
			Local b:Int = pairs[pindex][1]

			Local w:Int
			If pindex = 0 Then w = a Else w = b   ' first tie: lower id wins; second tie: higher id wins

			winners :+ [w]

			Local legs:TFixtureState[] = GetTwoLeg(sfSS.fixtures, a, b)
			AssertEqualsI(2, legs.Length, "Each tie should have 2 legs")

			' Score both legs emphatically for winner, home/away aware: 2-0 when w is home, 0-2 when w is away
			For Local l:Int = 0 Until 2
				Local f:TFixtureState = legs[l]

				If f.homeTeamId = w Then
					Score(eng, comp, state, "SF", f.id, 2, 0)
				Else
					Score(eng, comp, state, "SF", f.id, 0, 2)
				End If
			Next
		Next

		' Compute winners from recorded legs (sanity) and assert the Final contains them
		Local wA:Int = AggregateWinnerNoAway(GetTwoLeg(sfSS.fixtures, pairs[0][0], pairs[0][1]))
		Local wB:Int = AggregateWinnerNoAway(GetTwoLeg(sfSS.fixtures, pairs[1][0], pairs[1][1]))

		Local fSS:TStageState = state.stages[1]
		AssertEquals(EStageStatus.Running.Ordinal(), fSS.status.Ordinal(), "Final should be initialized after semis complete")
		AssertEqualsI(1, fSS.fixtures.Length, "Final should have one match")
		Local fx:TFixtureState = fSS.fixtures[0]
		AssertTrue(HasUnorderedPair(fx, wA, wB), "Final must be between winners of both ties")
	End Method


	' B) Aggregate WITH away-goals: craft 2–2 aggregate where chosen team wins by away goals
	Method test_SemisTwoLeg_AwayGoalsBreakTie() { test }

		Local comp:TCompetition = MakeParticipants(4)

		Local semis:TStage = BracketStageTwoLeg("SF", 4, True) ' away-goals on
		Local finalStage:TStage = FinalStageSingleLeg("F")
		finalStage.input.fromStageId = "SF"

		Local eng:TCompetitionEngine = New TCompetitionEngine
		eng.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		eng.RegisterScorer(  EStageType.Bracket, New TBracketScorer)
		eng.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)

		comp.stages = [semis, finalStage]
		Local state:TCompetitionState = eng.Initialize(comp)

		Local sfSS:TStageState = state.stages[0]
		Local pairs:Int[][] = Round1Pairs(sfSS.fixtures)
		AssertEqualsI(2, pairs.Length, "Should detect 2 semi-final pairs")

		' Pick first tie; lower-ID should win on away goals with a 2–2 aggregate
		Local a:Int = pairs[0][0], b:Int = pairs[0][1]
		Local low:Int = a
		Local high:Int = b
		Local legs:TFixtureState[] = GetTwoLeg(sfSS.fixtures, a, b)
		AssertEqualsI(2, legs.Length, "Chosen tie should have 2 legs")

		' Branch-agnostic scoring to ensure:
		' - Total aggregate 2–2
		' - low has MORE away goals
		' Plan:
		'   If low is HOME in a leg → set that leg 1–0 (no away goals for high)
		'   If low is AWAY in a leg → set that leg 2–1 to the HOME team (so low gets 1 away goal)
		' Totals: low home 1, away 1 → 2; high home 2, away 0 → 2; away goals: low=1 > high=0.
		For Local l:Int = 0 Until 2
			Local f:TFixtureState = legs[l]
			If f.homeTeamId = low Then
				Score(eng, comp, state, "SF", f.id, 1, 0) ' low home win 1–0
			ElseIf f.awayTeamId = low Then
				Score(eng, comp, state, "SF", f.id, 2, 1) ' low away loses 2–1 (earns 1 away goal)
			End If
		Next

		' ' Finish the other tie with a clear winner so stage completes
		' Local other:Int[] = pairs[1]
		' Local legsB:TFixtureState[] = GetTwoLeg(sfSS.fixtures, other[0], other[1])
		' For Local l:Int = 0 Until 2
		' 	Local f:TFixtureState = legsB[l]
		' 	' make home team win 2–0 in both legs (aggregate 4–0)
		' 	Score(eng, comp, state, "SF", f.id, 2, 0)
		' Next


		' Decide a deterministic winner for the "other" tie
		Local other:Int[] = pairs[1]
		Local legsB:TFixtureState[] = GetTwoLeg(sfSS.fixtures, other[0], other[1])
		AssertEqualsI(2, legsB.Length, "Other tie must have 2 legs")

		' Pick a winner (e.g., lower ID) and score both legs accordingly
		Local winB:Int = Min(other[0], other[1])
		For Local l:Int = 0 Until 2
			Local f:TFixtureState = legsB[l]
			If f.homeTeamId = winB Then
				' winner is home → 2–0
				Score(eng, comp, state, "SF", f.id, 2, 0)
			Else
				' winner is away → 0–2
				Score(eng, comp, state, "SF", f.id, 0, 2)
			End If
		Next

		' Compute away-goals winner from recorded legs and assert Final contains them
		Local wTie:Int = AggregateWinnerAwayGoals(legs)
		Local fSS:TStageState = state.stages[1]
		AssertEquals(EStageStatus.Running.Ordinal(), fSS.status.Ordinal(), "Final should be initialized after semis complete")
		AssertEqualsI(1, fSS.fixtures.Length, "Final should have one match")

		Local fx:TFixtureState = fSS.fixtures[0]
		Local finalA:Int = fx.homeTeamId, finalB:Int = fx.awayTeamId
		AssertTrue(finalA = wTie Or finalB = wTie, "Final must include away-goals winner of the chosen tie")
	End Method

	Function MakeParticipants:TCompetition(n:Int)
		Local c:TCompetition = New TCompetition
		For Local i:Int = 1 To n
			Local p:TParticipant = New TParticipant
			p.id = i; p.name = "Seed" + i
			c.participants :+ [p]
		Next

		Return c
	End Function

	Function BracketStageTwoLeg:TStage(id:String, size:Int, useAwayGoals:Int)
		Local st:TStage = New TStage
		st.id = id
		st.stageType = EStageType.Bracket
		st.input = New TEntrySource
		st.input.mode = EEntryMode.Direct
		st.input.seeding = New TSeedingPolicy
		st.input.seeding.seedingMethod = ESeedingMethod.Ranking

		st.config = New TBracketConfig
		TBracketConfig(st.config).configType = EConfigType.Bracket
		TBracketConfig(st.config).size = size
		TBracketConfig(st.config).format = EBracketFormat.SingleElim
		TBracketConfig(st.config).reseedEachRound = False
		TBracketConfig(st.config).byes = 0
		TBracketConfig(st.config).policy = New TSchedulePolicy
		TBracketConfig(st.config).policy.venuePolicy = New TVenuePolicy
		TBracketConfig(st.config).policy.venuePolicy.venueType = EVenue.TwoLegAggregate

		TBracketConfig(st.config).matchFormat = New TMatchFormat
		TBracketConfig(st.config).matchFormat.legs = 2
		TBracketConfig(st.config).matchFormat.aggregateScores = True
		TBracketConfig(st.config).matchFormat.awayGoalsRule = useAwayGoals
		TBracketConfig(st.config).matchFormat.extraTimeMinutes = 0
		TBracketConfig(st.config).matchFormat.penalties = False

		Return st
	End Function

	Function FinalStageSingleLeg:TStage(id:String)
		Local st:TStage = New TStage
		st.id = id
		st.stageType = EStageType.Bracket
		st.input = New TEntrySource
		st.input.mode = EEntryMode.FromStage
		st.input.seeding = New TSeedingPolicy
		st.input.seeding.seedingMethod = ESeedingMethod.Ranking

		st.config = New TBracketConfig
		TBracketConfig(st.config).configType = EConfigType.Bracket
		TBracketConfig(st.config).size = 2
		TBracketConfig(st.config).format = EBracketFormat.SingleElim
		TBracketConfig(st.config).byes = 0
		TBracketConfig(st.config).policy = New TSchedulePolicy
		TBracketConfig(st.config).policy.venuePolicy = New TVenuePolicy
		TBracketConfig(st.config).policy.venuePolicy.venueType = EVenue.Neutral

		TBracketConfig(st.config).matchFormat = New TMatchFormat
		TBracketConfig(st.config).matchFormat.legs = 1
		TBracketConfig(st.config).matchFormat.aggregateScores = False

		Return st
	End Function

	Function Score(eng:TCompetitionEngine, comp:TCompetition, state:TCompetitionState, stageId:String, fxId:String, h:Int, a:Int)
		Local res:TResultPayload = New TResultPayload
		res.kind = EResultKind.HeadToHeadScore
		res.scoreHome = h; res.scoreAway = a
		eng.RecordResult(comp, state, stageId, fxId, res)
	End Function

	' Return the two leg fixtures for a tie, sorted by leg ascending
	Function GetTwoLeg:TFixtureState[](fx:TFixtureState[], a:Int, b:Int)
		Local out:TFixtureState[] = []
		For Local f:TFixtureState = EachIn fx
			If (f.homeTeamId = a And f.awayTeamId = b) Or (f.homeTeamId = b And f.awayTeamId = a) Then
				out :+ [f]
			End If
		Next

		For Local i:Int = 0 Until out.Length - 1
			For Local j:Int = i + 1 Until out.Length
				If out[i].leg > out[j].leg Then
					Local t:TFixtureState = out[i]; out[i] = out[j]; out[j] = t
				End If
			Next
		Next

		Return out
	End Function

	' Find all unordered pairs (round 1)
	Function Round1Pairs:Int[][](fx:TFixtureState[])

		Local seen:Int[][]
		For Local f:TFixtureState = EachIn fx
			If f.round <> 1 Then
				Continue
			End If

			Local a:Int = f.homeTeamId
			Local b:Int = f.awayTeamId

			If a > b Then
				Local t:Int = a; a = b; b = t
			End If

			Local exists:Int
			For Local p:Int[] = EachIn seen
				If p[0] = a And p[1] = b Then exists = True; Exit
			Next

			If Not exists Then
				seen :+ [[a, b]]
			End If
		Next

		Return seen
	End Function

	' Compute winner under NO away-goals (pure aggregate)
	Function AggregateWinnerNoAway:Int(legs:TFixtureState[])
		Local sum:TIntMap = New TIntMap ' pid -> goals
		For Local f:TFixtureState = EachIn legs
			Local h:Int = f.homeTeamId, a:Int = f.awayTeamId
			Local sh:Int = f.scoreHome, sa:Int = f.scoreAway
			sum.Insert(h, String(Int(String(sum.ValueForKey(h))) + sh))
			sum.Insert(a, String(Int(String(sum.ValueForKey(a))) + sa))
		Next
		' pick higher total
		Local pids:Int[] = []
		For Local it:TIntKey = EachIn sum.Keys()
			pids :+ [ it.value ]
		Next

		If pids.Length <> 2 Then
			Return 0
		End If

		Local g0:Int = Int(String(sum.ValueForKey(pids[0])))
		Local g1:Int = Int(String(sum.ValueForKey(pids[1])))
		If g0 > g1 Then Return pids[0] Else Return pids[1]
	End Function

	' Compute winner WITH away-goals
	Function AggregateWinnerAwayGoals:Int(legs:TFixtureState[])
		' totals and away goals
		Local tot:TIntMap = New TIntMap
		Local away:TIntMap = New TIntMap
		For Local f:TFixtureState = EachIn legs
			Local h:Int = f.homeTeamId, a:Int = f.awayTeamId
			Local sh:Int = f.scoreHome, sa:Int = f.scoreAway
			tot.Insert(h, String(Int(String(tot.ValueForKey(h))) + sh))
			tot.Insert(a, String(Int(String(tot.ValueForKey(a))) + sa))
			' away goals for away team
			away.Insert(a, String(Int(String(away.ValueForKey(a))) + sa))
		Next

		Local pids:Int[]
		For Local it:TIntKey = EachIn tot.Keys()
			pids :+ [ it.value ]
		Next

		If pids.Length <> 2 Then
			Return 0
		End If

		Local t0:Int = Int(String(tot.ValueForKey(pids[0])))
		Local t1:Int = Int(String(tot.ValueForKey(pids[1])))
		If t0 <> t1 Then
			If t0 > t1 Then
				Return pids[0]
			Else
				Return pids[1]
			End If
		End IF
		' tie on aggregate → away goals
		Local a0:Int = Int(String(away.ValueForKey(pids[0])))
		Local a1:Int = Int(String(away.ValueForKey(pids[1])))
		If a0 <> a1 Then
			If a0 > a1 Then
				Return pids[0]
			Else
				Return pids[1]
			End If
		End If
		' (If still tied, ET/Pens would apply; our tests avoid that)
		Return 0
	End Function

	Function HasUnorderedPair:Int(f:TFixtureState, a:Int, b:Int)
		Return (f.homeTeamId = a And f.awayTeamId = b) Or (f.homeTeamId = b And f.awayTeamId = a)
	End Function

End Type

Type TSeriesPositionPointsTest Extends TTest

	Method testExactFractionalTableBonusMultiplierAndAdjustment() { test }
		Local comp:TCompetition = New TCompetition
		For Local id:Int = 1 To 2
			Local participant:TParticipant = New TParticipant
			participant.id = id
			participant.kind = EParticipantKind.Individual
			comp.participants :+ [participant]
		Next

		Local stage:TStage = New TStage
		stage.id = "EXACT"
		stage.stageType = EStageType.Series
		Local cfg:TSeriesConfig = New TSeriesConfig
		cfg.pointsScale = 40
		Local event:TSeriesEvent = New TSeriesEvent
		event.id = "E1"
		event.pointsMultiplierExact = "0.5"
		cfg.events = [event]
		cfg.scoring = New TScoringSystem
		cfg.scoring.mode = EScoringMode.PositionTable
		Local first:TPointsTableEntry = New TPointsTableEntry
		first.position = 1
		first.pointsExact = "1.25"
		Local second:TPointsTableEntry = New TPointsTableEntry
		second.position = 2
		second.pointsExact = "0.1"
		cfg.scoring.table = [first, second]
		Local bonus:TBonusRule = New TBonusRule
		bonus.code = "BONUS"
		bonus.pointsExact = "0.05"
		bonus.maxPointsPerAwardExact = "0.15"
		bonus.uniquePerSession = True
		cfg.scoring.bonuses = [bonus]
		stage.config = cfg
		comp.stages = [stage]

		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Series, New TSeriesScheduler)
		engine.RegisterScorer(EStageType.Series, New TSeriesScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local analysis:TClinchAnalysis = engine.AnalyzeClinching(comp, state, "EXACT")
		AssertEquals(28, Int(analysis.BoundFor(1).maximumAdditional))

		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.Classification
		result.order = [1, 2]
		Local award:TResultAward = New TResultAward
		award.code = "BONUS"
		award.participantId = 1
		award.pointsOverrideExact = "0.2"
		result.awards = [award]
		Local rejected:Int
		Try
			engine.RecordResult(comp, state, "EXACT", state.stages[0].fixtures[0].id, result)
		Catch problem:Object
			rejected = True
		End Try

		AssertTrue(rejected)
		AssertEquals(EFixtureStatus.Scheduled.Ordinal(), state.stages[0].fixtures[0].status.Ordinal())
		award.pointsOverrideExact = "0.15"
		engine.RecordResult(comp, state, "EXACT", state.stages[0].fixtures[0].id, result)
		AssertPoints(state.stages[0], 1, 28)
		AssertPoints(state.stages[0], 2, 2)

		Local deduction:TResultPayload = New TResultPayload
		deduction.kind = EResultKind.AdminAdjustment
		Local adjustment:TPointAdjustment = New TPointAdjustment
		adjustment.participantId = 1
		adjustment.pointsDeltaExact = "-0.2"
		deduction.adjustments = [adjustment]
		engine.RecordResult(comp, state, "EXACT", "", deduction)
		AssertPoints(state.stages[0], 1, 20)
		For Local row:TLeaderboardRow = EachIn state.stages[0].leaderboard.rows
			If row.participantId = 1 Then
				AssertEquals("0.5", TSeriesScorer.PointsText(row, cfg))
			End If
		Next
	End Method

	Method testExactPointsRejectUnrepresentableScale() { test }
		AssertEquals(1, ExactPointUnits("0.1", 10))
		Local rejected:Int
		Try
			ExactPointUnits("0.1", 2)
		Catch error:Object
			rejected = True
		End Try

		AssertTrue(rejected)
	End Method

	Method test_TwoEvents_PositionTable_WithAwards() { test }
		' ---- Participants ----
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 4
			Local p:TParticipant = New TParticipant
			p.id = i; p.name = "Driver" + i
			p.kind = EParticipantKind.Individual
			comp.participants :+ [p]
		Next

		' ---- Scoring: base position-table + FASTEST_LAP award (1pt, RACE only) ----
		Local scoring:TScoringSystem = New TScoringSystem
		scoring.mode = EScoringMode.PositionTable
		scoring.table = [ Pts(1, 8), Pts(2, 6), Pts(3, 4), Pts(4, 2) ]
		scoring.bonuses = [..
            BonusRule("FASTEST_LAP", 1, ["RACE"], True, False, False, 0, True, 10)..
        ]
		' code, points, allowedSessions, uniquePerSession, uniquePerEvent,
		' uniquePerParticipantPerEvent, maxAwardsPerEvent, requireFinish, minFinishPosition

		scoring.aggregation = New TAggregation
		scoring.aggregation.sumPoints = True

		' ---- Series: 2 events, each with one RACE session ----
		Local ev1:TSeriesEvent = New TSeriesEvent; ev1.id = "E1"; ev1.name = "GP1"
		ev1.sessions = [ Sess("RACE", Null) ]
		Local ev2:TSeriesEvent = New TSeriesEvent; ev2.id = "E2"; ev2.name = "GP2"
		ev2.sessions = [ Sess("RACE", Null) ]

		Local sCfg:TSeriesConfig = New TSeriesConfig
		sCfg.events = [ev1, ev2]
		sCfg.scoring = scoring

		Local st:TStage = New TStage
		st.id = "SER"
		st.stageType = EStageType.Series
		st.config = sCfg
		comp.stages = [st]


		' ---- Engine wiring ----
		Local eng:TCompetitionEngine = New TCompetitionEngine
		eng.RegisterScheduler(EStageType.Series, New TSeriesScheduler)
		eng.RegisterScorer(  EStageType.Series, New TSeriesScorer)
		eng.RegisterAdvancer(EStageType.Series, New TSeriesAdvancer)

		Local state:TCompetitionState = eng.Initialize(comp)
		Local ss:TStageState = state.stages[0]

		' ---- Event 1 RACE: order + award ----
		' Order: 1,2,3,4 → base: 8,6,4,2
		' Award: FASTEST_LAP to driver 2 (+1) — allowed (RACE, P2 <= top-10)
		Local e1race:TFixtureState = FindSessionById(ss, "E1", "RACE")
		AssertTrue(e1race <> Null, "Expect to find E1 RACE session")
		Local res1:TResultPayload = New TResultPayload
		res1.kind = EResultKind.Classification
		res1.order = [1, 2, 3, 4]
		Local a1:TResultAward = New TResultAward
		a1.code = "FASTEST_LAP"; a1.participantId = 2; a1.pointsOverride = 0
		a1.conditions = New TAwardConditions; a1.conditions.minFinishPosition = 10; a1.conditions.mustFinish = True
		res1.awards = [a1]

		eng.RecordResult(comp, state, st.id, e1race.id, res1)

		' ---- Event 2 RACE: order + award ----
		' Order: 2,1,4,3 → base: 8,6,4,2
		' Award: FASTEST_LAP to driver 1 (+1)
		Local e2race:TFixtureState = FindSessionById(ss, "E2", "RACE")
		Local res2:TResultPayload = New TResultPayload
		res2.kind = EResultKind.Classification
		res2.order = [2, 1, 4, 3]
		Local a2:TResultAward = New TResultAward
		a2.code = "FASTEST_LAP"; a2.participantId = 1; a2.pointsOverride = 0
		a2.conditions = New TAwardConditions; a2.conditions.minFinishPosition = 10; a2.conditions.mustFinish = True
		res2.awards = [a2]
		eng.RecordResult(comp, state, st.id, e2race.id, res2)

		' ---- Compute standings ----
		Local scorer:IStageScorer = New TSeriesScorer
		scorer.ComputeStandings(comp, st, ss)

		' Totals:
		' E1: D1=8, D2=6+1=7, D3=4, D4=2
		' E2: D2=8, D1=6+1=7, D4=4, D3=2
		' Sum: D1=15, D2=15, D3=6, D4=6
		AssertPoints(ss, 1, 15)
		AssertPoints(ss, 2, 15)
		AssertPoints(ss, 3, 6)
		AssertPoints(ss, 4, 6)
	End Method

	' ---------- helpers ----------
	Function Pts:TPointsTableEntry(pos:Int, pts:Int)
		Local e:TPointsTableEntry = New TPointsTableEntry
		e.position = pos; e.points = pts
		Return e
	End Function

	' Convenience ctor for TBonusRule with all fields
	Function BonusRule:TBonusRule(code:String, pts:Int, allow:String[], uniqSess:Int, uniqEvent:Int, uniqPerPartEvent:Int, maxPerEvent:Int, reqFinish:Int, minPos:Int)
		Local b:TBonusRule = New TBonusRule
		b.code = code
		b.points = pts
		b.allowedSessions = allow
		b.uniquePerSession = uniqSess
		b.uniquePerEvent = uniqEvent
		b.uniquePerParticipantPerEvent = uniqPerPartEvent
		b.maxAwardsPerEvent = maxPerEvent
		b.requireFinish = reqFinish
		b.minFinishPosition = minPos
		Return b
	End Function

	Function Sess:TSession(code:String, scoringOverride:TScoringSystem)
		Local s:TSession = New TSession
		s.code = code
		s.scoringOverride = scoringOverride
		Return s
	End Function

	Function FindSessionById:TFixtureState(ss:TStageState, evId:String, sessCode:String)
		For Local f:TFixtureState = EachIn ss.fixtures
			If f.id.Find(evId) >= 0 And f.id.Find(sessCode) >= 0 Then
				Return f
			End If
		Next

		Return Null
	End Function

	Function AssertPoints(ss:TStageState, pid:Int, expected:Int)
		For Local r:TLeaderboardRow = EachIn ss.leaderboard.rows
			If r.participantId = pid Then
				AssertEqualsI(expected, r.points, "Driver " + pid + " points")
				Return
			End If
		Next

		Fail("Missing participant " + pid + " in leaderboard")
	End Function

End Type

Type TSeriesSessionOverrideAndAwardsTest Extends TTest

	Method test_SprintOverride_And_AwardsValidation() { test }
		' ---- Participants ----
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 4
			Local p:TParticipant = New TParticipant
			p.id = i; p.name = "D" + i
			comp.participants :+ [p]
		Next

		' ---- Base scoring (RACE) + bonus registry (FASTEST_LAP allowed only in RACE) ----
		Local base:TScoringSystem = New TScoringSystem
		base.mode = EScoringMode.PositionTable
		base.table = [ Pts(1, 10), Pts(2, 6), Pts(3, 4), Pts(4, 3) ]
		base.bonuses = [..
            BonusRule("FASTEST_LAP", 1, ["RACE"], True, False, False, 0, True, 10)..
        ]
		base.aggregation = New TAggregation
		base.aggregation.sumPoints = True

		' ---- Sprint override (3,2,1,0) ----
		Local sprint:TScoringSystem = New TScoringSystem
		sprint.mode = EScoringMode.PositionTable
		sprint.table = [ Pts(1, 3), Pts(2, 2), Pts(3, 1), Pts(4, 0) ]

		' ---- Series: one event with SPRINT + RACE ----
		Local ev:TSeriesEvent = New TSeriesEvent
		ev.id = "E1"; ev.name = "Weekend 1"
		ev.sessions = [ Sess("SPRINT", sprint), Sess("RACE", Null) ]  ' RACE uses base

		Local cfg:TSeriesConfig = New TSeriesConfig
		cfg.events = [ev]
		cfg.scoring = base

		Local st:TStage = New TStage
		st.id = "SER"
		st.stageType = EStageType.Series
		st.config = cfg
		comp.stages = [st]


		' ---- Engine wiring ----
		Local eng:TCompetitionEngine = New TCompetitionEngine
		eng.RegisterScheduler(EStageType.Series, New TSeriesScheduler)
		eng.RegisterScorer(  EStageType.Series, New TSeriesScorer)
		eng.RegisterAdvancer(EStageType.Series, New TSeriesAdvancer)

		Local state:TCompetitionState = eng.Initialize(comp)
		Local ss:TStageState = state.stages[0]

		Local fxSprint:TFixtureState = FindSessionById(ss, "E1", "SPRINT")
		Local fxRace:TFixtureState = FindSessionById(ss, "E1", "RACE")
		AssertTrue(fxSprint <> Null And fxRace <> Null, "Both sessions should exist")

		' ---- SPRINT: order uses override; award FASTEST_LAP (RACE-only) should be ignored ----
		' Sprint order: 2,1,3,4 -> 3,2,1,0
		Local resS:TResultPayload = New TResultPayload
		resS.kind = EResultKind.Classification
		resS.order = [2, 1, 3, 4]
		resS.awards = [ NewAward("FASTEST_LAP", 3, 0, 10, True) ] ' not allowed in SPRINT -> ignored
		eng.RecordResult(comp, state, st.id, fxSprint.id, resS)

		' ---- RACE: base table; try two FASTEST_LAP awards; uniquePerSession means only first applies ----
		' Race order: 1,2,3,4 -> 10,6,4,3
		Local resR:TResultPayload = New TResultPayload
		resR.kind = EResultKind.Classification
		resR.order = [1, 2, 3, 4]
		resR.awards = [..
            NewAward("FASTEST_LAP", 2, 0, 10, True),  ' should count (+1 to #2)
            NewAward("FASTEST_LAP", 1, 0, 10, True)..   ' ignored (uniquePerSession)
        ]
		eng.RecordResult(comp, state, st.id, fxRace.id, resR)

		' ---- Compute standings ----
		Local scorer:IStageScorer = New TSeriesScorer
		scorer.ComputeStandings(comp, st, ss)

		' Totals:
		' Sprint: D1=2, D2=3, D3=1, D4=0    (award ignored)
		' Race  : D1=10, D2=6(+1)=7, D3=4, D4=3
		' Sum   : D1=12, D2=10, D3=5, D4=3
		AssertPoints(ss, 1, 12)
		AssertPoints(ss, 2, 10)
		AssertPoints(ss, 3, 5)
		AssertPoints(ss, 4, 3)
	End Method

	' ---------- helpers ----------
	Function Pts:TPointsTableEntry(pos:Int, pts:Int)
		Local e:TPointsTableEntry = New TPointsTableEntry
		e.position = pos; e.points = pts
		Return e
	End Function

	' Convenience ctor for full TBonusRule
	Function BonusRule:TBonusRule(code:String, pts:Int, allow:String[], uniqSess:Int, uniqEvent:Int, uniqPerPartEvent:Int, maxPerEvent:Int, reqFinish:Int, minPos:Int)
		Local b:TBonusRule = New TBonusRule
		b.code = code
		b.points = pts
		b.allowedSessions = allow
		b.uniquePerSession = uniqSess
		b.uniquePerEvent = uniqEvent
		b.uniquePerParticipantPerEvent = uniqPerPartEvent
		b.maxAwardsPerEvent = maxPerEvent
		b.requireFinish = reqFinish
		b.minFinishPosition = minPos
		Return b
	End Function

	Function Sess:TSession(code:String, scoringOverride:TScoringSystem)
		Local s:TSession = New TSession
		s.code = code
		s.scoringOverride = scoringOverride
		Return s
	End Function

	Function FindSessionById:TFixtureState(ss:TStageState, evId:String, sessCode:String)
		For Local f:TFixtureState = EachIn ss.fixtures
			' Prefer exact metadata if your fixtures store it:
			If f.seriesEventId <> "" Or f.sessionCode <> "" Then
				If f.seriesEventId = evId And f.sessionCode = sessCode Then
					Return f
				End If
			Else
				' fallback by id pattern
				If f.id.Find(evId) >= 0 And f.id.Find(sessCode) >= 0 Then
					Return f
				End If
			End If
		Next

		Return Null
	End Function

	Function NewAward:TResultAward(code:String, pid:Int, overridePts:Int, minFinishPos:Int, mustFinish:Int)
		Local a:TResultAward = New TResultAward
		a.code = code
		a.participantId = pid
		a.pointsOverride = overridePts
		a.conditions = New TAwardConditions
		a.conditions.minFinishPosition = minFinishPos
		a.conditions.mustFinish = mustFinish
		Return a
	End Function

	Function AssertPoints(ss:TStageState, pid:Int, expected:Int)
		For Local r:TLeaderboardRow = EachIn ss.leaderboard.rows
			If r.participantId = pid Then
				AssertEqualsI(expected, r.points, "P" + pid + " points")
				Return
			End If
		Next

		Fail("Missing participant " + pid)
	End Function

End Type

Type TJsonConfigRoundTripTest Extends TTest

	Method test_SeriesConfig_RoundTrip() { test }
		' ----- Build a config: Series with 2 events, Sprint override, FASTEST_LAP bonus -----
		Local comp:TCompetition = New TCompetition
		comp.name = "RT Demo"

		' participants
		For Local i:Int = 1 To 4
			Local p:TParticipant = New TParticipant
			p.id = i; p.name = "Driver" + i
			p.kind = EParticipantKind.Individual
			comp.participants :+ [p]
		Next

		' scoring base (race) + registry of bonuses (source of truth)
		Local base:TScoringSystem = New TScoringSystem
		base.mode = EScoringMode.PositionTable
		base.table = [ Pts(1, 8), Pts(2, 6), Pts(3, 4), Pts(4, 2) ]
		base.bonuses = [..
            BonusRule("FASTEST_LAP", 1, ["RACE"], True, False, False, 0, True, 10)..
        ]
		base.aggregation = New TAggregation
		base.aggregation.sumPoints = True

		Local sprint:TScoringSystem = New TScoringSystem
		sprint.mode = EScoringMode.PositionTable
		sprint.table = [ Pts(1, 3), Pts(2, 2), Pts(3, 1), Pts(4, 0) ]

		Local ev1:TSeriesEvent = New TSeriesEvent; ev1.id = "E1"; ev1.name = "GP1"
		ev1.sessions = [ Sess("SPRINT", sprint), Sess("RACE", Null) ]
		Local ev2:TSeriesEvent = New TSeriesEvent; ev2.id = "E2"; ev2.name = "GP2"
		ev2.sessions = [ Sess("RACE", Null) ]

		Local sCfg:TSeriesConfig = New TSeriesConfig
		sCfg.events = [ev1, ev2]
		sCfg.scoring = base

		Local stage:TStage = New TStage
		stage.id = "SER"
		stage.stageType = EStageType.Series
		stage.config = sCfg
		stage.input = New TEntrySource
		stage.input.mode = EEntryMode.Direct

		comp.stages = [stage]

		' ----- Save to JSON -----
		Local path:String = "tmp_rt_config.json"
		SaveJson(path, comp)

		' ----- Load back -----
		Local loaded:TCompetition = TCompetition( LoadJson(path, "TCompetition") )
		DeleteFile(path)

		' ----- Assertions -----
		AssertEquals("RT Demo", loaded.name, "name")
		AssertEqualsI(4, loaded.participants.Length, "participants count")
		AssertEqualsI(1, loaded.stages.Length, "stage count")
		AssertEquals(EStageType.Series.Ordinal(), loaded.stages[0].stageType.Ordinal(), "stage type series")

		Local cfg:TSeriesConfig = TSeriesConfig( loaded.stages[0].config )
		AssertTrue(cfg <> Null, "series config present")
		AssertEqualsI(2, cfg.events.Length, "events count")
		AssertEquals("SPRINT", cfg.events[0].sessions[0].code, "first session is sprint")
		AssertEqualsI(1, cfg.scoring.bonuses.Length, "one bonus registered")
		AssertEquals("FASTEST_LAP", cfg.scoring.bonuses[0].code, "bonus code kept")
		AssertEqualsI(1, cfg.scoring.bonuses[0].points, "bonus points kept")
		AssertEqualsI(True, cfg.scoring.bonuses[0].uniquePerSession, "uniquePerSession kept")
		AssertEqualsI(10, cfg.scoring.bonuses[0].minFinishPosition, "minFinishPosition kept")
	End Method

	' ----- helpers -----
	Function Pts:TPointsTableEntry(pos:Int, pts:Int)
		Local e:TPointsTableEntry = New TPointsTableEntry
		e.position = pos; e.points = pts
		Return e
	End Function

	Function BonusRule:TBonusRule(code:String, pts:Int, allow:String[], uniqSess:Int, uniqEvent:Int, uniqPerPartEvent:Int, maxPerEvent:Int, reqFinish:Int, minPos:Int)
		Local b:TBonusRule = New TBonusRule
		b.code = code; b.points = pts
		b.allowedSessions = allow
		b.uniquePerSession = uniqSess
		b.uniquePerEvent = uniqEvent
		b.uniquePerParticipantPerEvent = uniqPerPartEvent
		b.maxAwardsPerEvent = maxPerEvent
		b.requireFinish = reqFinish
		b.minFinishPosition = minPos
		Return b
	End Function

	Function Sess:TSession(code:String, scoringOverride:TScoringSystem)
		Local s:TSession = New TSession
		s.code = code
		s.scoringOverride = scoringOverride
		Return s
	End Function

	Function SaveJson(path:String, obj:Object)
		Local serializer:TConfigSerializer = New TConfigSerializer
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", serializer).WithEmptyArrays().Build()

		Local ws:TStream = WriteStream(path)
		jconv.ToJson(obj, ws)
		ws.Close()
	End Function

	Function LoadJson:Object(path:String, rootType:String)
		Local serializer:TConfigSerializer = New TConfigSerializer
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", serializer).WithEmptyArrays().Build()

		Local rs:TStream = ReadStream(path)
		Local o:Object = jconv.FromJson(rs, rootType)
		rs.Close()
		Return o
	End Function

End Type

Type TJsonStateRoundTripTest Extends TTest

	Method test_SeriesState_SaveLoad_Recompute() { test }
		' ---- Build a tiny Series and run one event with an award ----
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 3
			Local p:TParticipant = New TParticipant
			p.id = i; p.name = "D" + i
			comp.participants :+ [p]
		Next

		' scoring + bonus registry
		Local scoring:TScoringSystem = New TScoringSystem
		scoring.mode = EScoringMode.PositionTable
		scoring.table = [ Pts(1, 5), Pts(2, 3), Pts(3, 1) ]
		scoring.bonuses = [ BonusRule("FASTEST_LAP", 1, ["RACE"], True, False, False, 0, True, 10) ]
		scoring.aggregation = New TAggregation
		scoring.aggregation.sumPoints = True

		Local ev:TSeriesEvent = New TSeriesEvent; ev.id = "E1"; ev.name = "Round 1"
		ev.sessions = [ Sess("RACE", Null) ]

		Local sCfg:TSeriesConfig = New TSeriesConfig
		sCfg.events = [ev]; sCfg.scoring = scoring

		Local stage:TStage = New TStage
		stage.id = "SER"
		stage.stageType = EStageType.Series
		stage.config = sCfg
		comp.stages = [stage]


		' engine
		Local eng:TCompetitionEngine = New TCompetitionEngine
		eng.RegisterScheduler(EStageType.Series, New TSeriesScheduler)
		eng.RegisterScorer(  EStageType.Series, New TSeriesScorer)
		eng.RegisterAdvancer(EStageType.Series, New TSeriesAdvancer)

		Local state:TCompetitionState = eng.Initialize(comp)
		Local ss:TStageState = state.stages[0]

		' record classification + award
		Local fx:TFixtureState = FindSession(ss, "E1", "RACE")
		Local res:TResultPayload = New TResultPayload
		res.kind = EResultKind.Classification
		res.order = [2, 1, 3]  ' D2 wins, then D1, then D3
		Local a:TResultAward = New TResultAward
		a.code = "FASTEST_LAP"; a.participantId = 1; a.pointsOverride = 0
		a.conditions = New TAwardConditions; a.conditions.minFinishPosition = 10; a.conditions.mustFinish = True
		res.awards = [a]
		eng.RecordResult(comp, state, stage.id, fx.id, res)

		' compute standings (pre-save)
		Local scorer:IStageScorer = New TSeriesScorer
		scorer.ComputeStandings(comp, stage, ss)
		AssertPoints(ss, 2, 5)   ' P2: 5
		AssertPoints(ss, 1, 3 + 1) ' P1: 4 (3 + FL)
		AssertPoints(ss, 3, 1)

		' ---- Save both comp and state ----
		Local pathC:String = "tmp_rt_comp.json"
		Local pathS:String = "tmp_rt_state.json"
		SaveJson(pathC, comp, "TCompetition")
		SaveJson(pathS, state, "TCompetitionState")

		' ---- Load both back ----
		Local comp2:TCompetition = TCompetition( LoadJson(pathC, "TCompetition") )
		Local state2:TCompetitionState = TCompetitionState( LoadJson(pathS, "TCompetitionState") )
		DeleteFile(pathC); DeleteFile(pathS)

		' ---- Recompute standings on loaded state ----
		Local st2:TStage = comp2.stages[0]
		Local ss2:TStageState = state2.stages[0]
		Local scorer2:IStageScorer = New TSeriesScorer
		scorer2.ComputeStandings(comp2, st2, ss2)

		' fixtures preserved?
		AssertEqualsI(ss.fixtures.Length, ss2.fixtures.Length, "fixture count preserved")
		AssertEquals(EFixtureStatus.Completed.Ordinal(), ss2.fixtures[0].status.Ordinal(), "fixture status preserved")

		' standings preserved after recompute
		AssertPoints(ss2, 2, 5)
		AssertPoints(ss2, 1, 4)
		AssertPoints(ss2, 3, 1)
	End Method

	' ----- helpers -----
	Function Pts:TPointsTableEntry(pos:Int, pts:Int)
		Local e:TPointsTableEntry = New TPointsTableEntry
		e.position = pos; e.points = pts
		Return e
	End Function

	Function BonusRule:TBonusRule(code:String, pts:Int, allow:String[], uniqSess:Int, uniqEvent:Int, uniqPerPartEvent:Int, maxPerEvent:Int, reqFinish:Int, minPos:Int)
		Local b:TBonusRule = New TBonusRule
		b.code = code; b.points = pts
		b.allowedSessions = allow
		b.uniquePerSession = uniqSess
		b.uniquePerEvent = uniqEvent
		b.uniquePerParticipantPerEvent = uniqPerPartEvent
		b.maxAwardsPerEvent = maxPerEvent
		b.requireFinish = reqFinish
		b.minFinishPosition = minPos
		Return b
	End Function

	Function Sess:TSession(code:String, scoringOverride:TScoringSystem)
		Local s:TSession = New TSession
		s.code = code
		s.scoringOverride = scoringOverride
		Return s
	End Function

	Function FindSession:TFixtureState(ss:TStageState, evId:String, code:String)
		For Local f:TFixtureState = EachIn ss.fixtures
			If f.seriesEventId = evId And f.sessionCode = code Then
				Return f
			End If
			' fallback if metadata not set
			If f.id.Find(evId) >= 0 And f.id.Find(code) >= 0 Then
				Return f
			End If
		Next

		Return Null
	End Function

	Function AssertPoints(ss:TStageState, pid:Int, expected:Int)
		For Local r:TLeaderboardRow = EachIn ss.leaderboard.rows
			If r.participantId = pid Then
				AssertEqualsI(expected, r.points, "P" + pid + " points")
				Return
			End If
		Next

		Fail("Missing participant " + pid)
	End Function

	Function SaveJson(path:String, obj:Object, rootType:String)
		Local serializer:TConfigSerializer = New TConfigSerializer
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", serializer).WithEmptyArrays().Build()

		Local ws:TStream = WriteStream(path)
		jconv.ToJson(obj, ws)
		ws.Close()
	End Function

	Function LoadJson:Object(path:String, rootType:String)
		Local serializer:TConfigSerializer = New TConfigSerializer
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", serializer).WithEmptyArrays().Build()

		Local rs:TStream = ReadStream(path)
		Local o:Object = jconv.FromJson(rs, rootType)
		rs.Close()
		Return o
	End Function

End Type

Type TReplaySeriesTest Extends TTest

	Method test_Series_RoundTrip_ReplayLogs() { test }
		' ---- Build Series with base scoring + FASTEST_LAP award ----
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 4
			Local p:TParticipant = New TParticipant
			p.id = i; p.name = "D" + i
			p.kind = EParticipantKind.Individual
			comp.participants :+ [p]
		Next

		Local scoring:TScoringSystem = New TScoringSystem
		scoring.mode = EScoringMode.PositionTable
		scoring.table = [ Pts(1, 8), Pts(2, 6), Pts(3, 4), Pts(4, 2) ]
		scoring.bonuses = [ BonusRule("FASTEST_LAP", 1, ["RACE"], True, False, False, 0, True, 10) ]
		scoring.aggregation = New TAggregation
		scoring.aggregation.sumPoints = True

		Local ev1:TSeriesEvent = New TSeriesEvent; ev1.id = "E1"; ev1.name = "GP1"; ev1.sessions = [ Sess("RACE", Null) ]
		Local ev2:TSeriesEvent = New TSeriesEvent; ev2.id = "E2"; ev2.name = "GP2"; ev2.sessions = [ Sess("RACE", Null) ]

		Local sCfg:TSeriesConfig = New TSeriesConfig
		sCfg.events = [ev1, ev2]
		sCfg.scoring = scoring

		Local st:TStage = New TStage
		st.id = "SER"; st.stageType = EStageType.Series; st.config = sCfg
		st.input = New TEntrySource; st.input.mode = EEntryMode.Direct
		comp.stages = [st]

		Local eng:TCompetitionEngine = WireEngine()
		Local state:TCompetitionState = eng.Initialize(comp)
		Local ss:TStageState = state.stages[0]

		' Record results (also stored in resultLog by RecordResult)
		Local f1:TFixtureState = FindSession(ss, "E1", "RACE")
		Local f2:TFixtureState = FindSession(ss, "E2", "RACE")

		eng.RecordResult(comp, state, "SER", f1.id, Classify([1, 2, 3, 4], [ Award("FASTEST_LAP", 2, 0, 10, True) ]))
		eng.RecordResult(comp, state, "SER", f2.id, Classify([2, 1, 4, 3], [ Award("FASTEST_LAP", 1, 0, 10, True) ]))

		' Compute standings before save
		Local scorer:IStageScorer = New TSeriesScorer
		scorer.ComputeStandings(comp, st, ss)
		Local pre:Int[] = SnapshotPoints(ss)

		' Save comp + state
		SaveJson("rt_comp_series.json", comp, "TCompetition")
		SaveJson("rt_state_series.json", state, "TCompetitionState")

		' Load comp + state
		Local compSaved:TCompetition = TCompetition(LoadJson("rt_comp_series.json", "TCompetition"))
		Local stateSaved:TCompetitionState = TCompetitionState(LoadJson("rt_state_series.json", "TCompetitionState"))
		DeleteFile("rt_comp_series.json"); DeleteFile("rt_state_series.json")

		' Fresh engine/state, then replay logs from saved
		Local eng2:TCompetitionEngine = WireEngine()
		Local state2:TCompetitionState = eng2.Initialize(compSaved)
		ReplayFromLogs(eng2, compSaved, state2, stateSaved)

		' Recompute standings after replay
		Local st2:TStage = compSaved.stages[0]
		Local ss2:TStageState = state2.stages[0]
		Local scorer2:IStageScorer = New TSeriesScorer
		scorer2.ComputeStandings(compSaved, st2, ss2)
		Local post:Int[] = SnapshotPoints(ss2)

		AssertArrayEquals(pre, post, "Series points identical after replay")
	End Method

	' ---------- helpers ----------
	Function WireEngine:TCompetitionEngine()
		Local e:TCompetitionEngine = New TCompetitionEngine
		e.RegisterScheduler(EStageType.Series, New TSeriesScheduler)
		e.RegisterScorer(  EStageType.Series, New TSeriesScorer)
		e.RegisterAdvancer(EStageType.Series, New TSeriesAdvancer)
		Return e
	End Function

	Function Pts:TPointsTableEntry(pos:Int, pts:Int)
		Local x:TPointsTableEntry = New TPointsTableEntry
		x.position = pos
		x.points = pts
		Return x
	End Function

	Function BonusRule:TBonusRule(code:String, pts:Int, allow:String[], uniqSess:Int, uniqEvent:Int, uniqPerPartEvent:Int, maxPerEvent:Int, reqFinish:Int, minPos:Int)
		Local b:TBonusRule = New TBonusRule
		b.code = code; b.points = pts; b.allowedSessions = allow
		b.uniquePerSession = uniqSess; b.uniquePerEvent = uniqEvent; b.uniquePerParticipantPerEvent = uniqPerPartEvent
		b.maxAwardsPerEvent = maxPerEvent; b.requireFinish = reqFinish; b.minFinishPosition = minPos
		Return b
	End Function

	Function Sess:TSession(code:String, scoringOverride:TScoringSystem)
		Local s:TSession = New TSession; s.code = code; s.scoringOverride = scoringOverride
		Return s
	End Function

	Function Classify:TResultPayload(order:Int[], awards:TResultAward[] = Null)
		Local r:TResultPayload = New TResultPayload
		r.kind = EResultKind.Classification
		r.order = order
		r.awards = awards
		Return r
	End Function

	Function Award:TResultAward(code:String, pid:Int, ov:Int, minPos:Int, mustFinish:Int)
		Local a:TResultAward = New TResultAward
		a.code = code; a.participantId = pid; a.pointsOverride = ov
		a.conditions = New TAwardConditions; a.conditions.minFinishPosition = minPos; a.conditions.mustFinish = mustFinish
		Return a
	End Function

	Function FindSession:TFixtureState(ss:TStageState, evId:String, code:String)
		For Local f:TFixtureState = EachIn ss.fixtures
			If f.seriesEventId = evId And f.sessionCode = code Then
				Return f
			End If
		Next

		Return Null
	End Function

	Function SnapshotPoints:Int[](ss:TStageState)
		Local pts:Int[]
		For Local r:TLeaderboardRow = EachIn ss.leaderboard.rows
			pts :+ [r.points]
		Next

		Return pts
	End Function

	Function SaveJson(path:String, obj:Object, rootType:String)
		Local serializer:TConfigSerializer = New TConfigSerializer
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", serializer).WithEmptyArrays().Build()
		Local ws:TStream = WriteStream(path)
		jconv.ToJson(obj, ws)
		ws.Close()
	End Function

	Function LoadJson:Object(path:String, rootType:String)
		Local serializer:TConfigSerializer = New TConfigSerializer
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", serializer).WithEmptyArrays().Build()
		Local rs:TStream = ReadStream(path)
		Local o:Object = jconv.FromJson(rs, rootType)
		rs.Close()
		Return o
	End Function

	' Core replay: iterate saved stages/fixtures and reapply each payload in resultLog order
	Function ReplayFromLogs(eng:TCompetitionEngine, compFresh:TCompetition, stateFresh:TCompetitionState, stateSaved:TCompetitionState)
		For Local si:Int = 0 Until stateSaved.stages.Length
			Local savedSS:TStageState = stateSaved.stages[si]
			For Local f:TFixtureState = EachIn savedSS.fixtures
				If f.resultLog = Null Then
					Continue
				End If

				For Local ev:TResultPayload = EachIn f.resultLog
					eng.RecordResult(compFresh, stateFresh, compFresh.stages[si].id, f.id, ev)
				Next
			Next
		Next
	End Function

	Function AssertArrayEquals(a:Int[], b:Int[], msg:String)
		AssertEqualsI(a.Length, b.Length, "len " + msg)
		For Local i:Int = 0 Until a.Length
			AssertEqualsI(a[i], b[i], "idx " + i + " " + msg)
		Next
	End Function

End Type

Type TReplayGroupTest Extends TTest

	Method test_Group_RoundTrip_ReplayLogs() { test }
		' 4 teams single group, single round-robin
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 4
			Local p:TParticipant = New TParticipant; p.id = i; p.name = "T" + i
			comp.participants :+ [p]
		Next

		Local gcfg:TGroupConfig = New TGroupConfig
		gcfg.configType = EConfigType.Group
		gcfg.groups = 1; gcfg.groupSize = 4
		gcfg.roundRobinPerOpponent = 1
		gcfg.pointsWin = 3; gcfg.pointsDraw = 1; gcfg.pointsLoss = 0
		gcfg.tiebreakers = [ ETiebreaker.Points, ETiebreaker.GoalDifference, ETiebreaker.GoalsFor ]
		gcfg.policy = New TSchedulePolicy; gcfg.policy.venuePolicy = New TVenuePolicy; gcfg.policy.venuePolicy.venueType = EVenue.HomeAway
		gcfg.policy.scheduleSeed = 42

		Local st:TStage = New TStage
		st.id = "G"; st.stageType = EStageType.Group
		st.config = gcfg
		st.input = New TEntrySource; st.input.mode = EEntryMode.Direct
		comp.stages = [st]

		Local eng:TCompetitionEngine = WireEngine()
		Local state:TCompetitionState = eng.Initialize(comp)
		Local ss:TStageState = state.stages[0]

		' Record three fixtures deterministically
		Local fxs:TFixtureState[] = ss.fixtures[..]
		SortById(fxs)

		eng.RecordResult(comp, state, "G", fxs[0].id, H2H(2, 0)) ' 1 beats 2
		eng.RecordResult(comp, state, "G", fxs[1].id, H2H(1, 1)) ' draw
		eng.RecordResult(comp, state, "G", fxs[2].id, H2H(0, 3)) ' away big win
		' (Optionally finish all fixtures; three is enough to test replay equivalence.)

		' Compute standings pre-save
		Local scorer:IStageScorer = New TGroupScorer
		scorer.ComputeStandings(comp, st, ss)
		Local pre:Int[] = SnapshotTable(ss)

		' Save
		SaveJson("rt_comp_group.json", comp, "TCompetition")
		SaveJson("rt_state_group.json", state, "TCompetitionState")

		' Load
		Local compSaved:TCompetition = TCompetition(LoadJson("rt_comp_group.json", "TCompetition"))
		Local stateSaved:TCompetitionState = TCompetitionState(LoadJson("rt_state_group.json", "TCompetitionState"))
		'DeleteFile("rt_comp_group.json"); DeleteFile("rt_state_group.json")

		' Fresh & replay
		Local eng2:TCompetitionEngine = WireEngine()
		Local state2:TCompetitionState = eng2.Initialize(compSaved)
		ReplayFromLogs(eng2, compSaved, state2, stateSaved)

		' Recompute
		Local st2:TStage = compSaved.stages[0]
		Local ss2:TStageState = state2.stages[0]
		Local scorer2:IStageScorer = New TGroupScorer
		scorer2.ComputeStandings(compSaved, st2, ss2)
		Local post:Int[] = SnapshotTable(ss2)

		AssertArrayEquals(pre, post, "Group table identical after replay")
	End Method

	' helpers
	Function WireEngine:TCompetitionEngine()
		Local e:TCompetitionEngine = New TCompetitionEngine
		e.RegisterScheduler(EStageType.Group, New TGroupScheduler)
		e.RegisterScorer(  EStageType.Group, New TGroupScorer)
		e.RegisterAdvancer(EStageType.Group, New TGroupAdvancer)
		Return e
	End Function

	Function H2H:TResultPayload(h:Int, a:Int)
		Local r:TResultPayload = New TResultPayload
		r.kind = EResultKind.HeadToHeadScore
		r.scoreHome = h
		r.scoreAway = a
		Return r
	End Function

	Function SortById(f:TFixtureState[])
		For Local i:Int = 0 Until f.Length - 1
			For Local j:Int = i + 1 Until f.Length
				If f[i].id > f[j].id Then Local t:TFixtureState = f[i]; f[i] = f[j]; f[j] = t
			Next
		Next
	End Function

	Function SnapshotTable:Int[](ss:TStageState)
		' Compare replayed totals by entrant. With only three matches recorded,
		' unresolved ties need not have a meaningful display order.
		Local arr:Int[]
		For Local r:TLeaderboardRow = EachIn ss.leaderboard.rows
			arr :+ [r.participantId, r.points]
		Next

		For Local i:Int = 0 Until arr.Length Step 2
			For Local j:Int = i + 2 Until arr.Length Step 2
				If arr[j] < arr[i] Then
					Local id:Int = arr[i], points:Int = arr[i + 1]
					arr[i] = arr[j]; arr[i + 1] = arr[j + 1]
					arr[j] = id; arr[j + 1] = points
				End If
			Next
		Next

		Return arr
	End Function

	Function SaveJson(path:String, obj:Object, rootType:String)
		Local serializer:TConfigSerializer = New TConfigSerializer
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", serializer).WithEmptyArrays().Build()
		Local ws:TStream = WriteStream(path)
		jconv.ToJson(obj, ws)
		ws.Close()
	End Function

	Function LoadJson:Object(path:String, rootType:String)
		Local serializer:TConfigSerializer = New TConfigSerializer
		Local jconv:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", serializer).WithEmptyArrays().Build()
		Local rs:TStream = ReadStream(path)
		Local o:Object = jconv.FromJson(rs, rootType)
		rs.Close()
		Return o
	End Function

	Function ReplayFromLogs(eng:TCompetitionEngine, compFresh:TCompetition, stateFresh:TCompetitionState, stateSaved:TCompetitionState)
		For Local si:Int = 0 Until stateSaved.stages.Length
			Local savedSS:TStageState = stateSaved.stages[si]
			For Local f:TFixtureState = EachIn savedSS.fixtures
				If f.resultLog = Null Then
					Continue
				End If

				For Local ev:TResultPayload = EachIn f.resultLog
					eng.RecordResult(compFresh, stateFresh, compFresh.stages[si].id, f.id, ev)
				Next
			Next
		Next
	End Function

	Function AssertArrayEquals(a:Int[], b:Int[], msg:String)
		AssertEqualsI(a.Length, b.Length, "len " + msg)
		For Local i:Int = 0 Until a.Length
			AssertEqualsI(a[i], b[i], "idx " + i + " " + msg)
		Next
	End Function

End Type

Type TGroupVenueBalanceTest Extends TTest

	Method test_MaxConsecutiveHomeAway_Limit2() { test }
		' --- Build a deterministic 1-group, 6-team RR schedule ---
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 6
			Local p:TParticipant = New TParticipant
			p.id = i; p.name = "T" + i
			comp.participants :+ [p]
		Next

		Local gcfg:TGroupConfig = New TGroupConfig
		gcfg.configType = EConfigType.Group
		gcfg.groups = 1
		gcfg.groupSize = 6
		gcfg.roundRobinPerOpponent = 1 ' single round robin is enough to see streak issues

		' Scoring doesn’t matter for this test
		gcfg.pointsWin = 3; gcfg.pointsDraw = 1; gcfg.pointsLoss = 0
		gcfg.tiebreakers = [ ETiebreaker.Points, ETiebreaker.GoalDifference, ETiebreaker.GoalsFor ]

		' Policy: enforce max 2 consecutive home/away; seed for determinism
		gcfg.policy = New TSchedulePolicy
		gcfg.policy.venuePolicy = New TVenuePolicy
		gcfg.policy.venuePolicy.venueType = EVenue.HomeAway
		gcfg.policy.maxConsecHome = 2
		gcfg.policy.maxConsecAway = 2
		gcfg.policy.groupOrder = EGroupScheduleType.RoundRobin
		gcfg.policy.scheduleSeed = 42

		Local st:TStage = New TStage
		st.id = "G"
		st.stageType = EStageType.Group
		st.config = gcfg
		st.input = New TEntrySource
		st.input.mode = EEntryMode.Direct
		comp.stages = [st]

		' --- Engine / Initialize ---
		Local eng:TCompetitionEngine = New TCompetitionEngine
		eng.RegisterScheduler(EStageType.Group, New TGroupScheduler)
		eng.RegisterScorer(  EStageType.Group, New TGroupScorer)
		eng.RegisterAdvancer(EStageType.Group, New TGroupAdvancer)

		Local state:TCompetitionState = eng.Initialize(comp)
		Local ss:TStageState = state.stages[0]

		' --- Analyze per-team streaks over rounds ---
		Local violations:String[] = CheckVenueStreakViolations(ss.fixtures, gcfg.policy.maxConsecHome, gcfg.policy.maxConsecAway)
		Local sb:TStringBuilder = New TStringBuilder
		sb.JoinStrings(violations, "; ")

		' Expect none (will FAIL until we implement balancing)
		AssertTrue(violations.Length = 0, sb.ToString())
	End Method

	' ---------- helpers ----------

	' Returns a list of human-readable violations like:
	' "Team 3: HOME streak=3 at rounds [2,3,4]"
	Function CheckVenueStreakViolations:String[](fx:TFixtureState[], maxH:Int, maxA:Int)
		' Build a per-team round list with H/A flags
		' Order fixtures by (round, leg, id) to have stable traversal
		Local ordered:TFixtureState[] = fx[..]
		SortFixtures(ordered)

		' team -> list of (round:Int, isHome:Int {-1 away, +1 home})
		Local sched:TIntMap = New TIntMap ' pid -> TList of TPair(round:Int, ha:Int)
		For Local f:TFixtureState = EachIn ordered
			If f.homeTeamId > 0 Then
				AppendHA(sched, f.homeTeamId, f.round, 1)
			End If

			If f.awayTeamId > 0 Then
				AppendHA(sched, f.awayTeamId, f.round, -1)
			End If
		Next

		' For each team, compute max consecutive home/away and collect violations
		Local out:String[]
		For Local it:TIntKey = EachIn sched.Keys()
			Local pid:Int = it.value
			Local lst:TList = TList(sched.ValueForKey(pid))
			' copy to array of pairs sorted by round
			Local items:THAItem[] = ToHAArray(lst)
			SortHAItems(items)

			Local cur:Int = 0, curStart:Int = 0
			Local curType:Int = 0 ' 1=home, -1=away
			Local i:Int
			For i = 0 Until items.Length
				Local t:Int = items[i].ha
				If cur = 0 Then
					cur = 1; curType = t; curStart = i
				ElseIf t = curType Then
					cur :+ 1
				Else
					' streak ended; evaluate
					If curType = 1 And cur > maxH Then
						out :+ [ "Team " + pid + ": HOME streak=" + cur + " at rounds " + SpanRounds(items, curStart, i - 1) ]
					ElseIf curType = -1 And cur > maxA Then
						out :+ [ "Team " + pid + ": AWAY streak=" + cur + " at rounds " + SpanRounds(items, curStart, i - 1) ]
					End If
					' start new
					cur = 1; curType = t; curStart = i
				End If
			Next
			' tail streak
			If cur > 0 Then
				If curType = 1 And cur > maxH Then
					out :+ [ "Team " + pid + ": HOME streak=" + cur + " at rounds " + SpanRounds(items, curStart, i - 1) ]
				ElseIf curType = -1 And cur > maxA Then
					out :+ [ "Team " + pid + ": AWAY streak=" + cur + " at rounds " + SpanRounds(items, curStart, i - 1) ]
				End If
			End If
		Next

		Return out
	End Function

	Type THAItem
		Field round:Int
		Field ha:Int   ' 1=home, -1=away
	End Type

	Function AppendHA(m:TIntMap, pid:Int, round:Int, ha:Int)
		Local lst:TList = TList(m.ValueForKey(pid))
		If lst = Null Then lst = New TList; m.Insert(pid, lst)

		Local it:THAItem = New THAItem; it.round = round; it.ha = ha
		lst.AddLast(it)
	End Function

	Function ToHAArray:THAItem[](lst:TList)
		Local out:THAItem[]
		For Local o:Object = EachIn lst
			out :+ [THAItem(o)]
		Next

		Return out
	End Function

	Function SortHAItems(a:THAItem[])
		For Local i:Int = 0 Until a.Length - 1
			For Local j:Int = i + 1 Until a.Length
				If a[i].round > a[j].round Then
					Local t:THAItem = a[i]; a[i] = a[j]; a[j] = t
				End If
			Next
		Next
	End Function

	Function SortFixtures(a:TFixtureState[])
		For Local i:Int = 0 Until a.Length - 1
			For Local j:Int = i + 1 Until a.Length
				If a[i].round > a[j].round Or (a[i].round = a[j].round And a[i].leg > a[j].leg) Or (a[i].round = a[j].round And a[i].leg = a[j].leg And a[i].id > a[j].id) Then
					Local t:TFixtureState = a[i]; a[i] = a[j]; a[j] = t
				End If
			Next
		Next
	End Function

	Function SpanRounds:String(items:THAItem[], s:Int, e:Int)
		Local r:String = "["
		For Local i:Int = s Until e
			r :+ items[i].round + ","
		Next

		r :+ items[e].round + "]"
		Return r
	End Function

End Type

Type TGroupDoubleRRBalanceTest Extends TTest

	Method test_DoubleRoundRobin_BalancedHomeAway_NoLongStreaks() { test }
		' --- Build a deterministic 1-group, 6-team double round-robin schedule ---
		Local comp:TCompetition = New TCompetition
		For Local i:Int = 1 To 6
			Local p:TParticipant = New TParticipant
			p.id = i; p.name = "T" + i
			comp.participants :+ [p]
		Next

		Local gcfg:TGroupConfig = New TGroupConfig
		gcfg.configType = EConfigType.Group
		gcfg.groups = 1
		gcfg.groupSize = 6
		gcfg.roundRobinPerOpponent = 2 ' home & away

		gcfg.pointsWin = 3; gcfg.pointsDraw = 1; gcfg.pointsLoss = 0
		gcfg.tiebreakers = [ ETiebreaker.Points, ETiebreaker.GoalDifference, ETiebreaker.GoalsFor ]

		gcfg.policy = New TSchedulePolicy
		gcfg.policy.venuePolicy = New TVenuePolicy
		gcfg.policy.venuePolicy.venueType = EVenue.HomeAway
		gcfg.policy.maxConsecHome = 2
		gcfg.policy.maxConsecAway = 2
		gcfg.policy.groupOrder = EGroupScheduleType.RoundRobin
		gcfg.policy.scheduleSeed = 42 ' determinism

		Local st:TStage = New TStage
		st.id = "G"
		st.stageType = EStageType.Group
		st.config = gcfg
		st.input = New TEntrySource
		st.input.mode = EEntryMode.Direct
		comp.stages = [st]

		' --- Engine / Initialize ---
		Local eng:TCompetitionEngine = New TCompetitionEngine
		eng.RegisterScheduler(EStageType.Group, New TGroupScheduler)
		eng.RegisterScorer(  EStageType.Group, New TGroupScorer)
		eng.RegisterAdvancer(EStageType.Group, New TGroupAdvancer)

		Local state:TCompetitionState = eng.Initialize(comp)
		Local ss:TStageState = state.stages[0]

		' --- Assertions ---

		' (A) Each team has equal number of home and away matches
		For Local pid:Int = 1 To 6
			Local h:Int, a:Int
			CountHomeAwayForTeam(ss.fixtures, pid, h, a)
			AssertEqualsI(h, a, "Team " + pid + " must have equal home & away")
		Next

		' (B) No long home/away streaks (>2)
		Local violations:String[] = CheckVenueStreakViolations(ss.fixtures, gcfg.policy.maxConsecHome, gcfg.policy.maxConsecAway)
		Local sb:TStringBuilder = New TStringBuilder
		sb.JoinStrings(violations, "; ")

		AssertTrue(violations.Length = 0, sb.ToString())

		' (C) For every pair of teams, exactly two meetings (one home, one away)
		For Local i:Int = 1 To 6
			For Local j:Int = i + 1 To 6
				Local cnt:Int, hForI:Int, hForJ:Int
				PairCounts(ss.fixtures, i, j, cnt, hForI, hForJ)
				AssertEqualsI(2, cnt, "Pair " + i + "-" + j + " must meet exactly twice")
				AssertTrue(hForI = 1 And hForJ = 1, "Pair " + i + "-" + j + " must split home/away (1-1)")
			Next
		Next
	End Method

	' ---------- helpers ----------

	Function CountHomeAwayForTeam(fx:TFixtureState[], pid:Int, h:Int Var, a:Int Var)
		h = 0; a = 0
		For Local f:TFixtureState = EachIn fx
			If f.homeTeamId = pid Then
				h :+ 1
			End If

			If f.awayTeamId = pid Then
				a :+ 1
			End If
		Next
	End Function

	' Returns violations like: "Team 3: AWAY streak=3 at rounds [4,5,6]"
	Function CheckVenueStreakViolations:String[](fx:TFixtureState[], maxH:Int, maxA:Int)
		Local ordered:TFixtureState[] = fx[..]
		SortFixtures(ordered)

		Local sched:TIntMap = New TIntMap ' pid -> TList of THAItem
		For Local f:TFixtureState = EachIn ordered
			If f.homeTeamId > 0 Then
				AppendHA(sched, f.homeTeamId, f.round, 1)
			End If

			If f.awayTeamId > 0 Then
				AppendHA(sched, f.awayTeamId, f.round, -1)
			End If
		Next

		Local out:String[] = []
		For Local it:TIntKey = EachIn sched.Keys()
			Local pid:Int = it.value
			Local lst:TList = TList(sched.ValueForKey(pid))
			Local items:THAItem[] = ToHAArray(lst)
			SortHAItems(items)

			Local cur:Int = 0, curStart:Int = 0, curType:Int = 0
			Local i:Int
			For i = 0 Until items.Length
				Local t:Int = items[i].ha
				If cur = 0 Then
					cur = 1; curType = t; curStart = i
				ElseIf t = curType Then
					cur :+ 1
				Else
					If curType = 1 And cur > maxH Then
						out :+ [ "Team " + pid + ": HOME streak=" + cur + " at rounds " + SpanRounds(items, curStart, i - 1) ]
					End If

					If curType = -1 And cur > maxA Then
						out :+ [ "Team " + pid + ": AWAY streak=" + cur + " at rounds " + SpanRounds(items, curStart, i - 1) ]
					End If

					cur = 1; curType = t; curStart = i
				End If
			Next

			If cur > 0 Then
				If curType = 1 And cur > maxH Then
					out :+ [ "Team " + pid + ": HOME streak=" + cur + " at rounds " + SpanRounds(items, curStart, i - 1) ]
				End If

				If curType = -1 And cur > maxA Then
					out :+ [ "Team " + pid + ": AWAY streak=" + cur + " at rounds " + SpanRounds(items, curStart, i - 1) ]
				End If
			End If
		Next

		Return out
	End Function

	Type THAItem
		Field round:Int
		Field ha:Int   ' 1=home, -1=away
	End Type

	Function AppendHA(m:TIntMap, pid:Int, round:Int, ha:Int)
		Local lst:TList = TList(m.ValueForKey(pid))
		If lst = Null Then lst = New TList; m.Insert(pid, lst)

		Local it:THAItem = New THAItem; it.round = round; it.ha = ha
		lst.AddLast(it)
	End Function

	Function ToHAArray:THAItem[](lst:TList)
		Local out:THAItem[] = []
		For Local o:Object = EachIn lst
			out :+ [THAItem(o)]
		Next

		Return out
	End Function

	Function SortHAItems(a:THAItem[])
		For Local i:Int = 0 Until a.Length - 1
			For Local j:Int = i + 1 Until a.Length
				If a[i].round > a[j].round Then
					Local t:THAItem = a[i]; a[i] = a[j]; a[j] = t
				End If
			Next
		Next
	End Function

	Function SortFixtures(a:TFixtureState[])
		For Local i:Int = 0 Until a.Length - 1
			For Local j:Int = i + 1 Until a.Length
				If a[i].round > a[j].round Or (a[i].round = a[j].round And a[i].leg > a[j].leg) Or (a[i].round = a[j].round And a[i].leg = a[j].leg And a[i].id > a[j].id) Then
					Local t:TFixtureState = a[i]; a[i] = a[j]; a[j] = t
				End If
			Next
		Next
	End Function

	Function SpanRounds:String(items:THAItem[], s:Int, e:Int)
		Local r:String = "["
		For Local i:Int = s Until e
			r :+ items[i].round + ","
		Next

		r :+ items[e].round + "]"
		Return r
	End Function

	' Count pair meetings and home splits
	Function PairCounts(fx:TFixtureState[], a:Int, b:Int, cnt:Int Var, homeForA:Int Var, homeForB:Int Var)
		cnt = 0; homeForA = 0; homeForB = 0
		For Local f:TFixtureState = EachIn fx
			If (f.homeTeamId = a And f.awayTeamId = b) Then
				cnt :+ 1; homeForA :+ 1
			ElseIf (f.homeTeamId = b And f.awayTeamId = a) Then
				cnt :+ 1; homeForB :+ 1
			End If
		Next
	End Function

	Function JoinViolations:String(v:String[])
		If v.Length = 0 Then
			Return ""
		End If

		Local s:String = "Venue streak violations:" + "~n"
		For Local x:String = EachIn v; s :+ x + "~n"; Next

		Return s
	End Function

End Type
