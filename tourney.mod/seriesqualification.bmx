' Exact series analysis enumerates the classifications accepted by RecordResult:
' every non-empty ordered subset of the stage entrants is a possible result.
Rem
bbdoc: Remaining series session considered in a qualification search.
End Rem
Type TSeriesQualificationEvent
	Rem
	bbdoc: ID of the associated fixture.
	End Rem
	Field fixtureId:String
	Rem
	bbdoc: Points by position values associated with this series qualification event.
	End Rem
	Field pointsByPosition:Int[]
	Rem
	bbdoc: Number of back eligible for this series qualification event.
	about: One flag per ordered countback block.
	End Rem
	Field countbackEligible:Int[] ' one flag per ordered countback block
End Type

Rem
bbdoc: Explores remaining series points and countback outcomes.
End Rem
Type TSeriesQualificationSearch Extends TQualificationSearch
	Rem
	bbdoc: #TSeriesQualificationEvent entries associated with this series qualification search.
	End Rem
	Field events:TSeriesQualificationEvent[]
	Rem
	bbdoc: Entrant IDs associated with this series qualification search.
	End Rem
	Field entrantIds:Int[]
	Rem
	bbdoc: Target indices values associated with this series qualification search.
	End Rem
	Field targetIndices:Int[]
	Rem
	bbdoc: #TSeriesRankingData value used by this series qualification search.
	End Rem
	Field ranking:TSeriesRankingData
	Rem
	bbdoc: #TStringMap value used by this series qualification search.
	End Rem
	Field visited:TStringMap = New TStringMap
	Rem
	bbdoc: #TStringMap value used by this series qualification search.
	End Rem
	Field partialVisited:TStringMap = New TStringMap
	Rem
	bbdoc: Nodes visited for this series qualification search.
	End Rem
	Field nodesVisited:Long

	Method WithinNodeLimit:Int()
		nodesVisited :+ 1
		If nodesVisited > Max(Long(1000), Long(limit) * 20) Then exhausted = True; Return False

		Return True
	End Method

	Method StateKey:String(eventIndex:Int)
		Local key:String = String(eventIndex)
		For Local total:Long = EachIn points
			key :+ "|" + total
		Next

		For Local rule:ETiebreaker = EachIn ranking.rules
			Select rule
				Case ETiebreaker.Wins
					For Local i:Int = 0 Until ids.Length
						key :+ "|w" + ranking.blocks[0].counts[i][0]
					Next
				Case ETiebreaker.FinishCountback
					For Local block:TSeriesCountbackBlock = EachIn ranking.blocks
						For Local i:Int = 0 Until ids.Length
							For Local position:Int = EachIn block.positions
								key :+ "|c" + block.counts[i][position - 1]
							Next
						Next
					Next
			End Select
		Next

		Return key
	End Method

	Method CompareRanks:Int(a:Int, b:Int) Override
		Return ranking.Compare(a, b, points[a], points[b])
	End Method

	Method CompareBounds:Int(a:Int, b:Int, aPoints:Long, bPoints:Long, aUpper:Int, bUpper:Int, remainingCountback:Int[])
		For Local rule:ETiebreaker = EachIn ranking.rules
			Select rule
				Case ETiebreaker.Points
					If aPoints > bPoints Then
						Return 1
					End If

					If aPoints < bPoints Then
						Return -1
					End If
				Case ETiebreaker.Wins
					Local av:Int = ranking.blocks[0].counts[a][0]
					Local bv:Int = ranking.blocks[0].counts[b][0]
					If aUpper Then
						av :+ remainingCountback[0]
					End If

					If bUpper Then
						bv :+ remainingCountback[0]
					End If

					If av > bv Then
						Return 1
					End If

					If av < bv Then
						Return -1
					End If
				Case ETiebreaker.FinishCountback
					For Local blockIndex:Int = 0 Until ranking.blocks.Length
						Local block:TSeriesCountbackBlock = ranking.blocks[blockIndex]
						For Local position:Int = EachIn block.positions
							Local av:Int = block.counts[a][position - 1]
							Local bv:Int = block.counts[b][position - 1]
							If aUpper Then
								av :+ remainingCountback[blockIndex]
							End If

							If bUpper Then
								bv :+ remainingCountback[blockIndex]
							End If

							If av > bv Then
								Return 1
							End If

							If av < bv Then
								Return -1
							End If
						Next
					Next
			End Select
		Next

		Return 0
	End Method

	' Independent bounds are deliberately generous to each entrant. They can
	' prove a whole branch without assuming simultaneous finishes are possible.
	Method BoundOutcome:Int(firstEvent:Int)
		Local minimum:Long[] = points[..]
		Local maximum:Long[] = points[..]
		Local remainingCountback:Int[] = New Int[ranking.blocks.Length]
		For Local eventIndex:Int = firstEvent Until events.Length
			Local event:TSeriesQualificationEvent = events[eventIndex]
			Local low:Int
			Local high:Int
			For Local pointsForPlace:Int = EachIn event.pointsByPosition
				low = Min(low, pointsForPlace)
				high = Max(high, pointsForPlace)
			Next

			For Local target:Int = EachIn targetIndices
				If target < 0 Then
					Continue
				End If

				minimum[target] :+ low
				maximum[target] :+ high
			Next

			For Local blockIndex:Int = 0 Until ranking.blocks.Length
				If event.countbackEligible[blockIndex] Then
					remainingCountback[blockIndex] :+ 1
				End If
			Next
		Next

		Local challengers:Int
		Local certainAbove:Int
		For Local i:Int = 0 Until ids.Length
			If i = candidate Then
				Continue
			End If

			If CompareBounds(i, candidate, maximum[i], minimum[candidate], True, False, remainingCountback) >= 0 Then
				challengers :+ 1
			End If

			If CompareBounds(i, candidate, minimum[i], maximum[candidate], False, True, remainingCountback) > 0 Then
				certainAbove :+ 1
			End If
		Next

		If challengers < analysis.places Then
			Return 1
		End If

		If certainAbove >= analysis.places Then
			Return -1
		End If

		Return 0
	End Method

	Method RecordBoundWitness(firstEvent:Int, bound:Int)
		Local witness:TQualificationOutcome[] = CopyChoices()
		For Local i:Int = firstEvent Until events.Length
			Local outcome:TQualificationOutcome = New TQualificationOutcome
			outcome.fixtureId = events[i].fixtureId
			outcome.classificationOrder = [entrantIds[0]]
			witness :+ [outcome]
		Next

		If bound > 0 Then
			If Not foundPossible Then
				analysis.qualifyingScenario = witness
			End If

			foundPossible = True
		Else
			If Not foundNotCertain Then
				analysis.failingScenario = witness
			End If

			foundNotCertain = True
		End If
	End Method

	Method TailCanAffectRank:Int(eventIndex:Int, nextPosition:Int)
		For Local i:Int = nextPosition Until entrantIds.Length
			If events[eventIndex].pointsByPosition[i] <> 0 Then
				Return True
			End If

			For Local rule:ETiebreaker = EachIn ranking.rules
				If rule = ETiebreaker.Wins And i = 0 And events[eventIndex].countbackEligible[0] Then
					Return True
				End If

				If rule = ETiebreaker.FinishCountback Then
					For Local blockIndex:Int = 0 Until ranking.blocks.Length
						If Not events[eventIndex].countbackEligible[blockIndex] Then
							Continue
						End If

						For Local position:Int = EachIn ranking.blocks[blockIndex].positions
							If position = i + 1 Then
								Return True
							End If
						Next
					Next
				End If
			Next
		Next

		Return False
	End Method

	Method VisitEvents(eventIndex:Int)
		If exhausted Or (foundPossible And foundNotCertain) Then
			Return
		End If

		Local key:String = StateKey(eventIndex)
		If visited.Contains(key) Then
			Return
		End If

		visited.Insert(key, "1")
		If Not WithinNodeLimit() Then
			Return
		End If

		If eventIndex = events.Length Then ScoreLeaf(); Return

		Local bound:Int = BoundOutcome(eventIndex)
		If bound <> 0 Then RecordBoundWitness(eventIndex, bound); Return

		Local used:Int[] = New Int[entrantIds.Length]
		VisitPositions(eventIndex, used, New Int[0])
	End Method

	Method VisitPositions(eventIndex:Int, used:Int[], order:Int[])
		If exhausted Or (foundPossible And foundNotCertain) Then
			Return
		End If

		Local key:String = StateKey(eventIndex) + "@" + order.Length
		For Local flag:Int = EachIn used
			If flag Then key :+ "1" Else key :+ "0"
		Next

		If partialVisited.Contains(key) Then
			Return
		End If

		partialVisited.Insert(key, "1")
		If Not WithinNodeLimit() Then
			Return
		End If

		If order.Length > 0 Then
			Local outcome:TQualificationOutcome = New TQualificationOutcome
			outcome.fixtureId = events[eventIndex].fixtureId
			outcome.classificationOrder = order[..]
			choices :+ [outcome]
			VisitEvents(eventIndex + 1)
			choices = choices[..choices.Length - 1]
			If exhausted Or (foundPossible And foundNotCertain) Then
				Return
			End If
		End If

		If order.Length = entrantIds.Length Then
			Return
		End If

		If order.Length > 0 And Not TailCanAffectRank(eventIndex, order.Length) Then
			Return
		End If

		Local pointsForPlace:Int = events[eventIndex].pointsByPosition[order.Length]
		For Local i:Int = 0 Until entrantIds.Length
			If used[i] Then
				Continue
			End If

			used[i] = True
			Local target:Int = targetIndices[i]
			If target >= 0 Then
				points[target] :+ pointsForPlace
			End If

			If target >= 0 Then
				For Local blockIndex:Int = 0 Until ranking.blocks.Length
					If events[eventIndex].countbackEligible[blockIndex] Then
						ranking.blocks[blockIndex].counts[target][order.Length] :+ 1
					End If
				Next
			End If

			VisitPositions(eventIndex, used, order + [entrantIds[i]])
			If target >= 0 Then
				For Local blockIndex:Int = 0 Until ranking.blocks.Length
					If events[eventIndex].countbackEligible[blockIndex] Then
						ranking.blocks[blockIndex].counts[target][order.Length] :- 1
					End If
				Next
			End If

			If target >= 0 Then
				points[target] :- pointsForPlace
			End If

			used[i] = False
			If exhausted Or (foundPossible And foundNotCertain) Then
				Return
			End If
		Next
	End Method
