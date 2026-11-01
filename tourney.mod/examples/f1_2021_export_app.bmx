SuperStrict

Framework BRL.StandardIO
Import toolkit.tourney
Include "f1_2021_replay.bmx"
Include "f1_2021_snapshot_export.bmx"

Local outputPath:String = AppDir + "/f1_2021_snapshots.tsv"
If AppArgs.Length > 1 Then
	outputPath = AppArgs[1]
End If

Local sessions:Int = TF12021SnapshotExport.Export(AppDir + "/f1_2021_replay.tsv", outputPath)
Print "Exported " + sessions + " F1 sessions to " + outputPath
