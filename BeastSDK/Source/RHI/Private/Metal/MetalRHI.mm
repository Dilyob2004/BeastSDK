// Metal RHI: the only backend on Apple platforms. Same semantics as the OpenGL/Vulkan backends:
// a cleared frame, scissored ClearRect (replaces color and alpha, like glClear), textured triangle
// draws with Opaque/StraightAlpha/PremultipliedAlpha blending, 128 bytes of fragment constants,
// and immutable offscreen layers rendered once and cached (and pooled when released).
// Compiled with ARC on iOS (and macOS later); all calls happen on the Run (main) thread.
#if defined(__APPLE__)
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include "RHI/Private/RHIInternal.h"
#include "RHI/Private/LayerTargetPool.h"
#include "Core/Application.h"
#include <dispatch/dispatch.h>
#include <atomic>
#include <cstddef>
#include <cstring>
#include <string>
#include <unordered_map>

namespace Beast::Detail
{
    namespace
    {
        // Window drawables and layer targets share one format, so one pipeline state serves both.
        constexpr MTLPixelFormat TargetFormat = MTLPixelFormatBGRA8Unorm;
        constexpr long FramesInFlight = 3;
        constexpr NSUInteger VertexBufferIndex = 0;

        // ClearRect: a full-target triangle limited by the scissor, writing the color unblended.
        const char* ClearSource = R"(
#include <metal_stdlib>
using namespace metal;
struct BeastClearOut { float4 position [[position]]; };
vertex BeastClearOut BeastClearVertex(uint id [[vertex_id]])
{
    float2 corner = float2((id << 1) & 2, id & 2);
    BeastClearOut out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    return out;
}
fragment float4 BeastClearFragment(constant float4& color [[buffer(0)]]) { return color; }
)";

        NSString* String(const std::string& text)
        {
            return [[NSString alloc] initWithBytes:text.data() length:text.size() encoding:NSUTF8StringEncoding];
        }
        std::string Describe(NSError* error)
        {
            return error ? std::string(error.localizedDescription.UTF8String ?: "unknown error") : std::string("unknown error");
        }
        id<MTLLibrary> Compile(id<MTLDevice> device, const std::string& source, const std::string& name)
        {
            MTLCompileOptions* options = [MTLCompileOptions new];
            options.languageVersion = MTLLanguageVersion2_1;
            // Coverage math (rounded rectangles, shadows) must match the GLSL/SPIR-V backends.
            if (@available(iOS 18.0, macOS 15.0, *)) options.mathMode = MTLMathModeSafe;
            else
            {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                options.fastMathEnabled = NO;
#pragma clang diagnostic pop
            }
            NSError* error = nil;
            id<MTLLibrary> library = [device newLibraryWithSource:String(source) options:options error:&error];
            if (!library) throw std::runtime_error("MSL compile failed [" + name + "]: " + Describe(error));
            return library;
        }
        MTLClearColor Clear(RHIColor color) { return MTLClearColorMake(color.r, color.g, color.b, color.a); }
        MTLScissorRect Scissor(RHIRect rect)
        { return MTLScissorRect{NSUInteger(rect.x), NSUInteger(rect.y), NSUInteger(rect.width), NSUInteger(rect.height)}; }

