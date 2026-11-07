/* Exercises Henge's actual Metal replay methods with deterministic command records.
   Transport stubs deliberately provide no guest data; no guest memory is captured. */
#ifndef PVG_REPLAY_SOURCE
#define PVG_REPLAY_SOURCE "../devices/pvg_metal.m"
#endif
#include PVG_REPLAY_SOURCE

int hv_pvg_lite_task_read(HvPvgLite *p, uint32_t t, uint64_t o, void *d, uint32_t n) { (void)p; (void)t; (void)o; memset(d, 0, n); return -1; }
void hv_pvg_lite_task_pages(HvPvgLite *p, uint32_t t, uint64_t f, uint64_t n, uint32_t *out) { (void)p; (void)t; (void)f; memset(out, 0, (size_t)n * 4); }
uint8_t *hv_pvg_lite_page(HvPvgLite *p, uint32_t n) { (void)p; (void)n; return NULL; }
void *hv_pvg_lite_phys(HvPvgLite *p, uint64_t a, uint64_t n) { (void)p; (void)a; (void)n; return NULL; }
uint64_t hv_pvg_lite_task_objects(HvPvgLite *p, uint32_t t) { (void)p; (void)t; return 0; }
const uint8_t *hv_pvg_lite_surface(HvPvgLite *p, uint32_t m) { (void)p; (void)m; return NULL; }
uint8_t *hv_pvg_lite_display_page(HvPvgLite *p) { (void)p; return NULL; }
void hv_pvg_lite_complete(HvPvgLite *p, uint32_t c, uint32_t s) { (void)p; (void)c; (void)s; }
void hv_pvg_lite_command(HvPvgLite *p, const uint32_t *c, uint32_t n) { (void)p; (void)c; (void)n; }

static void check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static void put16(uint8_t *p, size_t o, uint16_t v) { memcpy(p + o, &v, 2); }
static void put32(uint8_t *p, size_t o, uint32_t v) { memcpy(p + o, &v, 4); }
static void put64(uint8_t *p, size_t o, uint64_t v) { memcpy(p + o, &v, 8); }

@interface TestReplay : HvReplay
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, HvObject *> *testObjects;
@property(nonatomic) NSUInteger lookups;
- (void)store:(id)value ref:(uint32_t)ref;
@end
@implementation TestReplay
- (instancetype)init {
    if ((self = [super init])) {
        _testObjects = [NSMutableDictionary new];
        complaints = [NSMutableSet new];
        tasks = [NSMutableDictionary new];
        pipeline_set = YES;
    }
    return self;
}
- (void)store:(id)value ref:(uint32_t)ref {
    HvObject *entry = [HvObject new];
    entry->object = value;
    if ([value respondsToSelector:@selector(length)]) entry->length = [(id<MTLBuffer>)value length];
    self.testObjects[@(ref)] = entry;
}
- (id)get:(uint32_t)ref task:(uint32_t)task { (void)task; self.lookups++; HvObject *entry = self.testObjects[@(ref)]; return entry ? entry->object : nil; }
- (HvObject *)object:(uint32_t)ref task:(uint32_t)task { (void)task; self.lookups++; return self.testObjects[@(ref)]; }
@end

@interface TestBuffer : NSObject
@property(nonatomic) NSUInteger length;
@property(nonatomic, strong) NSMutableData *bytes;
@end
@implementation TestBuffer
- (void *)contents { return self.bytes.mutableBytes; }
- (BOOL)conformsToProtocol:(Protocol *)protocol {
    return protocol == @protocol(MTLBuffer) || protocol == @protocol(MTLResource) || [super conformsToProtocol:protocol];
}
@end

