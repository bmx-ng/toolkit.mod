' Historical 2024 Tour de France replay from ASO's stage and checkpoint tables.
Type TTour2024StageData
	Field finishes:TCyclingRiderResult[]
	Field checkpoints:TCyclingCheckpointResult[]
	Field adjustments:TCyclingPointAdjustment[]
	Field teamAdjustments:TCyclingTeamAdjustment[]
End Type

Type TTour2024Expected
	Field code:String
	Field ids:Int[]
	Field values:Long[]
End Type

' Optional observer for examples that display the calculated standings as the
' historical results are played through the engine.
Interface ITour2024StageObserver
	Method OnStage(comp:TCompetition, state:TCompetitionState, stageNumber:Int)
End Interface

Type TTour2024ObserverBridge Implements ICompetitionResultObserver
	Field target:ITour2024StageObserver
	Field stageId:String

	Method OnResultRecorded(comp:TCompetition, state:TCompetitionState, resultStageId:String, fixtureId:String, result:TResultPayload)
		If resultStageId <> stageId Or result.kind <> EResultKind.Custom Or result.customCode <> "cycling-stage" Then
			Return
		End If

		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
			If fixture.id = fixtureId Then target.OnStage(comp, state, fixture.round); Return
		Next

		Throw "Tour observer received an unknown fixture: " + fixtureId
	End Method
End Type

