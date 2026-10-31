using Beast.BuildTool;

// {{ProjectName}}: the Launch module plus the Beast SDK library (external project "Beast").
public sealed class {{ProjectIdentifier}}Target : TargetRules
{
    public {{ProjectIdentifier}}Target(ModulesInfo info)
    {
        Modules.Add("Launch");
        TargetDependencies.Add("Beast");
        // iOS: a UIKit application bundle (scenes, CAMetalLayer), not a console program.
        ConsoleApplication = info.Platform != PlatformType.IOS;
    }
}
