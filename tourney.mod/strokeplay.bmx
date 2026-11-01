' Individual and team stroke play share one per-hole scoring and ranking path.
Rem
bbdoc: A per-hole value used in golf scoring and countback.
End Rem
Type TStrokeHoleValue
	Rem
	bbdoc: Gross for this stroke hole value.
	End Rem
	Field gross:Int
	Rem
	bbdoc: Net for this stroke hole value.
	End Rem
	Field net:Int
	Rem
	bbdoc: Points for this stroke hole value.
	End Rem
	Field points:Int
	Rem
	bbdoc: Value for this stroke hole value.
	End Rem
	Field value:Int
End Type

Rem
bbdoc: One golfer's round total and status.
End Rem
Type TStrokeRoundScore
	Rem
	bbdoc: Values values associated with this stroke round score.
	End Rem
	Field values:Int[]
	Rem
	bbdoc: Gross for this stroke round score.
	End Rem
	Field gross:Int
	Rem
	bbdoc: Net for this stroke round score.
	End Rem
	Field net:Int
	Rem
	bbdoc: Points for this stroke round score.
	End Rem
	Field points:Int
	Rem
	bbdoc: Aggregate for this stroke round score.
	End Rem
	Field aggregate:Int
End Type

Rem
bbdoc: Shared gross, net, Stableford, team, and countback calculations.
End Rem
Type TStrokePlayRules
	Function RoundRule:TStrokePlayRoundConfig(cfg:TStrokePlayConfig, round:Int)
		If round <= cfg.rounds.Length Then
			Return cfg.rounds[round - 1]
		End If

		Return cfg.playoffRound
	End Function

	Function HoleCount:Int(cfg:TStrokePlayConfig, round:Int)
		Local rule:TStrokePlayRoundConfig = RoundRule(cfg, round)
		If rule <> Null Then
			Return rule.holeCount
		End If

		Return cfg.playoffHoleCount
	End Function

	Function Mode:EStrokeScoringMode(cfg:TStrokePlayConfig, round:Int)
		If round > cfg.rounds.Length Then
			Return cfg.playoffScoring
		End If

		Return cfg.scoring
	End Function

	Function HasId:Int(ids:Int[], id:Int)
		For Local candidate:Int = EachIn ids
			If candidate = id Then
				Return True
			End If
		Next

		Return False
	End Function

	Function EntityIds:Int[](cfg:TStrokePlayConfig, entrants:Int[])
		If cfg.teams = Null Or cfg.teams.Length = 0 Then
			Return entrants[..]
		End If

		Local ids:Int[]
		For Local team:TStrokeTeam = EachIn cfg.teams
			ids :+ [team.teamId]
		Next

		Return ids
	End Function

	Function Team:TStrokeTeam(cfg:TStrokePlayConfig, id:Int)
		If cfg.teams = Null Then
			Return Null
		End If

		For Local team:TStrokeTeam = EachIn cfg.teams
			If team.teamId = id Then
				Return team
			End If
		Next

		Return Null
	End Function

	Function CardIds:Int[](cfg:TStrokePlayConfig, entities:Int[])
		If cfg.teams = Null Or cfg.teams.Length = 0 Then
			Return entities[..]
		End If

		Local ids:Int[]
		For Local id:Int = EachIn entities
			Local team:TStrokeTeam = Team(cfg, id)
			If team = Null Then
				Throw "Unknown stroke play team"
			End If

			For Local member:Int = EachIn team.memberIds
				If Not HasId(ids, member) Then
					ids :+ [member]
				End If
			Next
		Next

		Return ids
	End Function

	Function IsScheduled:Int(cfg:TStrokePlayConfig, fixture:TFixtureState, id:Int)
		Local team:TStrokeTeam = Team(cfg, id)
		If team = Null Then
			Return HasId(fixture.participantIds, id)
		End If

		For Local member:Int = EachIn team.memberIds
			If HasId(fixture.participantIds, member) Then
				Return True
			End If
		Next

		Return False
	End Function

	Function Handicap:Int(cfg:TStrokePlayConfig, round:Int, id:Int, hole:Int)
		Local rule:TStrokePlayRoundConfig = RoundRule(cfg, round)
		If rule = Null Then
			Return 0
		End If

		Local definitions:TStrokeHandicap[] = rule.handicaps
		For Local entry:TStrokeHandicap = EachIn definitions
			If entry.participantId <> id Then
				Continue
			End If

			If entry.received <> Null And entry.received.Length > 0 Then
				Return entry.received[hole]
			End If

			If entry.playingHandicap = 0 Then
				Return 0
			End If

			Local count:Int = rule.holeCount
			Local index:Int = rule.strokeIndexes[hole]
			If entry.playingHandicap >= 0 Then
				Local base:Int = entry.playingHandicap / count
				Local extra:Int = entry.playingHandicap Mod count
				If index <= extra Then
					base :+ 1
				End If

				Return base
			End If

			Local given:Int = -entry.playingHandicap
			Local base:Int = -(given / count)
			Local extra:Int = given Mod count
			If index > count - extra Then
				base :- 1
			End If

			Return base
		Next

		Return 0
	End Function

	Function Stableford:Int(cfg:TStrokePlayConfig, relative:Int)
		If cfg.stablefordBands <> Null And cfg.stablefordBands.Length > 0 Then
			For Local band:TStrokePointBand = EachIn cfg.stablefordBands
				If relative <= band.maxRelativeToPar Then
					Return band.points
				End If
			Next

			Return cfg.stablefordDefaultPoints
		End If

		Local points:Int = cfg.stablefordParPoints - relative
		If points < 0 Then
			points = 0
		End If

		Return points
	End Function

	Function Hole:TStrokeHoleValue(cfg:TStrokePlayConfig, fixture:TFixtureState, card:TStrokeScorecard, hole:Int)
		If card = Null Or card.status <> EStrokeCardStatus.Completed Then
			Return Null
		End If

		Local mode:EStrokeScoringMode = Mode(cfg, fixture.round)
		Local gross:Int = card.holes[hole]
		If gross = 0 And mode <> EStrokeScoringMode.Stableford Then
			Return Null
		End If

		Local result:TStrokeHoleValue = New TStrokeHoleValue
		result.gross = gross
		If gross > 0 Then
			result.net = gross - Handicap(cfg, fixture.round, card.participantId, hole)
			If mode = EStrokeScoringMode.Stableford Then
				result.points = Stableford(cfg, result.net - RoundRule(cfg, fixture.round).pars[hole])
			End If
		End If

		Select mode
			Case EStrokeScoringMode.Gross
				result.value = result.gross
			Case EStrokeScoringMode.Net
				result.value = result.net
			Case EStrokeScoringMode.Stableford
				result.value = result.points
		End Select

		Return result
	End Function

	Function Better:Int(cfg:TStrokePlayConfig, a:Int, b:Int, playoff:Int = False)
		Local mode:EStrokeScoringMode = cfg.scoring
		If playoff Then
			mode = cfg.playoffScoring
		End If

		If mode = EStrokeScoringMode.Stableford Then
			Return a > b
		End If

		Return a < b
	End Function

	Function RoundScore:TStrokeRoundScore(cfg:TStrokePlayConfig, fixture:TFixtureState, id:Int)
		Local team:TStrokeTeam = Team(cfg, id)
		Local members:Int[] = [id]
		If team <> Null Then
			members = team.memberIds
		End If

		If team = Null Then
			For Local card:TStrokeScorecard = EachIn fixture.strokeCards
				If card.participantId <> id Then
					Continue
				End If

				If card.status = EStrokeCardStatus.Completed And card.roundStrokes > 0 Then
					Local aggregate:TStrokeRoundScore = New TStrokeRoundScore
					aggregate.gross = card.roundStrokes
					aggregate.net = card.roundStrokes
					aggregate.aggregate = True
					Return aggregate
				End If

				Exit
			Next
		End If

		Local holeCount:Int = HoleCount(cfg, fixture.round)
		Local score:TStrokeRoundScore = New TStrokeRoundScore
		For Local hole:Int = 0 Until holeCount
			Local candidates:TStrokeHoleValue[]
			For Local card:TStrokeScorecard = EachIn fixture.strokeCards
				If Not HasId(members, card.participantId) Then
					Continue
				End If

				Local candidate:TStrokeHoleValue = Hole(cfg, fixture, card, hole)
				If candidate <> Null Then
					candidates :+ [candidate]
				End If
			Next

			Local needed:Int = 1
			If team <> Null Then
				needed = cfg.teamBestPerHole
				If needed = 0 Then
					needed = team.memberIds.Length
				End If
			End If

			If candidates.Length < needed Then
				Return Null
			End If

			For Local i:Int = 0 Until candidates.Length
				For Local j:Int = i + 1 Until candidates.Length
					If Better(cfg, candidates[j].value, candidates[i].value, fixture.round > cfg.rounds.Length) Then
						Local swap:TStrokeHoleValue = candidates[i]
						candidates[i] = candidates[j]
						candidates[j] = swap
					End If
				Next
			Next

			Local holeValue:Int
			For Local i:Int = 0 Until needed
				holeValue :+ candidates[i].value
				score.gross :+ candidates[i].gross
				score.net :+ candidates[i].net
				score.points :+ candidates[i].points
			Next

			score.values :+ [holeValue]
		Next

		Return score
	End Function

	Function Total:Int(cfg:TStrokePlayConfig, standing:TStrokeStanding)
		Select cfg.scoring
			Case EStrokeScoringMode.Net
				Return standing.netStrokes
			Case EStrokeScoringMode.Stableford
				Return standing.points
		End Select

		Return standing.strokes
	End Function

	Function Countback:Int(cfg:TStrokePlayConfig, a:TStrokeStanding, b:TStrokeStanding)
		For Local segment:TStrokeCountbackSegment = EachIn cfg.countback
			Local round:Int = cfg.rounds.Length - segment.roundsFromEnd
			Local av:TStrokeRoundValues
			Local bv:TStrokeRoundValues
			For Local values:TStrokeRoundValues = EachIn a.roundValues
				If values.round = round Then av = values; Exit
			Next

			For Local values:TStrokeRoundValues = EachIn b.roundValues
				If values.round = round Then bv = values; Exit
			Next

			If av = Null Or bv = Null Then
				Continue
			End If

			If av.holes = Null Or bv.holes = Null Then
				Throw "Hole countback needs hole-by-hole scorecards"
			End If

			If av.holes.Length < segment.lastHoles Or bv.holes.Length < segment.lastHoles Then
				Throw "Hole countback needs complete hole-by-hole scorecards"
			End If

			Local ascore:Int
			Local bscore:Int
			For Local i:Int = av.holes.Length - segment.lastHoles Until av.holes.Length
				ascore :+ av.holes[i]
				bscore :+ bv.holes[i]
			Next

			If ascore <> bscore Then
				If Better(cfg, ascore, bscore) Then Return -1 Else Return 1
			End If
		Next

		Return 0
	End Function

	Function SameRank:Int(cfg:TStrokePlayConfig, a:TStrokeStanding, b:TStrokeStanding, withCountback:Int = True)
		If Total(cfg, a) <> Total(cfg, b) Then
			Return False
		End If

		If withCountback And Countback(cfg, a, b) <> 0 Then
			Return False
		End If

		Return True
	End Function

	Function BetterStanding:Int(cfg:TStrokePlayConfig, a:TStrokeStanding, b:TStrokeStanding)
		Local aa:Int = a.status = "active"
		Local bb:Int = b.status = "active"
		If aa <> bb Then
			Return aa > bb
		End If

		If a.roundsCompleted <> b.roundsCompleted Then
			Return a.roundsCompleted > b.roundsCompleted
		End If

		Local av:Int = Total(cfg, a)
		Local bv:Int = Total(cfg, b)
		If av <> bv Then
			Return Better(cfg, av, bv)
		End If

		Local count:Int = Countback(cfg, a, b)
		If count <> 0 Then
			Return count < 0
		End If

		Return a.participantId < b.participantId
	End Function
