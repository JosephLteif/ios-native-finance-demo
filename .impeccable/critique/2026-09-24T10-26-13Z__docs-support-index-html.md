---
target: public support page design review
total_score: 29
max_score: 40
na_heuristics:
p0_count: 0
p1_count: 0
target_identity: "file:C:\\Programming\\Finance-App\\docs\\support\\index.html"
target_fingerprint: "sha256:a5444d2df8e654e11832afc3c411286602394bb5f1966580ecb18dfcfdf84d68"
target_path: "C:\\Programming\\Finance-App\\docs\\support\\index.html"
timestamp: 2026-09-24T10-26-13Z
slug: docs-support-index-html
closed: true
---
# Pocket Ledger Support Page Design Review

**Target:** Public Support page, [live page](https://josephlteif.github.io/pocket-ledger/support/), source [docs/support/index.html](/C:/Programming/Finance-App/docs/support/index.html) and [docs/styles.css](/C:/Programming/Finance-App/docs/styles.css). This review covers the website support page, not the iOS app UI.

## Design Health Score

| # | Heuristic | Score | Key issue |
|---|---|---:|---|
| 1 | Visibility of System Status | 2 | The mail link has no fallback if a mail app does not open. |
| 2 | Match System / Real World | 4 | Clear contact language and familiar email conventions. |
| 3 | User Control and Freedom | 3 | Navigation is clear; no explicit recovery guidance for a failed handoff. |
| 4 | Consistency and Standards | 3 | Coherent visual language and familiar links. |
| 5 | Error Prevention | 3 | The warning not to send account or transaction details is useful. |
| 6 | Recognition Rather Than Recall | 4 | Email, privacy link, and suggested report details are visible. |
| 7 | Flexibility and Efficiency | 3 | One direct contact path, but no prefilled subject. |
| 8 | Aesthetic and Minimalist Design | 3 | Focused page; tiny index labels are less legible. |
| 9 | Error Recovery | 2 | No next step if the mail app cannot handle the link. |
| 10 | Help and Documentation | 2 | Contact guidance is present, but no self-service troubleshooting. |
| **Total** |  | **29/40 — Good** |  |

## Design Specificity Verdict

The page feels authored: the fieldbook framing, ruled background, serif/monospace pairing, and restrained palette create a consistent editorial identity. It avoids the generic AI landing-page look. Its product-specific privacy reminder and device-support instructions connect that identity to Pocket Ledger; without those details, the visual system could fit many editorial brands.

The automated scan reported two findings for docs/support/index.html: all-caps-body and extreme-negative-tracking. The all-caps finding appears to be a false positive for the short masthead label styled as uppercase. The tracking finding corresponds to the large serif display headline (letter-spacing: -0.065em); it may be intentional, but should be checked at narrow widths and larger text settings. The detector process returned exit code 0 despite its guidance saying findings should return 2.

## Overall Impression

A strong, calm contact page with a clear visual point of view and useful privacy guidance. The biggest opportunity is to make the email handoff more reliable and reduce the effort required to compose a useful support message.

## What's Working

- The visual identity is cohesive and distinctive, rather than assembled from stock landing-page patterns.
- The email address is prominent, and the page tells people what device details help while discouraging disclosure of financial data.
- The page has semantic headings, a skip link, and a visible keyboard focus treatment. The contact address is exposed as a link in the accessibility tree.

## Priority Issues

1. **[P2] Add a fallback for the email handoff.** A mailto link depends on the visitor having a mail app configured. Add a short instruction such as “If your email app doesn’t open, copy the address above,” or provide a copy action with an announced success state.
   **Suggested command:** $impeccable clarify
2. **[P2] Reduce message-composition effort.** The page asks for device model, OS version, and reproduction steps, but opens a blank message. Prefill a concise subject such as “Pocket Ledger support”; keep any body template optional and retain the financial-data privacy reminder.
   **Suggested command:** $impeccable optimize
3. **[P2] Set a truthful reply expectation.** “A real person, at the other end” reassures visitors but may imply an actively monitored inbox. Add a response estimate only if it is dependable; otherwise clarify what kind of contact this inbox supports.
   **Suggested command:** $impeccable clarify
4. **[P3] Improve the smallest labels’ legibility.** The contact index uses 0.6rem (about 9.6px) and the overline uses 0.68rem (about 10.9px). Increase these secondary labels modestly. Check the display headline’s tight tracking at mobile widths and with enlarged text before changing it; the detector flag alone does not prove a visual defect.
   **Suggested command:** $impeccable typeset

## Persona Red Flags

- **Jordan, first-time visitor:** The page clearly says email is the contact route, but does not explain that the link launches an external mail app or what to do if it fails.
- **Casey, mobile visitor:** The diagnostic details are useful, but composing the message starts blank; leaving the page to check device/version details may interrupt the task.
- **Sam, accessibility-dependent visitor:** Semantic headings and the skip link are positives. Small all-caps labels may be hard to read at default sizing. VoiceOver, 200% zoom, and magnification were not tested.

## Minor Observations

- The live page says “Write to Joseph.” The Gmail address is the exact address supplied for contact.
- The browser review used dark appearance. Light appearance, mobile viewport, reduced motion, forced colors, and enlarged text were not visually verified.
- No page edits were made.

## Questions to Consider

- Should this stay a focused email page, or add a small troubleshooting section? Options: keep the email-only page; add a few common troubleshooting answers; add only the copy-address fallback.
- Which improvement should come first? Options: reliable email fallback; lower-friction message composition; typography/accessibility polish.
