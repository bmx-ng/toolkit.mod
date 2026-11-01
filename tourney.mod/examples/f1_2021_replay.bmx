' Historical 2021 F1 season: classifications are inputs; all points come from rules.
Type TF12021Replay
	Function Points:TPointsTableEntry(position:Int, value:Int)
		Local entry:TPointsTableEntry = New TPointsTableEntry
		entry.position = position
		entry.points = value
		Return entry
	End Function

	Function Ids:Int[](csv:String)
		Local result:Int[]
		For Local value:String = EachIn csv.Split(",")
			result :+ [Int(value)]
		Next
		Return result
	End Function

	Function DriverUnits:Int(state:TCompetitionState, id:Int)
		For Local row:TLeaderboardRow = EachIn state.stages[0].championships[0].leaderboard.rows
			If row.participantId = id Then Return row.points
		Next
		Throw "Missing driver in F1 standings: " + id
	End Function

	Function Run:Int(path:String, timeline:TCompetitionTimeline = Null)
		Local stream:TStream = ReadStream(path)
		If stream = Null Then Throw "Cannot read " + path
		Local comp:TCompetition = New TCompetition
		comp.name = "2021 Formula One World Championship"
		Local cfg:TSeriesConfig = New TSeriesConfig
		cfg.pointsScale = 2
		cfg.tiebreakers = [ETiebreaker.Points, ETiebreaker.FinishCountback]
		cfg.scoring = New TScoringSystem
		cfg.scoring.mode = EScoringMode.PositionTable
		cfg.scoring.table = [Points(1, 25), Points(2, 18), Points(3, 15), Points(4, 12), Points(5, 10), Points(6, 8), Points(7, 6), Points(8, 4), Points(9, 2), Points(10, 1)]
		Local fastest:TBonusRule = New TBonusRule
		fastest.code = "FASTEST_LAP"
		fastest.points = 1
		fastest.allowedSessions = ["RACE"]
		fastest.uniquePerSession = True
		fastest.requireFinish = True
		fastest.minFinishPosition = 10
		cfg.scoring.bonuses = [fastest]
		Local sprintScore:TScoringSystem = New TScoringSystem
		sprintScore.mode = EScoringMode.PositionTable
		sprintScore.table = [Points(1, 3), Points(2, 2), Points(3, 1)]
		Local drivers:TChampionshipConfig = New TChampionshipConfig
		drivers.code = "DRIVERS"
		drivers.filterByKind = True
		drivers.participantKind = EParticipantKind.Individual
		drivers.tiebreakers = [ETiebreaker.Points, ETiebreaker.FinishCountback]
		Local constructors:TChampionshipConfig = New TChampionshipConfig
		constructors.code = "CONSTRUCTORS"
		constructors.parentTeamPoints = True
		constructors.tiebreakers = [ETiebreaker.Points, ETiebreaker.FinishCountback]
		cfg.championships = [drivers, constructors]
		Local lines:String[]
		Local expectedDrivers:TStringMap = New TStringMap
		Local expectedTeams:TStringMap = New TStringMap
		While Not stream.Eof()
			Local line:String = stream.ReadLine().Trim()
			If line = "" Or line.StartsWith("#") Then Continue
			Local fields:String[] = line.Split("|")
			Select fields[0]
				Case "D", "T"
					Local p:TParticipant = New TParticipant
					p.id = Int(fields[1])
					p.name = fields[2]
					If fields[0] = "D" Then
						p.kind = EParticipantKind.Individual
						p.parentTeamId = Int(fields[3])
						expectedDrivers.Insert(fields[1], fields[4])
					Else
						p.kind = EParticipantKind.Team
						expectedTeams.Insert(fields[1], fields[3])
					End If
					comp.participants :+ [p]
				Case "R"
					Local ev:TSeriesEvent = New TSeriesEvent
					ev.id = "R" + fields[1]
					ev.name = fields[2]
					If fields[1] = "12" Then ev.pointsMultiplierExact = "0.5"
					Local race:TSession = New TSession
					race.code = "RACE"
					ev.sessions = [race]
					cfg.events :+ [ev]
					lines :+ [line]
				Case "S"
					Local ev:TSeriesEvent = cfg.events[cfg.events.Length - 1]
					If ev.id <> "R" + fields[1] Then Throw "Sprint round mismatch"
					Local sprint:TSession = New TSession
					sprint.code = "SPRINT"
					sprint.scoringOverride = sprintScore
					ev.sessions = [sprint, ev.sessions[0]]
					' The source lists race rows before their sprint rows. Replay each
					' weekend in session order so intermediate standings are historical.
					Local raceLine:String = lines[lines.Length - 1]
					lines[lines.Length - 1] = line
					lines :+ [raceLine]
			End Select
		Wend
		stream.Close()
		If cfg.events.Length <> 22 Or lines.Length <> 25 Or comp.participants.Length <> 31 Then Throw "Incomplete F1 season"
		Local stage:TStage = New TStage
		stage.id = "F1_2021"
		stage.stageType = EStageType.Series
		stage.config = cfg
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Series, New TSeriesScheduler)
		engine.RegisterScorer(EStageType.Series, New TSeriesScorer)
		engine.RegisterAdvancer(EStageType.Series, New TSeriesAdvancer)
		If timeline <> Null Then engine.AddResultObserver(timeline)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local entrants:Int[]
		For Local p:TParticipant = EachIn comp.participants
			If p.kind = EParticipantKind.Individual Then entrants :+ [p.id]
		Next
		state.stages[0].entrants = entrants
		For Local line:String = EachIn lines
			Local fields:String[] = line.Split("|")
			Local payload:TResultPayload = New TResultPayload
			payload.kind = EResultKind.Classification
			Local code:String = fields[0]
			If code = "R" Then
				payload.order = Ids(fields[4])
				If Int(fields[3]) <> 0 Then
					Local award:TResultAward = New TResultAward
					award.code = "FASTEST_LAP"
					award.participantId = Int(fields[3])
					payload.awards = [award]
				End If
				code = "RACE"
			Else
				payload.order = Ids(fields[2])
				code = "SPRINT"
			End If
			Local belgian:Int = code = "RACE" And fields[1] = "12"
			Local maxBefore:Int
			Local sainzBefore:Int
			If belgian Then
				maxBefore = DriverUnits(state, 9)
				sainzBefore = DriverUnits(state, 18)
			End If
			engine.RecordResult(comp, state, stage.id, stage.id + "_R" + fields[1] + "_" + code, payload)
			If belgian Then
				If DriverUnits(state, 9) - maxBefore <> 25 Then Throw "Belgian win should award 12.5 points"
				If DriverUnits(state, 18) - sainzBefore <> 1 Then Throw "Belgian P10 should award 0.5 points"
			End If
		Next
		Local checkedDrivers:Int
		Local checkedTeams:Int
		For Local named:TNamedLeaderboard = EachIn state.stages[0].championships
			Local expected:TStringMap = expectedDrivers
			If named.code = "CONSTRUCTORS" Then expected = expectedTeams
			For Local row:TLeaderboardRow = EachIn named.leaderboard.rows
				Local official:String = String(expected.ValueForKey(String(row.participantId)))
				If official = "" Then Throw "Unexpected F1 standings entrant " + row.participantId
				Local actual:String = TSeriesScorer.PointsText(row, cfg)
				If actual <> official Then Throw named.code + " " + row.participantId + ": expected " + official + ", got " + actual
				If named.code = "DRIVERS" Then checkedDrivers :+ 1 Else checkedTeams :+ 1
			Next
		Next
		If checkedDrivers <> 21 Or checkedTeams <> 10 Then Throw "Incomplete F1 standings"
		If state.stages[0].championships[0].leaderboard.rows[0].participantId <> 9 Then Throw "Wrong driver champion"
		If state.stages[0].championships[1].leaderboard.rows[0].participantId <> 108 Then Throw "Wrong constructor champion"
		Return checkedDrivers + checkedTeams
	End Function
End Type