        // GPU timestamps arrive on a Metal completion thread; shared so late handlers never touch the RHI.
        struct GpuTiming
        {
            std::atomic<std::uint64_t> frame{0};
            std::atomic<double> milliseconds{-1};
        };
    }

    class MetalRHI final : public RHI
    {
        struct Function { std::weak_ptr<const RHIShader> owner; id<MTLFunction> function; };
        struct Pipeline { std::weak_ptr<const RHIPipeline> owner; id<MTLRenderPipelineState> state; };
        struct Texture
        {
            std::weak_ptr<const RHITexture> owner;
            id<MTLTexture> texture;
            std::uint32_t width = 0, height = 0;
            std::uint64_t bytes = 0;
            bool target = false; // Layer render target (pooled), not an uploaded bitmap.
        };
        struct Arena { id<MTLBuffer> buffer; NSUInteger offset = 0; };

        void* window_;
        CAMetalLayer* layer_;
        id<MTLDevice> device_;
        id<MTLCommandQueue> queue_;
        id<MTLRenderPipelineState> clear_;
        id<MTLSamplerState> nearest_, linear_;
        dispatch_semaphore_t inFlight_;
        RHIOptions options_;
        RHIFrameStats stats_;
        RHILayerStats layerStats_;
        std::shared_ptr<GpuTiming> timing_ = std::make_shared<GpuTiming>();
        std::unordered_map<const RHIShader*, Function> functions_;
        std::unordered_map<const RHIPipeline*, Pipeline> pipelines_;
        std::unordered_map<const RHITexture*, Texture> textures_;
        LayerTargetPool<Texture> layerPool_;
        Arena arenas_[FramesInFlight];
        unsigned frame_ = 0;

        id<MTLFunction> GetFunction(const RHIShaderHandle& shader)
        {
            if (auto found = functions_.find(shader.get()); found != functions_.end()) return found->second.function;
            const auto& desc = shader->GetDesc();
            id<MTLLibrary> library = Compile(device_, desc.msl, desc.name);
            id<MTLFunction> function = [library newFunctionWithName:String(desc.entryPoint)];
            if (!function) throw std::runtime_error("MSL function not found: " + desc.entryPoint + " in " + desc.name);
            functions_.emplace(shader.get(), Function{shader, function});
            return function;
        }
        id<MTLRenderPipelineState> GetPipeline(const RHIPipelineHandle& pipeline)
        {
            if (auto found = pipelines_.find(pipeline.get()); found != pipelines_.end()) return found->second.state;
            const auto& desc = pipeline->GetDesc();
            MTLRenderPipelineDescriptor* descriptor = [MTLRenderPipelineDescriptor new];
            descriptor.label = String(desc.vertexShader->GetDesc().name + "+" + desc.fragmentShader->GetDesc().name);
            descriptor.vertexFunction = GetFunction(desc.vertexShader);
            descriptor.fragmentFunction = GetFunction(desc.fragmentShader);
            static_assert(sizeof(RHIVertex) == 32 && offsetof(RHIVertex, u) == 8 && offsetof(RHIVertex, color) == 16);
            MTLVertexDescriptor* vertex = [MTLVertexDescriptor vertexDescriptor];
            vertex.attributes[0].format = MTLVertexFormatFloat2; vertex.attributes[0].offset = 0; vertex.attributes[0].bufferIndex = VertexBufferIndex;
            vertex.attributes[1].format = MTLVertexFormatFloat2; vertex.attributes[1].offset = 8; vertex.attributes[1].bufferIndex = VertexBufferIndex;
            vertex.attributes[2].format = MTLVertexFormatFloat4; vertex.attributes[2].offset = 16; vertex.attributes[2].bufferIndex = VertexBufferIndex;
            vertex.layouts[VertexBufferIndex].stride = sizeof(RHIVertex);
            descriptor.vertexDescriptor = vertex;
            auto* color = descriptor.colorAttachments[0];
            color.pixelFormat = TargetFormat;
            if (desc.blend != RHIBlend::Opaque)
            {
                // Same factors as glBlendFuncSeparate(src, 1 - srcAlpha, 1, 1 - srcAlpha).
                color.blendingEnabled = YES;
                color.rgbBlendOperation = color.alphaBlendOperation = MTLBlendOperationAdd;
                color.sourceRGBBlendFactor = desc.blend == RHIBlend::StraightAlpha ? MTLBlendFactorSourceAlpha : MTLBlendFactorOne;
                color.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
                color.sourceAlphaBlendFactor = MTLBlendFactorOne;
                color.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            }
            NSError* error = nil;
            id<MTLRenderPipelineState> state = [device_ newRenderPipelineStateWithDescriptor:descriptor error:&error];
            if (!state) throw std::runtime_error("Metal pipeline creation failed: " + Describe(error));
            pipelines_.emplace(pipeline.get(), Pipeline{pipeline, state});
            return state;
        }
        void Destroy(Texture& texture) noexcept { texture.texture = nil; texture.owner.reset(); }

        // Uploads bitmaps and renders layers (children first) before the pass that samples them;
        // render encoders cannot nest, so this runs ahead of the parent's encoder.
        void Prepare(const RHICommandList& commands, id<MTLCommandBuffer> buffer)
        {
            for (const auto& command : commands.GetCommands())
                if (const auto* draw = std::get_if<RHIDrawTriangles>(&command))
                {
                    GetPipeline(draw->pipeline);
                    GetTexture(draw->texture, buffer);
                }
        }
        id<MTLTexture> GetTexture(const RHITextureHandle& handle, id<MTLCommandBuffer> buffer)
        {
            if (auto found = textures_.find(handle.get()); found != textures_.end()) return found->second.texture;
            const auto& desc = handle->GetDesc();
            Texture native;
            native.owner = handle; native.width = desc.width; native.height = desc.height;
            native.bytes = std::uint64_t(desc.width) * desc.height * 4;
            if (const auto* content = handle->GetContent())
            {
                Prepare(*content, buffer); // Nested layers first.
                native.target = true;
                Texture pooled;
                if (layerPool_.Take(desc.width, desc.height, pooled)) { native.texture = pooled.texture; ++layerStats_.reuses; }
                else
                {
                    MTLTextureDescriptor* texture = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:TargetFormat
                        width:desc.width height:desc.height mipmapped:NO];
                    texture.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
                    texture.storageMode = MTLStorageModePrivate;
                    native.texture = [device_ newTextureWithDescriptor:texture];
                    if (!native.texture) throw std::runtime_error("Cannot allocate a Metal layer target.");
                    ++layerStats_.allocations;
                }
                MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
                pass.colorAttachments[0].texture = native.texture;
                pass.colorAttachments[0].loadAction = MTLLoadActionClear;
                pass.colorAttachments[0].storeAction = MTLStoreActionStore;
                pass.colorAttachments[0].clearColor = Clear(content->GetClearColor());
                id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
                encoder.label = @"Beast layer";
                Encode(encoder, *content, int(desc.width), int(desc.height));
                [encoder endEncoding];
                ++layerStats_.renders;
            }
            else
            {
                MTLTextureDescriptor* texture = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                    width:desc.width height:desc.height mipmapped:NO];
                texture.usage = MTLTextureUsageShaderRead;
                native.texture = [device_ newTextureWithDescriptor:texture];
                if (!native.texture) throw std::runtime_error("Cannot allocate a Metal texture.");
                // A new texture is never in use by the GPU, so a CPU upload is safe.
                [native.texture replaceRegion:MTLRegionMake2D(0, 0, desc.width, desc.height) mipmapLevel:0
                    withBytes:desc.pixels.data() bytesPerRow:NSUInteger(desc.width) * 4];
            }
            id<MTLTexture> result = native.texture;
            textures_.emplace(handle.get(), std::move(native));
            return result;
        }
        NSUInteger UploadVertices(const std::vector<RHIVertex>& vertices, id<MTLBuffer>& buffer)
        {
            auto& arena = arenas_[frame_];
            const NSUInteger bytes = NSUInteger(vertices.size() * sizeof(RHIVertex));
            if (!arena.buffer || arena.offset + bytes > arena.buffer.length)
            {
                // Earlier draws keep the previous buffer alive: encoders retain what they reference.
                const NSUInteger capacity = std::max<NSUInteger>(std::max<NSUInteger>(bytes, 1 << 20), arena.buffer ? arena.buffer.length * 2 : 0);
                arena.buffer = [device_ newBufferWithLength:capacity options:MTLResourceStorageModeShared | MTLResourceCPUCacheModeWriteCombined];
                if (!arena.buffer) throw std::runtime_error("Cannot allocate a Metal vertex buffer.");
                arena.offset = 0;
            }
            const NSUInteger offset = arena.offset;
            std::memcpy(static_cast<std::uint8_t*>(arena.buffer.contents) + offset, vertices.data(), bytes);
            arena.offset = (offset + bytes + 255) & ~NSUInteger(255);
            buffer = arena.buffer;
            return offset;
        }
        void Encode(id<MTLRenderCommandEncoder> encoder, const RHICommandList& commands, int width, int height)
        {
            [encoder setCullMode:MTLCullModeNone];
            for (const auto& command : commands.GetCommands())
            {
                if (const auto* clear = std::get_if<RHIClearRect>(&command))
                {
                    const auto rect = Clip(clear->rect, width, height);
                    if (!rect.width || !rect.height) continue;
                    const float color[4] = {clear->color.r, clear->color.g, clear->color.b, clear->color.a};
                    [encoder setRenderPipelineState:clear_];
                    [encoder setScissorRect:Scissor(rect)];
                    [encoder setFragmentBytes:color length:sizeof(color) atIndex:0];
                    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
                    continue;
                }
                const auto& draw = std::get<RHIDrawTriangles>(command);
                const auto rect = Clip(draw.scissor.value_or(RHIRect{0, 0, width, height}), width, height);
                if (!rect.width || !rect.height) continue;
                id<MTLBuffer> vertices = nil;
                const NSUInteger offset = UploadVertices(draw.vertices, vertices);
                [encoder setRenderPipelineState:pipelines_.at(draw.pipeline.get()).state];
                [encoder setScissorRect:Scissor(rect)];
                [encoder setVertexBuffer:vertices offset:offset atIndex:VertexBufferIndex];
                [encoder setFragmentTexture:textures_.at(draw.texture.get()).texture atIndex:0];
                [encoder setFragmentSamplerState:draw.texture->GetDesc().filter == RHIFilter::Linear ? linear_ : nearest_ atIndex:0];
                [encoder setFragmentBytes:draw.constants.data() length:sizeof(draw.constants) atIndex:0];
                [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:NSUInteger(draw.vertices.size())];
            }
        }
        void Collect()
        {
            for (auto it = functions_.begin(); it != functions_.end();) it = it->second.owner.expired() ? functions_.erase(it) : std::next(it);
            for (auto it = pipelines_.begin(); it != pipelines_.end();) it = it->second.owner.expired() ? pipelines_.erase(it) : std::next(it);
            for (auto it = textures_.begin(); it != textures_.end();)
            {
                if (!it->second.owner.expired()) { ++it; continue; }
                Texture native = std::move(it->second);
                it = textures_.erase(it);
                native.owner.reset();
                // Metal orders later writes after earlier reads of a tracked resource, so a pooled
                // target can be re-rendered while an older frame that samples it is still in flight.
                if (native.target) layerPool_.Put(std::move(native), options_.layerPoolBytes, layerStats_, [this](Texture& t) { Destroy(t); });
            }
        }
    public:
        MetalRHI(const Window& window, RHIOptions options) : window_(window.nativeHandle), options_(options)
        {
            layer_ = (__bridge CAMetalLayer*)window.nativeHandle;
            if (!layer_ || ![layer_ isKindOfClass:[CAMetalLayer class]]) throw std::invalid_argument("The Metal RHI requires a CAMetalLayer surface.");
            device_ = layer_.device ?: MTLCreateSystemDefaultDevice();
            if (!device_) throw std::runtime_error("No Metal device is available.");
            layer_.device = device_;
            layer_.pixelFormat = TargetFormat;
            layer_.framebufferOnly = YES;
#if TARGET_OS_OSX
            layer_.displaySyncEnabled = options.vsync;
#endif
            queue_ = [device_ newCommandQueue];
            if (!queue_) throw std::runtime_error("Cannot create a Metal command queue.");
            inFlight_ = dispatch_semaphore_create(FramesInFlight);

            id<MTLLibrary> library = Compile(device_, ClearSource, "BeastClear");
            MTLRenderPipelineDescriptor* clear = [MTLRenderPipelineDescriptor new];
            clear.label = @"Beast clear";
            clear.vertexFunction = [library newFunctionWithName:@"BeastClearVertex"];
            clear.fragmentFunction = [library newFunctionWithName:@"BeastClearFragment"];
            clear.colorAttachments[0].pixelFormat = TargetFormat;
            NSError* error = nil;
            clear_ = [device_ newRenderPipelineStateWithDescriptor:clear error:&error];
            if (!clear_) throw std::runtime_error("Metal clear pipeline creation failed: " + Describe(error));

            MTLSamplerDescriptor* sampler = [MTLSamplerDescriptor new];
            sampler.sAddressMode = sampler.tAddressMode = MTLSamplerAddressModeClampToEdge;
            sampler.minFilter = sampler.magFilter = MTLSamplerMinMagFilterNearest;
            nearest_ = [device_ newSamplerStateWithDescriptor:sampler];
            sampler.minFilter = sampler.magFilter = MTLSamplerMinMagFilterLinear;
            linear_ = [device_ newSamplerStateWithDescriptor:sampler];
            if (options.validation) Log("Metal validation: set MTL_DEBUG_LAYER=1 (Xcode scheme or simctl environment) to enable it.");
            Log(("Metal device: " + std::string(device_.name.UTF8String ?: "unknown")).c_str());
        }
        ~MetalRHI() override
        {
            // Wait (bounded) for frames in flight so the layer and resources outlive their GPU work.
            for (long index = 0; index < FramesInFlight; ++index)
                dispatch_semaphore_wait(inFlight_, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
            for (long index = 0; index < FramesInFlight; ++index) dispatch_semaphore_signal(inFlight_);
            layerPool_.Clear([this](Texture& t) { Destroy(t); });
        }
        RHIBackend GetBackend() const noexcept override { return RHIBackend::Metal; }
        RHIFrameStats GetFrameStats() const noexcept override
        {
            auto result = stats_;
            result.layers = layerStats_;
            layerPool_.ReadStats(result.layers);
            const double milliseconds = timing_->milliseconds.load();
            if (milliseconds >= 0) { result.gpuMs = milliseconds; result.gpuFrame = timing_->frame.load(); }
            return result;
        }
        bool Submit(const Window& window, const RHICommandList& commands) override
        {
            SubmitCpuTimer cpuTimer(stats_, options_.profiling);
            CheckSubmission(window, window_, commands);
            if (window.width <= 0 || window.height <= 0) return false;
            // Never block the main thread: with three frames queued, skip and retry next display link.
            if (dispatch_semaphore_wait(inFlight_, DISPATCH_TIME_NOW) != 0) return false;
            bool committed = false;
            try
            {
                @autoreleasepool
                {
                    Collect();
                    const CGSize size = CGSizeMake(window.width, window.height);
                    if (!CGSizeEqualToSize(layer_.drawableSize, size)) layer_.drawableSize = size;
                    frame_ = (frame_ + 1) % FramesInFlight;
                    arenas_[frame_].offset = 0;
                    id<MTLCommandBuffer> buffer = [queue_ commandBuffer];
                    if (!buffer) throw std::runtime_error("Cannot create a Metal command buffer.");
                    buffer.label = @"Beast frame";
                    Prepare(commands, buffer);
                    id<CAMetalDrawable> drawable = [layer_ nextDrawable];
                    if (!drawable)
                    {
                        // Layers already encoded still complete; the frame itself is retried.
                        dispatch_semaphore_t semaphore = inFlight_;
                        [buffer addCompletedHandler:^(id<MTLCommandBuffer>) { dispatch_semaphore_signal(semaphore); }];
                        [buffer commit];
                        return false;
                    }
                    MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
                    pass.colorAttachments[0].texture = drawable.texture;
                    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
                    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
                    pass.colorAttachments[0].clearColor = Clear(commands.GetClearColor());
                    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
                    encoder.label = @"Beast frame";
                    Encode(encoder, commands, int(drawable.texture.width), int(drawable.texture.height));
                    [encoder endEncoding];
                    [buffer presentDrawable:drawable];
                    const std::uint64_t number = ++stats_.submittedFrames;
                    dispatch_semaphore_t semaphore = inFlight_;
                    std::shared_ptr<GpuTiming> timing = options_.profiling ? timing_ : nullptr;
                    [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
                        if (timing && completed.status == MTLCommandBufferStatusCompleted && completed.GPUEndTime > completed.GPUStartTime)
                        {
                            timing->milliseconds = (completed.GPUEndTime - completed.GPUStartTime) * 1000.0;
                            timing->frame = number;
                        }
                        if (completed.status == MTLCommandBufferStatusError)
                            NSLog(@"[Beast] Metal command buffer failed: %@", completed.error.localizedDescription);
                        dispatch_semaphore_signal(semaphore);
                    }];
                    committed = true;
                    [buffer commit];
                }
                return true;
            }
            catch (...)
            {
                if (!committed) dispatch_semaphore_signal(inFlight_);
                throw;
            }
        }
    };

    std::unique_ptr<RHI> CreateMetalRHI(const Window& window, RHIOptions options)
    { return std::make_unique<MetalRHI>(window, options); }
}
#endif
