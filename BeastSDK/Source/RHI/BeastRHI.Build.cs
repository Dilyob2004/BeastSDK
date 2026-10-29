using System.IO;
using Beast.BuildTool;

// Render hardware interface: OpenGL 4.6 / OpenGL ES and Vulkan. GL, EGL and Vulkan are loaded at
// run time (LoadLibrary/dlopen), so only headers are needed at build time.
public sealed class BeastRHI : ModuleRules
{
    public BeastRHI(ModulesInfo info)
    {
        PublicDependencies.Add("BeastCore");
        string thirdParty = Path.Combine(info.ProjectDirectory!, "ThirdParty");
        PublicSystemIncludePaths.Add(Path.Combine(thirdParty, "OpenGL"));
        PublicSystemIncludePaths.Add(Path.Combine(thirdParty, "Vulkan-Headers", "include"));
        if (info.Platform == PlatformType.Android)
        {
            InputLibraries.Add("android"); // ANativeWindow
            InputLibraries.Add("dl");
        }
    }
}
