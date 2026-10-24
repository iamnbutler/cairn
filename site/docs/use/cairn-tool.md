---
title: The cairn tool
nav: The cairn tool
eyebrow: Use
lede: The command line for building, checking and shipping a Cairn app. Planned; today the repository's make targets do its work.
---

:::note Not built yet
There is no `cairn` command today. It is planned in
[issue #75](https://github.com/iamnbutler/cairn/issues/75), together with making Cairn a package an
app can depend on. This page says what it will do and how to do each thing now.
:::

## Planned commands

| Command | What it will do | Today |
|---|---|---|
| `cairn new` | start an app in its own repository | add an app beside the examples ([how](/docs/book/first-app/#adding-your-own-app-today)) |
| `cairn build` | build the Lean app and its Swift host | `make build` |
| `cairn run` | open the app in a window | `make demo DEMO=Cairn<App>` |
| `cairn check` | everything a change must pass | `make check` |
| `cairn map` | build the app's map | `make map APP=<App>` |
| `cairn fuzz` | claim-driven fuzzing | `make fuzz APP=<App>` |
| `cairn conform` | replay the model against the running app | `make conformance APP=<App>` |
| `cairn bundle --sign` | a signed `.app` | `make bundle APP=<App> SIGN=<identity>` |
| `cairn bench` | the app's benchmarks | `make bench` (Cairn's own) |
| `cairn doc` | docs from the code ([#74](https://github.com/iamnbutler/cairn/issues/74)) | none |
| `cairn doctor` | check the toolchain | none |

## The make targets, today

Run them from the root of the Cairn repository. Each is shown as it is in the Makefile.

### Build and run

`make build` builds the Lean libraries and the Swift host.

<!-- include Makefile#make-demo -->

### Check

<!-- include Makefile#make-check -->

<!-- include Makefile#make-selftest -->

### Fuzz and conformance

<!-- include Makefile#make-fuzz -->

<!-- include Makefile#make-conformance -->

### Maps

<!-- include Makefile#make-map -->

### Ship

<!-- include Makefile#make-bundle -->

<!-- include Makefile#make-size -->