End Type

Rem
bbdoc: Creates golf rounds, cut stages, and playoff holes.
End Rem
Type TStrokePlayScheduler Implements IStageScheduler, IProgressiveStageScheduler
	Method Validate(cfg:TStrokePlayConfig, entrants:Int)
		If cfg = Null Or cfg.rounds = Null Or cfg.rounds.Length = 0 Then
			Throw "Stroke play needs configured rounds"
		End If

		Local definitions:TStrokePlayRoundConfig[] = cfg.rounds[..]
		If cfg.playoffRound <> Null Then
			definitions :+ [cfg.playoffRound]
		End If

		Local roundNumber:Int
		For Local round:TStrokePlayRoundConfig = EachIn definitions
			roundNumber :+ 1
			Local mode:EStrokeScoringMode = cfg.scoring
			If roundNumber > cfg.rounds.Length Then
				mode = cfg.playoffScoring
			End If

			If round = Null Or round.holeCount < 1 Then
				Throw "Stroke play round needs a positive hole count"
			End If

			If round.pars <> Null And round.pars.Length > 0 Then
				If round.pars.Length <> round.holeCount Then
					Throw "Stroke play par list must cover every hole"
				End If

				For Local par:Int = EachIn round.pars
					If par < 1 Then
						Throw "Stroke play par must be positive"
					End If
				Next
			ElseIf mode = EStrokeScoringMode.Stableford Then
				Throw "Stableford needs par for every hole"
			End If

			If round.strokeIndexes <> Null And round.strokeIndexes.Length > 0 Then
				If round.strokeIndexes.Length <> round.holeCount Then
					Throw "Stroke indexes must cover every hole"
				End If

				Local indexes:Int[]
				For Local index:Int = EachIn round.strokeIndexes
					If index < 1 Or index > round.holeCount Or TStrokePlayRules.HasId(indexes, index) Then
						Throw "Stroke indexes must be a permutation"
					End If

					indexes :+ [index]
				Next
			End If

			Local seen:Int[]
			For Local handicap:TStrokeHandicap = EachIn round.handicaps
				If handicap = Null Or handicap.participantId <= 0 Or TStrokePlayRules.HasId(seen, handicap.participantId) Then
					Throw "Invalid or duplicate stroke handicap entrant"
				End If

				If handicap.received <> Null And handicap.received.Length > 0 Then
					If handicap.received.Length <> round.holeCount Then
						Throw "Stroke handicap must cover every hole"
					End If
				ElseIf handicap.playingHandicap <> 0 And (round.strokeIndexes = Null Or round.strokeIndexes.Length <> round.holeCount) Then
					Throw "Playing handicap needs a hole stroke index"
				End If

				seen :+ [handicap.participantId]
			Next
		Next

		Local entityCount:Int = entrants
		If cfg.teams <> Null And cfg.teams.Length > 0 Then
			entityCount = cfg.teams.Length
			Local teamIds:Int[]
			Local members:Int[]
			For Local team:TStrokeTeam = EachIn cfg.teams
				If team = Null Or team.teamId <= 0 Or TStrokePlayRules.HasId(teamIds, team.teamId) Or team.memberIds = Null Or team.memberIds.Length = 0 Then
					Throw "Invalid stroke play team"
				End If

				If cfg.teamBestPerHole < 0 Or cfg.teamBestPerHole > team.memberIds.Length Then
					Throw "Invalid team scores counted per hole"
				End If

				teamIds :+ [team.teamId]
				For Local member:Int = EachIn team.memberIds
					If member <= 0 Or TStrokePlayRules.HasId(members, member) Then
						Throw "A stroke play member must belong to one team"
					End If

					members :+ [member]
				Next
			Next

			For Local teamId:Int = EachIn teamIds
				If TStrokePlayRules.HasId(members, teamId) Then
					Throw "Stroke play team and member IDs must be distinct"
				End If
			Next
		End If

		If cfg.cutAfterRound < 0 Or cfg.cutAfterRound >= cfg.rounds.Length Then
			Throw "Stroke play cut must precede the final round"
		End If

		If cfg.cutAfterRound > 0 And (cfg.cutPlaces < 1 Or cfg.cutPlaces > entityCount) Then
			Throw "Invalid stroke play cut places"
		End If

		If cfg.playoffHoleCount < 0 Then
			Throw "Stroke play playoff hole count cannot be negative"
		End If

		If cfg.playoffRound = Null And cfg.playoffHoleCount > 0 And cfg.playoffScoring = EStrokeScoringMode.Stableford Then
			Throw "Stableford playoff needs a playoff round with pars"
		End If

		Local lastThreshold:Int = -2147483647
		For Local band:TStrokePointBand = EachIn cfg.stablefordBands
			If band = Null Or band.maxRelativeToPar <= lastThreshold Then
				Throw "Stableford bands must have increasing thresholds"
			End If

			lastThreshold = band.maxRelativeToPar
		Next

		For Local segment:TStrokeCountbackSegment = EachIn cfg.countback
			If segment = Null Or segment.roundsFromEnd < 0 Or segment.roundsFromEnd >= cfg.rounds.Length Then
				Throw "Invalid stroke play countback round"
			End If

			Local round:Int = cfg.rounds.Length - segment.roundsFromEnd
			If segment.lastHoles < 1 Or segment.lastHoles > cfg.rounds[round - 1].holeCount Then
				Throw "Invalid countback hole count"
			End If
		Next
	End Method

	Method NewRound:TFixtureState(stage:TStage, ids:Int[], round:Int)
		Local fixture:TFixtureState = New TFixtureState
		fixture.id = stage.id + "_ROUND_" + round
		fixture.round = round
		fixture.participantIds = ids[..]
		fixture.status = EFixtureStatus.Scheduled
		Return fixture
	End Method

	Method BuildFixtures:TFixtureState[](comp:TCompetition, stage:TStage)
		If comp.participants = Null Or comp.participants.Length = 0 Then
			Throw "Stroke play needs entrants"
		End If

		Local cfg:TStrokePlayConfig = TStrokePlayConfig(stage.config)
		Validate(cfg, comp.participants.Length)
		Local ids:Int[]
		If cfg.teams <> Null And cfg.teams.Length > 0 Then
			Local entities:Int[] = TStrokePlayRules.EntityIds(cfg, Null)
			For Local entity:Int = EachIn entities
				Local found:Int
				For Local participant:TParticipant = EachIn comp.participants
					If participant.id = entity Then found = True; Exit
				Next

				If Not found Then
					Throw "Stroke play team needs a competition participant"
				End If
			Next

			ids = TStrokePlayRules.CardIds(cfg, entities)
		Else
			For Local participant:TParticipant = EachIn comp.participants
				ids :+ [participant.id]
			Next
		End If

		Return [NewRound(stage, ids, 1)]
	End Method

	Method NextFixtures:TFixtureState[](comp:TCompetition, stage:TStage, state:TStageState)
		Local cfg:TStrokePlayConfig = TStrokePlayConfig(stage.config)
		Local latest:TFixtureState = state.fixtures[state.fixtures.Length - 1]
		If latest.status <> EFixtureStatus.Completed Then
			Return Null
		End If

		If latest.round >= cfg.rounds.Length Then
			Local tied:Int[]
			If latest.round = cfg.rounds.Length Then
				If state.strokeStandings = Null Or state.strokeStandings.Length = 0 Then
					Return Null
				End If

				Local leader:TStrokeStanding = state.strokeStandings[0]
				For Local standing:TStrokeStanding = EachIn state.strokeStandings
					If standing.status = "active" And standing.roundsCompleted = cfg.rounds.Length And TStrokePlayRules.SameRank(cfg, leader, standing) Then
						tied :+ [standing.participantId]
					End If
				Next
			Else
				Local best:Int
				Local found:Int
				Local entities:Int[] = TStrokePlayRules.EntityIds(cfg, latest.participantIds)
				For Local id:Int = EachIn entities
					If Not TStrokePlayRules.IsScheduled(cfg, latest, id) Then
						Continue
					End If

					Local score:TStrokeRoundScore = TStrokePlayRules.RoundScore(cfg, latest, id)
					If score = Null Then
						Throw "Playoff needs a completed team or individual score"
					End If

					Local total:Int
					For Local value:Int = EachIn score.values
						total :+ value
					Next

					If Not found Or TStrokePlayRules.Better(cfg, total, best, True) Then best = total; tied = Null; found = True

					If total = best Then
						tied :+ [id]
					End If
				Next
			End If

			If tied.Length < 2 Then
				Return Null
			End If

			If TStrokePlayRules.HoleCount(cfg, cfg.rounds.Length + 1) = 0 Then
				Throw "Stroke play lead is tied; configure playoff holes and retry progression"
			End If

			Local playoff:TFixtureState = NewRound(stage, TStrokePlayRules.CardIds(cfg, tied), latest.round + 1)
			playoff.id = stage.id + "_PLAYOFF_" + (latest.round + 1 - cfg.rounds.Length)
			Return [playoff]
		End If

		Local entities:Int[]
		If latest.round = cfg.cutAfterRound Then
			Local cutoff:TStrokeStanding
			Local places:Int
			For Local standing:TStrokeStanding = EachIn state.strokeStandings
				If standing.status <> "active" Then
					Continue
				End If

				places :+ 1
				If places = cfg.cutPlaces Then
					cutoff = standing
				End If

				If places > cfg.cutPlaces And cutoff <> Null Then
					If Not TStrokePlayRules.SameRank(cfg, cutoff, standing, cfg.cutUsesCountback) Then
						Exit
					End If
				End If

				entities :+ [standing.participantId]
			Next
		Else
			For Local standing:TStrokeStanding = EachIn state.strokeStandings
				If standing.status = "active" And TStrokePlayRules.IsScheduled(cfg, latest, standing.participantId) Then
					entities :+ [standing.participantId]
				End If
			Next
		End If

		If entities.Length = 0 Then
			Throw "Stroke play has no eligible entrants for next round"
		End If

		Return [NewRound(stage, TStrokePlayRules.CardIds(cfg, entities), latest.round + 1)]
	End Method
