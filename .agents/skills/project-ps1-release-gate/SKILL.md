---
name: project-csharp-release-gate
description: Enforce the OC Writing Focus project's C#-first development and release workflow. Use for every feature implementation, bug fix, UI change, device integration change, test, demonstration, launch, packaging, or EXE release task in this repository. Require verification through the C# WPF source and explicit user approval before rebuilding or replacing the main EXE.
---

# C# Main Development And EXE Release Gate

Treat `csharp/src/OCWritingFocus.Wpf/OCWritingFocus.Wpf.csproj` as the main development and verification entry point. Treat the sibling pair `dist/OCWritingFocus.exe` and `dist/OCWritingFocus.dependencies/` as one indivisible main release artifact. The implementation under `powershell/` is a legacy version and is changed only when explicitly requested or when a targeted compatibility regression is necessary.

## Development Workflow

1. Implement requested behavior in the C# source by default.
2. Build `csharp/OCWritingFocus.CSharp.sln` and run the C# core tests.
3. Compile and validate WPF XAML when desktop UI markup changes.
4. Run `npm test` when shared JavaScript behavior, cross-version compatibility, or the full project is affected.
5. Launch the C# WPF project for interactive testing or feature demonstration. Do not use an existing EXE to demonstrate unpublished changes.
6. Report what was tested, any device-dependent gaps, and whether the C# source version is ready for release.

Use this development launch command when a GUI run is needed:

```powershell
dotnet run --project csharp\src\OCWritingFocus.Wpf\OCWritingFocus.Wpf.csproj
```

## EXE Release Gate

- Do not run `npm run build:desktop` or another publish command during ordinary implementation, testing, or demonstration.
- Do not overwrite, delete, or replace `dist/OCWritingFocus.exe` or `dist/OCWritingFocus.dependencies/` without explicit user approval in the current conversation.
- Once the requested functionality is implemented and verification is complete, tell the user that the C# development version is ready and ask whether to update the main EXE.
- Treat answers such as `更新 EXE`, `重新打包`, or an equivalent explicit instruction as approval.
- After approval, publish the self-contained multi-file C# main version, launch the new EXE once, verify that its main window remains responsive and that no startup error log is created, then report the artifact path, EXE checksum, file count, and total directory size.
- If the user explicitly requests an EXE build at the start, that request is approval; still complete C# source verification before packaging.

## Legacy PowerShell Version

- Use `npm run desktop:powershell` to launch the legacy source version.
- Use `npm run build:desktop:powershell` only when the user explicitly requests a PowerShell-version EXE rebuild.
- New features and routine fixes do not need to be duplicated into PowerShell unless the user asks for parity.

## Completion Criteria

Consider a change ready to offer for EXE packaging only when:

- Relevant C# builds and automated checks pass.
- The changed desktop flow has been demonstrated through the C# WPF project when GUI behavior is involved.
- Known hardware-dependent behavior is clearly identified if a physical device is unavailable.
- No required implementation work remains.

End the implementation handoff with a direct question such as: `C# 主版本已验证完成，是否现在更新主版本 EXE？`
