using System.IO;
using Beast.BuildTool;

// android_native_app_glue.c from the NDK. Its ANativeActivity_onCreate is renamed, so the
// application's BEAST_APPLICATION macro exports the real entry point and forwards to it.
// A separate module, because the definition must apply to this one file only.
public sealed class BeastAndroidGlue : ModuleRules
{
    public BeastAndroidGlue(ModulesInfo info)
    {
        if (info.AndroidNdkRoot == null) return; // Android only
        string glue = Path.Combine(info.AndroidNdkRoot, "sources", "android", "native_app_glue");
        PublicIncludePaths.Add(glue);
        AdditionalSources.Add(Path.Combine(glue, "android_native_app_glue.c"));
        Definitions.Add("ANativeActivity_onCreate=BeastNativeActivityOnCreate");
        InputLibraries.Add("android");
        InputLibraries.Add("log");
    }
}
