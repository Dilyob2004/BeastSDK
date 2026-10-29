#include "Beast.h"

class HelloScene final : public Beast::UI::Scene
{
public:
    HelloScene()
    {
        using namespace Beast::UI;
        auto message = std::make_shared<Text>("Hello, Beast!", 24.0f);
        auto button = std::make_shared<Button>("Say hello", [message] {
            message->SetText("Native UI, written in C++.");
        });
        using namespace Beast::UI::Build;
        ui.SetRoot(Make<Center>(VBox({message, button}, 16)));
    }
};

BEAST_UI_APPLICATION(HelloScene, {.title = "{{ProjectName}}"})
