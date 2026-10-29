using Beast.BuildTool;

// Beast SDK as a static library for Beast.BuildTool.v2. Applications connect it with
//   Config/BuildConfig.json: "externalProjects": [ { "name": "Beast", "path": "<path to BeastSDK>" } ]
//   <App>.Target.cs:          TargetDependencies.Add("Beast");
//   Launch.Build.cs:          PrivateDependencies.Add("BeastUI");
public sealed class BeastTarget : TargetRules
{
    public BeastTarget(ModulesInfo info)
    {
        Type = TargetType.StaticLibrary;
        Modules.Add("BeastUI"); // and, through its dependencies, Core, Input, Platform, RHI
    }
}
