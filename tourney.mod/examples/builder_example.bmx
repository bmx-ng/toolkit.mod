SuperStrict

Framework BRL.StandardIO
Import toolkit.tourney

' Two groups send their winners into a final. The builder produces an ordinary
' TCompetition; the usual engine plays it and the usual serializers can save it.
Local builder:TCompetitionBuilder = New TCompetitionBuilder("Four-team cup")
For Local id:Int = 1 To 4
	Local team:TParticipant = New TParticipant
	team.id = id
	team.name = "Team " + id
	team.kind = EParticipantKind.Team
	builder.AddParticipant(team)
Next

builder.AddGroups("GROUPS", 2, 2)
builder.AddBracket("FINAL", 2)
builder.ConnectTop("GROUPS", "FINAL", 1, EFilterScope.PerGroup)
Local competition:TCompetition = builder.BuildChecked()

Local engine:TCompetitionEngine = New TCompetitionEngine
engine.RegisterScheduler(EStageType.Group, New TGroupScheduler)
engine.RegisterScorer(EStageType.Group, New TGroupScorer)
engine.RegisterAdvancer(EStageType.Group, New TGroupAdvancer)
engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
Local state:TCompetitionState = engine.Initialize(competition)
For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
	Print fixture.id + ": " + fixture.homeTeamId + " vs " + fixture.awayTeamId
	engine.RecordResultAndAdvance(competition, state, "GROUPS", fixture.id, 1, 0)
Next

Local finalFixture:TFixtureState = state.stages[1].fixtures[0]
Print "Final: " + finalFixture.homeTeamId + " vs " + finalFixture.awayTeamId
engine.RecordResultAndAdvance(competition, state, "FINAL", finalFixture.id, 1, 0)
Print "Winner: Team " + finalFixture.homeTeamId
