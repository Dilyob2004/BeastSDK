using Beast.BuildTool;

// Application, window, memory, tracing, hot reload runtime.
// Note: Core/HotReload.h includes UI/Application.h. BeastUI depends on BeastCore, so that
// dependency cannot be declared here (module cycle); it compiles because Source/ is the
// include root of every SDK module. Moving the hot reload runtime into BeastUI removes this.
public sealed class BeastCore : ModuleRules
{
    public BeastCore(ModulesInfo info)
    {
        PublicDependencies.Add("BeastInput");
        if (info.Platform == PlatformType.Android)
        {
            InputLibraries.Add("android"); // ATrace (API 29)
            InputLibraries.Add("log");
            InputLibraries.Add("dl");      // hot reload: dlopen
        }
    }
}