/* Only selectors used by these records are implemented. An unexpected selector is a test failure. */
@interface RecordingEncoder : NSObject {
@public
    NSUInteger calls, start, count, instances, baseInstance, offset, indirectOffset, indexType, primitive;
    NSInteger baseVertex;
    NSRange range;
    NSUInteger offsets[31], strides[31];
    id bindings[31];
    id indexBuffer, indirectBuffer;
}
@end
@implementation RecordingEncoder
- (void)setVertexBuffers:(const id<MTLBuffer> __unsafe_unretained *)buffers offsets:(const NSUInteger *)values withRange:(NSRange)r {
    check(r.location <= 31 && r.length <= 31 - r.location, "replay emitted an invalid buffer binding range");
    range = r; calls++;
    for (NSUInteger i = 0; i < r.length; i++) bindings[r.location + i] = buffers[i], offsets[r.location + i] = values[i];
}
- (void)setVertexBuffers:(const id<MTLBuffer> __unsafe_unretained *)buffers offsets:(const NSUInteger *)values attributeStrides:(const NSUInteger *)s withRange:(NSRange)r {
    [self setVertexBuffers:buffers offsets:values withRange:r];
    for (NSUInteger i = 0; i < r.length; i++) strides[r.location + i] = s[i];
}
- (void)setBuffers:(const id<MTLBuffer> __unsafe_unretained *)buffers offsets:(const NSUInteger *)values withRange:(NSRange)r { [self setVertexBuffers:buffers offsets:values withRange:r]; }
- (void)setVertexBufferOffset:(NSUInteger)o atIndex:(NSUInteger)i { calls++; offsets[i] = o; }
- (void)setVertexBufferOffset:(NSUInteger)o attributeStride:(NSUInteger)s atIndex:(NSUInteger)i { calls++; offsets[i] = o; strides[i] = s; }
- (void)drawPrimitives:(MTLPrimitiveType)p vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n { [self drawPrimitives:p vertexStart:s vertexCount:n instanceCount:1 baseInstance:0]; }
- (void)drawPrimitives:(MTLPrimitiveType)p vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n instanceCount:(NSUInteger)i { [self drawPrimitives:p vertexStart:s vertexCount:n instanceCount:i baseInstance:0]; }
- (void)drawPrimitives:(MTLPrimitiveType)p vertexStart:(NSUInteger)s vertexCount:(NSUInteger)n instanceCount:(NSUInteger)i baseInstance:(NSUInteger)b { calls++; primitive = p; start = s; count = n; instances = i; baseInstance = b; }
- (void)drawIndexedPrimitives:(MTLPrimitiveType)p indexCount:(NSUInteger)n indexType:(MTLIndexType)t indexBuffer:(id<MTLBuffer>)b indexBufferOffset:(NSUInteger)o { [self drawIndexedPrimitives:p indexCount:n indexType:t indexBuffer:b indexBufferOffset:o instanceCount:1 baseVertex:0 baseInstance:0]; }
- (void)drawIndexedPrimitives:(MTLPrimitiveType)p indexCount:(NSUInteger)n indexType:(MTLIndexType)t indexBuffer:(id<MTLBuffer>)b indexBufferOffset:(NSUInteger)o instanceCount:(NSUInteger)i { [self drawIndexedPrimitives:p indexCount:n indexType:t indexBuffer:b indexBufferOffset:o instanceCount:i baseVertex:0 baseInstance:0]; }
- (void)drawIndexedPrimitives:(MTLPrimitiveType)p indexCount:(NSUInteger)n indexType:(MTLIndexType)t indexBuffer:(id<MTLBuffer>)b indexBufferOffset:(NSUInteger)o instanceCount:(NSUInteger)i baseVertex:(NSInteger)v baseInstance:(NSUInteger)s { calls++; primitive = p; count = n; indexType = t; indexBuffer = b; offset = o; instances = i; baseVertex = v; baseInstance = s; }
- (void)drawPrimitives:(MTLPrimitiveType)p indirectBuffer:(id<MTLBuffer>)b indirectBufferOffset:(NSUInteger)o { calls++; primitive = p; indirectBuffer = b; indirectOffset = o; }
- (void)drawIndexedPrimitives:(MTLPrimitiveType)p indexType:(MTLIndexType)t indexBuffer:(id<MTLBuffer>)b indexBufferOffset:(NSUInteger)o indirectBuffer:(id<MTLBuffer>)a indirectBufferOffset:(NSUInteger)ao { calls++; primitive = p; indexType = t; indexBuffer = b; offset = o; indirectBuffer = a; indirectOffset = ao; }
@end

