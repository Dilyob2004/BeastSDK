using System.IO;
using Beast.BuildTool;

// Windows (Win32, UI Automation), Android (NativeActivity, Choreographer, IME, accessibility) and
// iOS (UIKit scenes, CAMetalLayer, CADisplayLink). Folders Windows/, Android/ and IOS/ are compiled
// only for their platform.
public sealed class BeastPlatform : ModuleRules
{
    public BeastPlatform(ModulesInfo info)
    {
        PublicDependencies.Add("BeastCore");
        if (info.Platform == PlatformType.Windows)
        {
            foreach (string library in new[] { "user32.lib", "gdi32.lib", "dwmapi.lib", "shell32.lib",
                "ole32.lib", "oleaut32.lib", "uiautomationcore.lib", "advapi32.lib" })
                InputLibraries.Add(library);
        }
        if (info.Platform == PlatformType.IOS)
        {
            Frameworks.Add("UIKit");
            Frameworks.Add("QuartzCore");
            Frameworks.Add("Foundation");
        }
        if (info.Platform == PlatformType.Android)
        {
            PublicDependencies.Add("BeastAndroidGlue");
            InputLibraries.Add("android");
            InputLibraries.Add("log");
            // Java side of text input, clipboard, accessibility and window insets (package com.beast.sdk).
            AndroidJavaSources.Add(Path.Combine(info.ProjectDirectory!, "Platform", "Android"), "com/beast/sdk");
        }
    }
}
