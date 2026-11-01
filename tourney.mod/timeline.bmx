' Immutable standings snapshots made after each successful result update.
' The recorder is attached to an engine through AddResultObserver.
Rem
bbdoc: Participant identity stored in a standings timeline.
End Rem
Type TTimelineParticipant
	Rem
	bbdoc: Stable identifier of this timeline participant.
	End Rem
	Field id:Int
	Rem
	bbdoc: Display name of this timeline participant.
	End Rem
	Field name:String
	Rem
	bbdoc: ID of the parent team associated with this timeline participant.
	End Rem
	Field parentTeamId:Int
	Rem
	bbdoc: ID of the division associated with this timeline participant.
	End Rem
	Field divisionId:String
	Rem
	bbdoc: Kind of this timeline participant.
	End Rem
	Field kind:EParticipantKind
End Type

Rem
bbdoc: A snapshot of standings after one recorded result.
End Rem
Type TStandingsFrame
	Rem
	bbdoc: ID of the associated stage.
	End Rem
	Field stageId:String
	Rem
	bbdoc: ID of the associated fixture.
	End Rem
	Field fixtureId:String
	Rem
	bbdoc: Round for this standings frame.
	End Rem
	Field round:Int
	Rem
	bbdoc: Bracket position for this standings frame.
	End Rem
	Field bracketPosition:Int
	Rem
	bbdoc: ID of the event associated with this standings frame.
	End Rem
	Field eventId:String
	Rem
	bbdoc: Session code of this standings frame.
	End Rem
	Field sessionCode:String
	Rem
	bbdoc: Stage status selected for this standings frame.
	End Rem
	Field stageStatus:EStageStatus
	Rem
	bbdoc: Key identifying the associated group.
	End Rem
	Field groupKey:String
	Rem
	bbdoc: ID of the home team associated with this standings frame.
	End Rem
	Field homeTeamId:Int
	Rem
	bbdoc: ID of the away team associated with this standings frame.
	End Rem
	Field awayTeamId:Int
	Rem
	bbdoc: Score home for this standings frame.
	End Rem
	Field scoreHome:Int
	Rem
	bbdoc: Score away for this standings frame.
	End Rem
	Field scoreAway:Int
	Rem
	bbdoc: Fair play home for this standings frame.
	End Rem
	Field fairPlayHome:Int
	Rem
	bbdoc: Fair play away for this standings frame.
	End Rem
	Field fairPlayAway:Int
	Rem
	bbdoc: Penalties home for this standings frame.
	End Rem
	Field penaltiesHome:Int
	Rem
	bbdoc: Penalties away for this standings frame.
	End Rem
	Field penaltiesAway:Int
	Rem
	bbdoc: After extra time for this standings frame.
	End Rem
	Field afterExtraTime:Int
	Rem
	bbdoc: #TNamedLeaderboard entries associated with this standings frame.
	End Rem
	Field boards:TNamedLeaderboard[]
	Rem
	bbdoc: #TGroupTable entries associated with this standings frame.
	End Rem
	Field groups:TGroupTable[]
	Rem
	bbdoc: Classification order values associated with this standings frame.
	End Rem
	Field classificationOrder:Int[]
	Rem
	bbdoc: #TResultAward entries associated with this standings frame.
	End Rem
	Field awards:TResultAward[]

	Rem
	bbdoc: Finds a standings board stored in this frame.
	param: Championship code, or empty for the main board.
	returns: The frame's #TLeaderboard, or #Null when the board is absent.
	End Rem
	Method Board:TLeaderboard(code:String = "")
		For Local named:TNamedLeaderboard = EachIn boards
			If named.code = code Then
				Return named.leaderboard
			End If
		Next

		Return Null
	End Method
End Type