static void emit(TestReplay *replay, id encoder, uint32_t tag, uint8_t *bytes, uint32_t size) {
    [replay render:(id<MTLRenderCommandEncoder>)encoder tag:tag rec:(Rec){bytes, size} task:2];
}
static void binding(TestReplay *r, id e, uint32_t ref, uint64_t offset) {
    uint8_t bytes[20] = {0}; put32(bytes, 4, 1); put32(bytes, 8, ref); put64(bytes, 12, offset);
    emit(r, e, 125, bytes, sizeof bytes);
}
static void indexed(TestReplay *r, id e, uint32_t tag, uint32_t indexRef, uint64_t offset, uint64_t count, uint64_t instances, int64_t baseVertex, uint64_t baseInstance) {
    uint8_t bytes[48] = {0};
    put16(bytes, 0, MTLPrimitiveTypeTriangle); put16(bytes, 2, MTLIndexTypeUInt16); put32(bytes, 4, indexRef);
    put64(bytes, 8, offset); put64(bytes, 16, count); put64(bytes, 24, instances); put64(bytes, 32, (uint64_t)baseVertex); put64(bytes, 40, baseInstance);
    emit(r, e, tag, bytes, sizeof bytes);
}

/* Backing bytes include a plausible next record, but Rec.size ends before them.
   This reproduces adjacent-record reads without reading outside the test allocation. */
static void test_truncated_records(void) {
    TestReplay *r = [TestReplay new];
    RecordingEncoder *e = [RecordingEncoder new];
    TestBuffer *b = [TestBuffer new]; b.length = 4096;
    [r store:b ref:7]; [r store:b ref:8];
    uint8_t bytes[64] = {0};
    const uint32_t drawTags[] = {1, 7, 10, 17, 29};
    const uint32_t shortSizes[] = {6, 10, 32, 20, 16};
    put16(bytes, 0, MTLPrimitiveTypeTriangle); put32(bytes, 4, 7); put32(bytes, 8, 8);
    for (NSUInteger i = 0; i < sizeof drawTags / sizeof *drawTags; i++) {
        NSUInteger calls = e->calls, lookups = r.lookups;
        emit(r, e, drawTags[i], bytes, shortSizes[i]);
        check(e->calls == calls && r.lookups == lookups, "truncated draw must be rejected before resource lookup or encoding");
    }
    memset(bytes, 0, sizeof bytes); put32(bytes, 4, 2); put32(bytes, 8, 7); put32(bytes, 20, 8);
    NSUInteger calls = e->calls, lookups = r.lookups;
    const uint32_t bindingTags[] = {125, 110, 157};
    for (NSUInteger i = 0; i < sizeof bindingTags / sizeof *bindingTags; i++) {
        emit(r, e, bindingTags[i], bytes, 20); // count says two; record contains one.
        check(e->calls == calls && r.lookups == lookups, "truncated render binding array must not consume adjacent record");
    }
    [r compute:(id<MTLComputeCommandEncoder>)e tag:203 rec:(Rec){bytes, 20} task:2];
    check(e->calls == calls && r.lookups == lookups, "truncated compute array must not consume adjacent record");
    put32(bytes, 0, 30); // two complete elements, but their range exceeds Metal's 31 slots.
    emit(r, e, 125, bytes, 32);
    check(e->calls == calls && r.lookups == lookups, "vertex binding range 30+2 must be rejected");
    [r compute:(id<MTLComputeCommandEncoder>)e tag:203 rec:(Rec){bytes, 32} task:2];
    check(e->calls == calls && r.lookups == lookups, "compute binding range 30+2 must be rejected");
    puts("PASS: actual replay rejects adjacent-record draw/binding reads and invalid binding ranges before resource lookup");
}

