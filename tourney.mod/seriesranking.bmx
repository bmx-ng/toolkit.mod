' Shared series ranking rules for recorded standings and future scenarios.
Rem
bbdoc: One configured block of finishing-position countback criteria.
End Rem
Type TSeriesCountbackBlock
	Rem
	bbdoc: Positions values associated with this series countback block.
	End Rem
	Field positions:Int[]
	Rem
	bbdoc: Session codes values associated with this series countback block.
	End Rem
	Field sessionCodes:String[]
	Rem
	bbdoc: Number of s for this series countback block.
	about: Entrant index, then finishing position minus one.
	End Rem
	Field counts:Int[][] ' entrant index, then finishing position minus one

	Method IncludesSession:Int(sessionCode:String)
		If sessionCodes = Null Or sessionCodes.Length = 0 Then
			Return True
		End If

		For Local code:String = EachIn sessionCodes
			If code = sessionCode Then
				Return True
			End If
		Next

		Return False
	End Method
End Type

Rem
bbdoc: Per-participant finish counts used for series tie breaking.
End Rem
Type TSeriesRankingData
	Rem
	bbdoc: Ids values associated with this series ranking data.
	End Rem
	Field ids:Int[]
	Rem
	bbdoc: #TSeriesCountbackBlock entries associated with this series ranking data.
	End Rem
	Field blocks:TSeriesCountbackBlock[]
	Rem
	bbdoc: Rules selected for this series ranking data.
	End Rem
	Field rules:ETiebreaker[]
	Rem
	bbdoc: Parent team points for this series ranking data.
	End Rem
	Field parentTeamPoints:Int

	Method IndexOf:Int(id:Int)
		For Local i:Int = 0 Until ids.Length
			If ids[i] = id Then
				Return i
			End If
		Next

		Return -1
	End Method

	Method TargetIndex:Int(comp:TCompetition, entrantId:Int)
		Local target:Int = entrantId
		If parentTeamPoints Then
			Local participant:TParticipant = TSeriesScorer.FindParticipantById(comp, entrantId)
			If participant = Null Then
				Return -1
			End If

			target = participant.parentTeamId
		End If

		Return IndexOf(target)
	End Method

	Method Compare:Int(a:Int, b:Int, aPoints:Long, bPoints:Long)
		For Local rule:ETiebreaker = EachIn rules
			Select rule
				Case ETiebreaker.Points
					If aPoints > bPoints Then
						Return 1
					End If

					If aPoints < bPoints Then
						Return -1
					End If
				Case ETiebreaker.Wins
					If blocks[0].counts[a][0] > blocks[0].counts[b][0] Then
						Return 1
					End If

					If blocks[0].counts[a][0] < blocks[0].counts[b][0] Then
						Return -1
					End If
				Case ETiebreaker.FinishCountback
					For Local block:TSeriesCountbackBlock = EachIn blocks
						For Local position:Int = EachIn block.positions
							If block.counts[a][position - 1] > block.counts[b][position - 1] Then
								Return 1
							End If

							If block.counts[a][position - 1] < block.counts[b][position - 1] Then
								Return -1
							End If
						Next
					Next
			End Select
		Next

		Return 0
	End Method
End Type

