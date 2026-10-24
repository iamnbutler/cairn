module

public import Examples.Yap.App
public import Examples.Yap.Starts
public import Examples.Yap.Sending
public import Examples.Yap.Recent

/-! # Yap on Cairn: the machine's guarantees, through `receive`

The claims ^311–^323 were proved of `step` (`Examples.Yap.Proofs` and friends). The app runs
`step` inside `receive` (`Examples.Yap.App`), so each is carried through it here: what reaches
the host is the effects `receive` returns, and those come from three places only.

* The app's own requests (`Ask`): by their type, never an upload, a `typeText` or a
  `deleteFile` (`Ask.machineOnly`).
* The machine's commands, translated in order by `trAll`: an upload comes only from
  `transcribe` or `transcribeChunk`, a `typeText` only from `type`, a `deleteFile` only from
  `deleteDays` (`tr_upload`, `tr_typeText`, `tr_deleteFile`).
* The samples the app lets go (`collect`): `forgetClip`, an `Ask`.

And the input the machine gets is fixed by the message (`prep_tick`, `prep_reply`,
`prep_days`): only the clock and timers tick, only a reply `2q` is the machine's reply `q`. -/

@[expose] public section

namespace Examples.Yap
open Cairn

/-! ## What only the machine asks for -/

/-- An upload, a `typeText` or a `deleteFile`. -/
def _root_.Cairn.Request.machineOnly : Request → Bool
  | .upload .. | .typeText .. | .deleteFile _ => true
  | _ => false

theorem Ask.request_ok (a : Ask) : Request.machineOnly a.request = false := by
  cases a <;> rfl

theorem Ask.effect_ok {x : Nat × Ask} {id : Nat} {r : Request} (h : Ask.effect x = .request id r) :
    r.machineOnly = false := by
  simp only [Ask.effect, Effect.request.injEq] at h
  rw [← h.2]; exact Ask.request_ok _

theorem mem_asks_ok {as : List (Nat × Ask)} {id : Nat} {r : Request}
    (h : Effect.request id r ∈ as.map Ask.effect) : r.machineOnly = false := by
  obtain ⟨x, -, hx⟩ := List.mem_map.1 h
  exact Ask.effect_ok hx

theorem not_mem_asks {as : List (Nat × Ask)} {id : Nat} {r : Request}
    (h : Effect.request id r ∈ as.map Ask.effect) (hr : r.machineOnly = true) : False := by
  rw [mem_asks_ok h] at hr; cases hr

theorem overlay_apply_ok (o : Overlay) (now c : Nat) (oc : OverlayCmd) {id : Nat} {r : Request}
    (h : Effect.request id r ∈ (o.apply now c oc).2) : False := by
  cases oc <;> simp only [Overlay.apply] at h
  all_goals first
    | (simp at h; done)
    | (split at h <;> simp at h)
    | (split at h <;> (try split at h) <;> simp at h)

theorem mem_deletes {io : Io} {ds : List Nat} {e : Effect} (h : e ∈ (deletes io ds).2) :
    ∃ id d, d ∈ ds ∧ e = .request id (.deleteFile (dayPath d)) := by
  induction ds generalizing io with
  | nil => simp [deletes] at h
  | cons d ds ih =>
    simp only [deletes, List.mem_cons] at h
    rcases h with h | h
    · exact ⟨_, d, List.mem_cons_self, h⟩
    · obtain ⟨id, d', hd, he⟩ := ih h
      exact ⟨id, d', List.mem_cons_of_mem _ hd, he⟩

/-- The commands `tr` sends as the app's own requests. -/
theorem tr_ask (io : Io) (c : Cmd)
    (h : c.kind ∉ [.transcribe, .chunk, .type, .save, .saveConfig, .deleteDays, .copy, .wakeAt,
      .overlay]) :
    (tr io c).2 = (trAsk io c).2.map Ask.effect := by
  cases c <;> first | rfl | simp [Cmd.kind] at h

/-- **A `typeText` request is a `type` command**, sent as `2q`. -/
theorem tr_typeText {io : Io} {c : Cmd} {id pid : Nat} {text : String} {ret : Bool}
    (h : Effect.request id (.typeText pid text ret) ∈ (tr io c).2) :
    ∃ q n, c = .type q n pid text ret ∧ id = 2 * q := by
  by_cases hk : c.kind ∈ [.transcribe, .chunk, .type, .save, .saveConfig, .deleteDays, .copy,
      .wakeAt, .overlay]
  · cases c <;> simp [Cmd.kind] at hk <;> simp only [tr] at h
    case type q n p t r =>
      simp only [List.mem_singleton, Effect.request.injEq, Request.typeText.injEq] at h
      obtain ⟨rfl, rfl, rfl, rfl⟩ := h
      exact ⟨q, n, rfl, rfl⟩
    case deleteDays ds =>
      obtain ⟨_, _, _, he⟩ := mem_deletes h
      simp at he
    case overlay c o => exact (overlay_apply_ok _ _ _ _ h).elim
    all_goals simp [transcription] at h
  · rw [tr_ask io c hk] at h
    exact (not_mem_asks h rfl).elim