static void test_recorded_calls(void) {
    TestReplay *r = [TestReplay new];
    RecordingEncoder *e = [RecordingEncoder new];
    TestBuffer *b = [TestBuffer new]; b.length = 1 << 20; b.bytes = [NSMutableData dataWithLength:b.length];
    [r store:b ref:7]; [r store:b ref:8];
    binding(r, e, 7, 48);
    check(e->range.location == 0 && e->range.length == 1 && e->bindings[0] == b && e->offsets[0] == 48, "vertex buffer ref and byte offset");
    binding(r, e, 0, 0);
    check(e->bindings[0] == nil && e->offsets[0] == 0, "nil vertex binding remains a valid unbind");
    binding(r, e, 7, 48);
    uint8_t bytes[64] = {0};
    put32(bytes, 0, 3); put32(bytes, 4, 1); put32(bytes, 8, 7); put64(bytes, 12, 96); put64(bytes, 20, 32);
    emit(r, e, 165, bytes, 28);
    check(e->bindings[3] == b && e->offsets[3] == 96 && e->strides[3] == 32, "dynamic vertex binding stride and offset");
    memset(bytes, 0, sizeof bytes); put32(bytes, 0, 3); put64(bytes, 4, 160); put64(bytes, 12, 48);
    emit(r, e, 166, bytes, 20);
    check(e->offsets[3] == 160 && e->strides[3] == 48, "dynamic stride offset-only update");
    indexed(r, e, 10, 7, 12, 9, 5, 4, 7);
    check(e->count == 9 && e->offset == 12 && e->instances == 5 && e->baseVertex == 4 && e->baseInstance == 7 && e->indexBuffer == b, "wide indexed instanced draw fields");
    indexed(r, e, 28, 7, 8, 3, 2, -2, 4);
    check(e->baseVertex == -2 && e->baseInstance == 4 && e->count == 3, "wide signed base vertex");
    memset(bytes, 0, sizeof bytes); put16(bytes, 0, MTLPrimitiveTypeTriangle); put16(bytes, 2, MTLIndexTypeUInt16); put32(bytes, 4, 7);
    put16(bytes, 8, 6); put16(bytes, 10, 3); put16(bytes, 12, 2); put16(bytes, 14, (uint16_t)-3); put16(bytes, 16, 5);
    emit(r, e, 29, bytes, 18);
    check(e->offset == 6 && e->count == 3 && e->instances == 2 && e->baseVertex == -3 && e->baseInstance == 5, "compact signed indexed base vertex");
    emit(r, e, 11, bytes, 18);
    check(e->baseVertex == 65533, "tag 11 retains its unsigned base vertex wire format");
    memset(bytes, 0, sizeof bytes); put64(bytes, 0, 4); put64(bytes, 8, 6); put64(bytes, 16, 3); put64(bytes, 24, 2); put16(bytes, 32, MTLPrimitiveTypeTriangle);
    emit(r, e, 4, bytes, 34);
    check(e->start == 4 && e->count == 6 && e->instances == 3 && e->baseInstance == 2, "nonindexed instancing and base instance");
    memset(bytes, 0, sizeof bytes); put16(bytes, 0, MTLPrimitiveTypeTriangle); put16(bytes, 2, MTLIndexTypeUInt32); put32(bytes, 4, 7); put32(bytes, 8, 8); put64(bytes, 12, 16); put64(bytes, 20, 32);
    emit(r, e, 17, bytes, 28);
    check(e->indexBuffer == b && e->indirectBuffer == b && e->offset == 16 && e->indirectOffset == 32 && e->indexType == MTLIndexTypeUInt32, "indirect indexed buffer references and offsets");
    puts("PASS: actual replay vertex bindings, strides, indexed/instanced/base-vertex/base-instance and indirect parameter forwarding");
}

static void test_buffer_bounds(void) {
    TestReplay *r = [TestReplay new];
    RecordingEncoder *e = [RecordingEncoder new];
    TestBuffer *b = [TestBuffer new]; b.length = 32;
    [r store:b ref:7]; [r store:[NSObject new] ref:8];
    uint8_t bytes[48] = {0};
    NSUInteger calls = e->calls;
    indexed(r, e, 10, 99, 0, 3, 1, 0, 0);
    check(e->calls == calls, "missing index resource rejected");
    indexed(r, e, 10, 8, 0, 3, 1, 0, 0);
    check(e->calls == calls, "non-buffer index resource rejected");
    indexed(r, e, 10, 7, 1, 3, 1, 0, 0);
    check(e->calls == calls, "misaligned 16-bit index offset rejected");
    indexed(r, e, 10, 7, 28, 3, 1, 0, 0);
    check(e->calls == calls, "index count crossing buffer end rejected");
    indexed(r, e, 10, 7, UINT64_MAX - 1, UINT64_MAX, 1, 0, 0);
    check(e->calls == calls, "overflowing index buffer span rejected");
    put16(bytes, 0, MTLPrimitiveTypeTriangle); put16(bytes, 2, 2); put32(bytes, 4, 7); put64(bytes, 16, 3); put64(bytes, 24, 1);
    NSUInteger lookups = r.lookups;
    emit(r, e, 10, bytes, 48);
    check(e->calls == calls && r.lookups == lookups, "unsupported index format rejected before resource lookup");
    binding(r, e, 8, 0);
    check(e->calls == calls, "non-buffer vertex binding rejected");
    binding(r, e, 7, 33);
    check(e->calls == calls, "vertex binding beyond resource end rejected");
    /* Four indirect primitive words fit at offset 16; five indexed words do not.
       The fake buffer deliberately has no contents, proving no CPU argument read. */
    memset(bytes, 0, sizeof bytes); put32(bytes, 0, 7); put16(bytes, 4, MTLPrimitiveTypeTriangle); put64(bytes, 8, 16);
    emit(r, e, 16, bytes, 16);
    check(e->calls == calls + 1 && e->indirectOffset == 16, "four-word indirect primitive arguments fit exactly");
    calls = e->calls;
    put64(bytes, 8, 20); emit(r, e, 16, bytes, 16);
    check(e->calls == calls, "truncated indirect primitive arguments rejected");
    put64(bytes, 8, 2); emit(r, e, 16, bytes, 16);
    check(e->calls == calls, "misaligned indirect primitive offset rejected");
    memset(bytes, 0, sizeof bytes); put16(bytes, 0, MTLPrimitiveTypeTriangle); put16(bytes, 2, MTLIndexTypeUInt16); put32(bytes, 4, 7); put32(bytes, 8, 7); put64(bytes, 20, 16);
    emit(r, e, 17, bytes, 28);
    check(e->calls == calls, "indexed indirect arguments require five complete words");
    put64(bytes, 20, 12); emit(r, e, 17, bytes, 28);
    check(e->calls == calls + 1 && e->indirectOffset == 12, "five-word indexed indirect arguments fit exactly");
    puts("PASS: actual replay validates resource classes, index formats, alignment, spans and indirect argument storage without CPU reads");
}