Type TTour2024Replay
	Function Numbers:Int[](csv:String)
		Local values:Int[]
		For Local part:String = EachIn csv.Split(",")
			values :+ [Int(part)]
		Next

		Return values
	End Function

	Function Table:Int[](top:Int)
		Select top
			Case 50
				Return [50, 30, 20, 18, 16, 14, 12, 10, 8, 7, 6, 5, 4, 3, 2]
			Case 30
				Return [30, 25, 22, 19, 17, 15, 13, 11, 9, 7, 6, 5, 4, 3, 2]
			Case 20
				Return [20, 17, 15, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
		End Select

		Throw "Unknown 2024 Tour finish profile"
	End Function

	Function ClimbCategory:String(top:Int)
		Select top
			Case 40, 20
				Return "HC"
			Case 10
				Return "1"
			Case 5
				Return "2"
			Case 2
				Return "3"
			Case 1
				Return "4"
		End Select

		Throw "Unknown 2024 Tour climb category"
	End Function

	Function Expected:TTour2024Expected(expected:TTour2024Expected[], code:String)
		For Local value:TTour2024Expected = EachIn expected
			If value.code = code Then
				Return value
			End If
		Next

		Local value:TTour2024Expected = New TTour2024Expected
		value.code = code
		Return value
	End Function

	Function Board:TLeaderboard(state:TStageState, code:String)
		If code = "G" Then
			Return state.leaderboard
		End If

		Local name:String
		Select code
			Case "P"
				name = "POINTS"
			Case "M"
				name = "CLIMBER"
			Case "Y"
				name = "YOUTH"
			Case "T"
				name = "TEAM"
		End Select

		For Local board:TNamedLeaderboard = EachIn state.championships
			If board.code = name Then
				Return board.leaderboard
			End If
		Next

		Throw "Missing 2024 Tour classification: " + code
	End Function

	Function Run:Int(path:String, observer:ITour2024StageObserver = Null)
		Local stream:TStream = ReadStream(path)
		If stream = Null Then
			Throw "Cannot read Tour results: " + path
		End If

		Local comp:TCompetition = New TCompetition
		comp.name = "2024 Tour de France"
		Local cfg:TCyclingConfig = New TCyclingConfig
		cfg.ridersPerTeam = 3
		cfg.pointsScale = 2
		cfg.sprintPoints = [20, 17, 15, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
		Local climb:TCyclingClimbRule = New TCyclingClimbRule
		climb.category = "HC"
		climb.points = [20, 15, 12, 10, 8, 6, 4, 2]
		cfg.climbPoints :+ [climb]
		climb = New TCyclingClimbRule
		climb.category = "1"
		climb.points = [10, 8, 6, 4, 2, 1]
		cfg.climbPoints :+ [climb]
		climb = New TCyclingClimbRule
		climb.category = "2"
		climb.points = [5, 3, 2, 1]
		cfg.climbPoints :+ [climb]
		climb = New TCyclingClimbRule
		climb.category = "3"
		climb.points = [2, 1]
		cfg.climbPoints :+ [climb]
		climb = New TCyclingClimbRule
		climb.category = "4"
		climb.points = [1]
		cfg.climbPoints :+ [climb]
		Local stages:TTour2024StageData[]
		Local expected:TTour2024Expected[]
		While Not stream.Eof()
			Local line:String = stream.ReadLine().Trim()
			If line = "" Or line.StartsWith("#") Then
				Continue
			End If

			Local fields:String[] = line.Split("|")
			Select fields[0]
				Case "T"
					Local team:TParticipant = New TParticipant
					team.id = 1000 + Int(fields[1])
					team.name = fields[2]
					For Local i:Int = 3 Until fields.Length
						team.name :+ "|" + fields[i]
					Next

					team.kind = EParticipantKind.Team
					comp.participants :+ [team]
				Case "R"
					Local rider:TParticipant = New TParticipant
					rider.id = Int(fields[1])
					rider.parentTeamId = 1000 + Int(fields[2])
					rider.name = fields[4]
					If rider.name = "" Then
						Throw "Tour rider has no name: " + rider.id
					End If

					rider.kind = EParticipantKind.Individual
					comp.participants :+ [rider]
					If Int(fields[3]) Then
						cfg.youngRiderIds :+ [rider.id]
					End If
				Case "S"
					Local rule:TCyclingStageRule = New TCyclingStageRule
					rule.id = "STAGE_" + fields[1]
					rule.isTimeTrial = Int(fields[2])
					rule.finishPoints = Table(Int(fields[3]))
					If Not rule.isTimeTrial Then
						rule.finishBonusSeconds = [10, 6, 4]
					End If

					cfg.stages :+ [rule]
					stages :+ [New TTour2024StageData]
				Case "C"
					Local index:Int = Int(fields[1]) - 1
					Local rule:TCyclingStageRule = cfg.stages[index]
					Local definition:TCyclingCheckpointRule = New TCyclingCheckpointRule
					definition.code = fields[3]
					Local top:Int = Int(fields[4])
					If fields[2] = "P" Then
						definition.classification = "POINTS"
					ElseIf fields[2] = "B" Then
						definition.classification = "BONUS"
						definition.bonusSeconds = [8, 5, 2]
					Else
						definition.classification = "CLIMBER"
						definition.category = ClimbCategory(top)
						If top = 40 Then
							definition.points = [40, 30, 24, 20, 16, 12, 8, 4]
						End If
					End If

					rule.checkpoints :+ [definition]
					Local crossing:TCyclingCheckpointResult = New TCyclingCheckpointResult
					crossing.code = definition.code
					crossing.order = Numbers(fields[5])
					Local data:TTour2024StageData = stages[index]
					data.checkpoints :+ [crossing]
				Case "F"
					Local finish:TCyclingRiderResult = New TCyclingRiderResult
					finish.participantId = Int(fields[2])
					finish.place = Int(fields[3])
					finish.elapsedSeconds = Long(fields[4])
					finish.bonusSeconds = Int(fields[5])
					finish.bonusRecorded = True
					finish.penaltySeconds = Int(fields[6])
					finish.gcAdjustmentSeconds = Int(fields[7])
					Local data:TTour2024StageData = stages[Int(fields[1]) - 1]
					data.finishes :+ [finish]
				Case "A"
					Local adjustment:TCyclingPointAdjustment = New TCyclingPointAdjustment
					adjustment.participantId = Int(fields[2])
					adjustment.pointsUnits = Int(fields[3]) * cfg.pointsScale
					adjustment.reason = "Official points classification correction"
					Local data:TTour2024StageData = stages[Int(fields[1]) - 1]
					data.adjustments :+ [adjustment]
				Case "AT"
					Local adjustment:TCyclingTeamAdjustment = New TCyclingTeamAdjustment
					adjustment.teamId = 1000 + Int(fields[2])
					adjustment.seconds = Long(fields[3])
					adjustment.reason = "Official team classification correction"
					Local data:TTour2024StageData = stages[Int(fields[1]) - 1]
					data.teamAdjustments :+ [adjustment]
				Case "E"
					Local value:TTour2024Expected = Expected(expected, fields[1])
					If value.ids = Null Then
						expected :+ [value]
					End If

					Local id:Int = Int(fields[3])
					If fields[1] = "T" Then
						id :+ 1000
					End If

					If Int(fields[2]) <> value.ids.Length + 1 Then
						Throw "Nonsequential official Tour ranking"
					End If

					value.ids :+ [id]
					value.values :+ [Long(fields[4])]
				Default
					Throw "Unknown Tour replay row: " + line
			End Select
		Wend

		stream.Close()
		If cfg.stages.Length <> 21 Or stages.Length <> 21 Or cfg.youngRiderIds.Length <> 38 Then
			Throw "Incomplete Tour stage data"
		End If

		If comp.participants.Length <> 198 Then
			Throw "Incomplete Tour starting field"
		End If

		Local stage:TStage = New TStage
		stage.id = "TDF_2024"
		stage.stageType = EStageType.Series
		stage.formatCode = "cycling-stage-race"
		stage.config = cfg
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterFormat("cycling-stage-race", New TCyclingScheduler, New TCyclingScorer)
		If observer <> Null Then
			Local bridge:TTour2024ObserverBridge = New TTour2024ObserverBridge
			bridge.target = observer
			bridge.stageId = stage.id
			engine.AddResultObserver(bridge)
		End If

		Local state:TCompetitionState = engine.Initialize(comp)
		For Local number:Int = 1 To 21
			Local fixture:TFixtureState = state.stages[0].fixtures[number - 1]
			Local result:TResultPayload = New TResultPayload
			result.kind = EResultKind.Custom
			result.customCode = "cycling-stage"
			result.cyclingResults = stages[number - 1].finishes[..]
			result.cyclingCheckpoints = stages[number - 1].checkpoints[..]
			result.cyclingAdjustments = stages[number - 1].adjustments[..]
			result.cyclingTeamAdjustments = stages[number - 1].teamAdjustments[..]
			For Local id:Int = EachIn fixture.participantIds
				Local found:Int
				For Local finish:TCyclingRiderResult = EachIn result.cyclingResults
					If finish.participantId = id Then found = True; Exit
				Next

				If Not found Then
					Local withdrawal:TCyclingRiderResult = New TCyclingRiderResult
					withdrawal.participantId = id
					withdrawal.status = ECyclingRiderStatus.Withdrawn
					result.cyclingResults :+ [withdrawal]
				End If
			Next

			engine.RecordResult(comp, state, stage.id, fixture.id, result)
		Next

		If state.stages[0].status <> EStageStatus.Complete Then
			Throw "Tour replay did not complete"
		End If

		For Local value:TTour2024Expected = EachIn expected
			Local board:TLeaderboard = Board(state.stages[0], value.code)
			If board.rows.Length <> value.ids.Length Then
				Throw "Tour " + value.code + " classification field mismatch: " + board.rows.Length + " vs " + value.ids.Length
			End If

			For Local i:Int = 0 Until value.ids.Length
				Local row:TLeaderboardRow = board.rows[i]
				If row.participantId <> value.ids[i] Then
					Throw "Tour " + value.code + " ranking mismatch at " + (i + 1) + ": " + row.participantId + " vs " + value.ids[i]
				End If

				Local total:Long = row.points / cfg.pointsScale
				If value.code = "G" Or value.code = "Y" Or value.code = "T" Then
					total = row.timeSeconds
				End If

				If total <> value.values[i] Then
					Throw "Tour " + value.code + " score mismatch at " + (i + 1) + ": " + total + " vs " + value.values[i]
				End If
			Next
		Next

		Return state.stages[0].leaderboard.rows.Length
	End Function
End Type
