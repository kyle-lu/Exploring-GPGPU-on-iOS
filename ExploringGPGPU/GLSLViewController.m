//
//  GLSLViewController.m
//  ExploringGPGPU
//

#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/ES3/glext.h>
#import <CommonCrypto/CommonDigest.h>

#import "GLSLViewController.h"

#define SHA256_BLOCK_BYTES 32

#define COUNT (1 << 20)

#define PROFILE_ITERATIONS 8

@interface GLSLViewController () {
    GLuint gpuReadBuffer;
    GLuint gpuWriteBuffer;
    GLuint vao;

    unsigned char *cpuReadBuffer;
    unsigned char *cpuWriteBuffer;

    GLuint program;
}

@property (nonatomic, strong) EAGLContext *context;

@end


@implementation GLSLViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!self.context) {
        printf("This application requires OpenGL ES 3.0\n");
        abort();
    }


    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;

    [EAGLContext setCurrentContext:self.context];

    [self loadShaders];

    [self setupCPUBuffers];
    [self setupGPUBuffers];
    [self fillBuffers];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Shader Compilation

- (GLuint)createShaderWithType:(GLenum)type source:(GLchar const *)source {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, 0);
    glCompileShader(shader);


#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(shader, logLength, &logLength, log);
        printf("Shader compile log:\n%s\n", log);
        free(log);
    }
#endif

    GLint status;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(shader);
        return 0;
    }

    return shader;
}

- (void)loadShaders {
    GLuint programHandle = glCreateProgram();

    NSString *shaderPath = [[NSBundle mainBundle] pathForResource:@"sha256" ofType:@"vsh"];
    NSString *shaderSource = [NSString stringWithContentsOfFile:shaderPath encoding:NSUTF8StringEncoding error:nil];
    GLuint vertexShader = [self createShaderWithType:GL_VERTEX_SHADER source:[shaderSource UTF8String]];

    GLchar *fragmentShaderSource = (GLchar *)"#version 300 es\n\nvoid main() {}";
    GLuint fragmentShader = [self createShaderWithType:GL_FRAGMENT_SHADER source:fragmentShaderSource];

    glAttachShader(programHandle, vertexShader);
    glAttachShader(programHandle, fragmentShader);

    glBindAttribLocation(programHandle, 0, "block0");
    glBindAttribLocation(programHandle, 1, "block1");

    char *varyings[] = {"digest"};
    glTransformFeedbackVaryings(programHandle, 1, (const char * const *)varyings, GL_INTERLEAVED_ATTRIBS);

    glLinkProgram(programHandle);


#if defined(DEBUG)
    GLint logLength;

    glGetProgramiv(programHandle, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(programHandle, logLength, &logLength, log);
        printf("Program link log:\n%s\n", log);
        free(log);
    }
#endif

    GLint status;
    glGetProgramiv(programHandle, GL_LINK_STATUS, &status);
    if (status == 0) {
        printf("Link error\n");
        return;
    }

    program = programHandle;

    return;
}

- (void)setupCPUBuffers {
    cpuReadBuffer = malloc(SHA256_BLOCK_BYTES * COUNT);
    cpuWriteBuffer = malloc(CC_SHA256_DIGEST_LENGTH * COUNT);
}

