SuperStrict

Framework BRL.StandardIO
Import toolkit.tourney
Include "world_cup_2026_replay.bmx"

Local timeline:TCompetitionTimeline = New TCompetitionTimeline
Local champion:Int = TWorldCup2026Replay.Run(AppDir + "/world_cup_2026.tsv", timeline)
Print "World Cup replay: " + timeline.participants.Length + " teams, " + timeline.frames.Length + " matches, champion " + timeline.Participant(champion).name
