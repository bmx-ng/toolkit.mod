' Copyright (c) 2026 Bruce A Henderson
'
' This software is provided 'as-is', without any express or implied warranty.
' In no event will the authors be held liable for any damages arising from
' the use of this software.
'
' Permission is granted to anyone to use this software for any purpose,
' including commercial applications, and to alter it and redistribute it
' freely, subject to the following restrictions:
'
' 1. The origin of this software must not be misrepresented; you must not
'    claim that you wrote the original software. If you use this software
'    in a product, an acknowledgment in the product documentation would be
'    appreciated but is not required.
' 2. Altered source versions must be plainly marked as such, and must not be
'    misrepresented as being the original software.
' 3. This notice may not be removed or altered from any source distribution.
'
SuperStrict

Rem
bbdoc: Tournament management toolkit.
about: Provides tools and interfaces for managing tournament stages, configurations, and scheduling.
End Rem
Module Toolkit.Tourney

ModuleInfo "Version: 1.00"
ModuleInfo "Author: Bruce A Henderson"
ModuleInfo "License: zlib/libpng"

Import brl.random
Import Collections.IntMap
Import Text.JConv
Import Math.Decimal

Import "model.bmx"
Include "pointunits.bmx"
Include "ordering.bmx"
Include "calendarplanner.bmx"
Include "groups.bmx"
Include "roundrobin.bmx"
Include "league.bmx"
Include "postseason.bmx"
Include "brackets.bmx"
Include "elimination.bmx"
Include "series.bmx"
Include "seriesranking.bmx"
Include "clinching.bmx"
Include "qualification.bmx"
Include "seriesqualification.bmx"
Include "scores.bmx"
Include "cricket.bmx"
Include "swiss.bmx"
Include "heats.bmx"
Include "strokeplay.bmx"
Include "regatta.bmx"
Include "cycling.bmx"
Include "authoring.bmx"
Include "builder.bmx"

Rem
bbdoc: Creates a custom #TConfig during jconv deserialization.
about: Register a factory for each custom config code with #TConfigSerializer.RegisterConfig.
End Rem
Interface IConfigFactory
	Rem
	bbdoc: Creates an empty custom configuration for jconv to populate.
	returns: A new #TConfig instance matching the registered config code.
	End Rem
	Method Create:TConfig()
End Interface

Rem
bbdoc: Serializes and restores polymorphic stage configurations with jconv.
about: Register factories for custom `configCode` values before reading a definition.
End Rem
Type TConfigSerializer Extends TJConvSerializer
	Rem
	bbdoc: #TTreeMap<String, value used by this config serializer.
	End Rem
	Field factories:TTreeMap<String, IConfigFactory>

	Rem
	bbdoc: Associates a custom config code with its deserialization factory.
	param: Code stored in #TConfig.configCode.
	param: Factory that creates that configuration subtype.
	End Rem
	Method RegisterConfig(code:String, factory:IConfigFactory)
		If code = "" Or factory = Null Then
			Throw "Custom config needs a code and factory"
		End If

		If factories = Null Then
			factories = New TTreeMap<String, IConfigFactory>
		End If

		factories.Add(code, factory)
	End Method

	Method Serialize:TJSON(source:Object, sourceType:String) Override
		Local value:TConfig = TConfig(source)
		If value Then
			Return Super.Serialize(value, sourceType)
		End If
	End Method

	Method Deserialize:Object(json:TJSON, typeId:TTypeId, obj:Object) Override
		If TJSONObject(json) Then
			If Not obj Then
				Local codeField:TJSONString = TJSONString(TJSONObject(json).Get("configCode"))
				If codeField <> Null And codeField.Value() <> "" Then
					Local factory:IConfigFactory = Null
					If factories <> Null Then
						factory = IConfigFactory(factories[codeField.Value()])
					End If

					If factory = Null Then
						Throw "Unknown TConfig configCode: " + codeField.Value()
					End If

					obj = factory.Create()
					Return Super.Deserialize(json, TTypeId.ForObject(obj), obj)
				End If

				Local fld:TJSONString = TJSONString(TJSONObject(json).Get("configType"))

				If Not fld Then
					Throw "TConfig JSON missing configType field"
				End If

				Local ctype:EConfigType = EConfigType.FromString(fld.Value())

				Select ctype
					Case EConfigType.League
						obj = New TLeagueConfig
					Case EConfigType.Group
						obj = New TGroupConfig
					Case EConfigType.Bracket
						obj = New TBracketConfig
					Case EConfigType.Series
						obj = New TSeriesConfig
					Case EconfigType.Swiss
						obj = New TSwissConfig
					Case EConfigType.Heats
						obj = New THeatsConfig
					Case EConfigType.StrokePlay
						obj = New TStrokePlayConfig
					Case EConfigType.Regatta
						obj = New TRegattaConfig
					Case EConfigType.Cycling
						obj = New TCyclingConfig
					Default
						Throw "Unknown TConfig configType: " + ctype.ToString()
				End Select

				Local configTypeId:TTypeId = TTypeId.ForObject(obj)

				Return Super.Deserialize(json, configTypeId, obj)
			End If
		End If

		Return obj
	End Method

End Type

' Engine-facing contracts for each stage type
Rem
bbdoc: Builds the initial fixtures for a stage format.
about: Register an implementation with #TCompetitionEngine.RegisterScheduler or #TCompetitionEngine.RegisterFormat.
End Rem
Interface IStageScheduler
	Rem
	bbdoc: Creates the initial fixtures for a stage.
	param: Competition definition containing the participants.
	param: Stage whose configuration defines the fixtures.
	returns: Scheduled fixture states for the initial round.
	End Rem
	Method BuildFixtures:TFixtureState[](comp:TCompetition, stage:TStage)
End Interface

' Progressive formats create a round only after the preceding round has results.
Rem
bbdoc: Generates a format's next fixtures after earlier results are known.
about: The engine calls this contract for progressive rounds such as Swiss pairings or elimination stages.
End Rem
Interface IProgressiveStageScheduler
	Rem
	bbdoc: Creates the next fixtures after earlier rounds have results.
	param: Competition definition.
	param: Progressive stage definition.
	param: Current stage state with completed earlier fixtures.
	returns: New fixtures, or an empty array when no round remains.
	End Rem
	Method NextFixtures:TFixtureState[](comp:TCompetition, stage:TStage, state:TStageState)
End Interface

Rem
bbdoc: Applies results, computes standings, and decides when a stage is complete.
about: A custom format provides its own result validation and ranking behaviour through this contract.
End Rem
Interface IStageScorer
	Rem
	bbdoc: Applies one result to the specified fixture.
	param: Competition definition.
	param: Stage definition and scoring rules.
	param: Stage state to update.
	param: Fixture ID receiving the result.
	param: Typed result to validate and apply.
	End Rem
	Method ApplyResult(comp:TCompetition, stage:TStage, st:TStageState, fxId:String, result:TResultPayload)

	Rem
	bbdoc: Recomputes this stage's standings from recorded results.
	param: Competition definition.
	param: Stage definition and ranking rules.
	param: Stage state whose standings are updated.
	End Rem
	Method ComputeStandings(comp:TCompetition, stage:TStage, st:TStageState) ' updates st.leaderboard

	Rem
	bbdoc: Reports whether the stage has satisfied its completion rules.
	param: Competition definition.
	param: Stage definition.
	param: Current stage state.
	returns: True when no further result is required for this stage.
	End Rem
	Method IsComplete:Int(comp:TCompetition, stage:TStage, st:TStageState) { asBool }
End Interface

Rem
bbdoc: Selects entrants a completed stage can route onward.
End Rem
Interface IStageAdvancer
	Rem
	bbdoc: Produces entrants selected from a completed stage.
	param: Competition definition.
	param: Completed source stage.
	param: Source stage state and standings.
	returns: Participants eligible for downstream routes.
	End Rem
	Method ProduceAdvancements:TParticipant[](comp:TCompetition, stage:TStage, st:TStageState)
End Interface

' Receives a completed engine update after standings and downstream stages are
' current. Implementations can record a timeline or update a presentation.
Rem
bbdoc: Receives the state after a result updates standings and dependent stages.
about: Use this to build timelines or presentation data outside the engine.
End Rem
Interface ICompetitionResultObserver
	Rem
	bbdoc: Receives a result after standings and dependent stages are current.
	param: Competition definition.
	param: Updated playing state.
	param: Stage that received the result.
	param: Fixture that received the result.
	param: Recorded result payload.
	End Rem
	Method OnResultRecorded(comp:TCompetition, state:TCompetitionState, stageId:String, fixtureId:String, result:TResultPayload)
End Interface

' Observers with accumulated history can reset before a corrected journal is replayed.
Rem
bbdoc: Resets observer history before a corrected action journal is replayed.
End Rem
Interface ICompetitionReplayObserver
	Rem
	bbdoc: Clears accumulated observer data before a corrected replay begins.
	End Rem
	Method OnReplayReset()
End Interface

' Optional calendar solver. Applications can supply a more advanced allocator
' without changing stage schedulers or result processing.
Rem
bbdoc: Assigns calendar slots to one stage's fixtures.
End Rem
Interface IFixtureSlotAllocator
	Rem
	bbdoc: Assigns candidate calendar slots to one stage's fixtures.
	param: Competition definition.
	param: Stage being scheduled.
	param: Fixtures whose slots may be assigned.
	End Rem
	Method Assign(comp:TCompetition, stage:TStage, fixtures:TFixtureState[])
End Interface

' Optional wider view for allocators that can respect earlier stages' slots.
Rem
bbdoc: Assigns slots while accounting for other stages' reservations.
End Rem
Interface ICompetitionSlotAllocator
	Rem
	bbdoc: Assigns slots while respecting assignments in other stages.
	param: Competition definition.
	param: Stage being scheduled.
	param: Fixtures whose slots may be assigned.
	param: Existing slot reservations from other stages.
	End Rem
	Method AssignWithReservations(comp:TCompetition, stage:TStage, fixtures:TFixtureState[], reservations:TSlotReservation[])
End Interface



