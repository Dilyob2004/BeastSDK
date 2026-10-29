using Beast.BuildTool;

// The Launch module is the executable entry point. Add include paths, defines and libraries here.
public sealed class Launch : ModuleRules
{
    public Launch(ModulesInfo info)
    {
        PrivateDependencies.Add("BeastUI"); // Beast SDK: #include "Beast.h"
    }
}
