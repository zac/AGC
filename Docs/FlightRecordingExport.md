# Bounded flight recording export

`LMFlightRecording.writeJSON(to:)` writes the existing compact, sorted-key
JSON format to a caller-owned file handle. It retains a roughly 1 MiB output
buffer plus the largest encoded frame, rather than the whole JSON document.
The caller owns closing, partial-file cleanup and atomic publication. The
method checks task cancellation between frames and propagates write failures.
The existing `encoded(prettyPrinted:)` API remains available.

Four `LMFlightReplaySiteTests` pass on September 5, 2026. Tests compare streamed
bytes directly with `encoded()` for zero, one and 2,000 frames, including
quoted/Unicode identifiers, selected-site contact diagnostics and a buffer
flush; they verify decoded equality, replay site continuity and write errors.

An isolated Release host benchmark repeats the same captured Highland frame
15,000 times in separate processes. Both methods write exactly 90,540,088
identical bytes. Whole-document encoding took 1.070 seconds, with process
maximum RSS rising from 26,345,472 to 637,681,664 bytes. Streaming took
0.925 seconds, rising from 26,345,472 to 30,834,688 bytes. This measures export
allocation in isolation, not full-flight terrain/GPU memory or device behavior.
The benchmark source, logs and outputs are in `/tmp/LM-Artemis-Realism`.

LM integrates this on a utility task, writes a unique partial file, and
publishes only by atomic rename after checking the current flight identity.
Restart/cancellation cannot publish a stale completed recording.