' ---------- Engine ----------
Rem
bbdoc: Creates fixtures, records results, advances stages, and analyzes competition state.
about: Register handlers for each built-in stage type used by a definition. Custom formats use #RegisterFormat; the engine does not render results.
End Rem
Type TCompetitionEngine
	Rem
	bbdoc: #TTreeMap<EStageType, value used by this competition engine.
	about: EStageType -> IStageScheduler.
	End Rem
	Field schedulers:TTreeMap<EStageType, IStageScheduler>        ' EStageType -> IStageScheduler
	Rem
	bbdoc: #TTreeMap<EStageType, value used by this competition engine.
	about: EStageType -> IStageScorer.
	End Rem
	Field scorers:TTreeMap<EStageType, IStageScorer>           ' EStageType -> IStageScorer
	Rem
	bbdoc: #TTreeMap<EStageType, value used by this competition engine.
	about: EStageType -> IStageAdvancer.
	End Rem
	Field advancers:TTreeMap<EStageType, IStageAdvancer>         ' EStageType -> IStageAdvancer
	Rem
	bbdoc: #TTreeMap<String, value used by this competition engine.
	End Rem
	Field formatSchedulers:TTreeMap<String, IStageScheduler>
	Rem
	bbdoc: #TTreeMap<String, value used by this competition engine.
	End Rem
	Field formatScorers:TTreeMap<String, IStageScorer>
	Rem
	bbdoc: #TTreeMap<String, value used by this competition engine.
	End Rem
	Field formatAdvancers:TTreeMap<String, IStageAdvancer>
	Rem
	bbdoc: #TTreeMap<EStageType, value used by this competition engine.
	End Rem
	Field clinchProviders:TTreeMap<EStageType, IClinchBoundsProvider>
	Rem
	bbdoc: #TTreeMap<String, value used by this competition engine.
	End Rem
	Field formatClinchProviders:TTreeMap<String, IClinchBoundsProvider>
	Rem
	bbdoc: Slot allocator for this competition engine.
	End Rem
	Field slotAllocator:IFixtureSlotAllocator
	Rem
	bbdoc: Result observers values associated with this competition engine.
	End Rem
	Field resultObservers:ICompetitionResultObserver[]
	Rem
	bbdoc: Suppress result observers for this competition engine.
	End Rem
	Field suppressResultObservers:Int
	Rem
	bbdoc: #TJConv value used by this competition engine.
	End Rem
	Field journalConverter:TJConv
	Rem
	bbdoc: Last schedule preference score for this competition engine.
	End Rem
	Field lastSchedulePreferenceScore:Long
	Rem
	bbdoc: Last schedule preference optimal for this competition engine.
	End Rem
	Field lastSchedulePreferenceOptimal:Int
	Rem
	bbdoc: Last schedule search nodes for this competition engine.
	End Rem
	Field lastScheduleSearchNodes:Int
	Rem
	bbdoc: Last schedule pruned nodes for this competition engine.
	End Rem
	Field lastSchedulePrunedNodes:Int
	Rem
	bbdoc: #TScheduleFailureReport value used by this competition engine.
	End Rem
	Field lastScheduleFailure:TScheduleFailureReport

	Rem
	bbdoc: Adds a callback invoked after each completed result update.
	param: Observer to receive the updated definition, state, fixture, and result.
	End Rem
	Method AddResultObserver(observer:ICompetitionResultObserver)
		If observer = Null Then
			Throw "Result observer is missing"
		End If

		resultObservers :+ [observer]
	End Method

	Rem
	bbdoc: Uses a converter when serializing results in the correction journal.
	param: Converter capable of round-tripping any custom payload data.
	about: Set this before recording results when custom payloads must survive correction replay.
	End Rem
	Method SetJournalConverter(converter:TJConv)
		If converter = Null Then
			Throw "Result journal converter is missing"
		End If

		journalConverter = converter
	End Method

	Rem
	bbdoc: Returns the converter used to persist correction actions.
	returns: The configured #TJConv, creating a default converter when needed.
	End Rem
	Method ResultJournalConverter:TJConv()
		If journalConverter = Null Then
			journalConverter = New TJConvBuilder.WithEmptyArrays().Build()
		End If

		Return journalConverter
	End Method

	Rem
	bbdoc: Registers the scheduler, scorer, and optional advancer for a custom format code.
	param: Stable code stored in #TStage.formatCode.
	param: Fixture scheduler for the format.
	param: Result scorer and standings calculator.
	param: Optional source of entrants for advancement routes.
	End Rem
	Method RegisterFormat(code:String, scheduler:IStageScheduler, scorer:IStageScorer, advancer:IStageAdvancer = Null)
		If code = "" Or scheduler = Null Or scorer = Null Then
			Throw "Custom format needs a code, scheduler and scorer"
		End If

		If formatSchedulers = Null Then
			formatSchedulers = New TTreeMap<String, IStageScheduler>
		End If

		If formatScorers = Null Then
			formatScorers = New TTreeMap<String, IStageScorer>
		End If

		If formatAdvancers = Null Then
			formatAdvancers = New TTreeMap<String, IStageAdvancer>
		End If

		formatSchedulers.Add(code, scheduler)
		formatScorers.Add(code, scorer)
		If advancer <> Null Then
			formatAdvancers.Add(code, advancer)
		End If
	End Method

	Rem
	bbdoc: Sets a per-stage calendar slot allocator.
	param: Allocator used while stages start.
	End Rem
	Method RegisterSlotAllocator(allocator:IFixtureSlotAllocator)
		slotAllocator = allocator
	End Method

	Rem
	bbdoc: Registers a fixture scheduler for a built-in stage type.
	param: Stage type handled by the scheduler.
	param: Scheduler to create its fixtures.
	End Rem
	Method RegisterScheduler(stageType:EStageType, s:IStageScheduler)
		If Not schedulers Then
			schedulers = New TTreeMap<EStageType, IStageScheduler>
		End If

		schedulers.Add(stageType, s)
	End Method

	Rem
	bbdoc: Registers a result scorer for a built-in stage type.
	param: Stage type handled by the scorer.
	param: Scorer to validate results and update standings.
	End Rem
	Method RegisterScorer(stageType:EStageType, s:IStageScorer)
		If Not scorers Then
			scorers = New TTreeMap<EStageType, IStageScorer>
		End If

		scorers.Add(stageType, s)
	End Method

	Rem
	bbdoc: Registers an advancement handler for a built-in stage type.
	param: Stage type handled by the advancer.
	param: Advancer that identifies routed entrants.
	End Rem
	Method RegisterAdvancer(stageType:EStageType, a:IStageAdvancer)
		If Not advancers Then
			advancers = New TTreeMap<EStageType, IStageAdvancer>
		End If

		advancers.Add(stageType, a)
	End Method

	Rem
	bbdoc: Registers maximum and minimum points bounds for clinching analysis.
	param: Built-in stage type to analyze.
	param: Provider of attainable final-points bounds.
	End Rem
	Method RegisterClinchBounds(stageType:EStageType, provider:IClinchBoundsProvider)
		If provider = Null Then
			Throw "Clinch bounds provider is missing"
		End If

		If clinchProviders = Null Then
			clinchProviders = New TTreeMap<EStageType, IClinchBoundsProvider>
		End If

		clinchProviders.Add(stageType, provider)
	End Method

	Rem
	bbdoc: Registers clinching bounds for a custom format.
	param: Code used when registering the custom format.
	param: Provider of attainable final-points bounds.
	End Rem
	Method RegisterFormatClinchBounds(code:String, provider:IClinchBoundsProvider)
		If code = "" Or provider = Null Then
			Throw "Custom clinch bounds need a format code and provider"
		End If

		If formatClinchProviders = Null Then
			formatClinchProviders = New TTreeMap<String, IClinchBoundsProvider>
		End If

		formatClinchProviders.Add(code, provider)
	End Method

	Rem
	bbdoc: Determines whether a standings leader has already clinched.
	param: Competition definition used to interpret the state.
	param: Current playing state.
	param: Stage to analyze.
	param: Named series championship, or the main table when empty.
	returns: A #TClinchAnalysis with attainable bounds and the clinching status.
	about: The result is limited to what the stage's bounds provider can certify.
	End Rem
	Method AnalyzeClinching:TClinchAnalysis(comp:TCompetition, state:TCompetitionState, stageId:String, championshipCode:String = "")
		If comp = Null Or state = Null Then
			Throw "Clinching analysis needs a competition and state"
		End If

		Local index:Int = FindStageIndex(state, stageId)
		If index < 0 Then
			Throw "Unknown stage: " + stageId
		End If

		Local stage:TStage = GetStage(comp, stageId)
		If stage = Null Then
			Throw "Unknown stage definition: " + stageId
		End If

		Local provider:IClinchBoundsProvider = Null
		If stage.formatCode <> "" Then
			If formatClinchProviders <> Null Then
				provider = IClinchBoundsProvider(formatClinchProviders[stage.formatCode])
			End If
		Else
			If clinchProviders <> Null Then
				provider = IClinchBoundsProvider(clinchProviders[stage.stageType])
			End If

			If provider = Null Then
				Select stage.stageType
					Case EStageType.Series
						provider = New TSeriesClinchBounds
					Case EStageType.Group, EStageType.League
						provider = New THeadToHeadClinchBounds
				End Select
			End If
		End If

		Return New TClinchAnalyzer.Analyze(comp, stage, state.stages[index], championshipCode, provider)
	End Method

	Rem
	bbdoc: Explores whether an entrant can reach a qualifying place.
	param: Competition definition used to interpret the state.
	param: Current playing state.
	param: Stage to analyze.
	param: Participant whose prospects are queried.
	param: Number of qualifying places.
	param: Group key for grouped standings, or empty for the main table.
	param: Maximum scenarios to explore before reporting a search limit.
	param: Named series championship, or the main table when empty.
	returns: A #TQualificationAnalysis with possible and guaranteed outcomes.
	about: A bounded search cannot prove every outcome when its scenario limit is reached.
	End Rem
	Method AnalyzeQualification:TQualificationAnalysis(comp:TCompetition, state:TCompetitionState, stageId:String, participantId:Int, places:Int, groupKey:String = "", maxScenarios:Int = 100000, championshipCode:String = "")
		If comp = Null Or state = Null Then
			Throw "Qualification analysis needs a competition and state"
		End If

		Local index:Int = FindStageIndex(state, stageId)
		If index < 0 Then
			Throw "Unknown stage: " + stageId
		End If

		Local stage:TStage = GetStage(comp, stageId)
		If stage = Null Then
			Throw "Unknown stage definition: " + stageId
		End If

		If stage.stageType = EStageType.Series Then
			If groupKey <> "" Then
				Throw "Series qualification does not use a group key"
			End If

			Return New TSeriesQualificationAnalyzer.Analyze(comp, stage, state.stages[index], participantId, places, championshipCode, maxScenarios)
		End If

		If championshipCode <> "" Then
			Throw "Named championships require a series stage"
		End If

		Return New TQualificationAnalyzer.Analyze(stage, state.stages[index], participantId, places, groupKey, maxScenarios)
	End Method

	' Start every stage without predecessors. The previous-stage fallback keeps
	' older ordered-pipeline configurations working.
	Rem
	bbdoc: Creates a new playing state and starts stages with known entrants.
	param: Definition containing participants and at least one stage.
	param: Whether to plan known root fixtures jointly on a calendar.
	returns: A new #TCompetitionState with root fixtures.
	about: When @planCalendar is true, initialization also invokes joint schedule planning.
	End Rem
	Method Initialize:TCompetitionState(comp:TCompetition, planCalendar:Int = False)
		If comp = Null Or comp.stages = Null Or comp.stages.Length = 0 Then
			Throw "A competition needs at least one stage"
		End If

		Local stState:TStageState[]
		For Local st:TStage = EachIn comp.stages
			If st = Null Or st.id = "" Then
				Throw "Every stage needs an id"
			End If

			For Local previous:TStageState = EachIn stState
				If previous.stageId = st.id Then
					Throw "Duplicate stage id: " + st.id
				End If
			Next

			Local ss:TStageState = New TStageState
			ss.stageId = st.id
			ss.status = EStageStatus.Pending
			ss.leaderboard = New TLeaderboard
			ss.leaderboard.rows = []
			stState :+ [ss]
		Next

		ValidateStageGraph(comp)

		Local state:TCompetitionState = New TCompetitionState
		state.competitionName = comp.name
		state.stages = stState
		For Local i:Int = 0 Until comp.stages.Length
			If StageSources(comp, i).Length = 0 Then
				StartStage(comp, state, i, comp.participants, planCalendar)
			End If
		Next

		If planCalendar Then
			PlanSchedule(comp, state)
		End If

		Return state
	End Method

	' Search the fixtures already generated across all started stages together.
	' Reassign permits changing scheduled (unplayed) slots in an existing state.
	Rem
	bbdoc: Places generated fixtures from started stages into calendar slots.
	param: Competition definition.
	param: Current playing state.
	param: Whether unplayed assignments may be moved.
	param: Maximum search nodes before the planner stops.
	returns: The number of fixtures assigned to slots.
	about: A search bound is distinct from a proof that no valid placement exists; inspect `lastScheduleFailure` when planning fails.
	End Rem
	Method PlanCalendar:Int(comp:TCompetition, state:TCompetitionState, reassign:Int = False, maxSearchNodes:Int = 100000)
		If slotAllocator <> Null Then
			Throw "Joint calendar planning uses the built-in slot allocator; remove the separately registered allocator"
		End If

		lastSchedulePreferenceScore = 0
		lastSchedulePreferenceOptimal = False
		lastScheduleSearchNodes = 0
		lastSchedulePrunedNodes = 0
		lastScheduleFailure = Null
		Local planner:TCompetitionCalendarPlanner = New TCompetitionCalendarPlanner
		Local assigned:Int
		Try
			assigned = planner.Assign(comp, state, reassign, maxSearchNodes)
		Catch problem:Object
			lastScheduleFailure = planner.failureReport
			lastScheduleSearchNodes = planner.nodes
			lastSchedulePrunedNodes = planner.prunedNodes
			Throw problem
		End Try

		lastSchedulePreferenceScore = planner.bestScore
		lastSchedulePreferenceOptimal = planner.optimal
		lastScheduleSearchNodes = planner.nodes
		lastSchedulePrunedNodes = planner.prunedNodes
		Return assigned
	End Method

	' Search weeks and slots together for fixed-length league stages with calendars.
	Rem
	bbdoc: Plans league weeks and calendar slots together.
	param: Competition definition.
	param: Current playing state.
	param: Whether unplayed week and slot assignments may be moved.
	param: Maximum search nodes before the planner stops.
	returns: The number of fixtures assigned to slots.
	about: This includes fixed-length league stages with calendars; preferences rank feasible plans without overriding hard constraints.
	End Rem
	Method PlanSchedule:Int(comp:TCompetition, state:TCompetitionState, reassign:Int = False, maxSearchNodes:Int = 100000)
		If slotAllocator <> Null Then
			Throw "Joint schedule planning uses the built-in slot allocator; remove the separately registered allocator"
		End If

		lastSchedulePreferenceScore = 0
		lastSchedulePreferenceOptimal = False
		lastScheduleSearchNodes = 0
		lastSchedulePrunedNodes = 0
		lastScheduleFailure = Null
		If comp <> Null And comp.stages <> Null Then
			For Local stage:TStage = EachIn comp.stages
				If stage = Null Then
					Continue
				End If

				Local leagueScheduler:TLeagueScheduler = TLeagueScheduler(GetSchedulerForStage(stage))
				If leagueScheduler <> Null And leagueScheduler.weekAllocator <> Null Then
					Throw "Joint schedule planning uses the built-in league week allocator"
				End If
			Next
		End If

		Local planner:TCompetitionCalendarPlanner = New TCompetitionCalendarPlanner
		Local assigned:Int
		Try
			assigned = planner.Assign(comp, state, reassign, maxSearchNodes, True)
		Catch problem:Object
			lastScheduleFailure = planner.failureReport
			lastScheduleSearchNodes = planner.nodes
			lastSchedulePrunedNodes = planner.prunedNodes
			Throw problem
		End Try

		lastSchedulePreferenceScore = planner.bestScore
		lastSchedulePreferenceOptimal = planner.optimal
		lastScheduleSearchNodes = planner.nodes
		lastSchedulePrunedNodes = planner.prunedNodes
		Return assigned
	End Method

	Rem
	bbdoc: Records a home-away score and updates the stage.
	param: Competition definition.
	param: Current playing state, updated in place.
	param: Stage containing the fixture.
	param: Fixture receiving the result.
	param: Home-side score.
	param: Away-side score.
	about: Convenience wrapper for #RecordResult with a head-to-head score payload.
	End Rem
	Method RecordResultAndAdvance(comp:TCompetition, state:TCompetitionState, stageId:String, fixtureId:String, homeScore:Int, awayScore:Int)
		Local payload:TResultPayload = New TResultPayload
		payload.kind = EResultKind.HeadToHeadScore
		payload.scoreHome = homeScore
		payload.scoreAway = awayScore
		RecordResult(comp, state, stageId, fixtureId, payload)
	End Method

	Rem
	bbdoc: Records a finishing order for a series fixture.
	param: Competition definition.
	param: Current playing state, updated in place.
	param: Series stage containing the fixture.
	param: Fixture receiving the classification.
	param: Participant IDs in finishing order.
	about: Convenience wrapper for #RecordResult with a classification payload.
	End Rem
	Method RecordSeriesClassificationAndAdvance(comp:TCompetition, state:TCompetitionState, stageId:String, fixtureId:String, order:Int[])
		Local payload:TResultPayload = New TResultPayload
		payload.kind = EResultKind.Classification
		payload.order = order
		RecordResult(comp, state, stageId, fixtureId, payload)
	End Method

	' Returns a rebuilt state; the supplied state is left untouched.
	Rem
	bbdoc: Replays the journal with one fixture result replaced.
	param: Competition definition used for the original results.
	param: Current playing state, left unchanged.
	param: Stage containing the result.
	param: Fixture whose result changes.
	param: Replacement result payload.
	returns: A #TResultCorrection containing a new state and any invalidated later actions.
	about: Keep the returned state. A later result is invalidated when its matchup no longer matches the replayed fixture.
	End Rem
	Method CorrectResult:TResultCorrection(comp:TCompetition, state:TCompetitionState, stageId:String, fixtureId:String, replacement:TResultPayload)
		Local replayer:TResultReplayer = New TResultReplayer
		Return replayer.Correct(Self, comp, state, stageId, fixtureId, replacement)
	End Method

	' List every undecided built-in table tie in a completed stage. The result
	' also includes a cross-group set when it currently blocks advancement.
	Rem
	bbdoc: Lists unresolved sporting ties in a completed built-in table.
	param: Competition definition.
	param: Current playing state.
	param: Stage whose tables are inspected.
	returns: Tied sets with scope keys; empty for unfinished stages.
	about: Display order alone does not resolve a sporting tie that straddles an advancement cutoff.
	End Rem
	Method UnresolvedTableTies:TUnresolvedTableTie[](comp:TCompetition, state:TCompetitionState, stageId:String)
		If comp = Null Or state = Null Then
			Throw "Table tie query needs a competition and state"
		End If

		Local index:Int = FindStageIndex(state, stageId)
		If index < 0 Then
			Throw "Unknown stage: " + stageId
		End If

		If state.stages[index].status <> EStageStatus.Complete Then
			Return []
		End If

		Local stage:TStage = GetStage(comp, stageId)
		If TGroupConfig(stage.config) = Null And TLeagueConfig(stage.config) = Null And TSeriesConfig(stage.config) = Null Then
			Return []
		End If

		Local journal:TJConv = ResultJournalConverter()
		Local snapshot:TCompetitionState = TCompetitionState(journal.FromJson(journal.ToJson(state), "TCompetitionState"))
		Local ss:TStageState = snapshot.stages[index]
		Local found:TUnresolvedTableTie[]
		found = CollectTableTies(stageId, "", ss.leaderboard.rows, found)
		If TGroupConfig(stage.config) <> Null Then
			Local advancer:TGroupAdvancer = New TGroupAdvancer
			If ss.groups = Null Or ss.groups.Length = 0 Then
				ss.groups = advancer.SnapshotGroupTables(comp, stage, ss)
			End If

			For Local group:TGroupTable = EachIn ss.groups
				found = CollectTableTies(stageId, group.key, group.rows, found)
			Next

			If stage.advancement <> Null And stage.advancement.Length > 0 Then
				advancer.ProduceAdvancements(comp, stage, ss)
				If advancer.unresolvedCrossGroupTie <> Null Then
					found :+ [advancer.unresolvedCrossGroupTie]
				End If
			End If
		End If

		For Local named:TNamedLeaderboard = EachIn ss.championships
			found = CollectTableTies(stageId, named.code, named.leaderboard.rows, found)
		Next

		Return found
	End Method

	Method CollectTableTies:TUnresolvedTableTie[](stageId:String, scopeKey:String, rows:TLeaderboardRow[], found:TUnresolvedTableTie[])
		If rows = Null Then
			Return found
		End If

		For Local row:TLeaderboardRow = EachIn rows
			If row.sportingRank <= 0 Then
				Continue
			End If

			Local already:Int
			For Local tie:TUnresolvedTableTie = EachIn found
				If tie.scopeKey <> scopeKey Then
					Continue
				End If

				For Local id:Int = EachIn tie.participantIds
					If id = row.participantId Then already = True; Exit
				Next

				If already Then
					Exit
				End If
			Next

			If already Then
				Continue
			End If

			Local tie:TUnresolvedTableTie = New TUnresolvedTableTie
			tie.stageId = stageId
			tie.scopeKey = scopeKey
			For Local member:TLeaderboardRow = EachIn rows
				If member.sportingRank = row.sportingRank Then
					tie.participantIds :+ [member.participantId]
				End If
			Next

			If tie.participantIds.Length > 1 Then
				found :+ [tie]
			End If
		Next

		Return found
	End Method

	' Decide an exact unresolved table tie. The ordered IDs are best to worst.
	' This returns a new state and retries advancement from a completed stage.
	Rem
	bbdoc: Records an official ordering of a tied set and retries advancement.
	param: Competition definition.
	param: Current playing state.
	param: Stage containing the tie.
	param: Table scope key, or empty for the main table.
	param: The complete tied set in decided best-to-worst order.
	param: Reason for the official decision.
	returns: A replacement #TCompetitionState containing the decision.
	about: Keep the returned state. The decision becomes a replayable journal action.
	End Rem
	Method RecordTableTieDecision:TCompetitionState(comp:TCompetition, state:TCompetitionState, stageId:String, scopeKey:String, orderedIds:Int[], reason:String)
		If comp = Null Or state = Null Or orderedIds = Null Or orderedIds.Length < 2 Or reason.Trim() = "" Then
			Throw "Table tie decision needs a tied set and reason"
		End If

		Local index:Int = FindStageIndex(state, stageId)
		If index < 0 Then
			Throw "Unknown stage: " + stageId
		End If

		Local stage:TStage = GetStage(comp, stageId)
		If TGroupConfig(stage.config) = Null And TLeagueConfig(stage.config) = Null And TSeriesConfig(stage.config) = Null Then
			Throw "Table tie decisions require a group, league, or series stage"
		End If

		If state.stages[index].status <> EStageStatus.Complete Then
			Throw "Table tie decision needs a completed stage: " + stageId
		End If

		Local replaySeed:Int = RndSeed()
		For Local targetIndex:Int = 0 Until comp.stages.Length
			If targetIndex = index Or state.stages[targetIndex].status = EStageStatus.Pending Then
				Continue
			End If

			If HasString(StageSources(comp, targetIndex), stageId) Then
				Throw "Dependent stage has already started; correct its earlier results before deciding this table tie"
			End If
		Next

		Local journal:TJConv = ResultJournalConverter()
		Local revised:TCompetitionState = TCompetitionState(journal.FromJson(journal.ToJson(state), "TCompetitionState"))
		Local ss:TStageState = revised.stages[index]
		Local rows:TLeaderboardRow[]
		If scopeKey = "" Then
			rows = ss.leaderboard.rows
		ElseIf TSeriesConfig(stage.config) <> Null Then
			For Local named:TNamedLeaderboard = EachIn ss.championships
				If named.code = scopeKey Then rows = named.leaderboard.rows; Exit
			Next
		Else
			If TGroupConfig(stage.config) = Null Then
				Throw "Group key needs a group stage"
			End If

			If ss.groups = Null Then
				Local advancer:TGroupAdvancer = New TGroupAdvancer
				ss.groups = advancer.SnapshotGroupTables(comp, stage, ss)
			End If

			If scopeKey = "bestAcross" Then
				Local advancer:TGroupAdvancer = New TGroupAdvancer
				advancer.ProduceAdvancements(comp, stage, ss)
				Local pending:TUnresolvedTableTie = advancer.unresolvedCrossGroupTie
				If pending = Null Or pending.participantIds.Length <> orderedIds.Length Then
					Throw "Cross-group decision must cover the unresolved advancement cutoff"
				End If

				For Local id:Int = EachIn orderedIds
					Local found:Int
					For Local candidate:Int = EachIn pending.participantIds
						If candidate = id Then
							found :+ 1
						End If
					Next

					If found <> 1 Then
						Throw "Cross-group decision must name each cutoff participant exactly once"
					End If
				Next
			Else
				For Local group:TGroupTable = EachIn ss.groups
					If group.key = scopeKey Then rows = group.rows; Exit
				Next
			End If
		End If

		If scopeKey <> "bestAcross" Or TSeriesConfig(stage.config) <> Null Then
			If rows = Null Then
				Throw "Unknown or empty table scope: " + scopeKey
			End If

			Local tiedRank:Int
			For Local row:TLeaderboardRow = EachIn rows
				If row.participantId = orderedIds[0] Then tiedRank = row.sportingRank; Exit
			Next

			If tiedRank <= 0 Then
				Throw "First participant is not in a built-in table tie"
			End If

			Local tiedCount:Int
			For Local row:TLeaderboardRow = EachIn rows
				If row.sportingRank <> tiedRank Then
					Continue
				End If

				tiedCount :+ 1
				Local found:Int
				For Local id:Int = EachIn orderedIds
					If id = row.participantId Then
						found :+ 1
					End If
				Next

				If found <> 1 Then
					Throw "Decision must name each tied participant exactly once"
				End If
			Next

			If tiedCount <> orderedIds.Length Then
				Throw "Decision must cover the exact tied set"
			End If
		End If

		Local decision:TTableTieDecision = New TTableTieDecision
		decision.scopeKey = scopeKey
		decision.participantIds = orderedIds[..]
		decision.reason = reason
		ss.tableTieDecisions :+ [decision]
		Local scorer:IStageScorer = GetScorerForStage(stage)
		If scorer = Null Then
			Throw "No scorer registered for stage type: " + stage.stageType
		End If

		ss.groups = Null
		scorer.ComputeStandings(comp, stage, ss)
		ApplyAdjustmentsOverlayToLeaderboard(ss, stage)
		RankAdjustedSeriesMain(comp, stage, ss)
		If stage.formatCode = "" And (TGroupConfig(stage.config) <> Null Or TLeagueConfig(stage.config) <> Null) Then
			Local rules:ETiebreaker[]
			Local winPoints:Int = 3
			Local drawPoints:Int = 1
			Local lossPoints:Int
			Local reapply:Int
			Local group:TGroupConfig = TGroupConfig(stage.config)
			Local league:TLeagueConfig = TLeagueConfig(stage.config)
			If group <> Null Then
				rules = group.tiebreakers
				winPoints = group.pointsWin; drawPoints = group.pointsDraw; lossPoints = group.pointsLoss
				reapply = group.reapplyHeadToHead
			ElseIf league <> Null Then
				rules = league.tiebreakers
				winPoints = league.pointsWin; drawPoints = league.pointsDraw; lossPoints = league.pointsLoss
				reapply = league.reapplyHeadToHead
			End If

			SortTableByTiebreakers(ss.leaderboard.rows, rules, ss.fixtures, winPoints, drawPoints, lossPoints, reapply, ss.tableTieDecisions)
		End If

		If scopeKey <> "" And TGroupConfig(stage.config) <> Null Then
			Local advancer:TGroupAdvancer = New TGroupAdvancer
			ss.groups = advancer.SnapshotGroupTables(comp, stage, ss)
		End If

		AdvanceFromStage(comp, revised, index)
		Local action:TRecordedAction = New TRecordedAction
		action.actionType = ERecordedActionType.TableTieDecision
		action.stageId = stageId
		action.scopeKey = scopeKey
		action.decisionOrder = orderedIds[..]
		action.reason = reason
		If state.stages[index].entrants <> Null Then
			action.entrantIds = state.stages[index].entrants[..]
		End If

		If state.replayBaseJson = "" Then
			revised.replayBaseJson = journal.ToJson(state)
			revised.replaySeed = replaySeed
		End If

		revised.actions :+ [action]
		Return revised
	End Method

	' Returns a new state. The requested fixture is pinned while the joint planner
	' validates every started stage; optionally release other unplayed assignments.
	Rem
	bbdoc: Changes one unplayed fixture's slot or round and records the revision.
	param: Competition definition.
	param: Current playing state.
	param: Stage containing the fixture.
	param: Fixture to revise.
	param: Required ID of a slot in the stage calendar.
	param: New round, or zero to retain the current round.
	param: Whether other flexible unplayed fixtures may be replanned.
	param: Maximum planner search nodes.
	returns: A replacement #TCompetitionState with the revised schedule.
	about: Keep the returned state; the revision is journalled so later result correction can replay it.
	End Rem
	Method ReviseFixtureSchedule:TCompetitionState(comp:TCompetition, state:TCompetitionState, stageId:String, fixtureId:String, slotId:String, round:Int = 0, replanFlexible:Int = False, maxSearchNodes:Int = 100000)
		If comp = Null Or state = Null Then
			Throw "Schedule revision needs a competition and state"
		End If

		If slotId = "" Then
			Throw "Schedule revision needs a slot id"
		End If

		Local stageIndex:Int = FindStageIndex(state, stageId)
		If stageIndex < 0 Then
			Throw "Unknown stage: " + stageId
		End If

		Local stage:TStage = GetStage(comp, stageId)
		Local calendar:TCalendar = GetSchedulePolicy(stage).calendar
		If calendar = Null Then
			Throw "Stage has no calendar: " + stageId
		End If

		Local selected:TSlot
		For Local slot:TSlot = EachIn calendar.slots
			If slot <> Null And slot.id = slotId Then selected = slot; Exit
		Next

		If selected = Null Then
			Throw "Unknown calendar slot: " + slotId
		End If

		Local original:TFixtureState
		For Local fixture:TFixtureState = EachIn state.stages[stageIndex].fixtures
			If fixture.id = fixtureId Then original = fixture; Exit
		Next

		If original = Null Then
			Throw "Unknown fixture: " + fixtureId
		End If

		If original.status <> EFixtureStatus.Scheduled And original.status <> EFixtureStatus.Postponed Then
			Throw "Only unplayed fixtures can be rescheduled: " + fixtureId
		End If

		If original.awayTeamId = 0 Then
			Throw "Bye fixtures cannot be rescheduled: " + fixtureId
		End If

		If round < 0 Then
			Throw "Schedule revision round cannot be negative"
		End If

		Local journal:TJConv = ResultJournalConverter()
		Local revised:TCompetitionState = TCompetitionState(journal.FromJson(journal.ToJson(state), "TCompetitionState"))
		Local target:TFixtureState
		For Local fixture:TFixtureState = EachIn revised.stages[stageIndex].fixtures
			If fixture.id = fixtureId Then target = fixture; Exit
		Next

		If replanFlexible Then
			For Local index:Int = 0 Until revised.stages.Length
				Local candidateStage:TStage = comp.stages[index]
				Local candidateCalendar:TCalendar = GetSchedulePolicy(candidateStage).calendar
				If candidateCalendar = Null Then
					Continue
				End If

				Local league:TLeagueConfig = TLeagueConfig(candidateStage.config)
				For Local fixture:TFixtureState = EachIn revised.stages[index].fixtures
					If fixture = target Or (fixture.status <> EFixtureStatus.Scheduled And fixture.status <> EFixtureStatus.Postponed) Then
						Continue
					End If

					fixture.slotId = ""
					fixture.venueId = ""
					If league <> Null And CalendarCanPlanLeagueWeeks(league.schedule, candidateCalendar) Then
						fixture.round = 0
					End If
				Next
			Next
		End If

		target.slotId = selected.id
		target.venueId = selected.venueId
		If round > 0 Then
			target.round = round
		ElseIf selected.round > 0 Then
			target.round = selected.round
		End If

		PlanSchedule(comp, revised, False, maxSearchNodes)
		target.status = EFixtureStatus.Scheduled

		Local action:TRecordedAction = New TRecordedAction
		action.actionType = ERecordedActionType.ScheduleRevision
		action.stageId = stageId
		action.fixtureId = fixtureId
		action.slotId = slotId
		action.round = round
		action.replanFlexible = replanFlexible
		action.homeTeamId = original.homeTeamId
		action.awayTeamId = original.awayTeamId
		If original.participantIds <> Null Then
			action.participantIds = original.participantIds[..]
		End If

		If original.heatEntrants <> Null Then
			action.heatEntrants = original.heatEntrants[..]
		End If

		action.groupKey = original.groupKey
		action.seriesEventId = original.seriesEventId
		action.sessionCode = original.sessionCode
		If state.stages[stageIndex].entrants <> Null Then
			action.entrantIds = state.stages[stageIndex].entrants[..]
		End If

		If state.replayBaseJson = "" Then
			revised.replayBaseJson = journal.ToJson(state)
			revised.replaySeed = RndSeed()
		End If

		revised.actions :+ [action]
		Return revised
	End Method

	Rem
	bbdoc: Validates and records a fixture result, then updates downstream stages.
	param: Competition definition.
	param: Current playing state, updated in place.
	param: Stage containing the fixture.
	param: Fixture receiving the result.
	param: Typed result payload.
	about: The stage scorer interprets the payload; completion may start dependent stages and invoke result observers.
	End Rem
	Method RecordResult(comp:TCompetition, state:TCompetitionState, stageId:String, fixtureId:String, result:TResultPayload)

		Local idx:Int = FindStageIndex(state, stageId)
		If idx < 0 Then
			Throw "Unknown stage: " + stageId
		End If

		Local st:TStage = GetStage(comp, stageId)
		Local ss:TStageState = state.stages[idx]
		If result = Null Then
			Throw "Result is missing"
		End If

		If ss.status <> EStageStatus.Running And Not (ss.status = EStageStatus.Complete And result.kind = EResultKind.AdminAdjustment) Then
			Throw "Stage is not running: " + stageId
		End If

		If result.kind <> EResultKind.AdminAdjustment Then
			Local fixture:TFixtureState = Null
			For Local f:TFixtureState = EachIn ss.fixtures
				If f.id = fixtureId Then fixture = f; Exit
			Next

			If fixture = Null Then
				Throw "Unknown fixture: " + fixtureId
			End If

			If fixture.status = EFixtureStatus.Completed Then
				Throw "Fixture already has a result: " + fixtureId
			End If

			If result.kind <> EResultKind.StatusOnly And fixture.status <> EFixtureStatus.Scheduled And fixture.status <> EFixtureStatus.InProgress Then
				Throw "Fixture is not playable: " + fixtureId
			End If

			ValidateResult(ss, fixture, result)
		End If
		' Capture the pre-action fixture identity and an immutable payload for replay.
		' The baseline is taken at the first action, after any caller-supplied draw or
		' calendar changes made before play begins.
		Local journal:TJConv = ResultJournalConverter()
		Local action:TRecordedAction = New TRecordedAction
		action.actionType = ERecordedActionType.Result
		action.stageId = stageId
		action.fixtureId = fixtureId
		action.kind = result.kind
		action.payloadJson = journal.ToJson(result)
		If ss.entrants <> Null Then
			action.entrantIds = ss.entrants[..]
		End If

		If result.kind <> EResultKind.AdminAdjustment Then
			For Local current:TFixtureState = EachIn ss.fixtures
				If current.id <> fixtureId Then
					Continue
				End If

				action.homeTeamId = current.homeTeamId
				action.awayTeamId = current.awayTeamId
				If current.participantIds <> Null Then
					action.participantIds = current.participantIds[..]
				End If

				If current.heatEntrants <> Null Then
					action.heatEntrants = current.heatEntrants[..]
				End If

				action.groupKey = current.groupKey
				action.seriesEventId = current.seriesEventId
				action.sessionCode = current.sessionCode
				Exit
			Next
		End If

		Local replayBase:String
		Local replaySeed:Int
		If state.replayBaseJson = "" Then
			replayBase = journal.ToJson(state)
			replaySeed = RndSeed()
		End If

		Local scorer:IStageScorer = GetScorerForStage(st)
		If Not scorer Then
			Throw "No scorer registered for stage type: " + st.stageType
		End If

		' 1) Apply the payload. The registered scorer decides which result kinds
		' it supports; one stage may accept several kinds across its sessions.
		Select result.kind
			Case EResultKind.HeadToHeadScore, EResultKind.SetBased, EResultKind.Classification, EResultKind.TimeBased, EResultKind.Custom
				scorer.ApplyResult(comp, st, ss, fixtureId, result)

			Case EResultKind.AdminAdjustment
				StoreAdjustments(ss, result.adjustments)

			Case EResultKind.StatusOnly
				MarkFixtureStatus(ss, fixtureId, result.statusCode) ' postponed/abandoned/cancelled

			Default
				Throw "Unsupported result kind for stage '" + stageId + "'"
		End Select

		' 2) Recompute standings for this stage
		ss.groups = Null
		scorer.ComputeStandings(comp, st, ss)
		ApplyAdjustmentsOverlayToLeaderboard(ss, st)
		RankAdjustedSeriesMain(comp, st, ss)
		If ss.status = EStageStatus.Running Then
			GenerateNextRound(comp, state, stageId)
		End If

		If st.formatCode = "" And (st.stageType = EStageType.Group Or st.stageType = EStageType.League) Then
			Local rules:ETiebreaker[]
			Local winPoints:Int = 3
			Local drawPoints:Int = 1
			Local lossPoints:Int = 0
			Local reapplyHeadToHead:Int
			Local group:TGroupConfig = TGroupConfig(st.config)
			Local league:TLeagueConfig = TLeagueConfig(st.config)
			If group <> Null Then
				rules = group.tiebreakers
				winPoints = group.pointsWin
				drawPoints = group.pointsDraw
				lossPoints = group.pointsLoss
				reapplyHeadToHead = group.reapplyHeadToHead
			End If

			If league <> Null Then
				rules = league.tiebreakers
				winPoints = league.pointsWin
				drawPoints = league.pointsDraw
				lossPoints = league.pointsLoss
				reapplyHeadToHead = league.reapplyHeadToHead
			End If

			SortTableByTiebreakers(ss.leaderboard.rows, rules, ss.fixtures, winPoints, drawPoints, lossPoints, reapplyHeadToHead, ss.tableTieDecisions)
		End If

		' 3) Start every destination whose required sources are complete.
		If ss.status <> EStageStatus.Complete And scorer.IsComplete(comp, st, ss) Then
			ss.status = EStageStatus.Complete
			AdvanceFromStage(comp, state, idx)
		End If

		If state.replayBaseJson = "" Then
			state.replayBaseJson = replayBase
			state.replaySeed = replaySeed
		End If

		state.actions :+ [action]
		If resultObservers <> Null And Not suppressResultObservers Then
			For Local observer:ICompetitionResultObserver = EachIn resultObservers
				observer.OnResultRecorded(comp, state, stageId, fixtureId, result)
			Next
		End If
	End Method

	' Also permits a retry after pairing or calendar allocation failed following
	' the final result of a round. The completed result remains in saved state.
	Rem
	bbdoc: Generates the next fixtures for a progressive stage.
	param: Competition definition.
	param: Current playing state.
	param: Stage whose next round is requested.
	returns: True when another round was generated.
	End Rem
	Method GenerateNextRound:Int(comp:TCompetition, state:TCompetitionState, stageId:String)
		Local idx:Int = FindStageIndex(state, stageId)
		If idx < 0 Then
			Throw "Unknown stage: " + stageId
		End If

		Local stage:TStage = GetStage(comp, stageId)
		Local ss:TStageState = state.stages[idx]
		If ss.status <> EStageStatus.Running Then
			Throw "Stage is not running: " + stageId
		End If

		Local progressive:IProgressiveStageScheduler = IProgressiveStageScheduler(GetSchedulerForStage(stage))
		If progressive = Null Then
			Return False
		End If

		Local nextFixtures:TFixtureState[] = progressive.NextFixtures(comp, stage, ss)
		If nextFixtures = Null Or nextFixtures.Length = 0 Then
			Return False
		End If

		Local combined:TFixtureState[] = ss.fixtures[..]
		combined :+ nextFixtures
		Local policy:TSchedulePolicy = GetSchedulePolicy(stage)
		If policy.calendar <> Null And policy.calendar.slots <> Null And policy.calendar.slots.Length > 0 Then
			Local allocator:IFixtureSlotAllocator = slotAllocator
			If allocator = Null Then
				allocator = New TCalendarSlotAllocator
			End If

			Local shared:ICompetitionSlotAllocator = ICompetitionSlotAllocator(allocator)
			If shared <> Null Then
				shared.AssignWithReservations(comp, stage, combined, CalendarReservations(comp, state, idx))
			Else
				allocator.Assign(comp, stage, combined)
			End If
		End If

		ss.fixtures = combined
		Local scorer:IStageScorer = GetScorerForStage(stage)
		If scorer <> Null Then
			scorer.ComputeStandings(comp, stage, ss)
			ApplyAdjustmentsOverlayToLeaderboard(ss, stage)
		End If

		Return True
	End Method

	' --- helpers ---
	Method GetScheduler:IStageScheduler(stageType:EStageType)
		If schedulers = Null Then
			Return Null
		End If

		Return IStageScheduler(schedulers[stageType])
	End Method

	Method GetScorer:IStageScorer(stageType:EStageType)
		If scorers = Null Then
			Return Null
		End If

		Return IStageScorer(scorers[stageType])
	End Method

	Method GetAdvancer:IStageAdvancer(stageType:EStageType)
		If advancers = Null Then
			Return Null
		End If

		Return IStageAdvancer(advancers[stageType])
	End Method

	Method GetSchedulerForStage:IStageScheduler(stage:TStage)
		If stage.formatCode <> "" Then
			If formatSchedulers = Null Then
				Return Null
			End If

			Return IStageScheduler(formatSchedulers[stage.formatCode])
		End If

		Return GetScheduler(stage.stageType)
	End Method

	Method GetScorerForStage:IStageScorer(stage:TStage)
		If stage.formatCode <> "" Then
			If formatScorers = Null Then
				Return Null
			End If

			Return IStageScorer(formatScorers[stage.formatCode])
		End If

		Return GetScorer(stage.stageType)
	End Method

	Method GetAdvancerForStage:IStageAdvancer(stage:TStage)
		If stage.formatCode <> "" Then
			If formatAdvancers = Null Then
				Return Null
			End If

			Return IStageAdvancer(formatAdvancers[stage.formatCode])
		End If

		Return GetAdvancer(stage.stageType)
	End Method

	Method FindStageIndex:Int(state:TCompetitionState, id:String)
		For Local i:Int = 0 Until state.stages.Length
			If state.stages[i].stageId = id Then
				Return i
			End If
		Next

		Return -1
	End Method

	Method GetStage:TStage(comp:TCompetition, id:String)
		For Local st:TStage = EachIn comp.stages
			If st.id = id Then
				Return st
			End If
		Next

		Return Null
	End Method

	' Explicit sources take precedence. An incoming advancement also declares a
	' source. Otherwise the preceding array entry is the legacy pipeline source.
	Method StageSources:String[](comp:TCompetition, targetIndex:Int)
		Local target:TStage = comp.stages[targetIndex]
		Local sources:String[]
		If target.independent Then
			Return sources
		End If

		If target.input <> Null Then
			If target.input.fromStageIds <> Null Then
				For Local id:String = EachIn target.input.fromStageIds
					If id <> "" And Not HasString(sources, id) Then
						sources :+ [id]
					End If
				Next
			End If

			If target.input.fromStageId <> "" And Not HasString(sources, target.input.fromStageId) Then
				sources :+ [target.input.fromStageId]
			End If
		End If

		If sources.Length > 0 Then
			Return sources
		End If

		For Local source:TStage = EachIn comp.stages
			For Local route:TAdvancement = EachIn source.advancement
				If route.toStageId = target.id And Not HasString(sources, source.id) Then
					sources :+ [source.id]
				End If
			Next
		Next

		If sources.Length = 0 And targetIndex > 0 Then
			sources :+ [comp.stages[targetIndex - 1].id]
		End If

		Return sources
	End Method

	Rem
	bbdoc: Checks stage IDs, dependencies, and routes for a valid graph.
	param: Competition definition to validate.
	End Rem
	Method ValidateStageGraph(comp:TCompetition)
		For Local source:TStage = EachIn comp.stages
			Local destinations:String[]
			For Local route:TAdvancement = EachIn source.advancement
				If route.toStageId <> "" And GetStage(comp, route.toStageId) = Null Then
					Throw "Unknown advancement destination: " + route.toStageId
				End If

				If route.toStageId <> "" And HasString(destinations, route.toStageId) Then
					Throw "Duplicate advancement destination from stage " + source.id + ": " + route.toStageId
				End If

				If route.toStageId <> "" Then
					destinations :+ [route.toStageId]
				End If
			Next
		Next

		For Local i:Int = 0 Until comp.stages.Length
			Local activation:TStageActivation = comp.stages[i].activation
			If activation = Null Or activation.kind = EStageActivationKind.Always Then
				Continue
			End If

			If activation.kind <> EStageActivationKind.IfReferenceEntrantLoses Then
				Throw "Unknown stage activation rule"
			End If

			Local sources:String[] = StageSources(comp, i)
			If sources.Length <> 1 Then
				Throw "Reference-entrant activation needs one source stage"
			End If

			Local source:TStage = GetStage(comp, sources[0])
			If source = Null Or source.stageType <> EStageType.Bracket Then
				Throw "Reference-entrant activation needs a bracket source"
			End If

			Local sourceIndex:Int = -1
			For Local j:Int = 0 Until comp.stages.Length
				If comp.stages[j].id = sources[0] Then sourceIndex = j; Exit
			Next

			If activation.referenceSourceId = "" Or Not HasString(StageSources(comp, sourceIndex), activation.referenceSourceId) Then
				Throw "Activation reference must feed the bracket source"
			End If
		Next

		Local resolved:Int[] = New Int[comp.stages.Length]
		For Local pass:Int = 0 Until comp.stages.Length
			Local progress:Int = False
			For Local i:Int = 0 Until comp.stages.Length
				If resolved[i] Then
					Continue
				End If

				Local ready:Int = True
				For Local id:String = EachIn StageSources(comp, i)
					Local sourceIndex:Int = -1
					For Local j:Int = 0 Until comp.stages.Length
						If comp.stages[j].id = id Then sourceIndex = j; Exit
					Next

					If sourceIndex < 0 Then
						Throw "Unknown source stage: " + id
					End If

					If Not resolved[sourceIndex] Then
						ready = False
					End If
				Next

				If ready Then resolved[i] = True; progress = True
			Next

			Local allResolved:Int = True
			For Local done:Int = EachIn resolved
				If Not done Then allResolved = False; Exit
			Next

			If allResolved Then
				Return
			End If

			If Not progress Then
				Throw "Stage dependencies contain a cycle"
			End If
		Next
	End Method

	Method HasString:Int(values:String[], value:String)
		For Local item:String = EachIn values
			If item = value Then
				Return True
			End If
		Next

		Return False
	End Method

	Method HasInt:Int(values:Int[], value:Int)
		For Local item:Int = EachIn values
			If item = value Then
				Return True
			End If
		Next

		Return False
	End Method

	Method StartStage(comp:TCompetition, state:TCompetitionState, index:Int, entrants:TParticipant[], deferCalendar:Int = False)
		Local stage:TStage = comp.stages[index]
		Local ss:TStageState = state.stages[index]
		Local sch:IStageScheduler = GetSchedulerForStage(stage)
		If sch = Null Or entrants = Null Or entrants.Length = 0 Then
			Return
		End If

		ss.entrants = []
		For Local p:TParticipant = EachIn entrants
			If p <> Null And Not HasInt(ss.entrants, p.id) Then
				ss.entrants :+ [p.id]
			End If
		Next

		Local runtimeStage:TStage = StageWithInputSlots(stage, ss)
		Local rankingSource:String
		If stage.input <> Null And stage.input.seeding <> Null Then
			rankingSource = stage.input.seeding.rankingStageId
		End If

		Local scheduled:TParticipant[]
		For Local participant:TParticipant = EachIn entrants
			Local seed:Int = InputSeed(ss, participant.id)
			If rankingSource <> "" Then
				seed = RankingSourceSeed(state, rankingSource, participant.id)
			End If

			If seed = 0 Then
				scheduled :+ [participant]
			Else
				Local copy:TParticipant = New TParticipant
				copy.id = participant.id
				copy.name = participant.name
				copy.region = participant.region
				copy.divisionId = participant.divisionId
				copy.homeVenueId = participant.homeVenueId
				copy.previousRank = participant.previousRank
				copy.seedRank = seed
				copy.drawPot = participant.drawPot
				copy.meta = participant.meta
				copy.parentTeamId = participant.parentTeamId
				copy.kind = participant.kind
				scheduled :+ [copy]
			End If
		Next

		Local leagueScheduler:TLeagueScheduler = TLeagueScheduler(sch)
		If deferCalendar And leagueScheduler <> Null Then
			Local leagueConfig:TLeagueConfig = TLeagueConfig(stage.config)
			Local calendar:TCalendar = GetSchedulePolicy(stage).calendar
			If leagueConfig <> Null And CalendarCanPlanLeagueWeeks(leagueConfig.schedule, calendar) Then
				If leagueScheduler.weekAllocator <> Null Then
					Throw "Joint schedule planning uses the built-in league week allocator"
				End If

				leagueScheduler.deferWeeks = True
			End If
		End If

		Try
			ss.fixtures = sch.BuildFixtures(WithTempEntrants(comp, scheduled), runtimeStage)
		Catch problem:Object
			If leagueScheduler <> Null Then
				leagueScheduler.deferWeeks = False
			End If

			Throw problem
		End Try

		If leagueScheduler <> Null Then
			leagueScheduler.deferWeeks = False
		End If

		Local bracketScheduler:TBracketScheduler = TBracketScheduler(sch)
		If bracketScheduler <> Null Then
			If bracketScheduler.lastByePositions <> Null Then
				ss.bracketByePositions = bracketScheduler.lastByePositions[..]
			End If

			If bracketScheduler.lastByeEntrants <> Null Then
				ss.bracketByeEntrants = bracketScheduler.lastByeEntrants[..]
			End If
		End If

		Local policy:TSchedulePolicy = GetSchedulePolicy(stage)
		If Not deferCalendar And policy.calendar <> Null And policy.calendar.slots <> Null And policy.calendar.slots.Length > 0 Then
			Local allocator:IFixtureSlotAllocator = slotAllocator
			If allocator = Null Then
				allocator = New TCalendarSlotAllocator
			End If

			Local shared:ICompetitionSlotAllocator = ICompetitionSlotAllocator(allocator)
			If shared <> Null Then
				shared.AssignWithReservations(comp, stage, ss.fixtures, CalendarReservations(comp, state, index))
			Else
				allocator.Assign(comp, stage, ss.fixtures)
			End If
		End If

		ss.status = EStageStatus.Running
		If IProgressiveStageScheduler(sch) <> Null Then
			Local initialScorer:IStageScorer = GetScorerForStage(stage)
			If initialScorer <> Null Then
				initialScorer.ComputeStandings(comp, stage, ss)
			End If
		End If

		If bracketScheduler <> Null And ss.fixtures.Length = 0 And ss.bracketByeEntrants <> Null And ss.bracketByeEntrants.Length > 0 Then
			ss.status = EStageStatus.Complete
			AdvanceFromStage(comp, state, index)
		End If
	End Method

	Method CalendarReservations:TSlotReservation[](comp:TCompetition, state:TCompetitionState, excludedIndex:Int)
		Local reservations:TSlotReservation[]
		For Local i:Int = 0 Until state.stages.Length
			If i = excludedIndex Then
				Continue
			End If

			Local calendar:TCalendar = GetSchedulePolicy(comp.stages[i]).calendar
			If calendar = Null Then
				Continue
			End If

			For Local fixture:TFixtureState = EachIn state.stages[i].fixtures
				If fixture.slotId = "" Or fixture.status = EFixtureStatus.Cancelled Then
					Continue
				End If

				Local slot:TSlot = Null
				For Local candidate:TSlot = EachIn calendar.slots
					If candidate.id = fixture.slotId Then slot = candidate; Exit
				Next

				If slot = Null Then
					Throw "Unknown reserved calendar slot: " + fixture.slotId
				End If

				Local reservation:TSlotReservation = New TSlotReservation
				reservation.stageId = comp.stages[i].id
				reservation.fixtureId = fixture.id
				reservation.dateTime = slot.dateTime
				reservation.venueId = slot.venueId
				reservation.homeTeamId = fixture.homeTeamId
				reservation.awayTeamId = fixture.awayTeamId
				reservations :+ [reservation]
			Next
		Next

		Return reservations
	End Method

	Method RankingSourceSeed:Int(state:TCompetitionState, sourceId:String, participantId:Int)
		For Local source:TStageState = EachIn state.stages
			If source.stageId <> sourceId Then
				Continue
			End If

			If source.status <> EStageStatus.Complete Or source.leaderboard = Null Then
				Throw "Ranking source needs completed standings: " + sourceId
			End If

			For Local rank:Int = 0 Until source.leaderboard.rows.Length
				If source.leaderboard.rows[rank].participantId = participantId Then
					Return rank + 1
				End If
			Next

			Throw "Entrant is absent from ranking source: " + participantId
		Next

		Throw "Unknown ranking source: " + sourceId
	End Method

	Method InputSeed:Int(stageState:TStageState, participantId:Int)
		For Local input:TStageInputState = EachIn stageState.inputs
			If input.seedRanks = Null Then
				Continue
			End If

			For Local i:Int = 0 Until input.entrantIds.Length
				If input.entrantIds[i] = participantId Then
					Return input.seedRanks[i]
				End If
			Next
		Next

		Return 0
	End Method

	Method StageWithInputSlots:TStage(stage:TStage, ss:TStageState)
		Local needsCopy:Int = False
		For Local input:TStageInputState = EachIn ss.inputs
			If (input.slotIds <> Null And input.slotIds.Length > 0) Or input.reseed Then needsCopy = True; Exit
		Next

		If Not needsCopy Then
			Return stage
		End If

		If stage.stageType <> EStageType.Bracket Then
			Throw "Fixed slots and reseeding need a bracket destination"
		End If

		Local copy:TStage = New TStage
		copy.id = stage.id
		copy.stageType = stage.stageType
		copy.formatCode = stage.formatCode
		copy.independent = stage.independent
		copy.schedule = stage.schedule
		copy.advancement = stage.advancement
		copy.input = New TEntrySource
		If stage.input <> Null Then
			copy.input.mode = stage.input.mode
			copy.input.fromStageId = stage.input.fromStageId
			copy.input.fromStageIds = stage.input.fromStageIds
			copy.input.seeding = stage.input.seeding
			copy.input.filter = stage.input.filter
			copy.input.postseasonPoolCode = stage.input.postseasonPoolCode
		End If

		copy.input.constraints = New TDrawConstraints
		If stage.input <> Null And stage.input.constraints <> Null Then
			copy.input.constraints.disallowSameGroup = stage.input.constraints.disallowSameGroup
			copy.input.constraints.disallowSameRegion = stage.input.constraints.disallowSameRegion
			copy.input.constraints.maxFromRegion = stage.input.constraints.maxFromRegion
			copy.input.constraints.maxFromPot = stage.input.constraints.maxFromPot
			copy.input.constraints.avoidPairs = stage.input.constraints.avoidPairs
			copy.input.constraints.avoidUntilRound = stage.input.constraints.avoidUntilRound
			If stage.input.constraints.lockedSlots <> Null Then
				copy.input.constraints.lockedSlots = stage.input.constraints.lockedSlots[..]
			End If
		End If

		Local reseed:Int = False
		For Local input:TStageInputState = EachIn ss.inputs
			If input.reseed Then
				reseed = True
			End If

			If input.slotIds = Null Then
				Continue
			End If

			If input.slotIds.Length <> input.entrantIds.Length Then
				Throw "Advancement slots do not match entrants"
			End If

			For Local i:Int = 0 Until input.slotIds.Length
				If input.slotIds[i] = "" Then
					Continue
				End If

				For Local existing:TPresetSlot = EachIn copy.input.constraints.lockedSlots
					If existing.slotId = input.slotIds[i] Or existing.participantId = input.entrantIds[i] Then
						Throw "Conflicting bracket slot assignment"
					End If
				Next

				Local placed:TPresetSlot = New TPresetSlot
				placed.participantId = input.entrantIds[i]
				placed.slotId = input.slotIds[i]
				copy.input.constraints.lockedSlots :+ [placed]
			Next
		Next

		If reseed Then
			Local original:TBracketConfig = TBracketConfig(stage.config)
			Local config:TBracketConfig = New TBracketConfig
			config.size = original.size
			config.format = original.format
			config.reseedEachRound = True
			config.byes = original.byes
			config.matchFormat = original.matchFormat
			config.policy = original.policy
			config.consolation = original.consolation
			config.doubleElim = original.doubleElim
			copy.config = config
		Else
			copy.config = stage.config
		End If

		Return copy
	End Method

	Method RoutedSlots:String[](mapping:TAdvancementMapping, entrantIds:Int[], sourceState:TStageState, target:TStage)
		If mapping = Null Or mapping.mode = EAdvMappingMode.Seeded Then
			Return Null
		End If

		Local config:TBracketConfig = TBracketConfig(target.config)
		If config = Null Then
			Throw "Advancement slots need a bracket destination"
		End If

		Local entrantCount:Int = entrantIds.Length
		Select mapping.mode
			Case EAdvMappingMode.FixedSlots
				If mapping.toSlots = Null Or mapping.toSlots.Length <> entrantCount Then
					Throw "Fixed advancement slots must match the selected entrants"
				End If

				Return mapping.toSlots[..]
			Case EAdvMappingMode.ConditionalSlots
				Return ConditionalRoutedSlots(mapping, entrantIds, sourceState, config.size)
			Case EAdvMappingMode.Partition
				Local half:Int = config.size / 2
				If entrantCount > half Then
					Throw "Advancement partition has too many entrants"
				End If

				Local start:Int
				Select mapping.partitionKey
					Case "left"
						start = 1
					Case "right"
						start = half + 1
					Default
						Throw "Bracket partition must be left or right"
				End Select

				Local slots:String[]
				For Local i:Int = 0 Until entrantCount
					slots :+ [String(start + i)]
				Next

				Return slots
		End Select

		Throw "Unsupported advancement mapping"
	End Method

	Method ConditionalRoutedSlots:String[](mapping:TAdvancementMapping, entrantIds:Int[], sourceState:TStageState, bracketSize:Int)
		If mapping.qualifyingRank < 1 Then
			Throw "Conditional slots need a positive qualifying rank"
		End If

		If sourceState.groups = Null Or sourceState.groups.Length = 0 Then
			Throw "Conditional slots need source group standings"
		End If

		If mapping.conditionalCases = Null Or mapping.conditionalCases.Length = 0 Then
			Throw "Conditional slots need at least one case"
		End If

		Local qualifiedGroups:String[]
		For Local group:TGroupTable = EachIn sourceState.groups
			If group.rows <> Null And group.rows.Length >= mapping.qualifyingRank Then
				If HasInt(entrantIds, group.rows[mapping.qualifyingRank - 1].participantId) Then
					qualifiedGroups :+ [group.key]
				End If
			End If
		Next

		Local selected:TConditionalSlotCase
		For Local choice:TConditionalSlotCase = EachIn mapping.conditionalCases
			If choice = Null Or choice.qualifyingGroupKeys = Null Or choice.qualifyingGroupKeys.Length <> qualifiedGroups.Length Then
				Continue
			End If

			Local matches:Int = True
			Local seen:String[]
			For Local key:String = EachIn choice.qualifyingGroupKeys
				If key = "" Or HasString(seen, key) Or Not HasString(qualifiedGroups, key) Then matches = False; Exit

				seen :+ [key]
			Next

			If matches Then
				If selected <> Null Then
					Throw "More than one conditional slot case matches the qualified groups"
				End If

				selected = choice
			End If
		Next

		If selected = Null Then
			Throw "No conditional slot case matches the qualified groups"
		End If

		Local assignments:TGroupRankSlot[]
		If mapping.baseAssignments <> Null Then
			assignments = mapping.baseAssignments[..]
		End If

		If selected.assignments <> Null Then
			assignments :+ selected.assignments
		End If

		If assignments.Length <> entrantIds.Length Then
			Throw "Conditional slot assignments must match the selected entrants"
		End If

		Local slots:String[] = New String[entrantIds.Length]
		For Local assignment:TGroupRankSlot = EachIn assignments
			If assignment = Null Or assignment.groupKey = "" Or assignment.rank < 1 Then
				Throw "Invalid conditional group-rank assignment"
			End If

			Local pid:Int
			For Local group:TGroupTable = EachIn sourceState.groups
				If group.key = assignment.groupKey Then
					If group.rows = Null Or assignment.rank > group.rows.Length Then
						Throw "Conditional slot rank is outside its group table"
					End If

					pid = group.rows[assignment.rank - 1].participantId
					Exit
				End If
			Next

			If pid = 0 Then
				Throw "Conditional slot group is absent from source standings"
			End If

			Local index:Int = -1
			For Local i:Int = 0 Until entrantIds.Length
				If entrantIds[i] = pid Then index = i; Exit
			Next

			If index < 0 Then
				Throw "Conditional slot assignment names an unqualified entrant"
			End If

			If slots[index] <> "" Then
				Throw "Conditional slot assigns an entrant twice"
			End If

			Local slot:Int = Int(assignment.slotId)
			If slot < 1 Or slot > bracketSize Or assignment.slotId <> String(slot) Then
				Throw "Conditional slot is outside the destination bracket"
			End If

			For Local existing:String = EachIn slots
				If existing = assignment.slotId Then
					Throw "Conditional slot is assigned twice"
				End If
			Next

			slots[index] = assignment.slotId
		Next

		For Local slot:String = EachIn slots
			If slot = "" Then
				Throw "Conditional slot leaves a selected entrant unplaced"
			End If
		Next

		Return slots
	End Method

	Method AdvanceFromStage(comp:TCompetition, state:TCompetitionState, sourceIndex:Int)
		Local source:TStage = comp.stages[sourceIndex]
		Local sourceState:TStageState = state.stages[sourceIndex]
		For Local targetIndex:Int = 0 Until comp.stages.Length
			Local targetState:TStageState = state.stages[targetIndex]
			If targetState.status <> EStageStatus.Pending Then
				Continue
			End If

			Local sources:String[] = StageSources(comp, targetIndex)
			If Not HasString(sources, source.id) Then
				Continue
			End If

			Local already:Int = False
			For Local input:TStageInputState = EachIn targetState.inputs
				If input.sourceStageId = source.id Then already = True; Exit
			Next

			If already Then
				Continue
			End If

			Local route:TAdvancement = Null
			For Local candidate:TAdvancement = EachIn source.advancement
				If candidate.toStageId = comp.stages[targetIndex].id Then route = candidate; Exit
			Next

			Local qualifiers:TParticipant[]
			Local adv:IStageAdvancer = GetAdvancerForStage(source)
			If adv <> Null Then
				If route <> Null Then
					Local routed:TStage = New TStage
					routed.id = source.id
					routed.stageType = source.stageType
					routed.config = source.config
					routed.input = source.input
					routed.advancement = [route]
					qualifiers = adv.ProduceAdvancements(comp, routed, sourceState)
				ElseIf source.advancement = Null Or source.advancement.Length = 0 Then
					qualifiers = adv.ProduceAdvancements(comp, source, sourceState)
				End If
			End If

			Local targetInput:TEntrySource = comp.stages[targetIndex].input
			Local seeded:TSeededField = Null
			If targetInput <> Null And targetInput.postseasonPoolCode <> "" Then
				Local leagueConfig:TLeagueConfig = TLeagueConfig(source.config)
				If leagueConfig = Null Or leagueConfig.postseason = Null Then
					Throw "Postseason input needs a league source with selection rules"
				End If

				seeded = TPostseasonSelector.Select(comp, sourceState, leagueConfig.postseason, targetInput.postseasonPoolCode)
				qualifiers = []
				For Local pid:Int = EachIn seeded.entrantIds
					qualifiers :+ [GetParticipant(comp, pid)]
				Next
			End If

			If qualifiers = Null And route = Null And targetInput <> Null And (targetInput.fromStageId <> "" Or (targetInput.fromStageIds <> Null And targetInput.fromStageIds.Length > 0)) Then
				' Explicit dependency with no filter passes every source entrant.
				For Local pid:Int = EachIn sourceState.entrants
					Local p:TParticipant = GetParticipant(comp, pid)
					If p <> Null Then
						qualifiers :+ [p]
					End If
				Next
			End If

			If qualifiers = Null Or qualifiers.Length = 0 Then
				Continue
			End If

			Local contribution:TStageInputState = New TStageInputState
			contribution.sourceStageId = source.id
			For Local p:TParticipant = EachIn qualifiers
				If p <> Null And Not HasInt(contribution.entrantIds, p.id) Then
					contribution.entrantIds :+ [p.id]
				End If
			Next

			If seeded <> Null Then
				For Local rank:Int = 1 To contribution.entrantIds.Length
					contribution.seedRanks :+ [rank]
				Next
			Else
				For Local pid:Int = EachIn contribution.entrantIds
					contribution.seedRanks :+ [InputSeed(sourceState, pid)]
				Next
			End If

			If route <> Null And route.mapping <> Null Then
				contribution.slotIds = RoutedSlots(route.mapping, contribution.entrantIds, sourceState, comp.stages[targetIndex])
				contribution.reseed = route.mapping.mode = EAdvMappingMode.Seeded
			End If

			targetState.inputs :+ [contribution]
			Local ready:Int = True
			For Local required:String = EachIn sources
				Local received:Int = False
				For Local input:TStageInputState = EachIn targetState.inputs
					If input.sourceStageId = required Then received = True; Exit
				Next

				If Not received Then ready = False; Exit
			Next

			If Not ready Then
				Continue
			End If

			Local entrants:TParticipant[]
			Local ids:Int[]
			For Local input:TStageInputState = EachIn targetState.inputs
				For Local pid:Int = EachIn input.entrantIds
					If Not HasInt(ids, pid) Then
						ids :+ [pid]
						entrants :+ [GetParticipant(comp, pid)]
					End If
				Next
			Next

			If Not ShouldStartStage(comp, state, targetIndex, sourceIndex) Then
				targetState.status = EStageStatus.Skipped
				Continue
			End If

			StartStage(comp, state, targetIndex, entrants)
		Next
	End Method

	Method ShouldStartStage:Int(comp:TCompetition, state:TCompetitionState, targetIndex:Int, sourceIndex:Int)
		Local activation:TStageActivation = comp.stages[targetIndex].activation
		If activation = Null Or activation.kind = EStageActivationKind.Always Then
			Return True
		End If

		Select activation.kind
			Case EStageActivationKind.IfReferenceEntrantLoses
				Local source:TStage = comp.stages[sourceIndex]
				Local sourceState:TStageState = state.stages[sourceIndex]
				If source.stageType <> EStageType.Bracket Then
					Throw "Reference-entrant activation needs a bracket source"
				End If

				Local reference:Int = 0
				For Local input:TStageInputState = EachIn sourceState.inputs
					If input.sourceStageId = activation.referenceSourceId Then
						If input.entrantIds.Length <> 1 Then
							Throw "Reference source must contribute one entrant"
						End If

						reference = input.entrantIds[0]
						Exit
					End If
				Next

				If reference = 0 Then
					Throw "Reference source was not received by the bracket"
				End If

				Local resolver:TBracketAdvancer = New TBracketAdvancer
				Local winners:Int[] = resolver.DetermineWinners(comp, source, sourceState, 1)
				If winners.Length <> 1 Then
					Throw "Conditional bracket has no winner"
				End If

				Return winners[0] <> reference
		End Select

		Throw "Unknown stage activation rule"
	End Method

	Method GetParticipant:TParticipant(comp:TCompetition, id:Int)
		For Local p:TParticipant = EachIn comp.participants
			If p.id = id Then
				Return p
			End If
		Next

		Return Null
	End Method

	' Resolve promotion, relegation, and playoff places into next-season moves.
	' This is a projection: callers decide when to create the next competition.
	Rem
	bbdoc: Projects promotion and relegation into next-season division moves.
	param: Competition definition with transition rules.
	param: Completed playing state.
	returns: Selected #TSeasonMovement records.
	about: The definition and participants are not changed; the caller creates the next season.
	End Rem
	Method ResolveSeasonMovements:TSeasonMovement[](comp:TCompetition, state:TCompetitionState)
		Local moves:TSeasonMovement[]
		For Local rule:TSeasonTransitionRule = EachIn comp.seasonTransitions
			Local stageIndex:Int = FindStageIndex(state, rule.fromStageId)
			If stageIndex < 0 Then
				Throw "Unknown season transition stage: " + rule.fromStageId
			End If

			Local ss:TStageState = state.stages[stageIndex]
			If ss.status <> EStageStatus.Complete Then
				Throw "Season transition stage is unfinished: " + rule.fromStageId
			End If

			If rule.destinationDivisionId = "" Or rule.selection = Null Then
				Throw "Season transition needs a destination and selection"
			End If

			Local rows:TLeaderboardRow[] = ss.leaderboard.rows
			If rule.championshipCode <> "" Then
				If comp.stages[stageIndex].stageType <> EStageType.Series Then
					Throw "Named championship movement needs a series stage"
				End If

				rows = Null
				For Local named:TNamedLeaderboard = EachIn ss.championships
					If named.code = rule.championshipCode Then rows = named.leaderboard.rows; Exit
				Next

				If rows = Null Then
					Throw "Unknown championship for season movement: " + rule.championshipCode
				End If
			End If

			Local selected:Int[]
			Local filter:TFilterRule = rule.selection
			Select filter.kind
				Case EFilterKind.TopN, EFilterKind.ByRank
					Local start:Int = Max(0, filter.startRank - 1)
					If filter.kind = EFilterKind.ByRank And filter.startRank = 0 Then
						start = Max(0, filter.n - 1)
					End If

					Local count:Int = filter.n
					If filter.kind = EFilterKind.ByRank Then
						count = 1
					End If

					For Local i:Int = start Until Min(start + count, rows.Length)
						selected :+ [rows[i].participantId]
					Next
				Case EFilterKind.BottomN
					For Local i:Int = rows.Length - 1 To Max(0, rows.Length - filter.n) Step -1
						selected :+ [rows[i].participantId]
					Next
				Case EFilterKind.Winner
					If rule.championshipCode <> "" Then
						If rows.Length > 0 Then
							selected :+ [rows[0].participantId]
						End If
					Else
						Local adv:IStageAdvancer = GetAdvancerForStage(comp.stages[stageIndex])
						If adv = Null Then
							Throw "Winner selection needs an advancer for stage: " + rule.fromStageId
						End If

						For Local p:TParticipant = EachIn adv.ProduceAdvancements(comp, comp.stages[stageIndex], ss)
							selected :+ [p.id]
						Next
					End If
				Case EFilterKind.All
					For Local row:TLeaderboardRow = EachIn rows
						selected :+ [row.participantId]
					Next
				Default
					Throw "Unsupported season transition selector"
			End Select

			If filter.kind = EFilterKind.TopN Or filter.kind = EFilterKind.ByRank Or filter.kind = EFilterKind.BottomN Or (filter.kind = EFilterKind.Winner And rule.championshipCode <> "") Then
				For Local i:Int = 0 Until rows.Length
					For Local j:Int = i + 1 Until rows.Length
						Local first:TLeaderboardRow = rows[i]
						Local second:TLeaderboardRow = rows[j]
						If first.sportingRank > 0 And first.sportingRank = second.sportingRank And HasInt(selected, first.participantId) <> HasInt(selected, second.participantId) Then
							Throw "Season movement crosses an unresolved sporting tie in " + rule.fromStageId
						End If
					Next
				Next
			End If

			For Local pid:Int = EachIn selected
				For Local existing:TSeasonMovement = EachIn moves
					If existing.participantId = pid Then
						Throw "Participant has more than one season movement: " + pid
					End If
				Next

				Local participant:TParticipant = GetParticipant(comp, pid)
				If participant = Null Then
					Throw "Unknown season transition participant: " + pid
				End If

				Local movement:TSeasonMovement = New TSeasonMovement
				movement.participantId = pid
				movement.fromDivisionId = participant.divisionId
				movement.toDivisionId = rule.destinationDivisionId
				movement.sourceStageId = rule.fromStageId
				moves :+ [movement]
			Next
		Next

		Return moves
	End Method

	Method ValidateResult(ss:TStageState, fixture:TFixtureState, result:TResultPayload)
		Select result.kind
			Case EResultKind.HeadToHeadScore
				If result.scoreHome < 0 Or result.scoreAway < 0 Then
					Throw "Scores cannot be negative"
				End If
			Case EResultKind.SetBased
				If result.sets = Null Or result.sets.Length = 0 Then
					Throw "Set result is empty"
				End If
			Case EResultKind.Classification
				If result.order = Null Or result.order.Length = 0 Then
					Throw "Classification is empty"
				End If

				Local seen:Int[]
				For Local pid:Int = EachIn result.order
					If Not HasInt(ss.entrants, pid) Then
						Throw "Unknown classification entrant: " + pid
					End If

					If HasInt(seen, pid) Then
						Throw "Duplicate classification entrant: " + pid
					End If

					seen :+ [pid]
				Next
			Case EResultKind.TimeBased
				If result.times = Null Or result.times.Length = 0 Then
					Throw "Timed result is empty"
				End If

				Local seen:Int[]
				For Local t:TParticipantTime = EachIn result.times
					If HasInt(seen, t.participantId) Then
						Throw "Duplicate timed entrant: " + t.participantId
					End If

					seen :+ [t.participantId]
				Next
		End Select
	End Method

	Method ApplyAdjustmentsOverlayToLeaderboard(ss:TStageState, stage:TStage = Null)
		If ss.leaderboard = Null Or ss.leaderboard.rows = Null Then
			Return
		End If

		If ss.adjustments = Null Or ss.adjustments.Length = 0 Then
			Return
		End If

		' build quick index: participantId -> row
		Local rows:TLeaderboardRow[] = ss.leaderboard.rows
		Function RowFor:TLeaderboardRow(id:Int, rows:TLeaderboardRow[])
			For Local r:TLeaderboardRow = EachIn rows
				If r.participantId = id Then
					Return r
				End If
			Next

			Return Null
		End Function

		For Local a:TPointAdjustment = EachIn ss.adjustments
			Local r:TLeaderboardRow = RowFor(a.participantId, rows)
			If r <> Null Then
				If a.pointsDeltaExact <> "" Then
					If stage = Null Or TSeriesConfig(stage.config) = Null Then
						Throw "Exact adjustments require a series stage"
					End If

					r.points :+ ExactPointUnits(a.pointsDeltaExact, TSeriesConfig(stage.config).pointsScale)
				Else
					r.points :+ a.pointsDelta
				End If
			End If
		Next
	End Method

	Method RankAdjustedSeriesMain(comp:TCompetition, stage:TStage, ss:TStageState)
		If stage.formatCode <> "" Or stage.stageType <> EStageType.Series Or ss.adjustments = Null Or ss.adjustments.Length = 0 Then
			Return
		End If

		Local cfg:TSeriesConfig = TSeriesConfig(stage.config)
		If cfg = Null Or cfg.scoring = Null Or cfg.scoring.mode <> EScoringMode.PositionTable Then
			Return
		End If

		TSeriesRanker.SortRows(ss.leaderboard.rows, TSeriesRanker.Build(comp, stage, ss, Null, ss.leaderboard.rows), ss.tableTieDecisions)
	End Method

	Method ApplyAdjustmentsToState(ss:TStageState, adjustments:TPointAdjustment[])
		StoreAdjustments(ss, adjustments)
		ApplyAdjustmentsOverlayToLeaderboard(ss)
	End Method

	' RecordResult uses this before recomputing the table, then overlays once.
	Method StoreAdjustments(ss:TStageState, adjustments:TPointAdjustment[])
		If adjustments = Null Or adjustments.Length = 0 Then
			Return
		End If

		' Store them
		If ss.adjustments = Null Then
			ss.adjustments = []
		End If

		For Local a:TPointAdjustment = EachIn adjustments
			ss.adjustments :+ [a]
		Next

	End Method

	Method MarkFixtureStatus(ss:TStageState, fixtureId:String, statusCode:EFixtureStatus)
		If ss = Null Or ss.fixtures = Null Then
			Return
		End If

		' ' Normalize a few common inputs
		' Local code:String = statusCode.Trim().ToLower()
		' Select code
		' 	Case "scheduled", "final", "postponed", "abandoned", "cancelled", "canceled", "walkover", "wo"
		' 		' ok
		' 	Default
		' 		' If unknown, keep as-is but don’t error
		' End Select
		' If code = "canceled" Then
		' 	code = "cancelled"
		' End If
		' If code = "wo" Then
		' 	code = "walkover"
		' End If

		For Local f:TFixtureState = EachIn ss.fixtures
			If f.id = fixtureId Then
				f.status = statusCode
				Exit
			End If
		Next
	End Method

	' Builds a temporary competition object with only given entrants (used to build fixtures of next stage quickly)
	Method WithTempEntrants:TCompetition(comp:TCompetition, entrants:TParticipant[])
		Local c:TCompetition = New TCompetition
		c.name = comp.name
		c.participants = entrants
		c.stages = comp.stages
		Return c
	End Method

	Rem
	bbdoc: Returns the next fixture in the competition state that is scheduled and has assigned teams.
	param: Competition definition for participant names.
	param: Current playing state.
	param: Optional filters; the query limit is set to one.
	returns: The next #TPlayableFixture, or #Null when none is available.
	End Rem
	Method NextFixture:TPlayableFixture(comp:TCompetition, state:TCompetitionState, opts:TPlayableQuery = Null)
		Local q:TPlayableQuery = opts
		If q = Null Then
			q = New TPlayableQuery
		End If

		q.limit = 1

		Local list:TList = GetPlayableFixtures(comp, state, q)
		If list And list.Count() > 0 Then
			Return TPlayableFixture(list.First())
		End If

		Return Null
	End Method

	' Return the current round’s playable fixtures (optionally filtered)
	Rem
	bbdoc: Returns currently playable fixtures according to a query.
	param: Competition definition for participant names.
	param: Current playing state.
	param: Optional filters, time requirements, and result limit.
	returns: A list of #TPlayableFixture values for the earliest unfinished round.
	about: If no stage is specified, the query uses the earliest stage with unfinished fixtures.
	End Rem
	Method GetPlayableFixtures:TList(comp:TCompetition, state:TCompetitionState, opts:TPlayableQuery)
		If opts = Null Then
			opts = New TPlayableQuery
		End If

		Local now:Long = CurrentTimeMillis()
		Local playable:TList = New TList

		' 1) Choose which stage to surface:
		Local targetStage:TStageState = Null
		If opts.stageId <> "" Then
			targetStage = FindStageById(state, opts.stageId)
		Else
			targetStage = EarliestStageWithUnfinishedFixtures(state)
		End If

		If targetStage = Null Then
			Return playable  ' nothing to play
		End If

		' 2) Determine the “current” round in that stage (earliest unfinished round)
		Local currentRound:Int = EarliestUnfinishedRound(targetStage)
		If currentRound = 0 Then
			Return playable
		End If

		' 3) Collect playable fixtures in that round
		For Local fx:TFixtureState = EachIn targetStage.fixtures
			If Not IsFixturePlayable(fx, currentRound, now, opts) Then
				Continue
			End If

			Local p:TPlayableFixture = New TPlayableFixture
			p.stageId = targetStage.stageId
			p.fixtureId = fx.id
			p.round = fx.round
			p.groupId = fx.groupKey
			p.homeId = fx.homeTeamId
			p.awayId = fx.awayTeamId
			p.home = GetParticipantNameById(comp, fx.homeTeamId)
			p.away = GetParticipantNameById(comp, fx.awayTeamId)
			p.status = fx.status
			p.slotId = fx.slotId
			p.slotTime = LookupSlotTime(state, targetStage.stageId, fx.round)
			playable.AddLast(p)
		Next

		' 4) Stable sort: by time (unslotted last), then group, then id
		playable.Sort(True, PlayableCompare)

		' 5) Limit if asked
		If opts.limit > 0 And playable.Count() > opts.limit Then
			Local trimmed:TList = New TList
			Local i:Int = 0
			For Local it:TPlayableFixture = EachIn playable
				trimmed.AddLast(it)
				i :+ 1
				If i = opts.limit Then
					Exit
				End If
			Next

			Return trimmed
		End If

		Return playable
	End Method

	Method GetParticipantNameById:String(comp:TCompetition, id:Int)
		For Local p:TParticipant = EachIn comp.participants
			If p.id = id Then
				Return p.name
			End If
		Next

		Return ""
	End Method

	Function LookupSlotTime:Long(state:TCompetitionState, stageId:String, round:Int)
		' If state = Null Or state.calendar = Null Or state.calendar.slots = Null Then Return 0
		' For Local s:TCalendarSlot = EachIn state.calendar.slots
		' 	If s.stageId = stageId And s.round = round Then
		' 		Return s.timeMillis
		' 	EndIf
		' Next
		Return 0
	End Function

	Function FindStageById:TStageState(state:TCompetitionState, sid:String)
		If state = Null Or state.stages = Null Then
			Return Null
		End If

		For Local st:TStageState = EachIn state.stages
			If st And st.stageId = sid Then
				Return st
			End If
		Next

		Return Null
	End Function

	Function EarliestStageWithUnfinishedFixtures:TStageState(state:TCompetitionState)
		If state = Null Or state.stages = Null Then
			Return Null
		End If

		For Local st:TStageState = EachIn state.stages
			If StageHasUnfinishedFixtures(st) Then
				Return st
			End If
		Next

		Return Null
	End Function

	Function StageHasUnfinishedFixtures:Int(st:TStageState)
		If st = Null Or st.fixtures = Null Then
			Return False
		End If

		For Local fx:TFixtureState = EachIn st.fixtures
			Select fx.status
				Case EFixtureStatus.Scheduled, EFixtureStatus.InProgress, EFixtureStatus.Postponed
					Return True
			End Select
		Next

		Return False
	End Function

	Function EarliestUnfinishedRound:Int(st:TStageState)
		If st = Null Or st.fixtures = Null Then
			Return 0
		End If

		Local minRound:Int = 2147483647
		Local found:Int = False
		For Local fx:TFixtureState = EachIn st.fixtures
			Select fx.status
				Case EFixtureStatus.Scheduled, EFixtureStatus.InProgress, EFixtureStatus.Postponed
					If fx.round < minRound Then
						minRound = fx.round
						found = True
					End If
			End Select
		Next

		If found Then
			Return minRound
		End If

		Return 0
	End Function

	Function IsFixturePlayable:Int(fx:TFixtureState, currentRound:Int, now:Long, opts:TPlayableQuery)
		' 1) status gate
		Select fx.status
			Case EFixtureStatus.Scheduled
			' ok
			Case EFixtureStatus.InProgress
			' allow resume (set to Return False if you don’t support resuming)
			Case EFixtureStatus.Postponed
				If opts.includePostponed = 0 Then
					Return False
				End If
			Default
				Return False   ' Completed/Cancelled/Forfeit/Abandoned
		End Select

		' 2) round gate
		If fx.round <> currentRound Then
			Return False
		End If

		' 3) teams assigned?
		If opts.requireAssignedTeams <> 0 Then
			If IsTbdTeam(fx.homeTeamId) Or IsTbdTeam(fx.awayTeamId) Then
				Return False
			End If
		End If

		' ' 4) time due?
		' If opts.onlyCurrentlyDue <> 0 Then
		' 	Local t:Long = GetSlotTimeMillis_NullSafe(fx.slotId) ' inline or call below
		' 	If t = 0 Or t > now Then
		' 		Return False
		' 	End If
		' End If

		Return True
	End Function

	Function PlayableCompare:Int(a:Object, b:Object)
		Local pa:TPlayableFixture = TPlayableFixture(a)
		Local pb:TPlayableFixture = TPlayableFixture(b)

		' by slot time (0 == unslotted → last)
		If pa.slotTime = 0 And pb.slotTime > 0 Then
			Return 1
		End If

		If pb.slotTime = 0 And pa.slotTime > 0 Then
			Return -1
		End If

		If pa.slotTime < pb.slotTime Then
			Return -1
		End If

		If pa.slotTime > pb.slotTime Then
			Return 1
		End If

		' by group
		If pa.groupId < pb.groupId Then
			Return -1
		End If

		If pa.groupId > pb.groupId Then
			Return 1
		End If

		' by fixture id (stable)
		If pa.fixtureId < pb.fixtureId Then
			Return -1
		End If

		If pa.fixtureId > pb.fixtureId Then
			Return 1
		End If

		Return 0
	End Function

	Function CurrentTimeMillis:ULong()
		Return CurrentUnixTime()
	End Function

	' Calendar lookup kept stateless: derive from state
	Function GetSlotTimeMillis:Long(state:TCompetitionState, slotId:String)
		' If slotId = "" Or state = Null Or state.calendar = Null Then Return 0
		' ' If you keep slots keyed by id, look up; if it’s a list, just iterate:
		' For Local s:TCalendarSlot = EachIn state.calendar.slots
		' 	If s.id = slotId Then
		' 		Return s.epochMillis
		' 	End If
		' Next
		Return 0
	End Function

	Function IsTbdTeam:Int(teamId:Int)
		Return teamId = -1
	End Function

End Type

Include "timeline.bmx"
Include "correction.bmx"
