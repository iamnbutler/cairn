#!/usr/bin/env python3
"""Reads one table of an Instruments trace, as `xctrace export` gives it, into rows.

    xctable.py TRACE SCHEMA [--fmt] [--limit N]     prints rows as JSON lines
    import xctable; xctable.rows(trace, schema)    -> [{mnemonic: Cell}]

`xctrace export --xpath` writes each value once with an `id` and later uses `ref` to it; this
resolves the refs. A Cell has `raw` (the element's text: nanoseconds for times and durations,
numbers as written) and `fmt` (Instruments' formatted string), and `kids` for nested values
(a thread's tid and process, say).
"""
import json
import subprocess
import sys
import xml.etree.ElementTree as ET


class Cell:
    __slots__ = ("tag", "raw", "fmt", "kids")

    def __init__(self, tag, raw, fmt, kids):
        self.tag, self.raw, self.fmt, self.kids = tag, raw, fmt, kids

    def num(self):
        try:
            return int(self.raw)
        except (TypeError, ValueError):
            try:
                return float(self.raw)
            except (TypeError, ValueError):
                return None

    def find(self, tag):
        """The first nested value with this tag (depth first), e.g. thread.find('pid')."""
        for k in self.kids:
            if k is None:
                continue
            if k.tag == tag:
                return k
            f = k.find(tag)
            if f is not None:
                return f
        return None

    def __repr__(self):
        return f"{self.tag}({self.fmt or self.raw})"


def export(trace, schema, run=1, pred=""):
    """`pred` narrows the table, e.g. 'not(@subsystem)' or '@category="CAMetalLayer"'."""
    xp = f'/trace-toc/run[@number="{run}"]/data/table[@schema="{schema}"{" and " + pred if pred else ""}]'
    out = subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--xpath", xp],
                         check=True, capture_output=True).stdout
    return out


def parse(xml_bytes):
    root = ET.fromstring(xml_bytes)
    ids = {}

    def cell(e):
        if e.tag == "sentinel":
            return None
        if "ref" in e.attrib:
            return ids[e.attrib["ref"]]
        # A backtrace's frames carry their symbol in `name`, not `fmt`.
        c = Cell(e.tag, (e.text or "").strip() or None, e.attrib.get("fmt", e.attrib.get("name")), [cell(k) for k in e])
        if "id" in e.attrib:
            ids[e.attrib["id"]] = c
        return c

    # An xpath can match several tables of one schema (os-signpost has one per filter);
    # their rows are concatenated.
    out = []
    for node in root.findall("node"):
        schema = node.find("schema")
        if schema is None:
            continue
        cols = [c.findtext("mnemonic") for c in schema.findall("col")]
        for r in node.findall("row"):
            out.append(dict(zip(cols, [cell(k) for k in r])))
    return out


def rows(trace, schema, run=1, pred=""):
    return parse(export(trace, schema, run, pred))


def tables(trace):
    """The schemas a trace has, in toc order."""
    toc = subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--toc"],
                         check=True, capture_output=True).stdout
    root = ET.fromstring(toc)
    return [t.attrib["schema"] for t in root.iter("table") if "schema" in t.attrib]


def toc_info(trace):
    """Device, process and duration from the trace's table of contents."""
    toc = subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--toc"],
                         check=True, capture_output=True).stdout
    root = ET.fromstring(toc)
    dev = root.find(".//target/device")
    proc = root.find(".//target/process")
    return {
        "device": dict(dev.attrib) if dev is not None else {},
        "process": dict(proc.attrib) if proc is not None else {},
        "duration": float(root.findtext(".//summary/duration") or 0),
        "template": root.findtext(".//summary/template-name"),
    }


if __name__ == "__main__":
    trace, schema = sys.argv[1], sys.argv[2]
    pred = sys.argv[sys.argv.index("--pred") + 1] if "--pred" in sys.argv else ""
    fmt = "--fmt" in sys.argv
    limit = int(sys.argv[sys.argv.index("--limit") + 1]) if "--limit" in sys.argv else None
    for i, r in enumerate(rows(trace, schema, pred=pred)):
        if limit is not None and i >= limit:
            break
        print(json.dumps({k: (v.fmt if fmt and v is not None else (v.raw if v is not None else None))
                          for k, v in r.items()}))
