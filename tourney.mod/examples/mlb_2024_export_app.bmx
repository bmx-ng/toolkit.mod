SuperStrict

Framework BRL.StandardIO
Import Toolkit.Tourney
Import Text.JConv
Include "mlb_2024_replay.bmx"
Include "mlb_2024_snapshot_export.bmx"

Local outputPath:String = AppDir + "/mlb_2024_snapshots.tsv"
If AppArgs.Length > 1 Then
	outputPath = AppArgs[1]
End If

Local games:Int = TMLB2024SnapshotExport.Export(AppDir + "/mlb_2024_replay.tsv", outputPath)
Print "Exported " + games + " MLB games to " + outputPath
