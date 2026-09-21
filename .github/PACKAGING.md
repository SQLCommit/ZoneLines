# Release packaging

Use **Prepare release** and **Release check** as before. The tag must match `addon.version`, for example `v1.3.1`.

- `.github/release.json` lists every file allowed in the ZIP. Add new runtime modules there; missing files stop packaging.
- Edit the root `README.md` for GitHub. Packaging converts it to plain Markdown inside `addons/zonelines/README.md`, preserving the source.
- Documentation comes from the revision being packaged. Existing ZIPs do not update when documentation changes.
- Internal notes, screenshots, tests, tools, backups, and temporary files are not release files.

Preview the release README in PowerShell:

```powershell
./.github/scripts/export-readme.ps1 -Output "$env:TEMP/ZoneLines-README.md"
```

Run the packaging checks:

```powershell
./.github/scripts/test-release-package.ps1
```

The bundled GdiFonts DLL, its license, and the three optional fonts are required package files. Fonts are never installed automatically.
