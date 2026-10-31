<p align="center">
  <img src="BuildTool/Templates/Windows/Resources/Default.png" width="88" alt="Beast logo">
</p>

<h1 align="center">Beast</h1>
<p align="center"><strong>Build native interfaces. Stay in C++.</strong></p>
<p align="center">A C++20 UI SDK and build toolchain for Windows and Android.</p>
<p align="center">
  <a href="LICENSE">MIT</a> · <a href="#quick-start">Quick start</a> ·
  <a href="#see-it-in-action">Demo</a> · <a href="ROADMAP.md">Roadmap</a> ·
  <a href="CONTRIBUTING.md">Contribute</a> · <a href="docs/README.ru.md">Русский</a>
</p>

Beast brings together a retained-mode C++ UI, OpenGL/Vulkan rendering, and a
build tool that turns C# module rules into native Windows executables and Android
packages. Write your application in C++, iterate with development hot reload,
and keep platform lifecycle plumbing inside the SDK.

**Early-stage / experimental.** APIs are evolving. Performance, text input, and
accessibility still need work across devices. Beast is not a Flutter runtime and
does not run Dart applications. It is an independent project, not part of Boost.Beast.

## See it in action

<p align="center">
  <img src="docs/images/ecosbor-home.png" width="30%" alt="EcoSbor home screen rendered by Beast">
  <img src="docs/images/ecosbor-guide.png" width="30%" alt="EcoSbor recycling guide rendered by Beast">
  <img src="docs/images/ecosbor-profile.png" width="30%" alt="EcoSbor profile rendered by Beast">
</p>

Actual **Windows/OpenGL captures** of [EcoSbor](Test/EcoSbor), the included C++
sample. They are not design mockups or Flutter screenshots. The same application
source also targets Android; platform behavior and performance can differ.

## What is inside?

- **C++ UI:** layout containers, buttons, text fields, scrolling, rounded clipping,
  shadows, ripple feedback, themes, and repaint/layer caches.
- **Native rendering:** an RHI abstraction over OpenGL / OpenGL ES and Vulkan,
  with shaders, textures, pipelines, command lists, and synchronization.
- **Text foundations:** HarfBuzz shaping, bidirectional text support, font
  fallback, Unicode grapheme/word handling, and a bounded glyph atlas.
- **Build rules in C#:** `*.Build.cs` modules, dependency resolution, SDK linkage,
  Windows resources, and Android packaging/signing.
- **Development workflow:** Visual Studio makefile solutions with file filters,
  Android install/run support, and hot reload for SDK UI applications.

| Today | Implementation |
| --- | --- |
| Development host | Windows; MSVC and .NET build tooling |
| Windows target | Native x64 executable; OpenGL 4.6 or Vulkan |
| Android target | Android 10+ (API 29); NDK Clang, NativeActivity, OpenGL ES or Vulkan |
| SDK library | `Beast.lib` on Windows; `libBeast.a` on Android |
| Linux / macOS / iOS | Not supported yet |

## Quick start

Run the commands below in **PowerShell**, from the repository root.

### 1. Prepare the toolchain

- Git, Visual Studio with **Desktop development with C++** (MSVC x64 toolset and Windows SDK;
  the current development setup uses Visual Studio 2026), and a GPU/driver supporting the
  selected rendering backend.
