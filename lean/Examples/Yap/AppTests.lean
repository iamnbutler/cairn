import Examples.Yap.App

/-! Checks of the app layer's encodings and decodings (`Examples.Yap.App`): the files Yap and
Yap (Cairn) share, and OpenAI's replies. -/

namespace Examples.Yap.AppTests
open Examples.Yap Cairn


#guard (transcription 7 0 none "m" none).wholeClip == some 7
#guard (transcription 7 0 (some 3) "m" none).wholeClip == none
#guard transcriptLine { clip := some 1, text := "Hi \"there\"", app := some "Notes", date := 1792749600000 }
  == "{\"app\":\"Notes\",\"date\":\"2026-10-23T10:00:00Z\",\"text\":\"Hi \\\"there\\\"\",\"typed\":false}"
#guard (parseTranscript "{\"date\":\"2026-10-23T10:00:00Z\",\"text\":\"x\",\"typed\":true}").map (·.date) == some 1792749600000
#guard configText {} == "{\n  \"keepTranscripts\" : true,\n  \"key\" : \"rightCommand\",\n  \"overlay\" : true,\n  \"retentionDays\" : 30\n}"
#guard parseConfig "{\"retentionDays\": 7, \"key\": \"f13\"}".toUTF8 == .ok { retentionDays := some 7, key := some "f13" }
#guard parseConfig "{\"retentionDays\": \"7\"}".toUTF8 == .unreadable "\"retentionDays\" should be a whole number"
#guard parseConfig "{".toUTF8 == .unreadable "not valid JSON"
#guard dayFiles ["2026-10-22.jsonl", ".DS_Store", "2026-10-23.jsonl", "2026-01-01.jsonl"]
  == ["2026-10-23.jsonl", "2026-10-22.jsonl", "2026-01-01.jsonl"]
#guard replaceLast "a\nb\na\n" "a\n" "c\n" == some "a\nb\nc\n"
#guard replaceLast "a\nb\n" "x\n" "c\n" == none
#guard (match transcriptReply (.http 200 [] "{\"text\":\"Hello.\"}".toUTF8) with | .ok t => t == "Hello." | _ => false)
#guard (match transcriptReply (.http 401 [] "{\"error\":{\"message\":\"Bad key\"}}".toUTF8) with
  | .failed e => e == "OpenAI 401: Bad key" | _ => false)
def boot1 : Boot :=
  { prefs := some none, model := some (some "whisper-1"), enabled := some (some false), submits := some none }
def boot2 : Boot :=
  { prefs := some (some (some true, none)), model := some none, enabled := some (some false), submits := some none }
#guard launchPrefs boot1 == some { enabled := false, submits := false, model := some "whisper-1" }
#guard launchPrefs boot2 == some { enabled := true, submits := false, model := none }
#guard (launchPrefs { boot1 with submits := none }).isNone

end Examples.Yap.AppTests
