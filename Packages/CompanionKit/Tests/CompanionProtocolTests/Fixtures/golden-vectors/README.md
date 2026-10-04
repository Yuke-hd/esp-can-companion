# Golden vectors

Wire-format test vectors for `CompanionProtocol`, pinned to one firmware commit
(see `manifest.json`).

- `config-documents/` is a verbatim copy of the firmware's canonical example
  configs (`docs/specs/configuration/examples/*.json`). The tests decode each
  one and check that it re-encodes to the same bytes.
- Every other file is **spec-derived**: the firmware has not published codec
  fixtures yet (Yuke-hd/mazda-can-accessory-controller#162). They were written
  from the companion spec at the pinned commit with an encoder independent of
  the Swift code. Each file has `vectors` (bytes and their decoded fields, using
  the spec's field names) and, where decoding can fail, `invalid` (bytes and the
  expected error).

When the firmware publishes its own fixtures, replace the spec-derived files
with copies of them, update `manifest.json` to the new commit and source, and
adapt the loaders in `GoldenVectorTests.swift` if the layout differs.
Never edit a vendored file by hand; re-copy it from the firmware.