/-- **A `deleteFile` request is a `deleteDays` command's**, for one of its days. -/
theorem tr_deleteFile {io : Io} {c : Cmd} {id : Nat} {path : String}
    (h : Effect.request id (.deleteFile path) ∈ (tr io c).2) :
    ∃ ds d, c = .deleteDays ds ∧ d ∈ ds ∧ path = dayPath d := by
  by_cases hk : c.kind ∈ [.transcribe, .chunk, .type, .save, .saveConfig, .deleteDays, .copy,
      .wakeAt, .overlay]
  · cases c <;> simp [Cmd.kind] at hk <;> simp only [tr] at h
    case deleteDays ds =>
      obtain ⟨_, d, hd, he⟩ := mem_deletes h
      simp only [Effect.request.injEq, Request.deleteFile.injEq] at he
      exact ⟨ds, d, rfl, hd, he.2⟩
    case overlay c o => exact (overlay_apply_ok _ _ _ _ h).elim
    all_goals simp [transcription] at h
  · rw [tr_ask io c hk] at h
    exact (not_mem_asks h rfl).elim

/-- **An upload is a transcription command's**: the whole clip for `transcribe`, a range of
windows for `transcribeChunk`, under the command's prompt, sent as `2q`. -/
theorem tr_upload {io : Io} {c : Cmd} {id : Nat} {r : Request} (h : Effect.request id r ∈ (tr io c).2)
    (hu : r.machineOnly = true) :
    (∃ q n mo p, c = .transcribe q n mo p ∧ id = 2 * q ∧ r = transcription n 0 none mo p) ∨
    (∃ q n a b mo p, c = .transcribeChunk q n a b mo p ∧ id = 2 * q ∧
      r = transcription n (a / Chunker.windowSamples) (some (b / Chunker.windowSamples)) mo p) ∨
    (∃ q n pid text ret, c = .type q n pid text ret ∧ r = .typeText pid text ret) ∨
    (∃ ds path, c = .deleteDays ds ∧ r = .deleteFile path) := by
  by_cases hk : c.kind ∈ [.transcribe, .chunk, .type, .save, .saveConfig, .deleteDays, .copy,
      .wakeAt, .overlay]
  · cases c <;> simp [Cmd.kind] at hk <;> simp only [tr] at h
    case transcribe q n mo p =>
      simp only [List.mem_singleton, Effect.request.injEq] at h
      exact Or.inl ⟨q, n, mo, p, rfl, h.1, h.2⟩
    case transcribeChunk q n a b mo p =>
      simp only [List.mem_singleton, Effect.request.injEq] at h
      exact Or.inr (Or.inl ⟨q, n, a, b, mo, p, rfl, h.1, h.2⟩)
    case type q n pid text ret =>
      simp only [List.mem_singleton, Effect.request.injEq] at h
      exact Or.inr (Or.inr (Or.inl ⟨q, n, pid, text, ret, rfl, h.2⟩))
    case deleteDays ds =>
      obtain ⟨_, d, -, he⟩ := mem_deletes h
      simp only [Effect.request.injEq] at he
      exact Or.inr (Or.inr (Or.inr ⟨ds, _, rfl, he.2⟩))
    case overlay c o => exact (overlay_apply_ok _ _ _ _ h).elim
    case save q t =>
      simp only [List.mem_singleton, Effect.request.injEq] at h
      rw [h.2] at hu; simp [Request.machineOnly] at hu
    case saveConfig q t =>
      simp only [List.mem_singleton, Effect.request.injEq] at h
      rw [h.2] at hu; simp [Request.machineOnly] at hu
    all_goals simp at h
  · rw [tr_ask io c hk] at h
    rw [mem_asks_ok h] at hu; cases hu

/-! ## The translation keeps order -/

theorem trAll_append (io : Io) (a b : List Cmd) :
    trAll io (a ++ b) = ((trAll (trAll io a).1 b).1, (trAll io a).2 ++ (trAll (trAll io a).1 b).2) := by
  induction a generalizing io with
  | nil => simp [trAll]
  | cons c a ih => simp [trAll, ih, List.append_assoc]

theorem mem_trAll {io : Io} {cs : List Cmd} {e : Effect} (h : e ∈ (trAll io cs).2) :
    ∃ c ∈ cs, ∃ io', e ∈ (tr io' c).2 := by
  induction cs generalizing io with
  | nil => simp [trAll] at h
  | cons c cs ih =>
    simp only [trAll, List.mem_append] at h
    rcases h with h | h
    · exact ⟨c, List.mem_cons_self, io, h⟩
    · obtain ⟨c', hc, io', he⟩ := ih h
      exact ⟨c', List.mem_cons_of_mem _ hc, io', he⟩