- The build tool is [Beast.BuildTool.v2](https://github.com/Dilyob2004/Beast.BuildTool.v2),
  included as the `Beast.BuildTool.v2` git submodule. `Setup.ps1` fetches and builds it; it needs
  the .NET 10 SDK, which `-InstallDotnet` installs without administrator rights.

```powershell
git clone --recurse-submodules https://github.com/Dilyob2004/BeastSDK.git
cd BeastSDK
.\Setup.ps1 -InstallDotnet -Android   # .NET 10, then the build tool; -Android: JDK 17, Android SDK and NDK
```

`-Android` is needed only for Android builds; add `-Emulator` for the emulator and AVD `beast_api34`.
Everything installs per user, into the Android Studio locations. Run `.\Setup.ps1` again after
`git pull`; `.\Setup.ps1 -Update` moves the build tool to its latest version. On Linux/macOS use
`./Setup.sh --install-dotnet --android` and `./beast.sh` (the SDK itself targets Windows and Android).

The submodule is pinned to a Beast.BuildTool.v2 release (`v2.0.4`); applications require at least
version 2.0.0 (`"minimumBuildToolVersion": "2.0.0"` in `Config/BuildConfig.json`). Instead of building it, you can
also use a self-contained release archive from [Releases](https://github.com/Dilyob2004/Beast.BuildTool.v2/releases)
(no .NET needed): unpack it, add the folder to `PATH` and run `beast` instead of `.\beast.ps1`.

### 2. Run EcoSbor

```powershell
Copy-Item Test/EcoSbor/Config/BuildConfig.example.json Test/EcoSbor/Config/BuildConfig.json
.\beast.ps1 build Test/EcoSbor --platform Windows --config Debug
.\Test\EcoSbor\Binaries\Windows\Debug\EcoSbor.exe
```

Copy the example config only on first setup; do not overwrite your existing local
configuration. Sample configs with machine-specific paths are ignored by Git.

### 3. Create your own project

```powershell
.\beast.ps1 new MyApp --path Test --template BeastSDK/Templates/UIApplication
.\beast.ps1 build Test/MyApp --platform Windows --config Debug
```

The template creates a UI application: `Source/MyApp.Target.cs` (the application plus the
`Beast` library), `Source/Launch` with a "Hello, Beast!" scene, `Config/BuildConfig.json` that
points at the SDK, platform resources, and a Visual Studio solution. Outputs go under `Binaries`;
build caches go under `Intermediate/Build` (the SDK is compiled there too, per application).

The SDK is a regular Beast.BuildTool.v2 project (`BeastSDK/Source/Beast.Target.cs`) with the modules
`BeastCore`, `BeastInput`, `BeastPlatform`, `BeastRHI` and `BeastUI`. An application connects it as an
external project:

```jsonc
// Config/BuildConfig.json
"externalProjects": [ { "name": "Beast", "path": "../../BeastSDK" } ]
```

```csharp
// Source/MyApp.Target.cs: Modules.Add("Launch"); TargetDependencies.Add("Beast");
// Source/Launch/Launch.Build.cs:
PrivateDependencies.Add("BeastUI"); // #include "Beast.h"
```

Add a module and regenerate IDE files:

```powershell
.\beast.ps1 module Core Test/MyApp
.\beast.ps1 generate Test/MyApp
```

Modules live under `Source/<Name>/<Name>.Build.cs`; declare the dependency in the using module's
rules (`PrivateDependencies.Add("Core")`). `Source` is an include root, so a header can be included
as `#include "Core/Public/Core.h"`. Rules reference: [Beast.BuildTool.v2 docs](https://github.com/Dilyob2004/Beast.BuildTool.v2/tree/main/docs).

### Android

`.\Setup.ps1 -Android` installs JDK 17, Android SDK platform 35, build tools and the NDK. Paths are
found automatically (`ANDROID_HOME`, `JAVA_HOME`, Android Studio locations) or set with
`android.javaHome`, `android.sdkRoot` and `android.ndkRoot` in the project's `Config/BuildConfig.json`.

```powershell
.\beast.ps1 build Test/EcoSbor --platform Android --config Debug
.\beast.ps1 run Test/EcoSbor --platform Android --no-build
```

Connect and authorize a USB device, or use an Android emulator. Use `--device`
or `--avd` to select a target. Android builds target ARM64 by default; add `"abis": ["arm64-v8a",
"x86_64"]` under `android` for emulators. Release APKs are signed, but the local
debug-key fallback is **not a production signing identity**. See
[Android signing](BuildTool/AndroidRelease.md) before distribution.

### Hot reload

Hot reload still runs through the bundled legacy `BuildTool` (as do the samples other than EcoSbor)
until it is moved onto `beast watch` of Beast.BuildTool.v2:

```powershell
dotnet build BuildTool/Beast.BuildTool.csproj -c Release   # legacy tool, .NET 8
.\BuildTool\bin\Beast.BuildTool.exe watch Test/HotReloadDemo --platform Windows
# In a separate session, for an already-running emulator:
.\BuildTool\bin\Beast.BuildTool.exe watch Test/HotReloadDemo --platform Android --device emulator-5554
```

Save application code to trigger a rebuild. This is a development feature for
`BEAST_UI_APPLICATION` projects, not arbitrary C++ process patching. State
preservation uses explicit scene hooks; SDK and build-rule changes can require
a restart. See [hot reload and Visual Studio integration](BuildTool/HotReload.md).

## Explore the source

| Directory | Purpose |
| --- | --- |
| [BeastSDK/Source](BeastSDK/Source) | Core, platform/window/input, RHI, and UI |
| [BuildTool](BuildTool) | C# build orchestration, project generation, templates |
| [BuildTool.VisualStudio](BuildTool.VisualStudio) | Optional Visual Studio launcher extension |
| [Test](Test) | EcoSbor, TextFieldDemo, rendering and hot-reload examples |
| [BeastSDK/Tests](BeastSDK/Tests) / [Tests](Tests) | SDK and build-tool regression tests |

More detail: [SDK](BeastSDK/README.md), [RHI](BeastSDK/Source/RHI/README.md),
[text features and limitations](BeastSDK/Source/UI/TextFeatures.md),
[roadmap](ROADMAP.md). Some detailed development notes are currently in Russian.

## Help shape Beast

Good contributions include minimal bug reproductions, Android device testing,
frame-time investigations, text/IME fixes, accessibility testing, documentation,
and small UI examples. **Issues and pull requests are welcome in English or Russian.**

Start with [CONTRIBUTING.md](CONTRIBUTING.md). Include the platform, GPU/backend,
build configuration, and reproduction steps when reporting a rendering problem.
If the project interests you, a GitHub star helps other developers discover it.

## License

Original Beast code is available under the [MIT License](LICENSE). Third-party
libraries, fonts, headers, and tools retain their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
