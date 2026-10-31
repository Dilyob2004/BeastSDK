#pragma once
#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

namespace Beast
{
    enum class Platform { Windows, Android, IOS };
    constexpr Platform CurrentPlatform()
    {
#if defined(_WIN32)
        return Platform::Windows;
#elif defined(__ANDROID__)
        return Platform::Android;
#elif defined(__APPLE__) && TARGET_OS_IOS
        return Platform::IOS; // Devices and the iOS Simulator.
#elif defined(__APPLE__)
#error BeastSDK supports iOS on Apple platforms; macOS is not implemented yet.
#else
#error BeastSDK currently supports Windows, Android and iOS.
#endif
    }
    // Apple platforms render only through Metal (OpenGL ES is deprecated there, Vulkan needs MoltenVK).
    constexpr bool IsApplePlatform() { return CurrentPlatform() == Platform::IOS; }
}
