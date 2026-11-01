' Replay is based on the pre-result snapshot and the ordered, serialized actions.
' Changed fixtures are invalidated instead of receiving an old score.
Rem
bbdoc: Rebuilds playing state after a corrected result and reports invalidated actions.
End Rem
Type TResultReplayer
	Method Correct:TResultCorrection(engine:TCompetitionEngine, comp:TCompetition, state:TCompetitionState, stageId:String, fixtureId:String, replacement:TResultPayload)
		If comp = Null Or state = Null Or replacement = Null Then
			Throw "Correction needs a competition, state, and replacement result"
		End If

		If replacement.kind = EResultKind.AdminAdjustment Or replacement.kind = EResultKind.StatusOnly Then
			Throw "Fixture correction needs a playable result"
		End If

		If state.replayBaseJson = "" Or state.actions = Null Or state.actions.Length = 0 Then
			Throw "State has no replay journal"
		End If

		Local target:Int = -1
		For Local i:Int = 0 Until state.actions.Length
			Local action:TRecordedAction = state.actions[i]
			If action.actionType = ERecordedActionType.Result And action.stageId = stageId And action.fixtureId = fixtureId And action.kind <> EResultKind.StatusOnly And action.kind <> EResultKind.AdminAdjustment Then
				If target >= 0 Then
					Throw "Fixture has more than one recorded result: " + fixtureId
				End If

				target = i
			End If
		Next

		If target < 0 Then
			Throw "No recorded result for fixture: " + fixtureId
		End If

		For Local observer:ICompetitionResultObserver = EachIn engine.resultObservers
			If ICompetitionReplayObserver(observer) = Null Then
				Throw "Result observer cannot reset for replay"
			End If
		Next

		Local converter:TJConv = engine.ResultJournalConverter()
		Local replacementJson:String = converter.ToJson(replacement)
		Local excluded:Int[] = New Int[state.actions.Length]
		Local reasons:String[] = New String[state.actions.Length]
		Local priorSuppression:Int = engine.suppressResultObservers
		Local priorRandomSeed:Int = RndSeed()
		engine.suppressResultObservers = True
		Local correction:TResultCorrection
		Try
			correction = Replay(engine, comp, state, converter, target, replacementJson, excluded, reasons)
		Catch problem:Object
			engine.suppressResultObservers = priorSuppression
			SeedRnd(priorRandomSeed)
			Throw problem
		End Try

		engine.suppressResultObservers = priorSuppression

		If engine.resultObservers <> Null And engine.resultObservers.Length > 0 Then
			For Local observer:ICompetitionResultObserver = EachIn engine.resultObservers
				ICompetitionReplayObserver(observer).OnReplayReset()
			Next
			' The successful dry run fixed the set of actions safe to replay.
			Try
				correction = Replay(engine, comp, state, converter, target, replacementJson, excluded, reasons)
			Catch problem:Object
				SeedRnd(priorRandomSeed)
				Throw problem
			End Try
		End If

		SeedRnd(priorRandomSeed)
		Return correction
	End Method

	Method Replay:TResultCorrection(engine:TCompetitionEngine, comp:TCompetition, source:TCompetitionState, converter:TJConv, target:Int, replacementJson:String, excluded:Int[], reasons:String[])
		Local answer:TResultCorrection = New TResultCorrection
		Local retry:Int
		Repeat
			retry = False
			answer.invalidated = []
			SeedRnd(source.replaySeed)
			Local rebuilt:TCompetitionState = TCompetitionState(converter.FromJson(source.replayBaseJson, "TCompetitionState"))
			If rebuilt = Null Then
				Throw "Replay baseline could not be restored"
			End If

			For Local i:Int = 0 Until source.actions.Length
				Local action:TRecordedAction = source.actions[i]
				If excluded[i] Then
					answer.invalidated :+ [Invalidation(action, reasons[i])]
					Continue
				End If

				If i >= target And Not Matches(action, rebuilt) Then
					If i = target Then
						Throw "Correction target fixture or entrants differ from the recorded action"
					End If

					excluded[i] = True
					reasons[i] = "Fixture or entrants changed after the correction"
					answer.invalidated :+ [Invalidation(action, reasons[i])]
					Continue
				End If

				Try
					If action.actionType = ERecordedActionType.ScheduleRevision Then
						rebuilt = engine.ReviseFixtureSchedule(comp, rebuilt, action.stageId, action.fixtureId, action.slotId, action.round, action.replanFlexible)
					ElseIf action.actionType = ERecordedActionType.TableTieDecision Then
						rebuilt = engine.RecordTableTieDecision(comp, rebuilt, action.stageId, action.scopeKey, action.decisionOrder, action.reason)
					Else
						Local payloadJson:String = action.payloadJson
						If i = target Then
							payloadJson = replacementJson
						End If

						Local payload:TResultPayload = TResultPayload(converter.FromJson(payloadJson, "TResultPayload"))
						engine.RecordResult(comp, rebuilt, action.stageId, action.fixtureId, payload)
					End If
				Catch problem:Object
					If i <= target Then
						Throw "Correction replay failed at " + action.stageId + "/" + action.fixtureId + ": " + problem.ToString()
					End If

					excluded[i] = True
					reasons[i] = "Recorded action no longer applies: " + problem.ToString()
					retry = True
					Exit
				End Try
			Next

			If Not retry Then
				answer.state = rebuilt
				Return answer
			End If
        Forever
	End Method

	Function Matches:Int(action:TRecordedAction, state:TCompetitionState)
		For Local stage:TStageState = EachIn state.stages
			If stage.stageId <> action.stageId Then
				Continue
			End If

			If Not SameIds(action.entrantIds, stage.entrants) Then
				Return False
			End If

			If action.actionType = ERecordedActionType.TableTieDecision Then
				Return True
			End If

			If action.actionType = ERecordedActionType.Result And action.kind = EResultKind.AdminAdjustment Then
				Return True
			End If

			For Local fixture:TFixtureState = EachIn stage.fixtures
				If fixture.id <> action.fixtureId Then
					Continue
				End If

				If fixture.homeTeamId <> action.homeTeamId Or fixture.awayTeamId <> action.awayTeamId Then
					Return False
				End If

				If Not SameIds(action.participantIds, fixture.participantIds) Then
					Return False
				End If

				If Not SameIds(action.heatEntrants, fixture.heatEntrants) Then
					Return False
				End If

				If fixture.groupKey <> action.groupKey Or fixture.seriesEventId <> action.seriesEventId Or fixture.sessionCode <> action.sessionCode Then
					Return False
				End If

				Return True
			Next

			Return False
		Next

		Return False
	End Function

	Function SameIds:Int(left:Int[], right:Int[])
		Local leftLength:Int
		Local rightLength:Int
		If left <> Null Then
			leftLength = left.Length
		End If

		If right <> Null Then
			rightLength = right.Length
		End If

		If leftLength <> rightLength Then
			Return False
		End If

		For Local i:Int = 0 Until leftLength
			If left[i] <> right[i] Then
				Return False
			End If
		Next

		Return True
	End Function

	Function Invalidation:TResultInvalidation(action:TRecordedAction, reason:String)
		Local entry:TResultInvalidation = New TResultInvalidation
		entry.action = action
		entry.reason = reason
		Return entry
	End Function
End Type
