module

/-! Little-endian byte encoding for the spike's frame and event buffers. -/

@[expose] public section


namespace Cairn.Spike

def pushU8 (b : ByteArray) (v : UInt8) : ByteArray := b.push v

def pushU16 (b : ByteArray) (v : UInt16) : ByteArray :=
  (b.push v.toUInt8).push (v >>> 8).toUInt8

def pushU32 (b : ByteArray) (v : UInt32) : ByteArray :=
  (((b.push v.toUInt8).push (v >>> 8).toUInt8).push (v >>> 16).toUInt8).push (v >>> 24).toUInt8

/-- Two's complement, truncated to 32 bits. -/
def pushI32 (b : ByteArray) (v : Int) : ByteArray :=
  pushU32 b (UInt32.ofNat (v % 4294967296).toNat)

def pushStr (b : ByteArray) (s : String) : ByteArray :=
  let bytes := s.toUTF8
  pushU16 b bytes.size.toUInt16 ++ bytes

def getU32 (b : ByteArray) (i : Nat) : UInt32 :=
  (b.get! i).toUInt32 ||| ((b.get! (i+1)).toUInt32 <<< 8) |||
  ((b.get! (i+2)).toUInt32 <<< 16) ||| ((b.get! (i+3)).toUInt32 <<< 24)

def getI32 (b : ByteArray) (i : Nat) : Int :=
  let u := (getU32 b i).toNat
  if u < 2147483648 then u else (u : Int) - 4294967296

end Cairn.Spike
