# DevSweep

## Your Mac isn't full. Your caches are.

**Delete 30+ GB of Xcode leftovers without nuking your VMs, Docker images, or game saves.**

DevSweep is a free, open-source macOS disk analyzer built in Krypton. It finds
the folders eating your SSD and cleans the stuff that is actually safe to
remove — starting with the duplicate iOS/watchOS simulator runtimes Xcode
keeps piling up.

> On the machine where this was built: **~29 GB of stale simulator runtimes**,
> **~3 GB of dead caches**, and a Data volume sitting at **97% capacity**.
> DevSweep found all of it. None of `.lima`, Docker, or game data was touched.

### Why this exists

Xcode downloads a new simulator runtime with every update and keeps the old
ones. Four runtime bundles (`2× iOS`, `2× watchOS`) can quietly consume 50 GB
while Finder still says "Storage: almost full." DevSweep uses Apple's own
`simctl` to identify and remove only superseded runtimes, plus stale build
data older than 30 days — and it refuses to run DerivedData cleanup while
Xcode is open.

### Features

- **Scan** curated high-value roots and show size, path, and a protection note.
- **Reveal** any row in Finder.
- **Xcode Sizes** — break down `~/Library/Developer/Xcode` instantly.
- **Check Runtimes** — preview exactly what `simctl --outdated` would delete.
- **Delete Outdated** — two-click confirmation, then removes only outdated
  simulator runtimes through Apple's helper.
- **Clear DerivedData** — only entries older than 30 days, skipped while Xcode
  is running.

### Never touched

`~/.lima` VM disks, Docker state and `kryptos*` images, game data, Xcode
`CodingAssistant`, and protected caches. Cleanup commands are fixed strings —
no user input is interpolated into a shell command.

### Build

Requires macOS arm64 and a Krypton toolchain (the Homebrew 2.5.0-alpha
install is what this was verified against).

```sh
./build.sh
```

Override the toolchain with `KRYPTON_ROOT=/path/to/krypton`. To sign during
the build:

```sh
DEV_IDENTITY="Developer ID Application: ... (TEAMID)" ./build.sh
```

The built app lands in `dist/DevSweep.app` (ignored by git).

### Distribution

Direct Developer ID release, not Mac App Store — the Store sandbox blocks
runtime deletion and most disk scanning. The bundle is signed with a hardened
runtime and timestamp; notarization is the remaining release step and is
documented in the source tree's release notes.

### License

Apache License 2.0 — see [LICENSE](LICENSE). Free forever, no telemetry, no
accounts, no upsell.
