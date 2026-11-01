' Complete 2026 men's World Cup: 12 fixed groups, eight best third-place
' qualifiers, a 32-team knockout tree, bronze match and final.
Type TWorldCup2026Match
	Field number:Int
	Field phase:String
	Field date:String
	Field homeId:Int
	Field awayId:Int
	Field homeGoals:Int
	Field awayGoals:Int
	Field homePenalties:Int
	Field awayPenalties:Int
	Field extraTime:Int
End Type

Type TWorldCup2026Replay
	Function StageState:TStageState(state:TCompetitionState, id:String)
		For Local stage:TStageState = EachIn state.stages
			If stage.stageId = id Then
				Return stage
			End If
		Next

		Throw "Missing World Cup stage: " + id
	End Function

	Function Fixture:TFixtureState(state:TCompetitionState, stageId:String, a:Int, b:Int)
		For Local fixture:TFixtureState = EachIn StageState(state, stageId).fixtures
			If fixture.status <> EFixtureStatus.Scheduled Then
				Continue
			End If

			If (fixture.homeTeamId = a And fixture.awayTeamId = b) Or (fixture.homeTeamId = b And fixture.awayTeamId = a) Then
				Return fixture
			End If
		Next

		Throw "World Cup fixture not scheduled: " + stageId + " " + a + " vs " + b
	End Function

	Function FindTeamId:Int(comp:TCompetition, name:String)
		For Local team:TParticipant = EachIn comp.participants
			If team.name = name Then
				Return team.id
			End If
		Next

		Throw "World Cup team missing: " + name
	End Function

	Function ThirdPlaceCases:TConditionalSlotCase[](path:String)
		Local source:TStream = ReadStream(path)
		If source = Null Then
			Throw "Cannot read World Cup third-place allocation table: " + path
		End If

		Local choices:TConditionalSlotCase[]
		Local thirdSlots:Int[] = [22, 30, 14, 2, 16, 4, 32, 24]
		While Not source.Eof()
			Local line:String = source.ReadLine().Trim()
			If line = "" Or line.StartsWith("#") Then
				Continue
			End If

			Local fields:String[] = line.Split("|")
			If fields.Length <> 2 Or Int(fields[0]) <> choices.Length + 1 Or fields[1].Length <> 8 Then
				Throw "Invalid World Cup third-place allocation row"
			End If

			Local choice:TConditionalSlotCase = New TConditionalSlotCase
			For Local i:Int = 0 Until 8
				Local key:String = fields[1][i..i + 1]
				If "ABCDEFGHIJKL".Find(key) < 0 Then
					Throw "Unknown group in World Cup allocation"
				End If

				For Local existing:String = EachIn choice.qualifyingGroupKeys
					If existing = key Then
						Throw "Duplicate group in World Cup allocation"
					End If
				Next

				choice.qualifyingGroupKeys :+ [key]
				Local assignment:TGroupRankSlot = New TGroupRankSlot
				assignment.groupKey = key
				assignment.rank = 3
				assignment.slotId = String(thirdSlots[i])
				choice.assignments :+ [assignment]
			Next

			For Local previous:TConditionalSlotCase = EachIn choices
				Local same:Int = True
				For Local key:String = EachIn choice.qualifyingGroupKeys
					Local found:Int = False
					For Local oldKey:String = EachIn previous.qualifyingGroupKeys
						If oldKey = key Then found = True; Exit
					Next

					If Not found Then same = False; Exit
				Next

				If same Then
					Throw "Duplicate World Cup third-place combination"
				End If
			Next

			choices :+ [choice]
		Wend

		source.Close()
		If choices.Length <> 495 Then
			Throw "Incomplete World Cup third-place allocation table"
		End If

		Return choices
	End Function

	Function Run:Int(path:String, timeline:TCompetitionTimeline = Null, thirdPlacePath:String = "")
		Local source:TStream = ReadStream(path)
		If source = Null Then
			Throw "Cannot read World Cup data: " + path
		End If

		Local builder:TCompetitionBuilder = New TCompetitionBuilder("2026 FIFA World Cup")
		Local groups:TPresetGroup[] = New TPresetGroup[12]
		For Local i:Int = 0 Until 12
			groups[i] = New TPresetGroup
			groups[i].code = "ABCDEFGHIJKL"[i..i + 1]
		Next

		Local fixedAssignments:TGroupRankSlot[]
		Local usedSlots:Int[]
		Local qualifierIds:Int[] = New Int[32]
		Local matches:TWorldCup2026Match[]
		While Not source.Eof()
			Local line:String = source.ReadLine().Trim()
			If line = "" Or line.StartsWith("#") Then
				Continue
			End If

			Local fields:String[] = line.Split("|")
			Select fields[0]
				Case "T"
					If fields.Length <> 4 Then
						Throw "Invalid World Cup team row"
					End If

					Local team:TParticipant = New TParticipant
					team.id = Int(fields[1])
					team.name = fields[2]
					team.kind = EParticipantKind.Team
					team.divisionId = fields[3]
					Local groupIndex:Int = fields[3][0] - 65
					If groupIndex < 0 Or groupIndex >= 12 Then
						Throw "Invalid World Cup group"
					End If

					Local preset:TPresetGroup = groups[groupIndex]
					preset.participantIds :+ [team.id]
					builder.AddParticipant(team)
				Case "B"
					If fields.Length <> 4 Then
						Throw "Invalid World Cup bracket slot"
					End If

					Local slot:Int = Int(fields[1])
					If slot < 1 Or slot > 32 Then
						Throw "Invalid World Cup bracket slot"
					End If

					For Local used:Int = EachIn usedSlots
						If used = slot Then
							Throw "Duplicate World Cup bracket slot"
						End If
					Next

					usedSlots :+ [slot]
					Local assignment:TGroupRankSlot = New TGroupRankSlot
					assignment.groupKey = fields[2]
					assignment.rank = Int(fields[3])
					assignment.slotId = String(slot)
					fixedAssignments :+ [assignment]
				Case "Q"
					If fields.Length <> 3 Then
						Throw "Invalid World Cup qualifier row"
					End If

					Local position:Int = Int(fields[1])
					If position < 1 Or position > 32 Or qualifierIds[position - 1] <> 0 Then
						Throw "Invalid or duplicate World Cup qualifier order"
					End If

					qualifierIds[position - 1] = Int(fields[2])
				Case "M"
					If fields.Length <> 11 Then
						Throw "Invalid World Cup match row"
					End If

					Local match:TWorldCup2026Match = New TWorldCup2026Match
					match.number = Int(fields[1])
					match.phase = fields[2]
					match.date = fields[3]
					match.homeId = Int(fields[4])
					match.awayId = Int(fields[5])
					match.homeGoals = Int(fields[6])
					match.awayGoals = Int(fields[7])
					match.homePenalties = Int(fields[8])
					match.awayPenalties = Int(fields[9])
					match.extraTime = Int(fields[10])
					If match.number <> matches.Length + 1 Then
						Throw "World Cup matches must be in result order"
					End If

					matches :+ [match]
				Default
					Throw "Unknown World Cup data row"
			End Select
		Wend

		source.Close()
		If builder.competition.participants.Length <> 48 Or matches.Length <> 104 Then
			Throw "Incomplete World Cup data"
		End If

		If fixedAssignments.Length <> 24 Then
			Throw "Incomplete World Cup fixed bracket slots"
		End If

		For Local id:Int = EachIn qualifierIds
			If id = 0 Then
				Throw "Incomplete World Cup qualification order"
			End If
		Next

		Local groupRules:TGroupConfig = New TGroupConfig
		groupRules.groups = 12
		groupRules.groupSize = 4
		groupRules.roundRobinPerOpponent = 1
		groupRules.presetGroups = groups
		groupRules.tiebreakers = [ETiebreaker.Points, ETiebreaker.GoalDifference, ETiebreaker.GoalsFor, ETiebreaker.HeadToHeadPoints, ETiebreaker.HeadToHeadGD]
		builder.AddStage("GROUPS", EStageType.Group, groupRules)
		Local options:TEliminationTreeOptions = New TEliminationTreeOptions
		options.idPrefix = "WORLD_CUP"
		options.size = 32
		options.kind = EEliminationTreeKind.SingleElimination
		options.thirdPlace = True
		options.fromStageId = "GROUPS"
		options.matchFormat = New TMatchFormat
		options.matchFormat.extraTimeMinutes = 30
		options.matchFormat.penalties = True
		Local tree:TEliminationTree = New TEliminationTreeBuilder.Append(builder.competition, options)
		Local topTwo:TFilterRule = New TFilterRule
		topTwo.kind = EFilterKind.TopN
		topTwo.n = 2
		topTwo.scope = EFilterScope.PerGroup
		Local bestThird:TFilterRule = New TFilterRule
		bestThird.kind = EFilterKind.BestXAcrossGroups
		bestThird.n = 8
		bestThird.startRank = 3
		Local mapping:TAdvancementMapping = New TAdvancementMapping
		mapping.mode = EAdvMappingMode.ConditionalSlots
		mapping.qualifyingRank = 3
		mapping.baseAssignments = fixedAssignments
		If thirdPlacePath = "" Then
			thirdPlacePath = path.Replace("world_cup_2026.tsv", "world_cup_2026_third_place.tsv")
		End If

		mapping.conditionalCases = ThirdPlaceCases(thirdPlacePath)
		builder.ConnectRules("GROUPS", tree.winnerRounds[0], [topTwo, bestThird], mapping)
		Local comp:TCompetition = builder.Build()
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Group, New TGroupScheduler)
		engine.RegisterScorer(EStageType.Group, New TGroupScorer)
		engine.RegisterAdvancer(EStageType.Group, New TGroupAdvancer)
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)
		If timeline <> Null Then
			engine.AddResultObserver(timeline)
		End If

		Local state:TCompetitionState = engine.Initialize(comp)
		If state.stages[0].fixtures.Length <> 72 Then
			Throw "World Cup group schedule needs 72 matches"
		End If

		For Local match:TWorldCup2026Match = EachIn matches
			Local stageId:String = "GROUPS"
			Select match.phase
				Case "R32"; stageId = tree.winnerRounds[0]
				Case "R16"; stageId = tree.winnerRounds[1]
				Case "QF"; stageId = tree.winnerRounds[2]
				Case "SF"; stageId = tree.winnerRounds[3]
				Case "THIRD"; stageId = tree.thirdPlaceStageId
				Case "FINAL"; stageId = tree.finalStageId
				Case "GROUP"
				Default; Throw "Unknown World Cup phase: " + match.phase
			End Select

			Local fixture:TFixtureState = Fixture(state, stageId, match.homeId, match.awayId)
			Local payload:TResultPayload = New TResultPayload
			payload.kind = EResultKind.HeadToHeadScore
			payload.afterExtraTime = match.extraTime
			If fixture.homeTeamId = match.homeId Then
				payload.scoreHome = match.homeGoals
				payload.scoreAway = match.awayGoals
				payload.penaltiesHome = match.homePenalties
				payload.penaltiesAway = match.awayPenalties
			Else
				payload.scoreHome = match.awayGoals
				payload.scoreAway = match.homeGoals
				payload.penaltiesHome = match.awayPenalties
				payload.penaltiesAway = match.homePenalties
			End If

			engine.RecordResult(comp, state, stageId, fixture.id, payload)
			If match.number = 72 Then
				Local entrants:Int[] = StageState(state, tree.winnerRounds[0]).entrants
				If entrants.Length <> 32 Then
					Throw "Wrong World Cup knockout field size"
				End If

				For Local i:Int = 0 Until 32
					If StageState(state, tree.winnerRounds[0]).inputs[0].entrantIds[i] <> qualifierIds[i] Then
						Throw "World Cup qualifier order differs at " + (i + 1) + ": expected " + qualifierIds[i] + ", got " + StageState(state, tree.winnerRounds[0]).inputs[0].entrantIds[i]
					End If
				Next
			End If
		Next

		If timeline <> Null And timeline.frames.Length <> 104 Then
			Throw "Incomplete World Cup timeline"
		End If

		Local champion:Int = tree.ChampionId(comp, state)
		If champion <> FindTeamId(comp, "Spain") Then
			Throw "Wrong World Cup champion"
		End If

		Local bronze:Int = tree.DecidingParticipant(comp, state, tree.thirdPlaceStageId, True)
		If bronze <> FindTeamId(comp, "England") Then
			Throw "Wrong World Cup bronze winner"
		End If

		For Local stage:TStageState = EachIn state.stages
			If stage.status <> EStageStatus.Complete Then
				Throw "Unfinished World Cup stage: " + stage.stageId
			End If
		Next

		Return champion
	End Function
End Type
