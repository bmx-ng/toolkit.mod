' Full-field replay from World Sailing's published Paris 2024 ILCA 7 score table.
Type TParisDinghyEntry
	Field id:Int
	Field rank:Int
	Field name:String
	Field noc:String
	Field races:String[]
	Field medal:String
	Field netUnits:Int
End Type

Type TParis2024MensDinghyReplay
	Function Units:Int(value:String)
		Local parts:String[] = value.Split(".")
		If parts.Length = 1 Then
			Return Int(parts[0]) * 10
		End If

		If parts.Length <> 2 Or parts[1].Length <> 1 Then
			Throw "Unsupported official sailing precision: " + value
		End If

		Return Int(parts[0]) * 10 + Int(parts[1])
	End Function

	Function RaceScore:TRegattaRaceScore(id:Int, value:String)
		Local tokens:String[] = value.Replace("(", "").Replace(")", "").Split(" ")
		Local score:TRegattaRaceScore = New TRegattaRaceScore
		score.participantId = id
		If tokens.Length > 1 Then
			score.code = tokens[1]
		End If

		If tokens[0].Find(".") >= 0 Or score.code <> "" Then
			score.scoreUnits = Units(tokens[0])
		Else
			score.place = Int(tokens[0])
		End If

		Return score
	End Function

	Function Entry:TParisDinghyEntry(entries:TParisDinghyEntry[], id:Int)
		If id < 1 Or id > entries.Length Then
			Throw "Unknown dinghy entrant"
		End If

		Return entries[id - 1]
	End Function

	Function Run:Int(path:String)
		Local stream:TStream = ReadStream(path)
		If stream = Null Then
			Throw "Cannot read dinghy results: " + path
		End If

		Local entries:TParisDinghyEntry[]
		Local comp:TCompetition = New TCompetition
		comp.name = "Paris 2024 Men's Dinghy (ILCA 7)"
		While Not stream.Eof()
			Local line:String = stream.ReadLine().Trim()
			If line = "" Or line.StartsWith("#") Then
				Continue
			End If

			Local fields:String[] = line.Split("|")
			If fields.Length <> 13 Then
				Throw "Malformed dinghy row: " + line
			End If

			Local entry:TParisDinghyEntry = New TParisDinghyEntry
			entry.id = entries.Length + 1
			entry.rank = Int(fields[0])
			entry.noc = fields[1]
			entry.name = fields[2]
			entry.races = fields[3..11]
			entry.medal = fields[11]
			entry.netUnits = Units(fields[12])
			entries :+ [entry]
			Local participant:TParticipant = New TParticipant
			participant.id = entry.id
			participant.name = entry.name
			participant.kind = EParticipantKind.Individual
			comp.participants :+ [participant]
		Wend

		stream.Close()
		If entries.Length <> 43 Then
			Throw "Incomplete Paris dinghy field"
		End If

		Local stage:TStage = New TStage
		stage.id = "PARIS_2024_ILCA7"
		stage.stageType = EStageType.Qualifying
		stage.formatCode = "regatta"
		Local cfg:TRegattaConfig = New TRegattaConfig
		cfg.scheduledRaces = 10
		cfg.minimumRaces = 3
		cfg.pointScale = 10
		cfg.discardAfterRaces = 3
		cfg.discardCount = 1
		cfg.medalPlaces = 10
		cfg.medalMultiplier = 2
		stage.config = cfg
		comp.stages = [stage]

		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterFormat("regatta", New TRegattaScheduler, New TRegattaScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		For Local round:Int = 1 To 8
			Local fixture:TFixtureState = state.stages[0].fixtures[round - 1]
			Local result:TResultPayload = New TResultPayload
			result.kind = EResultKind.Custom
			result.customCode = "regatta-race"
			For Local entry:TParisDinghyEntry = EachIn entries
				result.regattaScores :+ [RaceScore(entry.id, entry.races[round - 1])]
			Next

			engine.RecordResult(comp, state, stage.id, fixture.id, result)
		Next

		For Local round:Int = 9 To 10
			Local fixture:TFixtureState = state.stages[0].fixtures[round - 1]
			Local result:TResultPayload = New TResultPayload
			result.kind = EResultKind.StatusOnly
			result.statusCode = EFixtureStatus.Abandoned
			engine.RecordResult(comp, state, stage.id, fixture.id, result)
		Next

		If state.stages[0].fixtures.Length <> 11 Then
			Throw "Medal race was not generated"
		End If

		Local medal:TFixtureState = state.stages[0].fixtures[10]
		If medal.participantIds.Length <> 10 Then
			Throw "Wrong medal race field size"
		End If

		Local result:TResultPayload = New TResultPayload
		result.kind = EResultKind.Custom
		result.customCode = "regatta-race"
		For Local id:Int = EachIn medal.participantIds
			Local entry:TParisDinghyEntry = Entry(entries, id)
			If entry.medal = "-" Then
				Throw "Unqualified sailor entered medal race: " + entry.name
			End If

			Local score:TRegattaRaceScore = New TRegattaRaceScore
			score.participantId = id
			score.place = Int(entry.medal) / 2
			result.regattaScores :+ [score]
		Next

		engine.RecordResult(comp, state, stage.id, medal.id, result)
		If state.stages[0].status <> EStageStatus.Complete Then
			Throw "Dinghy regatta did not complete"
		End If

		For Local i:Int = 0 Until entries.Length
			Local standing:TRegattaStanding = state.stages[0].regattaStandings[i]
			Local entry:TParisDinghyEntry = Entry(entries, standing.participantId)
			If standing.participantId <> i + 1 Or entry.rank <> i + 1 Then
				Throw "Incorrect Paris dinghy ranking at " + (i + 1)
			End If

			If standing.totalUnits <> entry.netUnits Then
				Throw "Incorrect Paris dinghy points for " + entry.name + ": " + standing.totalUnits
			End If

			If (i < 10) <> standing.medalQualified Then
				Throw "Incorrect Paris dinghy medal qualification"
			End If
		Next

		Return entries.Length
	End Function
End Type