/-- Every command's effects are among the translation's. -/
theorem trAll_of_mem {io : Io} {cs : List Cmd} {c : Cmd} (h : c ∈ cs) :
    ∃ io', ∀ e ∈ (tr io' c).2, e ∈ (trAll io cs).2 := by
  induction cs generalizing io with
  | nil => simp at h
  | cons c' cs ih =>
    rcases List.mem_cons.1 h with rfl | h
    · exact ⟨io, fun e he => by simp only [trAll]; exact List.mem_append_left _ he⟩
    · obtain ⟨io', h'⟩ := ih (io := (tr io c').1) h
      exact ⟨io', fun e he => by simp only [trAll]; exact List.mem_append_right _ (h' e he)⟩

/-! ## What a message is to the machine -/

theorem coreAt_eq (s : AppState) (p : Prep) : ∃ w, coreAt s p = { s.core with wall := w } := by
  unfold coreAt
  split
  · exact ⟨_, rfl⟩
  · exact ⟨s.core.wall, rfl⟩

theorem receive_none {s : AppState} {m : Msg} (h : (prep s m).input = none) :
    receive s m = ({ core := coreAt s (prep s m), io := (prep s m).io, typed := s.typed },
      (prep s m).asks.map Ask.effect) := by
  simp only [receive, h]

theorem receive_some {s : AppState} {m : Msg} {i : Input} (h : (prep s m).input = some i) :
    receive s m = ((feedCore (coreAt s (prep s m)) (prep s m).io s.typed i).1,
      (prep s m).asks.map Ask.effect ++ (feedCore (coreAt s (prep s m)) (prep s m).io s.typed i).2) := by
  simp only [receive, h]

/-- Where `receive`'s effects come from: the app's own requests, or the translation of the
machine's commands for the message's input. -/
theorem mem_receive {s : AppState} {m : Msg} {e : Effect} (h : e ∈ (receive s m).2) :
    (∃ x, e = Ask.effect x) ∨
      ∃ i, (prep s m).input = some i ∧ ∃ c ∈ (step (coreAt s (prep s m)) i).2, ∃ io', e ∈ (tr io' c).2 := by
  cases hi : (prep s m).input with
  | none =>
    rw [receive_none hi] at h
    obtain ⟨x, -, rfl⟩ := List.mem_map.1 h
    exact Or.inl ⟨x, rfl⟩
  | some i =>
    rw [receive_some hi] at h
    simp only [feedCore, List.mem_append] at h
    rcases h with h | h | h
    · obtain ⟨x, -, rfl⟩ := List.mem_map.1 h
      exact Or.inl ⟨x, rfl⟩
    · exact Or.inr ⟨i, rfl, mem_trAll h⟩
    · obtain ⟨x, -, rfl⟩ := List.mem_map.1 h
      exact Or.inl ⟨x, rfl⟩

