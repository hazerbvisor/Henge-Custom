# Translation operand scanning candidate

Base: requested run 42621054396, source 090d60052e5df5d0ce9d60432ccb1a79eb71d82f. Existing runtime settings and fixes retained.

Build the used-register mask from decoded fields with constant shifts. If it contains no reserved guest registers, emit the instruction unchanged before constructing renaming scratch arrays. Otherwise retain the original renaming path. No guest instruction cache, MMU assumptions, targets, or synchronization are changed.

Original/candidate hot/cold emission and literals match for 20,000 cases locally. Native classification, operand, JIT-region, JIT, memory, MMU and exception regressions pass. Seven alternating paired emission benchmarks on the requested base are roughly unchanged (about 1% better repeated, 3% worse diverse ALU, under 1% worse diverse memory in one local run). This is an experimental candidate, not a demonstrated performance improvement. Device frame-time acceptance is unverified; retain the baseline and reject the candidate if it worsens pacing.

Runner repeats these checks and packages benchmark samples/test logs/provenance with the IPA. The exact original operand scanning path is reconstructed in build-only files by the test script; emitted byte comparisons run both implementations in one process.
