Rem
bbdoc: Builds a #TCompetition from participants, stages, and advancement routes.
about: The builder is an authoring convenience. #BuildChecked returns ordinary serializable model objects; the builder itself is not part of the saved definition or playing state.
End Rem
Type TCompetitionBuilder
	Rem
	bbdoc: #TCompetition value used by this competition builder.
	End Rem
	Field competition:TCompetition

	Rem
	bbdoc: Starts a builder for a competition named @name.
	param: The name stored in the resulting competition definition.
	End Rem
	Method New(name:String)
		competition = New TCompetition
		competition.name = name
	End Method

	Rem
	bbdoc: Adds a participant to the definition.
	param: Participant with a unique ID.
	End Rem
	Method AddParticipant(participant:TParticipant)
		If participant = Null Then
			Throw "Cannot add a null participant"
		End If

		For Local existing:TParticipant = EachIn competition.participants
			If existing.id = participant.id Then
				Throw "Duplicate participant id: " + participant.id
			End If
		Next

		competition.participants :+ [participant]
	End Method

	Rem
	bbdoc: Adds a built-in or custom stage.
	param: Unique stage ID.
	param: Built-in stage type.
	param: Serializable stage configuration.
	param: Registered custom format code, or empty for a built-in format.
	returns: The new #TStage for further configuration.
	End Rem
	Method AddStage:TStage(id:String, stageType:EStageType, config:TConfig, formatCode:String = "")
		Local stage:TStage = New TStage
		stage.id = id
		stage.stageType = stageType
		stage.config = config
		stage.formatCode = formatCode
		' Explicit connections determine dependencies; separate roots can coexist.
		stage.independent = True
		AppendStage(stage)
		Return stage
	End Method

	Rem
	bbdoc: Adds a round-robin group stage to the competition.
	param: A unique stage ID used by results and advancement routes.
	param: The number of groups to create.
	param: The number of entrants in each group.
	param: How many times each pair plays; defaults to one.
	returns: The new #TStage, which can be configured further before building.
	End Rem
	Method AddGroups:TStage(id:String, count:Int, size:Int, gamesPerOpponent:Int = 1)
		Return AddStage(id, EStageType.Group, TTourneyAuthoring.Groups(count, size, gamesPerOpponent))
	End Method

	Rem
	bbdoc: Adds a power-of-two knockout stage.
	param: Unique stage ID.
	param: Number of bracket positions.
	param: Odd best-of match count; one for single matches.
	returns: The new #TStage.
	End Rem
	Method AddBracket:TStage(id:String, size:Int, bestOfMatches:Int = 1)
		Return AddStage(id, EStageType.Bracket, TTourneyAuthoring.Bracket(size, bestOfMatches))
	End Method

	Rem
	bbdoc: Adds a multi-event series stage.
	param: Unique stage ID.
	param: Events and their sessions.
	param: Scoring rules shared by the events.
	param: Stored units per point, allowing exact fractions.
	returns: The new #TStage.
	End Rem
	Method AddSeries:TStage(id:String, events:TSeriesEvent[], scoring:TScoringSystem, pointsScale:Int = 1)
		Return AddStage(id, EStageType.Series, TTourneyAuthoring.Series(events, scoring, pointsScale))
	End Method

	' Keep specialised stages (including tree-builder output) expressible unchanged.
	Rem
	bbdoc: Adds an already configured stage to the definition.
	param: Stage with a unique, nonempty ID.
	about: Use this for specialised stages or stages created by an elimination tree builder.
	End Rem
	Method AppendStage(stage:TStage)
		If stage = Null Or stage.id = "" Then
			Throw "A stage needs an id"
		End If

		If FindStage(stage.id) <> Null Then
			Throw "Duplicate stage id: " + stage.id
		End If

		competition.stages :+ [stage]
	End Method

	Rem
	bbdoc: Looks up a stage already added to this builder.
	param: Stage ID to find.
	returns: The matching #TStage, or #Null.
	End Rem
	Method FindStage:TStage(id:String)
		For Local stage:TStage = EachIn competition.stages
			If stage.id = id Then
				Return stage
			End If
		Next

		Return Null
	End Method

	' Create a route and an explicit target dependency in one operation.
	' Supply the existing filter/outcome/mapping types for sport-specific rules.
	Rem
	bbdoc: Connects two stages with a selection rule or outcome.
	param: Source stage ID.
	param: Destination stage ID.
	param: Selection rule for routed entrants, if any.
	param: Bracket outcome to route; defaults to selected entrants.
	param: Optional draw placement at the destination.
	returns: The created #TAdvancement route.
	about: The connection also records the destination's dependency on the source.
	End Rem
	Method Connect:TAdvancement(sourceId:String, targetId:String, rule:TFilterRule = Null, outcome:EAdvancementOutcome = EAdvancementOutcome.Selected, mapping:TAdvancementMapping = Null)
		Local source:TStage = FindStage(sourceId)
		Local target:TStage = FindStage(targetId)
		If source = Null Then
			Throw "Unknown source stage: " + sourceId
		End If

		If target = Null Then
			Throw "Unknown destination stage: " + targetId
		End If

		If sourceId = targetId Then
			Throw "A stage cannot feed itself: " + sourceId
		End If

		If rule = Null And outcome = EAdvancementOutcome.Selected Then
			Throw "Connection needs a selection rule or outcome: " + sourceId + " -> " + targetId
		End If

		For Local existing:TAdvancement = EachIn source.advancement
			If existing.toStageId = targetId Then
				Throw "Duplicate advancement destination from stage " + sourceId + ": " + targetId
			End If
		Next

		Local route:TAdvancement = New TAdvancement
		route.toStageId = targetId
		route.rule = rule
		route.outcome = outcome
		route.mapping = mapping
		AddDependency(target, sourceId)
		source.advancement :+ [route]
		Return route
	End Method

	Rem
	bbdoc: Combines ordered selection rules into one destination route.
	param: Source stage ID.
	param: Destination stage ID.
	param: Nonempty selection rules evaluated for this route.
	param: Optional destination draw placement.
	returns: The created #TAdvancement route.
	End Rem
	Method ConnectRules:TAdvancement(sourceId:String, targetId:String, rules:TFilterRule[], mapping:TAdvancementMapping = Null)
		If rules = Null Or rules.Length = 0 Then
			Throw "Connection needs at least one selection rule"
		End If

		For Local rule:TFilterRule = EachIn rules
			If rule = Null Then
				Throw "Connection selection rule is missing"
			End If
		Next

		Local route:TAdvancement = Connect(sourceId, targetId, rules[0], EAdvancementOutcome.Selected, mapping)
		route.rules = rules[..]
		Return route
	End Method

	Rem
	bbdoc: Routes the top-ranked entrants from one stage to another.
	param: The ID of the stage whose standings select the entrants.
	param: The ID of the destination stage.
	param: The number of entrants selected from each @scope.
	param: Whether selection uses the whole table or separate groups; defaults to the whole table.
	param: The first rank to select, starting at one; defaults to one.
	returns: The created #TAdvancement route.
	about: The route also makes the destination depend on the source stage. For a groups-to-final competition, use @scope with `PerGroup` to select a winner from each group.
	End Rem
	Method ConnectTop:TAdvancement(sourceId:String, targetId:String, count:Int, scope:EFilterScope = EFilterScope.All, startRank:Int = 1)
		Return Connect(sourceId, targetId, TTourneyAuthoring.Top(count, scope, startRank))
	End Method

	Rem
	bbdoc: Routes the best entrants at one rank across all source groups.
	param: Source group stage ID.
	param: Destination stage ID.
	param: One-based group rank to compare.
	param: Number of entrants to select.
	returns: The created #TAdvancement route.
	End Rem
	Method ConnectBestAtRankAcrossGroups:TAdvancement(sourceId:String, targetId:String, rank:Int, count:Int)
		Return Connect(sourceId, targetId, TTourneyAuthoring.BestAtRankAcrossGroups(rank, count))
	End Method

	Rem
	bbdoc: Routes a bracket winner or loser to another stage.
	param: Source stage ID.
	param: Destination stage ID.
	param: Outcome to route; selected entrants require a selection rule.
	returns: The created #TAdvancement route.
	End Rem
	Method ConnectOutcome:TAdvancement(sourceId:String, targetId:String, outcome:EAdvancementOutcome)
		If outcome = EAdvancementOutcome.Selected Then
			Throw "Use a selection rule for a selected-entrant route"
		End If

		Return Connect(sourceId, targetId, Null, outcome)
	End Method

	' For a destination that performs its own selection, such as a league
	' postseason pool. It passes the source to that existing input mechanism.
	Rem
	bbdoc: Makes a destination wait for a source without adding a selection route.
	param: Source stage ID.
	param: Destination stage ID.
	about: Useful when the destination performs its own entrant selection, such as a league postseason pool.
	End Rem
	Method DependOn(sourceId:String, targetId:String)
		Local source:TStage = FindStage(sourceId)
		Local target:TStage = FindStage(targetId)
		If source = Null Then
			Throw "Unknown source stage: " + sourceId
		End If

		If target = Null Then
			Throw "Unknown destination stage: " + targetId
		End If

		If sourceId = targetId Then
			Throw "A stage cannot depend on itself: " + sourceId
		End If

		AddDependency(target, sourceId)
	End Method

	Method AddDependency(target:TStage, sourceId:String)
		If target.input = Null Then
			target.input = New TEntrySource
		End If

		If target.input.fromStageId = sourceId Then target.independent = False; Return

		For Local existing:String = EachIn target.input.fromStageIds
			If existing = sourceId Then target.independent = False; Return
		Next

		If target.input.fromStageId <> "" Then
			target.input.fromStageIds :+ [target.input.fromStageId]
			target.input.fromStageId = ""
		End If

		target.input.fromStageIds :+ [sourceId]
		If target.input.mode <> EEntryMode.SeededDraw Then
			target.input.mode = EEntryMode.FromStage
		End If

		target.independent = False
	End Method

	Rem
	bbdoc: Checks the stage graph and returns the definition.
	returns: The authored #TCompetition.
	about: Use #BuildChecked for additional built-in configuration preflight checks.
	End Rem
	Method Build:TCompetition()
		If competition.stages = Null Or competition.stages.Length = 0 Then
			Throw "A competition needs at least one stage"
		End If

		For Local i:Int = 0 Until competition.stages.Length
			Local stage:TStage = competition.stages[i]
			If stage = Null Or stage.id = "" Then
				Throw "Every stage needs an id"
			End If

			For Local j:Int = 0 Until i
				If competition.stages[j].id = stage.id Then
					Throw "Duplicate stage id: " + stage.id
				End If
			Next
		Next

		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.ValidateStageGraph(competition)
		Return competition
	End Method

	Rem
	bbdoc: Reports common authoring problems without changing the definition.
	returns: An array of #TAuthoringIssue values; empty when the preflight finds no issues.
	about: This preflight includes the stage graph checks performed by #Build, plus checks for common built-in configuration errors. Custom formats validate their own configurations.
	End Rem
	Method Check:TAuthoringIssue[]()
		Local issues:TAuthoringIssue[]
		Try
			Build()
		Catch problem:Object
			issues :+ [Issue("", "stages", problem.ToString())]
		End Try

		For Local stage:TStage = EachIn competition.stages
			If stage = Null Then
				Continue
			End If

			If stage.formatCode <> "" Then Continue ' custom formats validate their own config

			If stage.config = Null Then
				issues :+ [Issue(stage.id, "config", "Stage needs a configuration")]
				Continue
			End If

			Select stage.stageType
				Case EStageType.Group
					Local groups:TGroupConfig = TGroupConfig(stage.config)
					If groups = Null Then
						issues :+ [Issue(stage.id, "config", "Group stage needs TGroupConfig")]
					Else If groups.groups < 1 And (groups.presetGroups = Null Or groups.presetGroups.Length = 0) Then
						issues :+ [Issue(stage.id, "config.groups", "Group stage needs groups or a preset draw")]
					End If
				Case EStageType.Bracket
					Local bracket:TBracketConfig = TBracketConfig(stage.config)
					If bracket = Null Then
						issues :+ [Issue(stage.id, "config", "Bracket stage needs TBracketConfig")]
					Else If bracket.size < 2 Or (bracket.size & (bracket.size - 1)) <> 0 Then
						issues :+ [Issue(stage.id, "config.size", "Bracket size must be a power of two")]
					Else If bracket.matchFormat <> Null And bracket.matchFormat.bestOfMatches > 0 And bracket.matchFormat.bestOfMatches Mod 2 = 0 Then
						issues :+ [Issue(stage.id, "config.matchFormat.bestOfMatches", "Best-of matches must be odd")]
					End If
				Case EStageType.Swiss
					Local swiss:TSwissConfig = TSwissConfig(stage.config)
					If swiss = Null Then
						issues :+ [Issue(stage.id, "config", "Swiss stage needs TSwissConfig")]
					Else
						Try
							Local scheduler:TSwissScheduler = New TSwissScheduler
							scheduler.ValidateConfig(swiss)
						Catch problem:Object
							issues :+ [Issue(stage.id, "config", problem.ToString())]
						End Try
					End If
				Case EStageType.Series
					Local series:TSeriesConfig = TSeriesConfig(stage.config)
					If series = Null Then
						issues :+ [Issue(stage.id, "config", "Series stage needs TSeriesConfig")]
					Else
						If series.events = Null Or series.events.Length = 0 Then
							issues :+ [Issue(stage.id, "config.events", "Series needs at least one event")]
						End If

						Try
							TTourneyAuthoring.ValidateScoring(series.scoring, series.pointsScale)
							For Local event:TSeriesEvent = EachIn series.events
								If event = Null Or event.id = "" Then
									Throw "Series event needs an id"
								End If

								If event.pointsMultiplierExact <> "" Then
									Decimal(event.pointsMultiplierExact)
								End If

								For Local session:TSession = EachIn event.sessions
									If session = Null Or session.code = "" Then
										Throw "Series session needs a code"
									End If

									TTourneyAuthoring.ValidateScoring(session.scoringOverride, series.pointsScale)
								Next
							Next

							For Local championship:TChampionshipConfig = EachIn series.championships
								TTourneyAuthoring.ValidateScoring(championship.scoringOverride, series.pointsScale)
							Next
						Catch problem:Object
							issues :+ [Issue(stage.id, "config.points", problem.ToString())]
						End Try
					End If
				Case EStageType.League
					If TLeagueConfig(stage.config) = Null Then
						issues :+ [Issue(stage.id, "config", "League stage needs TLeagueConfig")]
					End If
			End Select
		Next

		Return issues
	End Method

	Rem
	bbdoc: Returns the definition after graph and authoring checks.
	returns: The built #TCompetition, ready for #TCompetitionEngine.Initialize.
	End Rem
	Method BuildChecked:TCompetition()
		Local issues:TAuthoringIssue[] = Check()
		If issues.Length > 0 Then
			Throw "Invalid competition definition at " + issues[0].fieldPath + ": " + issues[0].message
		End If

		Return Build()
	End Method

	Function Issue:TAuthoringIssue(stageId:String, fieldPath:String, message:String)
		Local issue:TAuthoringIssue = New TAuthoringIssue
		issue.stageId = stageId
		issue.fieldPath = fieldPath
		issue.message = message
		Return issue
	End Function
End Type
