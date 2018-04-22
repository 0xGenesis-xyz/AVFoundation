//
//  VideoCaptureViewController.m
//  AVFoundation
//
//  Created by Sylvanus on 4/20/18.
//  Copyright © 2018 Sylvanus. All rights reserved.
//

#import "VideoCaptureViewController.h"

@interface VideoCaptureViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (weak, nonatomic) IBOutlet UIView *previewView;
@property (weak, nonatomic) IBOutlet UIButton *recording;
@property BOOL isRecording;

@property (nonatomic, getter=isDeviceAuthorized) BOOL deviceAuthorized;
@property AVCaptureSession *session;

@property AVAssetWriter *assetWriter;
@property AVAssetWriterInput *assetWriterInput;
@property AVAssetWriterInputPixelBufferAdaptor *adaptor;
@property NSString *outputFilePath;
@property CMTime lastTimestamp;

@end

@implementation VideoCaptureViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [self.recording setTitle:@"Start" forState:UIControlStateNormal];
    self.isRecording = false;
    
    self.lastTimestamp = kCMTimeZero;
    [self setupCapture];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    previewLayer.frame = self.previewView.bounds;
    [self.previewView.layer addSublayer:previewLayer];
    
    [self.session startRunning];
}

- (IBAction)record:(UIButton *)sender {
    if (!self.isRecording) {
        NSLog(@"start recording...");
        [self.recording setTitle:@"Stop" forState:UIControlStateNormal];
        self.isRecording = YES;
        
        [self setupAssetWriter:CGSizeMake(300, 200)];

        [self.assetWriter startWriting];
        [self.assetWriter startSessionAtSourceTime:self.lastTimestamp];
    } else {
        NSLog(@"stop recording...");
        [self.recording setTitle:@"Start" forState:UIControlStateNormal];
        self.isRecording = NO;
        
        [self.assetWriterInput markAsFinished];
        [self.assetWriter finishWritingWithCompletionHandler:^{
            if ([self.assetWriter status] == AVAssetWriterStatusCompleted) {
                NSFileManager *fileManager = [NSFileManager defaultManager];
                if ([fileManager fileExistsAtPath:self.outputFilePath]) {
                    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                        [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:self.outputFilePath]];
                    } completionHandler:^(BOOL success, NSError * _Nullable error) {
                        if (success) {
                            NSLog(@"save to camera roll");
                        } else {
                            NSLog(@"save fail::%@", error.localizedDescription);
                        }
                    }];
                }
            } else {
                NSLog(@"%@", [self.assetWriter error]);
            }
        }];
    }
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    self.lastTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    if (self.isRecording) {
        NSLog(@"%u", (unsigned int)CVPixelBufferGetPixelFormatType(pixelBuffer));
        CVPixelBufferRef pixelBufferOut = [self processBuffer:pixelBuffer];
        
        if (pixelBufferOut == NULL) {
            NSLog(@"buffer null");
            return;
        }
        
        if ([self.adaptor.assetWriterInput isReadyForMoreMediaData]) {
            // [self.assetWriterInput appendSampleBuffer:sampleBuffer];
            [self.adaptor appendPixelBuffer:pixelBufferOut withPresentationTime:self.lastTimestamp];
        } else {
            NSLog(@"writer not ready");
        }
    }
}

- (CVPixelBufferRef)processBuffer:(CVPixelBufferRef)pixelBuffer {
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    OSType pixelFormatType = CVPixelBufferGetPixelFormatType(pixelBuffer);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    /*
    size_t numberOfPlanes = CVPixelBufferGetPlaneCount(pixelBuffer);
    void *planeBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer);
    size_t planeWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer);
    size_t planeHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer);
    size_t planeBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer);
    */
    CVPixelBufferRef pixelBufferOut;
    CVPixelBufferCreateWithBytes(NULL, width, height, pixelFormatType, baseAddress, bytesPerRow, NULL, NULL, NULL, &pixelBufferOut);
    //CVPixelBufferCreateWithPlanarBytes(NULL, width, height, pixelFormatType, <#void * _Nullable dataPtr#>, <#size_t dataSize#>, numberOfPlanes, planeBaseAddress, planeWidth, planeHeight, planeBytesPerRow, NULL, NULL, NULL, pixelBufferOut)
    return pixelBufferOut;
}

void releaseBytesCallback(void *releaseRefCon, const void *baseAddress) {
    CVPixelBufferRelease(releaseRefCon);
}

- (void)setupCapture {
    NSLog(@"configuring AVCaptureSession...");
    
    self.session = [[AVCaptureSession alloc] init];
    [self.session setSessionPreset:AVCaptureSessionPresetMedium];
    
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    [self.session addInput:input];
    
    AVCaptureVideoDataOutput *output = [AVCaptureVideoDataOutput new];
    NSLog(@"CVPixelFormat: %@", [output availableVideoCVPixelFormatTypes]);
    NSDictionary *outputSettings = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
    [output setVideoSettings: outputSettings];
    dispatch_queue_t queue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    [output setSampleBufferDelegate:self queue:queue];
    [self.session addOutput:output];
}

- (void)setupAssetWriter:(CGSize)size {
    NSLog(@"configuring AssetWriter...");
    
    NSString *documentsDirectoryPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *outputFileName = @"outputFile.m4v";
    self.outputFilePath = [NSString stringWithFormat:@"%@/%@", documentsDirectoryPath, outputFileName];
    
    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:self.outputFilePath]) {
        [fileManager removeItemAtPath:self.outputFilePath error:&error];
    }

    self.assetWriter = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:self.outputFilePath] fileType:AVFileTypeMPEG4 error:&error];
    
    NSDictionary *videoSettings = @{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: [NSNumber numberWithFloat:size.width],
        AVVideoHeightKey: [NSNumber numberWithFloat:size.height]
    };
    self.assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    [self.assetWriterInput setExpectsMediaDataInRealTime:YES];
    
    NSDictionary *pixelBufferAttributes = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (NSString *)kCVPixelBufferWidthKey: [NSNumber numberWithFloat:size.width],
        (NSString *)kCVPixelBufferHeightKey: [NSNumber numberWithFloat:size.height]
    };
    self.adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.assetWriterInput
                                                                                    sourcePixelBufferAttributes:pixelBufferAttributes];
    
    [self.assetWriter addInput:self.assetWriterInput];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
