import Cairn.Geometry
import Cairn.Claim
import Cairn.Font
import Cairn.Text.Field
import Cairn.Text.FieldTests
import Cairn.Text.Proofs
import Cairn.Text.Host
import Cairn.Text.Wrap
import Cairn.Text.WrapProofs
import Cairn.UI.Node
import Cairn.UI.Images
import Cairn.UI.Grid
import Cairn.UI.Hit
import Cairn.Input
import Cairn.Frame
import Cairn.Frame.Bytes
import Cairn.Frame.Encode
import Cairn.Frame.Events
import Cairn.Frame.Build
import Cairn.Frame.Menu
import Cairn.Frame.Dump
import Cairn.Abi
import Cairn.Frame.Layout
import Cairn.Frame.EventsTests
import Cairn.Frame.BuildTests
import Cairn.Abi.Tests
import Cairn.Surface
import Cairn.App
-- The runtime half of the claim language only: `Cairn.Claims` imports `Lean` and must stay out
-- of the host's library (see "Linking" in docs/claims.md).
import Cairn.Claims.Core
import Cairn.Runtime
import Cairn.Claims.Deliver
import Cairn.Layout

/-! # Everything in Cairn

Every module of Cairn but the tools and the fuzzer: the linked code (`Cairn`), its proofs and
tests, and the umbrellas over them. Not what apps import (that is `Cairn`, which links); what the
ledger, the axiom audit, the kernel replay and `make doc` read. In `CairnProofs`, never linked. -/