End Type

Rem
bbdoc: Updates golf standings and applies the cut or playoff result.
End Rem
Type TStrokePlayScorer Implements IStageScorer
	Method ApplyResult(comp:TCompetition, stage:TStage, state:TStageState, fixtureId:String, result:TResultPayload)
		If result.kind <> EResultKind.Custom Or result.customCode <> "stroke-play-card" Then
			Throw "Stroke play needs scorecards"
		End If

		Local fixture:TFixtureState
		For Local candidate:TFixtureState = EachIn state.fixtures
			If candidate.id = fixtureId Then fixture = candidate; Exit
		Next

		If fixture = Null Then
			Throw "Unknown stroke play round"
		End If

		If result.strokeCards = Null Or result.strokeCards.Length <> fixture.participantIds.Length Then
			Throw "Stroke play result must cover every round entrant"
		End If

		Local cfg:TStrokePlayConfig = TStrokePlayConfig(stage.config)
		Local holeCount:Int = TStrokePlayRules.HoleCount(cfg, fixture.round)
		Local mode:EStrokeScoringMode = TStrokePlayRules.Mode(cfg, fixture.round)
		Local seen:Int[]
		Local cardMode:Int ' 1 = hole scores, 2 = round totals
		For Local card:TStrokeScorecard = EachIn result.strokeCards
			If card = Null Then
				Throw "Missing stroke play scorecard"
			End If

			If Not TStrokePlayRules.HasId(fixture.participantIds, card.participantId) Then
				Throw "Stroke play scorecard has an unassigned entrant"
			End If

			If TStrokePlayRules.HasId(seen, card.participantId) Then
				Throw "Duplicate stroke play scorecard"
			End If

			seen :+ [card.participantId]
			If fixture.round > cfg.rounds.Length And card.status <> EStrokeCardStatus.Completed Then
				Throw "Playoff scorecards must be completed"
			End If

			If card.roundStrokes < 0 Then
				Throw "Round strokes cannot be negative"
			End If

			If card.status = EStrokeCardStatus.Completed Then
				If card.roundStrokes > 0 Then
					If fixture.round > cfg.rounds.Length Or mode <> EStrokeScoringMode.Gross Or (cfg.teams <> Null And cfg.teams.Length > 0) Or (cfg.countback <> Null And cfg.countback.Length > 0) Then
						Throw "Round totals require individual gross scoring without hole countback"
					End If

					If card.holes <> Null And card.holes.Length > 0 Then
						Throw "Round total cannot also contain hole scores"
					End If

					If cardMode = 1 Then
						Throw "Round result cannot mix totals and hole scores"
					End If

					cardMode = 2
				Else
					If cardMode = 2 Then
						Throw "Round result cannot mix totals and hole scores"
					End If

					cardMode = 1
					If card.holes = Null Or card.holes.Length <> holeCount Then
						Throw "Completed scorecard must cover every hole"
					End If

					For Local strokes:Int = EachIn card.holes
						If strokes < 0 Or (strokes = 0 And mode <> EStrokeScoringMode.Stableford And (cfg.teams = Null Or cfg.teamBestPerHole = 0)) Then
							Throw "Hole strokes must be positive unless the format permits an unplayed hole"
						End If
					Next
				End If
			ElseIf (card.holes <> Null And card.holes.Length > 0) Or card.roundStrokes <> 0 Then
				Throw "Incomplete scorecard cannot contain an official round score"
			End If
		Next

		fixture.strokeCards = result.strokeCards[..]
		fixture.resultLog :+ [result]
		fixture.status = EFixtureStatus.Completed
	End Method

	Method ComputeStandings(comp:TCompetition, stage:TStage, state:TStageState)
		Local cfg:TStrokePlayConfig = TStrokePlayConfig(stage.config)
		state.strokePlayWinnerId = 0
		Local standings:TStrokeStanding[]
		Local entities:Int[] = TStrokePlayRules.EntityIds(cfg, state.entrants)
		For Local id:Int = EachIn entities
			Local standing:TStrokeStanding = New TStrokeStanding
			standing.participantId = id
			standing.status = "active"
			For Local fixture:TFixtureState = EachIn state.fixtures
				If fixture.round > cfg.rounds.Length Or fixture.status <> EFixtureStatus.Completed Then
					Continue
				End If

				If Not TStrokePlayRules.IsScheduled(cfg, fixture, id) Then
					Continue
				End If

				Local score:TStrokeRoundScore = TStrokePlayRules.RoundScore(cfg, fixture, id)
				If score = Null Then
					standing.status = "withdrawn"
					If cfg.teams = Null Or cfg.teams.Length = 0 Then
						For Local card:TStrokeScorecard = EachIn fixture.strokeCards
							If card.participantId <> id Then
								Continue
							End If

							Select card.status
								Case EStrokeCardStatus.Disqualified
									standing.status = "disqualified"
								Case EStrokeCardStatus.DidNotStart
									standing.status = "did-not-start"
							End Select
						Next
					End If
				Else
					standing.strokes :+ score.gross
					standing.netStrokes :+ score.net
					standing.points :+ score.points
					standing.roundsCompleted :+ 1
					Local values:TStrokeRoundValues = New TStrokeRoundValues
					values.round = fixture.round
					values.holes = score.values
					If score.aggregate Then
						values.roundStrokes = score.gross
					End If

					standing.roundValues :+ [values]
				End If
			Next

			standings :+ [standing]
		Next

		For Local i:Int = 0 Until standings.Length
			For Local j:Int = i + 1 Until standings.Length
				If TStrokePlayRules.BetterStanding(cfg, standings[j], standings[i]) Then
					Local swap:TStrokeStanding = standings[i]
					standings[i] = standings[j]
					standings[j] = swap
				End If
			Next
		Next

		If cfg.cutAfterRound > 0 Then
			Local advancing:Int[]
			For Local fixture:TFixtureState = EachIn state.fixtures
				If fixture.round = cfg.cutAfterRound + 1 Then
					For Local entity:Int = EachIn entities
						If TStrokePlayRules.IsScheduled(cfg, fixture, entity) Then
							advancing :+ [entity]
						End If
					Next

					Exit
				End If
			Next

			If advancing <> Null Then
				For Local standing:TStrokeStanding = EachIn standings
					If standing.status = "active" And Not TStrokePlayRules.HasId(advancing, standing.participantId) Then
						standing.status = "cut"
					End If
				Next
			End If
		End If

		Local latest:TFixtureState = state.fixtures[state.fixtures.Length - 1]
		If latest.round > cfg.rounds.Length And latest.status = EFixtureStatus.Completed Then
			Local best:Int
			Local winner:Int
			Local tied:Int
			For Local entity:Int = EachIn entities
				If Not TStrokePlayRules.IsScheduled(cfg, latest, entity) Then
					Continue
				End If

				Local score:TStrokeRoundScore = TStrokePlayRules.RoundScore(cfg, latest, entity)
				If score = Null Then
					Continue
				End If

				Local total:Int
				For Local value:Int = EachIn score.values
					total :+ value
				Next

				If tied = 0 Or TStrokePlayRules.Better(cfg, total, best, True) Then best = total; winner = entity; tied = 1

				If total = best And entity <> winner Then
					tied :+ 1
				End If
			Next

			If tied = 1 Then
				state.strokePlayWinnerId = winner
				For Local i:Int = 1 Until standings.Length
					If standings[i].participantId = winner Then
						Local swap:TStrokeStanding = standings[0]
						standings[0] = standings[i]
						standings[i] = swap
						Exit
					End If
				Next
			End If
		End If

		Local rows:TLeaderboardRow[]
		For Local standing:TStrokeStanding = EachIn standings
			Local row:TLeaderboardRow = New TLeaderboardRow
			row.participantId = standing.participantId
			row.points = standing.points
			Local gross:TLeaderboardMetric = New TLeaderboardMetric
			gross.code = "strokes"
			gross.value = standing.strokes
			Local net:TLeaderboardMetric = New TLeaderboardMetric
			net.code = "netStrokes"
			net.value = standing.netStrokes
			Local points:TLeaderboardMetric = New TLeaderboardMetric
			points.code = "stablefordPoints"
			points.value = standing.points
			Local rounds:TLeaderboardMetric = New TLeaderboardMetric
			rounds.code = "roundsCompleted"
			rounds.value = standing.roundsCompleted
			row.metrics = [gross, net, points, rounds]
			rows :+ [row]
		Next

		state.strokeStandings = standings
		state.leaderboard.rows = rows
	End Method

	Method IsComplete:Int(comp:TCompetition, stage:TStage, state:TStageState) { asBool }
		Local cfg:TStrokePlayConfig = TStrokePlayConfig(stage.config)
		Local finalFixture:TFixtureState = state.fixtures[state.fixtures.Length - 1]
		If state.strokePlayWinnerId > 0 Then
			Return True
		End If

		If finalFixture.round <> cfg.rounds.Length Or finalFixture.status <> EFixtureStatus.Completed Then
			Return False
		End If

		If state.strokeStandings.Length = 0 Or state.strokeStandings[0].status <> "active" Or state.strokeStandings[0].roundsCompleted <> cfg.rounds.Length Then
			Throw "Stroke play has no completed finalist"
		End If

		If state.strokeStandings.Length > 1 Then
			Local first:TStrokeStanding = state.strokeStandings[0]
			Local second:TStrokeStanding = state.strokeStandings[1]
			If second.status = "active" And TStrokePlayRules.SameRank(cfg, first, second) Then
				Throw "Stroke play lead is tied; a playoff is required"
			End If
		End If

		Return True
	End Method
End Type
