#include "RHI/Private/RHIInternal.h"

namespace Beast
{
    std::unique_ptr<RHI> RHI::Create(const Window& window, RHIOptions options)
    {
        if (!window.HasSurface()) throw std::invalid_argument("RHI requires a live native window.");
        if (!IsRHIBackendSupported(options.backend))
            throw std::invalid_argument(IsApplePlatform()
                ? "iOS supports only the Metal RHI backend (RHIBackend::Metal or DefaultRHIBackend())."
                : "The Metal RHI backend is available only on Apple platforms; use OpenGL or Vulkan.");
        switch (options.backend)
        {
#if defined(__APPLE__)
        case RHIBackend::Metal: return Detail::CreateMetalRHI(window, options);
#else
        case RHIBackend::OpenGL: return Detail::CreateOpenGLRHI(window, options);
        case RHIBackend::Vulkan: return Detail::CreateVulkanRHI(window, options);
#endif
        default: throw std::invalid_argument("Unknown RHI backend.");
        }
    }
}