End Type

Rem
bbdoc: Analyzes qualification prospects in a named series championship.
End Rem
Type TSeriesQualificationAnalyzer
	Method Analyze:TQualificationAnalysis(comp:TCompetition, stage:TStage, state:TStageState, participantId:Int, places:Int, championshipCode:String, maxScenarios:Int)
		Local result:TQualificationAnalysis = New TQualificationAnalysis
		result.stageId = stage.id
		result.championshipCode = championshipCode
		result.participantId = participantId
		result.places = places
		result.status = EQualificationStatus.Indeterminate
		If places < 1 Or maxScenarios < 1 Then
			Throw "Qualification places and search limit must be positive"
		End If

		Local config:TSeriesConfig = TSeriesConfig(stage.config)
		If config = Null Or stage.formatCode <> "" Then
			result.reason = "Exact series qualification needs the built-in series format"
			Return result
		End If

		Local championship:TChampionshipConfig
		If championshipCode <> "" Then
			For Local item:TChampionshipConfig = EachIn config.championships
				If item.code = championshipCode Then championship = item; Exit
			Next

			If championship = Null Then
				Throw "Unknown championship: " + championshipCode
			End If
		End If

		' A completed board may include a recorded decision that separates a tie.
		' Its persisted sporting ranks are the authoritative final places.
		If state.status = EStageStatus.Complete Then
			Local finalRows:TLeaderboardRow[] = state.leaderboard.rows
			If championshipCode <> "" Then
				finalRows = Null
				For Local named:TNamedLeaderboard = EachIn state.championships
					If named.code = championshipCode Then finalRows = named.leaderboard.rows; Exit
				Next
			End If

			If finalRows <> Null And places <= finalRows.Length Then
				For Local i:Int = 0 Until finalRows.Length
					If finalRows[i].participantId <> participantId Or finalRows[i].sportingRank <= 0 Then
						Continue
					End If

					Local tied:Int
					For Local row:TLeaderboardRow = EachIn finalRows
						If row.sportingRank = finalRows[i].sportingRank Then
							tied :+ 1
						End If
					Next

					If finalRows[i].sportingRank <= places And finalRows[i].sportingRank + tied - 1 > places Then
						result.status = EQualificationStatus.Possible
					ElseIf i < places Then
						result.status = EQualificationStatus.Guaranteed
					Else
						result.status = EQualificationStatus.Eliminated
					End If

					Return result
				Next
			End If
		End If

		Local search:TSeriesQualificationSearch = New TSeriesQualificationSearch
		Local rows:TLeaderboardRow[] = New TClinchAnalyzer.ResolveRows(comp, stage, state, championship)
		For Local row:TLeaderboardRow = EachIn rows
			search.ids :+ [row.participantId]
			search.points :+ [Long(row.points)]
		Next

		search.ranking = TSeriesRanker.Build(comp, stage, state, championship, rows)
		search.candidate = search.IndexOf(participantId)
		If search.candidate < 0 Then
			Throw "Unknown qualification participant"
		End If

		If places > search.ids.Length Then
			Throw "Qualification places exceed entrant count"
		End If

		If state.entrants = Null Or state.entrants.Length = 0 Then
			result.reason = "Series entrants have not been determined"
			Return result
		End If

		search.entrantIds = state.entrants[..]
		For Local id:Int = EachIn search.entrantIds
			Local target:Int = id
			If championship <> Null And championship.parentTeamPoints Then
				Local participant:TParticipant = TSeriesScorer.FindParticipantById(comp, id)
				If participant = Null Then result.reason = "Unknown series entrant"; Return result

				target = participant.parentTeamId
			End If

			search.targetIndices :+ [search.IndexOf(target)]
		Next

		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.status = EFixtureStatus.Completed Or fixture.status = EFixtureStatus.Cancelled Then
				Continue
			End If

			Local scoresPoints:Int = New TSeriesClinchBounds.Included(championship, fixture.sessionCode)
			Local countsPlace:Int
			For Local block:TSeriesCountbackBlock = EachIn search.ranking.blocks
				If block.IncludesSession(fixture.sessionCode) Then
					countsPlace = True
				End If
			Next

			If Not scoresPoints And Not countsPlace Then
				Continue
			End If

			Local event:TSeriesQualificationEvent = New TSeriesQualificationEvent
			event.fixtureId = fixture.id
			event.pointsByPosition = New Int[search.entrantIds.Length]
			For Local block:TSeriesCountbackBlock = EachIn search.ranking.blocks
				event.countbackEligible :+ [block.IncludesSession(fixture.sessionCode)]
			Next

			If scoresPoints Then
				Local scoring:TScoringSystem = TSeriesScorer.ResolveSessionScoring(stage, fixture.seriesEventId, fixture.sessionCode)
				If championship <> Null And championship.scoringOverride <> Null Then
					scoring = championship.scoringOverride
				End If

				If scoring = Null Or scoring.mode <> EScoringMode.PositionTable Then
					result.reason = "A remaining session does not use position-table scoring"
					Return result
				End If

				If scoring.bonuses <> Null And scoring.bonuses.Length > 0 Then
					result.reason = "Future bonus awards need a scenario provider"
					Return result
				End If

				For Local entry:TPointsTableEntry = EachIn scoring.table
					If entry.position < 1 Then
						Continue
					End If

					If entry.position > event.pointsByPosition.Length Then
						Continue
					End If

					event.pointsByPosition[entry.position - 1] = TSeriesScorer.EventPointsUnits(stage, fixture.seriesEventId, ConfigPointUnits(entry.points, entry.pointsExact, TSeriesConfig(stage.config).pointsScale))
				Next
			End If

			search.events :+ [event]
		Next

		search.analysis = result
		search.limit = maxScenarios
		Local rootBound:Int = search.BoundOutcome(0)
		If rootBound <> 0 Then
			search.RecordBoundWitness(0, rootBound)
			If rootBound > 0 Then result.status = EQualificationStatus.Guaranteed Else result.status = EQualificationStatus.Eliminated

			Return result
		End If

		search.VisitEvents(0)
		If search.foundPossible And search.foundNotCertain Then
			result.status = EQualificationStatus.Possible
		ElseIf search.exhausted Then
			result.reason = "Search limit reached before qualification was decided"
		ElseIf search.foundPossible Then
			result.status = EQualificationStatus.Guaranteed
		Else
			result.status = EQualificationStatus.Eliminated
		End If

		Return result
	End Method
End Type