/* Offscreen scene: padded 32-byte vertices, a nonzero binding offset and base vertex,
   padded index/indirect buffers, two instances, and near geometry occluding far geometry. */
typedef struct { float xyz[3], pad, color[4]; } SceneVertex;
static id<MTLBuffer> scene_vertices(id<MTLDevice> d, float depth, float red, float blue) {
    SceneVertex vertices[5] = {0};
    const float xy[3][2] = {{-.25f, -.3f}, {.25f, -.3f}, {0, .3f}};
    for (int i = 0; i < 3; i++) { vertices[i+2].xyz[0] = xy[i][0]; vertices[i+2].xyz[1] = xy[i][1]; vertices[i+2].xyz[2] = depth; vertices[i+2].color[0] = red; vertices[i+2].color[2] = blue; vertices[i+2].color[3] = 1; }
    return [d newBufferWithBytes:vertices length:sizeof vertices options:MTLResourceStorageModeShared];
}
static NSData *render_scene(TestReplay *r, id<MTLRenderPipelineState> pipeline, id<MTLDepthStencilState> depth, BOOL indirect, BOOL far) {
    id<MTLTexture> color = [r get:5 task:2], z = [r get:6 task:2];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = color; pass.colorAttachments[0].loadAction = MTLLoadActionClear; pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    pass.depthAttachment.texture = z; pass.depthAttachment.loadAction = MTLLoadActionClear; pass.depthAttachment.storeAction = MTLStoreActionDontCare; pass.depthAttachment.clearDepth = 1;
    id<MTLCommandBuffer> cb = [r->queue commandBuffer];
    id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:pass];
    [e setRenderPipelineState:pipeline]; [e setDepthStencilState:depth];
    r->pipeline_set = YES;
    binding(r, e, 1, sizeof(SceneVertex));
    if (indirect) {
        uint8_t bytes[28] = {0}; put16(bytes, 0, MTLPrimitiveTypeTriangle); put16(bytes, 2, MTLIndexTypeUInt16); put32(bytes, 4, 2); put32(bytes, 8, 4); put64(bytes, 12, 8); put64(bytes, 20, 16);
        emit(r, e, 17, bytes, sizeof bytes);
    } else indexed(r, e, 10, 2, 8, 3, 2, 1, 0);
    if (far) { binding(r, e, 3, sizeof(SceneVertex)); indexed(r, e, 10, 2, 8, 3, 2, 1, 0); }
    [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
    check(cb.status == MTLCommandBufferStatusCompleted && !cb.error, "native scene command buffer completion");
    NSMutableData *pixels = [NSMutableData dataWithLength:64 * 64 * 4];
    [color getBytes:pixels.mutableBytes bytesPerRow:64*4 fromRegion:MTLRegionMake2D(0, 0, 64, 64) mipmapLevel:0];
    return pixels;
}
static void test_native_metal(void) {
    id<MTLDevice> d = MTLCreateSystemDefaultDevice();
    if (!d) { puts("SKIP: native Metal offscreen pixel tests: this runner has no Metal device"); return; }
    NSError *error = nil;
    NSString *msl = @"#include <metal_stdlib>\nusing namespace metal;\nstruct In { float3 p [[attribute(0)]]; float4 c [[attribute(1)]]; }; struct Out { float4 p [[position]]; float4 c; }; vertex Out v(In in [[stage_in]], uint instance [[instance_id]]) { Out o; o.p=float4(in.p,1); o.p.x += float(instance)*0.8-0.4; o.c=in.c; return o; } fragment float4 f(Out in [[stage_in]]) { return in.c; }";
    id<MTLLibrary> lib = [d newLibraryWithSource:msl options:nil error:&error];
    check(lib != nil, error.localizedDescription.UTF8String ?: "native MSL compilation");
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new]; pd.vertexFunction = [lib newFunctionWithName:@"v"]; pd.fragmentFunction = [lib newFunctionWithName:@"f"]; pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm; pd.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    MTLVertexDescriptor *vd = [MTLVertexDescriptor vertexDescriptor]; vd.attributes[0].format = MTLVertexFormatFloat3; vd.attributes[0].bufferIndex = 0; vd.attributes[0].offset = 0; vd.attributes[1].format = MTLVertexFormatFloat4; vd.attributes[1].bufferIndex = 0; vd.attributes[1].offset = 16; vd.layouts[0].stride = sizeof(SceneVertex); pd.vertexDescriptor = vd;
    id<MTLRenderPipelineState> pipeline = [d newRenderPipelineStateWithDescriptor:pd error:&error]; check(pipeline != nil, error.localizedDescription.UTF8String ?: "native pipeline creation");
    MTLDepthStencilDescriptor *dd = [MTLDepthStencilDescriptor new]; dd.depthCompareFunction = MTLCompareFunctionLess; dd.depthWriteEnabled = YES;
    id<MTLDepthStencilState> depth = [d newDepthStencilStateWithDescriptor:dd];
    TestReplay *r = [TestReplay new]; r->device = d; r->queue = [d newCommandQueue];
    [r store:scene_vertices(d, .2, 1, 0) ref:1]; [r store:scene_vertices(d, .8, 0, 1) ref:3];
    uint16_t indices[7] = {0, 0, 0, 0, 0, 1, 2}; [r store:[d newBufferWithBytes:indices length:sizeof indices options:MTLResourceStorageModeShared] ref:2];
    uint32_t args[9] = {0,0,0,0,3,2,0,1,0}; [r store:[d newBufferWithBytes:args length:sizeof args options:MTLResourceStorageModeShared] ref:4];
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:64 height:64 mipmapped:NO]; td.usage = MTLTextureUsageRenderTarget; td.storageMode = MTLStorageModeShared; [r store:[d newTextureWithDescriptor:td] ref:5];
    td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:64 height:64 mipmapped:NO]; td.usage = MTLTextureUsageRenderTarget; td.storageMode = MTLStorageModePrivate; [r store:[d newTextureWithDescriptor:td] ref:6];
    NSData *direct = render_scene(r, pipeline, depth, NO, YES);
    const uint8_t *pixels = direct.bytes;
    for (NSUInteger x = 19; x <= 45; x += 26) { const uint8_t *p = pixels + (32*64+x)*4; check(p[0] > 240 && p[1] < 8 && p[2] < 8, "indexed instances and depth produce two red triangles"); }
    check([direct isEqualToData:render_scene(r, pipeline, depth, YES, YES)], "indirect and direct scene images match");
    id<MTLBuffer> vertices = [r get:1 task:2]; SceneVertex *v = vertices.contents;
    for (int i = 2; i < 5; i++) v[i].color[0] = 0, v[i].color[1] = 1;
    NSData *updated = render_scene(r, pipeline, depth, NO, NO);
    const uint8_t *green = (const uint8_t *)updated.bytes + (32*64+19)*4;
    check(green[0] < 8 && green[1] > 240 && green[2] < 8, "dynamic shared-buffer update visible in next completed draw");
    printf("PASS: native Metal offscreen indexed/instanced geometry, padded strides/offsets, base vertex, indirect equivalence, depth and dynamic buffers on %s\n", d.name.UTF8String);
}

int main(void) {
    @autoreleasepool { test_truncated_records(); test_recorded_calls(); test_buffer_bounds(); test_native_metal(); }
    return 0;
}