Rem
bbdoc: Observer that records independent standings frames for presentation.
about: Attach this observer with #TCompetitionEngine.AddResultObserver. It copies standings after each result, so a renderer can browse past frames without changing the engine's current state. A correction resets and rebuilds the timeline.
End Rem
Type TCompetitionTimeline Implements ICompetitionResultObserver, ICompetitionReplayObserver
	Rem
	bbdoc: #TStandingsFrame entries associated with this competition timeline.
	End Rem
	Field frames:TStandingsFrame[]
	Rem
	bbdoc: #TTimelineParticipant entries associated with this competition timeline.
	End Rem
	Field participants:TTimelineParticipant[]

	Rem
	bbdoc: Clears frames and participant details before a correction replay.
	End Rem
	Method OnReplayReset()
		frames = Null
		participants = Null
	End Method

	Rem
	bbdoc: Looks up participant details copied into this timeline.
	param: Stable participant ID.
	returns: Matching #TTimelineParticipant, or #Null.
	End Rem
	Method Participant:TTimelineParticipant(id:Int)
		For Local item:TTimelineParticipant = EachIn participants
			If item.id = id Then
				Return item
			End If
		Next

		Return Null
	End Method

	Function CopyRows:TLeaderboard(source:TLeaderboard)
		Local copy:TLeaderboard = New TLeaderboard
		If source = Null Then
			Return copy
		End If

		For Local row:TLeaderboardRow = EachIn source.rows
			Local value:TLeaderboardRow = New TLeaderboardRow
			value.participantId = row.participantId
			value.sportingRank = row.sportingRank
			value.points = row.points
			value.timeSeconds = row.timeSeconds
			value.wins = row.wins
			value.draws = row.draws
			value.losses = row.losses
			value.noResults = row.noResults
			value.netRate = row.netRate
			value.gf = row.gf
			value.ga = row.ga
			For Local metric:TLeaderboardMetric = EachIn row.metrics
				Local item:TLeaderboardMetric = New TLeaderboardMetric
				item.code = metric.code
				item.value = metric.value
				value.metrics :+ [item]
			Next

			copy.rows :+ [value]
		Next

		Return copy
	End Function

	Rem
	bbdoc: Records an independent standings frame after a result update.
	param: Competition definition.
	param: Updated playing state.
	param: Stage that received the result.
	param: Fixture that received the result.
	param: Recorded result payload.
	End Rem
	Method OnResultRecorded(comp:TCompetition, state:TCompetitionState, stageId:String, fixtureId:String, result:TResultPayload)
		If participants = Null Then
			For Local source:TParticipant = EachIn comp.participants
				Local item:TTimelineParticipant = New TTimelineParticipant
				item.id = source.id
				item.name = source.name
				item.parentTeamId = source.parentTeamId
				item.divisionId = source.divisionId
				item.kind = source.kind
				participants :+ [item]
			Next
		End If

		Local stage:TStageState
		For Local candidate:TStageState = EachIn state.stages
			If candidate.stageId = stageId Then stage = candidate; Exit
		Next

		If stage = Null Then
			Throw "Timeline stage not found: " + stageId
		End If

		Local frame:TStandingsFrame = New TStandingsFrame
		frame.stageId = stageId
		frame.fixtureId = fixtureId
		frame.stageStatus = stage.status
		Local groupTables:TGroupTable[] = stage.groups
		If groupTables = Null Then
			For Local definition:TStage = EachIn comp.stages
				If definition.id = stageId And definition.stageType = EStageType.Group Then
					Local advancer:TGroupAdvancer = New TGroupAdvancer
					groupTables = advancer.SnapshotGroupTables(comp, definition, stage)
					Exit
				End If
			Next
		End If

		For Local group:TGroupTable = EachIn groupTables
			Local copy:TGroupTable = New TGroupTable
			copy.key = group.key
			Local source:TLeaderboard = New TLeaderboard
			source.rows = group.rows
			copy.rows = CopyRows(source).rows
			frame.groups :+ [copy]
		Next

		For Local fixture:TFixtureState = EachIn stage.fixtures
			If fixture.id = fixtureId Then
				frame.round = fixture.round
				frame.bracketPosition = fixture.bracketPosition
				frame.eventId = fixture.seriesEventId
				frame.sessionCode = fixture.sessionCode
				frame.groupKey = fixture.groupKey
				frame.homeTeamId = fixture.homeTeamId
				frame.awayTeamId = fixture.awayTeamId
				frame.scoreHome = fixture.scoreHome
				frame.scoreAway = fixture.scoreAway
				frame.fairPlayHome = fixture.fairPlayHome
				frame.fairPlayAway = fixture.fairPlayAway
				frame.penaltiesHome = fixture.penaltiesHome
				frame.penaltiesAway = fixture.penaltiesAway
				frame.afterExtraTime = fixture.afterExtraTime
				If fixture.classificationOrder <> Null Then
					frame.classificationOrder = fixture.classificationOrder[..]
				End If

				For Local award:TResultAward = EachIn fixture.awards
					Local item:TResultAward = New TResultAward
					item.code = award.code
					item.participantId = award.participantId
					item.pointsOverride = award.pointsOverride
					If award.conditions <> Null Then
						item.conditions = New TAwardConditions
						item.conditions.minFinishPosition = award.conditions.minFinishPosition
						item.conditions.mustFinish = award.conditions.mustFinish
					End If

					frame.awards :+ [item]
				Next

				Exit
			End If
		Next

		Local main:TNamedLeaderboard = New TNamedLeaderboard
		main.code = ""
		main.leaderboard = CopyRows(stage.leaderboard)
		frame.boards :+ [main]
		For Local named:TNamedLeaderboard = EachIn stage.championships
			Local copy:TNamedLeaderboard = New TNamedLeaderboard
			copy.code = named.code
			copy.leaderboard = CopyRows(named.leaderboard)
			frame.boards :+ [copy]
		Next

		frames :+ [frame]
	End Method
End Type
