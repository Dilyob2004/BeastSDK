using Beast.BuildTool;

// EcoSbor application: the Launch module plus the Beast SDK library (external project "Beast",
// see Config/BuildConfig.json -> externalProjects).
public sealed class EcoSborTarget : TargetRules
{
    public EcoSborTarget(ModulesInfo info)
    {
        Modules.Add("Launch");
        TargetDependencies.Add("Beast");
    }
}
