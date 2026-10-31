using System.IO;
using Beast.BuildTool;

// Render hardware interface: OpenGL 4.6 / OpenGL ES and Vulkan on Windows and Android, Metal on iOS.
// GL, EGL and Vulkan are loaded at run time (LoadLibrary/dlopen), so only headers are needed at
// build time. Apple platforms compile only the Metal backend (see RHI::Create and IsRHIBackendSupported).
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
        if (info.Platform is PlatformType.IOS or PlatformType.Mac)
        {
            ExcludedSources.Add("Private/OpenGL");
            ExcludedSources.Add("Private/Vulkan");
            Frameworks.Add("Metal");
            Frameworks.Add("QuartzCore"); // CAMetalLayer
            Frameworks.Add("Foundation");
        }
        else
        {
            ExcludedSources.Add("Private/Metal");
        }
    }
}
