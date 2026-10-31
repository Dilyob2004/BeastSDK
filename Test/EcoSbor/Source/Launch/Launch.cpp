#include "Launch/EcoScene.h"

// Vulkan on Windows and Android; Apple platforms accept only Metal.
BEAST_UI_APPLICATION(Eco::Scene, {.title = "ЭкоСбор — Beast", .width = 430, .height = 820,
    .backend = Beast::IsApplePlatform() ? Beast::RHIBackend::Metal : Beast::RHIBackend::Vulkan, .validation = true})
