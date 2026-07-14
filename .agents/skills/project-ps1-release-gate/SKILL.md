---
name: project-ps1-release-gate
description: Enforce the OC Writing Focus project's development and release workflow. Use for every feature implementation, bug fix, UI change, device integration change, test, demonstration, launch, packaging, or EXE release task in this repository. Require development verification and feature demonstrations through the WPF PS1 source, and require explicit user approval before rebuilding or replacing the EXE.
---

# PS1 Development And EXE Release Gate

Treat `src/desktop/OCWritingFocusApp.Wpf.ps1` as the development and verification entry point. Treat `dist/OCWritingFocus.exe` as a release artifact.

## Development Workflow

1. Implement requested behavior in the source files.
2. Validate PowerShell syntax and UTF-8 BOM encoding for changed PowerShell files.
3. Load and validate the embedded XAML when desktop UI markup changes.
4. Run relevant automated tests, including `npm test` when the shared core is affected.
5. Launch `src/desktop/OCWritingFocusApp.Wpf.ps1` for interactive testing or feature demonstration. Do not use the existing EXE to demonstrate unbuilt changes.
6. Report what was tested, any device-dependent gaps, and whether the source version is ready for release.

Use this development launch command when a GUI run is needed:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File src\desktop\OCWritingFocusApp.Wpf.ps1
```

## EXE Release Gate

- Do not run `scripts/build-desktop.ps1` or `npm run build:desktop` during ordinary implementation, testing, or demonstration.
- Do not overwrite, delete, or replace `dist/OCWritingFocus.exe` without explicit user approval in the current conversation.
- Once the requested functionality is implemented and verification is complete, tell the user that the PS1 development version is ready and ask whether to update the EXE version.
- Treat answers such as `更新 EXE`, `重新打包`, or an equivalent explicit instruction as approval.
- After approval, build the EXE, launch the new EXE once, verify that its main window remains responsive and that no startup error log is created, then report the artifact path.
- If the user explicitly requests an EXE build at the start, that request is approval; still complete PS1-based verification before packaging.

## Completion Criteria

Consider a change ready to offer for EXE packaging only when:

- Relevant syntax and automated checks pass.
- The changed desktop flow has been demonstrated through the PS1 entry point when GUI behavior is involved.
- Known hardware-dependent behavior is clearly identified if a physical device is unavailable.
- No required implementation work remains.

End the implementation handoff with a direct question such as: `PS1 开发版已验证完成，是否现在更新 EXE 版本？`
