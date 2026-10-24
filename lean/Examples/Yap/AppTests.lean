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
#guard parseConfig "{\"retentionDays\": \"7\"}".toUTF8 == .unreadable notInFormat
#guard parseConfig "{".toUTF8 == .unreadable notInFormat
#guard parseConfig "null".toUTF8 == .unreadable isMissing
-- As Yap's `Config` decodes (each checked against `JSONDecoder`): null is left out, a trailing
-- comma and a byte order mark are fine, whole numbers may have a fraction or exponent.
#guard parseConfig "{\"retentionDays\":null,\"key\":null}".toUTF8 == .ok {}
#guard parseConfig "{\"retentionDays\":1e1,}".toUTF8 == .ok { retentionDays := some 10 }
#guard parseConfig "\uFEFF{\"key\":\"f13\",\"key\":\"f14\"}".toUTF8 == .ok { key := some "f13" }
#guard parseConfig (ByteArray.mk #[0x7b, 0, 0x7d, 0]) == .ok {}
#guard parseConfig (ByteArray.mk #[0xff, 0xfe, 0x7b, 0, 0x7d, 0]) == .ok {}
#guard ["{\"retentionDays\":30.5}", "{\"keepTranscripts\":1}", "[]", "", "5", "{\"retentionDays\":01}",
    "{\"key\":5}", "{\"overlay\":false} x"].all fun t => parseConfig t.toUTF8 == .unreadable notInFormat
#guard configText { key := "a/b" } == "{\n  \"keepTranscripts\" : true,\n  \"key\" : \"a\\/b\",\n  \"overlay\" : true,\n  \"retentionDays\" : 30\n}"
-- Day-file lines as `JSONDecoder` reads a `Transcript`.
#guard (parseTranscript "{\"date\":\"2026-10-23T12:00:00+0200\",\"text\":\"x\",\"typed\":true,\"app\":null}").map (·.date) == some 1792749600000
#guard (parseTranscript "{\"date\":\"2026-10-23T10:00:00Z\",\"text\":\"x\",\"typed\":true,\"app\":5}").isNone
#guard (parseTranscript "{\"date\":\"2026-10-23T10:00:00Z\",\"text\":\"x\",\"typed\":1}").isNone
#guard (parseTranscript "{\"date\":\"2026-10-23T10:00:00\",\"text\":\"x\",\"typed\":true}").isNone
#guard (fileTranscripts "\uFEFF{\"date\":\"2026-10-23T10:00:00Z\",\"text\":\"a\u2028b\",\"typed\":true}\r\n".toUTF8).map (·.text) == ["a\u2028b"]
#guard Dates.parseIso "2026-10-23T24:30:00Z" == some 1792801800000 && Dates.parseIso "2026-02-31T10:00:00Z" == some 1772532000000
#guard Dates.parseIso "0001-01-01T00:00:00Z" == some (-62135769600000) && Dates.parseIso "2026-10-23T10:00:00+19" == none
#guard Dates.parseIso "2026-10-23T10:00:00.5GMT-01" == some 1792753200500 && Dates.parseIso "2026-13-01T00:00:00Z" == none
#guard readUtf8 "\uFEFF\uFEFFb".toUTF8 == some "\uFEFFb"
#guard parseFlag "YeS".toUTF8 && parseFlag "1".toUTF8 && !parseFlag "2".toUTF8 && !parseFlag " 1".toUTF8 && !parseFlag "Y".toUTF8
#guard dayFiles ["2026-10-22.jsonl", ".DS_Store", "2026-10-23.jsonl", "2026-01-01.jsonl"]
  == ["2026-10-23.jsonl", "2026-10-22.jsonl", "2026-01-01.jsonl"]
#guard replaceLast "a\nb\na\n" "a\n" "c\n" == some "a\nb\nc\n"
#guard replaceLast "a\nb\n" "x\n" "c\n" == none
#guard (match transcriptReply (.http 200 [] "{\"text\":\"Hello.\"}".toUTF8) with | .ok t => t == "Hello." | _ => false)
#guard (match transcriptReply (.http 401 [] "{\"error\":{\"message\":\"Bad key\"}}".toUTF8) with
  | .failed e => e == "OpenAI 401: Bad key" | _ => false)
#guard transcriptReply (.http 200 [] "{}".toUTF8) == .failed isMissing
#guard transcriptReply (.http 200 [] "{\"text\":null}".toUTF8) == .failed isMissing
#guard transcriptReply (.http 200 [] "{\"text\":5}".toUTF8) == .failed notInFormat
#guard transcriptReply (.http 200 [] "<html>".toUTF8) == .failed notInFormat
#guard transcriptReply (.http 200 [] "{\"text\":\"a\",}".toUTF8) == .ok "a"
-- The first 500 bytes, a character cut in two shown as U+FFFD (`String(decoding:as:)`).
#guard transcriptReply (.http 502 [] (String.ofList (List.replicate 499 'x') ++ "é").toUTF8)
  == .failed ("OpenAI 502: " ++ String.ofList (List.replicate 499 'x') ++ "\uFFFD")
#guard utf8Lossy [0x61, 0xF0, 0x9F, 0x98, 0x41, 0xC0, 0xAF, 0xED, 0xA0, 0x80, 0xE2, 0x82, 0xAC] == "a\uFFFDA\uFFFD\uFFFD\uFFFD\uFFFD\uFFFD€"
-- Typing failures in Yap's words.
#guard typeFault (some "Notes") .other "app 4 would not come to the front" == "Notes would not come to the front"
#guard typeFault none .other "x" == "that app would not come to the front" && typeFault none .notFound "x" == "that app is no longer running"
#guard typeFault none .denied "x" == "Accessibility is not granted, so Yap cannot type"
def boot1 : Boot :=
  { prefs := some none, model := some (some "whisper-1"), enabled := some (some false), submits := some none }
def boot2 : Boot :=
  { prefs := some (some (some true, none)), model := some none, enabled := some (some false), submits := some none }
#guard launchPrefs boot1 == some { enabled := false, submits := false, model := some "whisper-1" }
#guard launchPrefs boot2 == some { enabled := true, submits := false, model := none }
#guard (launchPrefs { boot1 with model := some (some "") }).map (·.model) == some (some "")
#guard (launchPrefs { boot1 with submits := none }).isNone

end Examples.Yap.AppTests