/-- A request only the machine makes comes from its commands. -/
theorem receive_machineOnly {s : AppState} {m : Msg} {id : Nat} {r : Request}
    (h : Effect.request id r ∈ (receive s m).2) (hr : r.machineOnly = true) :
    ∃ i, (prep s m).input = some i ∧ ∃ c ∈ (step (coreAt s (prep s m)) i).2, ∃ io',
      Effect.request id r ∈ (tr io' c).2 := by
  rcases mem_receive h with ⟨x, hx⟩ | h
  · rw [Ask.effect_ok hx.symm] at hr; cases hr
  · exact h

/-! ## Which input a message is -/

/-- What an input from a reply to the app's own request can be: never a tick or a machine
reply, and the day files only from a listing, with today by the clock as last heard. -/
def OwnIn (io : Io) (r : Cairn.Reply) : Input → Prop
  | .tick _ | .reply .. => False
  | .transcriptDays today days => ∃ ns, r = .names ns ∧
      today = (Dates.localDay io.wall io.zone).toNat ∧ days = ns.filterMap Dates.parseDayFile
  | _ => True

theorem booted_input (io : Io) : (booted io).input = none ∨ ∃ p, (booted io).input = some (.launch p) := by
  unfold booted
  split
  · exact Or.inl rfl
  · split
    · exact Or.inr ⟨_, rfl⟩
    · exact Or.inl rfl

theorem nextRecent_input (io : Io) (n : Nat) (rest : List String) (acc : List Transcript) :
    (nextRecent io n rest acc).input = none ∨ ∃ ts, (nextRecent io n rest acc).input = some (.recentLoaded ts) := by
  unfold nextRecent
  split
  · exact Or.inr ⟨_, rfl⟩
  · split
    · exact Or.inr ⟨_, rfl⟩
    · exact Or.inl rfl

theorem markDone_input (io : Io) : (markDone io).input = none := rfl

theorem ownReply_input {s : AppState} {p : Pend} {io : Io} {r : Cairn.Reply} {i : Input}
    (h : (ownReply s p io r).input = some i) : OwnIn io r i := by
  cases p <;> simp only [ownReply] at h
  case bootPrefs | bootModel | bootEnabled | bootSubmits =>
    rcases booted_input _ with h' | ⟨_, h'⟩ <;> rw [h'] at h <;> cases h <;> trivial
  case recentList n =>
    split at h
    · rcases nextRecent_input io n _ [] with h' | ⟨_, h'⟩ <;> rw [h'] at h <;> cases h <;> trivial
    · cases h; trivial
  case recentFile n rest acc =>
    split at h <;>
    · rcases nextRecent_input io n rest _ with h' | ⟨_, h'⟩ <;> rw [h'] at h <;> cases h <;> trivial
  case days =>
    split at h
    · cases h; exact ⟨_, rfl, rfl, rfl⟩
    · cases h
  case markRead =>
    split at h
    · split at h
      · cases h
      · rw [markDone_input] at h; cases h
    · rw [markDone_input] at h; cases h
    · rw [markDone_input] at h; cases h
  case markWrite => split at h <;> (rw [markDone_input] at h; cases h)
  case verify => split at h <;> cases h
  all_goals (repeat' (split at h)) <;> (try simp only [Option.some.injEq] at h) <;> (try subst h) <;> (first | trivial | (cases h) | skip)

theorem take_clock {io : Io} {id : Nat} {p : Pend} {io' : Io} (h : io.take id = some (p, io')) :
    io'.wall = io.wall ∧ io'.zone = io.zone := by
  unfold Io.take at h
  cases hl : io.pending.lookup id <;> simp only [hl, Option.map_none, Option.map_some,
    reduceCtorEq, Option.some.injEq, Prod.mk.injEq] at h
  obtain ⟨-, rfl⟩ := h
  exact ⟨rfl, rfl⟩

/-- What the machine's input says about the message it came from. -/
def MsgIn (s : AppState) (m : Msg) : Input → Prop
  | .tick _ => (∃ t, m = .clock t) ∨ ∃ n, m = .timer n
  | .reply q x => ∃ r, m = .reply (2 * q) r ∧ x = coreReply s.core q r
  | .transcriptDays today days => ∃ id ns, m = .reply id (.names ns) ∧
      today = (Dates.localDay s.io.wall s.io.zone).toNat ∧ days = ns.filterMap Dates.parseDayFile
  | _ => True

theorem prep_input_eq (s : AppState) (m : Msg) : (prep s m).input = (prepMsg s m).input := by
  simp only [prep]; split <;> simp_all

theorem prep_wall (s : AppState) (m : Msg) : (prep s m).wall = (prepMsg s m).wall := by
  simp only [prep]; split <;> rfl

theorem landed_clock (io : Io) (id : Nat) (r : Cairn.Reply) :
    (io.landed id r).wall = io.wall ∧ (io.landed id r).zone = io.zone := by
  unfold Io.landed; split <;> exact ⟨rfl, rfl⟩

theorem prep_input {s : AppState} {m : Msg} {i : Input} (h : (prep s m).input = some i) :
    MsgIn s m i := by
  rw [prep_input_eq] at h
  cases m with
  | clock t => simp only [prepMsg, Option.some.injEq] at h; subst h; exact Or.inl ⟨t, rfl⟩
  | timer n =>
    simp only [prepMsg] at h
    split at h
    · cases h
    · simp only [Option.some.injEq] at h; subst h; exact Or.inr ⟨n, rfl⟩
  | reply id r =>
    simp only [prepMsg] at h
    split at h
    · rename_i he
      simp only [Option.some.injEq] at h; subst h
      exact ⟨r, by rw [Nat.mul_div_cancel' (Nat.dvd_of_mod_eq_zero he)], rfl⟩
    · split at h
      · rename_i p io ht
        have hi := ownReply_input h
        obtain ⟨hw, hz⟩ := take_clock ht
        obtain ⟨hw', hz'⟩ := landed_clock s.io id r
        cases i <;> simp only [OwnIn] at hi <;> try trivial
        obtain ⟨ns, rfl, rfl, rfl⟩ := hi
        exact ⟨id, ns, rfl, by rw [hw, hz, hw', hz'], rfl⟩
      · cases h
  | sub x e =>
    cases x <;> cases e <;> simp only [prepMsg] at h <;>
      (try split at h) <;> (try split at h) <;> (try simp only [Option.some.injEq] at h) <;>
      (try subst h) <;> first | trivial | cases h

/-! ## The state `receive` leaves -/

theorem receive_state (s : AppState) (m : Msg) :
    ((prep s m).input = none ∧ (receive s m).1.core = coreAt s (prep s m) ∧ (receive s m).1.typed = s.typed) ∨
      ∃ i, (prep s m).input = some i ∧ (receive s m).1.core = (step (coreAt s (prep s m)) i).1 ∧
        (receive s m).1.typed = s.typed ++ typedClips (step (coreAt s (prep s m)) i).2 := by
  cases hi : (prep s m).input with
  | none => exact Or.inl ⟨rfl, by rw [receive_none hi], by rw [receive_none hi]⟩
  | some i => exact Or.inr ⟨i, rfl, by rw [receive_some hi]; rfl, by rw [receive_some hi]; rfl⟩

/-- A property of the machine's state that ignores the wall clock and is kept by every `step`
is kept by `receive`. -/
theorem receive_keeps (P : State → Prop) (hw : ∀ c w, P c → P { c with wall := w })
    (hs : ∀ c i, P c → P (step c i).1) (s : AppState) (m : Msg) (h : P s.core) :
    P (receive s m).1.core := by
  obtain ⟨w, hw'⟩ := coreAt_eq s (prep s m)
  have h' : P (coreAt s (prep s m)) := hw' ▸ hw _ w h
  rcases receive_state s m with ⟨-, hc, -⟩ | ⟨i, -, hc, -⟩ <;> rw [hc]
  · exact h'
  · exact hs _ i h'

/-! ## ^311: a shortcut never sends -/

theorem wholeClip_machineOnly {r : Request} {c : Nat} (h : r.wholeClip = some c) :
    r.machineOnly = true := by
  unfold Request.wholeClip at h
  split at h
  · rfl
  · cases h

theorem wholeClip_transcription (n : Nat) (mo : String) (p : Option String) :
    (transcription n 0 none mo p).wholeClip = some n := rfl

theorem wholeClip_chunk (n a b : Nat) (mo : String) (p : Option String) :
    (transcription n a (some b) mo p).wholeClip = none := by
  simp [transcription, Request.wholeClip]

/-- A whole-clip upload from the machine's commands is a `transcribe` command's. -/
theorem tr_wholeClip {io : Io} {c : Cmd} {id n : Nat} {r : Request}
    (h : Effect.request id r ∈ (tr io c).2) (hw : r.wholeClip = some n) :
    ∃ q mo p, c = .transcribe q n mo p ∧ id = 2 * q ∧ r = transcription n 0 none mo p := by
  rcases tr_upload h (wholeClip_machineOnly hw) with
    ⟨q, n', mo, p, rfl, hq, rfl⟩ | ⟨q, n', a, b, mo, p, rfl, hq, rfl⟩ | ⟨_, _, _, _, _, _, rfl⟩ |
    ⟨_, _, _, rfl⟩
  · rw [wholeClip_transcription] at hw; cases hw; exact ⟨q, mo, p, rfl, hq, rfl⟩
  · rw [wholeClip_chunk] at hw; cases hw
  · cases hw
  · cases hw

/-- **A shortcut never sends**, through the app: while the key is held and another key has gone
down with it, no message but the clock or a timer leads to a whole clip's upload. -/
theorem app_shortcut_never_sends (s : AppState) (m : Msg) (hk : s.core.keyHeld = true)
    (hc : s.core.chorded = true) (hcl : ∀ t, m ≠ .clock t) (hti : ∀ n, m ≠ .timer n)
    {id : Nat} {r : Request} (h : Effect.request id r ∈ (receive s m).2) : r.wholeClip = none := by
  cases hw : r.wholeClip with
  | none => rfl
  | some n =>
    obtain ⟨i, hi, c, hcm, io', he⟩ := receive_machineOnly h (wholeClip_machineOnly hw)
    obtain ⟨q, mo, p, rfl, -, -⟩ := tr_wholeClip he hw
    obtain ⟨w, hw'⟩ := coreAt_eq s (prep s m)
    rw [hw'] at hcm
    have ht : ∀ t, i ≠ .tick t := by
      rintro t rfl
      rcases prep_input hi with ⟨t', rfl⟩ | ⟨n', rfl⟩
      · exact hcl t' rfl
      · exact hti n' rfl
    exact absurd rfl (shortcut_never_sends { s.core with wall := w } i hk hc ht _ hcm)

/-- The menu never uploads. -/
theorem menuStep_no_upload (s : AppState) (a : MenuAction) {id : Nat} {r : Request}
    (h : Effect.request id r ∈ (menuStep s a).2) : r.machineOnly = false := by
  cases hm : r.machineOnly
  · rfl
  · obtain ⟨c, hc, io', he⟩ := mem_trAll h
    have hk := menu_kinds s.core a c hc
    rcases tr_upload he hm with ⟨_, _, _, _, rfl, -⟩ | ⟨_, _, _, _, _, _, rfl, -⟩ |
      ⟨_, _, _, _, _, rfl, -⟩ | ⟨_, _, rfl, -⟩ <;> simp [Cmd.kind] at hk

/-! ## ^312: hold or tap -/

theorem receive_keyUp_core (s : AppState) (k : Nat) (mo : Option Nat) (t : Nat) :
    (receive s (.sub (.globalKey k mo) (.keyUp t))).1.core = (step s.core (.keyUp t)).1 := rfl

theorem receive_clock_core (s : AppState) (tm : Time) :
    (receive s (.clock tm)).1.core = (step { s.core with wall := tm.wall } (.tick tm.mono)).1 := rfl

/-! ## ^313: one recording, and a new one is a new clip -/

theorem record_sub_iff (s : AppState) (c : Nat) :
    Sub.record c ∈ subscriptions s ↔ s.core.recording.map (·.clip) = some c := by
  have h1 : Sub.record c ∉ (if s.io.launched then [Sub.watchFile configPath, .watchFile dictionaryPath] else []) := by
    split <;> simp
  have h2 : Sub.record c ∉ (if wantsKey s then [Sub.globalKey s.core.hotkey.code s.core.hotkey.modifier] else []) := by
    split <;> simp
  unfold subscriptions
  simp only [List.mem_append, List.mem_singleton, reduceCtorEq, false_or, h1, h2, or_false]
  cases s.core.recording <;> simp [eq_comm]

theorem app_new_recording (s : AppState) (m : Msg) {r' : Recording}
    (h : (receive s m).1.core.recording = some r') (hn : s.core.recording.map (·.clip) ≠ some r'.clip) :
    s.core.recording = none ∧ r'.clip = s.core.nextClip := by
  obtain ⟨w, hw⟩ := coreAt_eq s (prep s m)
  rcases receive_state s m with ⟨-, hc, -⟩ | ⟨i, -, hc, -⟩ <;> rw [hc, hw] at h
  · exact absurd (by rw [show s.core.recording = some r' from h]; rfl) hn
  · exact step_new_recording { s.core with wall := w } i h hn

/-! ## ^314: every recording ends -/

theorem ends_after (s : State) (h : RecInv s) (t : Ms) (ht : s.now ≤ t) (w : Int) (u : Ms)
    (hu : t + latchLimit ≤ u) :
    (step { (step s (.keyUp t)).1 with wall := w } (.tick u)).1.recording = none := by
  have h1 := step_recInv s (.keyUp t) h
  have hk : (step s (.keyUp t)).1.keyHeld = false := by
    simp only [step]; split
    · rw [release_keyHeld]
    · simpa using ‹¬s.keyHeld = true›
  have hn : (step s (.keyUp t)).1.now = t := by
    simp only [step]; split
    · rw [release_now]; exact Nat.max_eq_right ht
    · exact Nat.max_eq_right ht
  generalize (step s (.keyUp t)).1 = s1 at h1 hk hn
  cases hr : s1.recording with
  | none => simp [step, tick, hr]
  | some r =>
    obtain ⟨hl, hd⟩ := h1 r hr
    have hlt : r.latched = true := by
      cases hr' : r.latched
      · simp [hl hr'] at hk
      · rfl
    have hdl : r.deadline ≤ max s1.now u := by
      have := hd hlt; rw [hn] at this; exact Nat.le_trans (Nat.le_trans this hu) (Nat.le_max_right _ _)
    simp only [step, tick, hr, hlt, hdl, and_self, ↓reduceIte]
    exact send_recording _ _

/-- **Every recording ends**, through the app: once the key's release is heard, the first clock
ten minutes on finds no recording. -/
theorem app_recording_ends (s : AppState) (h : RecInv s.core) (t : Nat) (k : Nat) (mo : Option Nat)
    (tm : Time) (ht : s.core.now ≤ t) (hm : t + latchLimit ≤ tm.mono) :
    (receive (receive s (.sub (.globalKey k mo) (.keyUp t))).1 (.clock tm)).1.core.recording = none := by
  rw [receive_clock_core, receive_keyUp_core]
  exact ends_after s.core h t ht tm.wall tm.mono hm

/-! ## ^315–^319: typing -/

theorem tr_save (io : Io) (q : Nat) (t : Transcript) :
    ∃ file, Effect.request (2 * q) (.appendFile file (transcriptLine t ++ "\n").toUTF8) ∈ (tr io (.save q t)).2 :=
  ⟨_, List.mem_singleton_self _⟩

theorem tr_play_basso (io : Io) : ∃ id, Effect.request id (.playSound "Basso") ∈ (tr io (.play .basso)).2 :=
  ⟨_, List.mem_singleton_self _⟩

/-- **Saved before typed**, through the app: when a transcript is typed it is in the recent list,
not yet marked typed, and (when transcripts are kept) the request appending it to its day file
comes earlier in the same effects. -/
theorem app_saved_before_typed (s : AppState) (m : Msg) {id pid : Nat} {text : String} {ret : Bool}
    (h : Effect.request id (.typeText pid text ret) ∈ (receive s m).2) :
    ∃ t ∈ (receive s m).1.core.recent, t.typed = false ∧
      ∃ pre post, (receive s m).2 = pre ++ Effect.request id (.typeText pid text ret) :: post ∧
        (s.core.settings.keepTranscripts = true →
          ∃ id' file, Effect.request id' (.appendFile file (transcriptLine t ++ "\n").toUTF8) ∈ pre) := by
  obtain ⟨i, hi, c, hc, io', he⟩ := receive_machineOnly h rfl
  obtain ⟨q, n, rfl, rfl⟩ := tr_typeText he
  obtain ⟨w, hw⟩ := coreAt_eq s (prep s m)
  have hc' := hc
  rw [hw] at hc'
  obtain ⟨t, ht, -, htyped, pre, post, hcs, hsave⟩ := saved_before_typed _ i hc'
  rw [← hw] at ht hcs
  rw [receive_some hi]
  refine ⟨t, ht, htyped, (prep s m).asks.map Ask.effect ++ (trAll (prep s m).io pre).2,
    (trAll (tr (trAll (prep s m).io pre).1 (.type q n pid text ret)).1 post).2 ++
      (collect (trAll (prep s m).io (step (coreAt s (prep s m)) i).2).1
        (step (coreAt s (prep s m)) i).1).2.map Ask.effect, ?_, ?_⟩
  · simp only [feedCore]
    rw [hcs, trAll_append]
    simp [trAll, tr, List.append_assoc]
  · intro hk
    obtain ⟨r, hr⟩ := hsave hk
    obtain ⟨io'', hio⟩ := trAll_of_mem (io := (prep s m).io) hr
    obtain ⟨file, hf⟩ := tr_save io'' r t
    exact ⟨_, file, List.mem_append_right _ (hio _ hf)⟩

/-- **A failed type is kept and flagged**, through the app. -/
theorem app_failed_type_flagged (s : AppState) (q c : Nat) (t : Transcript) (e : String) (f : Fault)
    (h : s.core.reqs.lookup q = some (.type c t)) :
    (receive s (.reply (2 * q) (.failed f e))).1.core.recent.head? = some { t with typed := false } ∧
      ∃ id, Effect.request id (.playSound "Basso") ∈ (receive s (.reply (2 * q) (.failed f e))).2 := by
  have hp : (prep s (.reply (2 * q) (.failed f e))).input =
      some (.reply q (.failed (typeFault t.app f e))) := by
    rw [prep_input_eq]; simp [prepMsg, coreReply, h]
  have hco : coreAt s (prep s (.reply (2 * q) (.failed f e))) = s.core := by
    simp [coreAt, prep_wall, prepMsg]
  obtain ⟨h1, h2⟩ := failed_type_flagged s.core q c t (typeFault t.app f e) h
  rw [receive_some hp, hco]
  refine ⟨h1, ?_⟩
  obtain ⟨io', hio⟩ := trAll_of_mem (io := (prep s (.reply (2 * q) (.failed f e))).io) h2
  obtain ⟨id, hid⟩ := tr_play_basso io'
  exact ⟨id, List.mem_append_right _ (List.mem_append_left _ (hio _ hid))⟩

/-- **Only a live reply types**, through the app: a `typeText` comes only from the reply `2q`
to a whole clip's transcription still in flight and not cancelled. -/
theorem app_only_live_replies_type (s : AppState) (m : Msg) {id pid : Nat} {text : String} {ret : Bool}
    (h : Effect.request id (.typeText pid text ret) ∈ (receive s m).2) :
    ∃ q r cr, m = .reply (2 * q) r ∧ (q, Req.clip cr) ∈ s.core.reqs ∧ cr.turn = s.core.turn := by
  obtain ⟨i, hi, c, hc, io', he⟩ := receive_machineOnly h rfl
  obtain ⟨q, n, rfl, rfl⟩ := tr_typeText he
  obtain ⟨w, hw⟩ := coreAt_eq s (prep s m)
  rw [hw] at hc
  obtain ⟨q', x, cr, rfl, hm, -, ht⟩ := late_reply_never_types _ i hc
  obtain ⟨r, rfl, -⟩ := prep_input hi
  exact ⟨q', r, cr, rfl, hm, ht⟩

/-- **Whole-word fixes**, through the app: what is typed is the text of an HTTP 2xx reply to a
whole clip's transcription, with the dictionary's fixes on whole words, trimmed, then a space or
Return. -/
theorem app_typed_text (s : AppState) (m : Msg) {id pid : Nat} {text : String} {ret : Bool}
    (h : Effect.request id (.typeText pid text ret) ∈ (receive s m).2) :
    ∃ q r raw cr, m = .reply (2 * q) r ∧ transcriptReply r = .ok raw ∧ (q, Req.clip cr) ∈ s.core.reqs ∧
      ReplacesAll cr.fixes raw.toList (applyFixes cr.fixes raw).toList ∧
      text = (if cr.submits then trimText (applyFixes cr.fixes raw)
              else trimText (applyFixes cr.fixes raw) ++ " ") := by
  obtain ⟨i, hi, c, hc, io', he⟩ := receive_machineOnly h rfl
  obtain ⟨q, n, rfl, rfl⟩ := tr_typeText he
  obtain ⟨w, hw⟩ := coreAt_eq s (prep s m)
  rw [hw] at hc
  obtain ⟨q', raw, cr, rfl, hl, -⟩ := step_type _ _ hc
  obtain ⟨q'', raw', cr', hi', hm, hfix, htext⟩ := typed_text _ _ hc
  simp only [Input.reply.injEq, Reply.ok.injEq] at hi'
  obtain ⟨rfl, rfl⟩ := hi'
  have hl' : s.core.reqs.lookup q' = some (.clip cr) := hl
  obtain ⟨r, hm', hx⟩ := prep_input hi
  simp only [coreReply, hl'] at hx
  exact ⟨q', r, raw, cr', hm', hx.symm, hm, hfix, htext⟩

/-! ## ^320: retention never deletes today -/

/-- **Retention never deletes today**, through the app: a day file is deleted only on the reply
to a listing of the transcripts folder, only one listed, and only one older than today by the
clock as last heard. -/
theorem app_retention_never_today (s : AppState) (m : Msg) {id : Nat} {path : String}
    (h : Effect.request id (.deleteFile path) ∈ (receive s m).2) :
    ∃ (id' : Nat) (ns : List String) (d : Nat), m = .reply id' (.names ns) ∧ path = dayPath d ∧
      d ∈ ns.filterMap Dates.parseDayFile ∧ d < (Dates.localDay s.io.wall s.io.zone).toNat := by
  obtain ⟨i, hi, c, hc, io', he⟩ := receive_machineOnly h rfl
  obtain ⟨ds, d, rfl, hd, rfl⟩ := tr_deleteFile he
  obtain ⟨today, days, rfl, -, hds⟩ := retention_never_today _ i ds hc
  obtain ⟨id', ns, rfl, rfl, rfl⟩ := prep_input hi
  obtain ⟨h1, h2⟩ := hds d hd
  exact ⟨id', ns, d, rfl, rfl, h1, h2⟩

/-! ## ^321: the first 25 terms -/

/-- **Only the first 25 terms are sent**, through the app: every upload is a transcription
whose prompt is the one a dictionary of just its first 25 terms would give. -/
theorem app_prompt (s : AppState) (m : Msg) {id : Nat} {me url : String} {hs : List (String × String)}
    {sec : Option Secret} {body : List Part} {to : Nat}
    (h : Effect.request id (.upload me url hs sec body to) ∈ (receive s m).2) :
    ∃ n a b mo p ctx, Request.upload me url hs sec body to = transcription n a b mo p ∧
      p = { s.core.dict with terms := s.core.dict.terms.take promptLimit }.promptFor ctx := by
  obtain ⟨i, hi, c, hc, io', he⟩ := receive_machineOnly h rfl
  obtain ⟨w, hw⟩ := coreAt_eq s (prep s m)
  rw [hw] at hc
  rcases tr_upload he rfl with ⟨q, n, mo, p, rfl, -, hr⟩ | ⟨q, n, a, b, mo, p, rfl, -, hr⟩ |
    ⟨_, _, _, _, _, -, hr⟩ | ⟨_, _, -, hr⟩
  · obtain ⟨ctx, hp⟩ := step_prompt _ i hc (p := p) rfl
    exact ⟨n, 0, none, mo, p, ctx, hr, hp⟩
  · obtain ⟨ctx, hp⟩ := step_prompt _ i hc (p := p) rfl
    exact ⟨n, _, _, mo, p, ctx, hr, hp⟩
  · cases hr
  · cases hr

/-! ## ^323: only sendable clips -/

/-- **Too short, silent or nowhere to type: never sent**, through the app: every whole-clip
upload is the recording in progress, long and loud enough, with an app to type into. -/
theorem app_sendable (s : AppState) (m : Msg) {id n : Nat} {r : Request}
    (h : Effect.request id r ∈ (receive s m).2) (hw : r.wholeClip = some n) :
    ∃ rec mo p, s.core.recording = some rec ∧ Sendable s.core.dict rec n p ∧
      r = transcription n 0 none mo p := by
  obtain ⟨i, hi, c, hc, io', he⟩ := receive_machineOnly h (wholeClip_machineOnly hw)
  obtain ⟨q, mo, p, rfl, -, hr⟩ := tr_wholeClip he hw
  obtain ⟨w, hw'⟩ := coreAt_eq s (prep s m)
  rw [hw'] at hc
  obtain ⟨rec, hrec, hs⟩ := step_transcribe _ i hc
  exact ⟨rec, mo, p, hrec, hs, hr⟩

/-! ## The menu's commands -/

theorem menuStep_core (s : AppState) (a : MenuAction) : (menuStep s a).1.core = (menu s.core a).1 := rfl

theorem menuStep_typed (s : AppState) (a : MenuAction) :
    (menuStep s a).1.typed = s.typed ++ typedClips (menu s.core a).2 := rfl

/-- The menu stops a recording or leaves it. -/
theorem menu_recording (s : State) (a : MenuAction) :
    (menu s a).1.recording = s.recording ∨ (menu s a).1.recording = none := by
  cases a <;> simp only [menu]
  case toggleEnabled => split <;> simp [cancel]
  all_goals first | exact Or.inl rfl | simp | (split <;> simp)

/-! ## Invariants over the machine's state and the typed log -/

/-- A property of the machine's state and the typed log that ignores the wall clock and is kept
by every `step` and every menu action. -/
structure Keeps (Q : State → List Nat → Prop) : Prop where
  wall : ∀ c ty w, Q c ty → Q { c with wall := w } ty
  step : ∀ c ty i, Q c ty → Q (step c i).1 (ty ++ typedClips (step c i).2)
  menu : ∀ c ty a, Q c ty → Q (menu c a).1 (ty ++ typedClips (menu c a).2)

theorem Keeps.receive {Q : State → List Nat → Prop} (hq : Keeps Q) (s : AppState) (m : Msg)
    (h : Q s.core s.typed) : Q (receive s m).1.core (receive s m).1.typed := by
  obtain ⟨w, hw⟩ := coreAt_eq s (prep s m)
  have h' : Q (coreAt s (prep s m)) s.typed := hw ▸ hq.wall _ _ w h
  rcases receive_state s m with ⟨-, hc, ht⟩ | ⟨i, -, hc, ht⟩ <;> rw [hc, ht]
  · exact h'
  · exact hq.step _ _ i h'

theorem Keeps.menuStep {Q : State → List Nat → Prop} (hq : Keeps Q) (s : AppState) (a : MenuAction)
    (h : Q s.core s.typed) : Q (menuStep s a).1.core (menuStep s a).1.typed := by
  rw [menuStep_core, menuStep_typed]; exact hq.menu _ _ a h

/-! ## ^314: `RecInv` -/

theorem keeps_recInv : Keeps fun c _ => RecInv c where
  wall _ _ _ h := h
  step c _ i h := step_recInv c i h
  menu c _ a h := h.calm (menu_calm c a)

/-! ## ^318: each clip typed at most once -/

/-- Every clip numbered so far is typed, or still live, at most once between them; a clip not
yet numbered not at all. -/
def TypedInv (c : State) (ty : List Nat) : Prop :=
  ∀ n, ty.count n + (live c).count n ≤ if n < c.nextClip then 1 else 0

theorem TypedInv.of_rel {c : State} {ty : List Nat} {o : State × List Cmd} (h : TypedInv c ty)
    (hr : Rel c o) : TypedInv o.1 (ty ++ typedClips o.2) := by
  intro n
  obtain ⟨hle, hn⟩ := hr
  have h1 := hn n
  have h2 := h n
  rw [List.count_append]
  unfold fresh at h1
  split at h1 <;> split at h2 <;> split <;> omega

theorem keeps_typedInv : Keeps TypedInv where
  wall _ _ _ h := h
  step c _ i h := h.of_rel (step_rel c i)
  menu c _ a h := h.of_rel (menu_rel c a)

theorem typedInv_init : TypedInv init [] := by
  intro n; simp [live, init, clipsOf]

theorem TypedInv.once {c : State} {ty : List Nat} (h : TypedInv c ty) (n : Nat) : ty.count n ≤ 1 := by
  have := h n; split at this <;> omega

/-! ## ^322: five recent -/

theorem keeps_small : Keeps fun c _ => Small c where
  wall _ _ _ h := h
  step c _ i h := step_small c i h
  menu c _ a h := menu_small c a h

/-! ## ^346: the original Yap keeps its key -/

theorem leave_original (s : AppState) (h : s.io.original ≠ some false) (k : Nat) (mo : Option Nat) :
    Sub.globalKey k mo ∉ subscriptions s := by
  have hw : wantsKey s = false := by
    unfold wantsKey
    cases ho : s.io.original with
    | none => simp
    | some b => cases b <;> simp_all
  unfold subscriptions
  rw [hw]
  simp only [List.mem_append, List.mem_singleton, reduceCtorEq, false_or, Bool.false_eq_true,
    ↓reduceIte, List.not_mem_nil, or_false, not_or]
  refine ⟨by split <;> simp, ?_⟩
  cases s.core.recording <;> simp

end Examples.Yap