Rem
bbdoc: Ranks series standings using points and configured countback.
End Rem
Type TSeriesRanker
	Function Build:TSeriesRankingData(comp:TCompetition, stage:TStage, state:TStageState, championship:TChampionshipConfig, rows:TLeaderboardRow[])
		Local config:TSeriesConfig = TSeriesConfig(stage.config)
		Local ranking:TSeriesRankingData = New TSeriesRankingData
		ranking.rules = config.tiebreakers
		If championship <> Null And championship.tiebreakers <> Null And championship.tiebreakers.Length > 0 Then
			ranking.rules = championship.tiebreakers
		End If

		If ranking.rules = Null Or ranking.rules.Length = 0 Then
			ranking.rules = [ETiebreaker.Points]
		End If

		If ranking.rules[0] <> ETiebreaker.Points Then
			Throw "Series ranking must start with points"
		End If

		For Local i:Int = 1 Until ranking.rules.Length
			If ranking.rules[i] <> ETiebreaker.Wins And ranking.rules[i] <> ETiebreaker.FinishCountback Then
				Throw "Unsupported series tiebreaker"
			End If
		Next

		For Local row:TLeaderboardRow = EachIn rows
			ranking.ids :+ [row.participantId]
		Next

		If championship <> Null Then
			ranking.parentTeamPoints = championship.parentTeamPoints
		End If

		Local policies:TSeriesCountbackConfig[] = config.countbackSequence
		If policies = Null Or policies.Length = 0 Then
			If config.countback <> Null Then
				policies = [config.countback]
			End If
		End If

		If championship <> Null Then
			If championship.countbackSequence <> Null And championship.countbackSequence.Length > 0 Then
				policies = championship.countbackSequence
			ElseIf championship.countback <> Null Then
				policies = [championship.countback]
			End If
		End If

		If policies = Null Or policies.Length = 0 Then
			policies = [New TSeriesCountbackConfig]
		End If

		Local maxPosition:Int = 1
		If state.entrants <> Null Then
			maxPosition = Max(maxPosition, state.entrants.Length)
		End If

		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.classificationOrder <> Null Then
				maxPosition = Max(maxPosition, fixture.classificationOrder.Length)
			End If
		Next

		For Local policy:TSeriesCountbackConfig = EachIn policies
			If policy = Null Then
				Throw "Countback block cannot be null"
			End If

			Local block:TSeriesCountbackBlock = New TSeriesCountbackBlock
			If policy.sessionCodes <> Null And policy.sessionCodes.Length > 0 Then
				block.sessionCodes = policy.sessionCodes[..]
			ElseIf championship <> Null And championship.sessionCodes <> Null And championship.sessionCodes.Length > 0 Then
				block.sessionCodes = championship.sessionCodes[..]
			End If

			If policy.positions <> Null And policy.positions.Length > 0 Then
				For Local position:Int = EachIn policy.positions
					If position < 1 Or position > 1000 Then
						Throw "Countback positions must be between 1 and 1000"
					End If

					For Local previous:Int = EachIn block.positions
						If previous = position Then
							Throw "Duplicate countback position"
						End If
					Next

					block.positions :+ [position]
					maxPosition = Max(maxPosition, position)
				Next
			End If

			ranking.blocks :+ [block]
		Next

		For Local block:TSeriesCountbackBlock = EachIn ranking.blocks
			If block.positions = Null Or block.positions.Length = 0 Then
				For Local position:Int = 1 To maxPosition
					block.positions :+ [position]
				Next
			End If

			For Local id:Int = EachIn ranking.ids
				block.counts :+ [New Int[maxPosition]]
			Next
		Next

		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.status <> EFixtureStatus.Completed Then
				Continue
			End If

			For Local block:TSeriesCountbackBlock = EachIn ranking.blocks
				If Not block.IncludesSession(fixture.sessionCode) Then
					Continue
				End If

				For Local i:Int = 0 Until fixture.classificationOrder.Length
					Local target:Int = ranking.TargetIndex(comp, fixture.classificationOrder[i])
					If target >= 0 Then
						block.counts[target][i] :+ 1
					End If
				Next
			Next
		Next

		Return ranking
	End Function

	Function SortRows(rows:TLeaderboardRow[], ranking:TSeriesRankingData, decisions:TTableTieDecision[] = Null, scopeKey:String = "")
		For Local i:Int = 0 Until rows.Length - 1
			For Local j:Int = i + 1 Until rows.Length
				Local ai:Int = ranking.IndexOf(rows[i].participantId)
				Local bi:Int = ranking.IndexOf(rows[j].participantId)
				Local comparison:Int = ranking.Compare(ai, bi, rows[i].points, rows[j].points)
				If comparison < 0 Or (comparison = 0 And rows[j].participantId < rows[i].participantId) Then
					Local swap:TLeaderboardRow = rows[i]; rows[i] = rows[j]; rows[j] = swap
				End If
			Next
		Next

		Local first:Int
		While first < rows.Length
			Local last:Int = first + 1
			While last < rows.Length
				Local a:Int = ranking.IndexOf(rows[first].participantId)
				Local b:Int = ranking.IndexOf(rows[last].participantId)
				If ranking.Compare(a, b, rows[first].points, rows[last].points) <> 0 Then
					Exit
				End If

				last :+ 1
			Wend

			Local decision:TTableTieDecision
			If last - first > 1 Then
				For Local candidate:TTableTieDecision = EachIn decisions
					If candidate.scopeKey <> scopeKey Or candidate.participantIds = Null Or candidate.participantIds.Length <> last - first Then
						Continue
					End If

					Local matches:Int = True
					For Local id:Int = EachIn candidate.participantIds
						Local found:Int
						For Local i:Int = first Until last
							If rows[i].participantId = id Then
								found :+ 1
							End If
						Next

						If found <> 1 Then matches = False; Exit
					Next

					If matches Then decision = candidate; Exit
				Next
			End If

			If decision <> Null Then
				For Local i:Int = first Until last
					For Local j:Int = i Until last
						If rows[j].participantId = decision.participantIds[i - first] Then
							Local swap:TLeaderboardRow = rows[i]; rows[i] = rows[j]; rows[j] = swap
							Exit
						End If
					Next

					rows[i].sportingRank = i + 1
				Next
			Else
				For Local i:Int = first Until last
					rows[i].sportingRank = first + 1
				Next
			End If

			first = last
		Wend
	End Function
End Type
