---
name: prefers-source-builds-over-third-party-repos
description: "Patrick prefers compiling from upstream source over adding third-party package repos (COPR, PPA) when the build is simple"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5446834e-bd33-4547-bc02-75f6b945df29
  modified: 2026-07-29T23:27:43.407Z
---

When a tool isn't in the official distro repos, Patrick would rather build it from
upstream source than enable a third-party repo like a Fedora COPR — at least when
the build is straightforward. Stated during the keyd install: "i'd rather not use an
external source if compiling it ourselfs if so easy."

**Why:** Avoids trusting an unofficial packager and an extra always-enabled repo for
a single small tool.

**How to apply:** For small, self-contained builds, lead with the source-build path
and clone into a new subfolder of `~/src` (his convention). Still mention that a
packaged option exists, but don't default to it. For genuinely heavy builds with deep
dependency trees, present both and let him choose. Also check out the latest release
tag rather than building from `master`. See [[keyd-mac-style-copy-paste]].
