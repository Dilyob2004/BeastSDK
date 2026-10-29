using System.IO;
using Beast.BuildTool;

// Retained UI: widgets, layout, canvas, text (HarfBuzz, SheenBidi, Unicode segmentation), TextField,
// accessibility. Depending on BeastUI gives an application the whole SDK (#include "Beast.h").
public sealed class BeastUI : ModuleRules
{
    public BeastUI(ModulesInfo info)
    {
        PublicDependencies.Add("BeastCore");
        PublicDependencies.Add("BeastInput");
        PublicDependencies.Add("BeastRHI");
        PublicDependencies.Add("BeastPlatform"); // Beast.h includes Platform/Platform.h

        // HarfBuzz and SheenBidi are compiled as part of UI (HarfBuzz.cpp, SheenBidi.c).
        string thirdParty = Path.Combine(info.ProjectDirectory!, "ThirdParty");
        PrivateIncludePaths.Add(Path.Combine(thirdParty, "SheenBidi", "Headers"));
        PrivateIncludePaths.Add(Path.Combine(thirdParty, "SheenBidi", "Source"));

        // Third-party notices (fonts, stb_truetype, HarfBuzz, SheenBidi, Unicode, Material Icons):
        // next to the program on Windows, assets/BeastSDK-LICENSES.txt in the APK.
        Resources.Add(Path.Combine(thirdParty, "BeastSDK-LICENSES.txt"), "BeastSDK-LICENSES.txt");
    }
}