- (void)setupGPUBuffers {
    glGenBuffers(1, &gpuReadBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, gpuReadBuffer);
    glBufferData(GL_ARRAY_BUFFER, SHA256_BLOCK_BYTES * COUNT, NULL, GL_STREAM_DRAW);

    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);

    glVertexAttribIPointer(0, 4, GL_UNSIGNED_INT, SHA256_BLOCK_BYTES, (const void *)0);
    glEnableVertexAttribArray(0);

    glVertexAttribIPointer(1, 4, GL_UNSIGNED_INT, SHA256_BLOCK_BYTES, (const void *)(SHA256_BLOCK_BYTES >> 1));
    glEnableVertexAttribArray(1);

    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);


    glGenBuffers(1, &gpuWriteBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, gpuWriteBuffer);
    glBufferData(GL_ARRAY_BUFFER, CC_SHA256_DIGEST_LENGTH * COUNT, NULL, GL_STREAM_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

- (void)fillBuffers {
    glBindBuffer(GL_ARRAY_BUFFER, gpuReadBuffer);
    unsigned char *gpuRead = glMapBufferRange(GL_ARRAY_BUFFER, 0, SHA256_BLOCK_BYTES * COUNT, GL_MAP_WRITE_BIT);
    if (gpuRead == NULL) {
        printf("error: 0x%04x\n", glGetError());
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        return;
    }

    unsigned char buffer[SHA256_BLOCK_BYTES], *cpu, *gpu, byte;
    srand((int)time(NULL));
    for (int i = 0; i < COUNT; i++) {
        memset(buffer, 0, SHA256_BLOCK_BYTES);
        byte = rand();
        memset(buffer, byte, 32);
        cpu = &cpuReadBuffer[i * SHA256_BLOCK_BYTES];
        memcpy(cpu, buffer, SHA256_BLOCK_BYTES);
        gpu = &gpuRead[i * SHA256_BLOCK_BYTES];
        memcpy(gpu, buffer, SHA256_BLOCK_BYTES);
    }

    glUnmapBuffer(GL_ARRAY_BUFFER);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

- (void)calculateCPUWithReadBuffer:(unsigned char * restrict)readBuffer
                       writeBuffer:(unsigned char * restrict)writeBuffer
                             count:(int)count
{
    for (int i = 0; i < count; i++) {
        CC_SHA256(&cpuReadBuffer[i * SHA256_BLOCK_BYTES], 32, &cpuWriteBuffer[i * CC_SHA256_DIGEST_LENGTH]);
    }
}

- (void)calculateGPUWithReadVAO:(GLuint)readVAO
                    writeBuffer:(GLuint)writeBuffer
                          count:(int)count
{
    glUseProgram(program);

    glEnable(GL_RASTERIZER_DISCARD);

    glBindVertexArray(readVAO);

    glBindBufferBase(GL_TRANSFORM_FEEDBACK_BUFFER, 0, writeBuffer);

    glBeginTransformFeedback(GL_POINTS);
    glDrawArrays(GL_POINTS, 0, count);
    glEndTransformFeedback();

    glDisable(GL_RASTERIZER_DISCARD);

    glFinish(); //force the calculations to happen NOW
}

- (void)profileWithBlock:(void (^)(int count))profileBlock {
    NSTimeInterval last = 0.0f;
    for (int count = 1 << 12; count <= COUNT; count <<= 1) {
        NSDate *start = [NSDate date];

        for (int iter = 0; iter < PROFILE_ITERATIONS; iter++) {
            profileBlock(count);
        }

        last = [[NSDate date] timeIntervalSinceDate:start]/PROFILE_ITERATIONS;
        printf("%lu hashes/s\n", (unsigned long)(count / last));
    }
}


- (void)measureCPU {
    printf("CPU\n");

    [self profileWithBlock:^(int count) {
        [self calculateCPUWithReadBuffer:cpuReadBuffer writeBuffer:cpuWriteBuffer count:count];
    }];
}

- (void)measureGPU {
    // shader warmup
    [self calculateGPUWithReadVAO:vao writeBuffer:gpuWriteBuffer count:128];

    printf("GPU\n");

    [self profileWithBlock:^(int count) {
        [self calculateGPUWithReadVAO:vao writeBuffer:gpuWriteBuffer count:count];
    }];
}

- (void)measure {
    [self measureCPU];
    [self measureGPU];
}

- (void)viewDidAppear:(BOOL)animated {
    [self measure];

    unsigned char *cpuBuffer = cpuWriteBuffer;

    glBindBuffer(GL_ARRAY_BUFFER, gpuWriteBuffer);
    unsigned char *gpuBuffer = glMapBufferRange(GL_ARRAY_BUFFER, 0, CC_SHA256_DIGEST_LENGTH * COUNT, GL_MAP_READ_BIT);

    [self compareCPUBuffer:cpuBuffer withGPUBuffer:gpuBuffer];

    glUnmapBuffer(GL_ARRAY_BUFFER);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

- (void)compareCPUBuffer:(unsigned char *)cpuBuffer withGPUBuffer:(unsigned char *)gpuBuffer {
    if (0 == memcmp(cpuBuffer, gpuBuffer, CC_SHA256_DIGEST_LENGTH * COUNT)) {
        printf("Hashes match!\n");
    } else {
        printf("Hashes NOT match!\n");
    }
}


@end
