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
                NSLog(@"%ld", (long)[self.assetWriter status]);
            }
        }];
    }
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    self.lastTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    if (self.isRecording) {
        CVPixelBufferRef pixelBufferOut = [self processBuffer:CVPixelBufferGetBaseAddress(pixelBuffer)
                                                        width:CVPixelBufferGetWidth(pixelBuffer)
                                                       height:CVPixelBufferGetHeight(pixelBuffer)
                                              pixelFormatType:CVPixelBufferGetPixelFormatType(pixelBuffer)
                                                       stride:CVPixelBufferGetBytesPerRow(pixelBuffer)];
        
        if (pixelBufferOut == NULL) {
            NSLog(@"buffer NULL");
        }
        
        if ([self.adaptor.assetWriterInput isReadyForMoreMediaData]) {
            // [self.assetWriterInput appendSampleBuffer:sampleBuffer];
            [self.adaptor appendPixelBuffer:pixelBufferOut withPresentationTime:self.lastTimestamp];
        } else {
            NSLog(@"writer not ready");
        }
    }
}

- (CVPixelBufferRef)processBuffer:(void *)baseAddress
                            width:(size_t)width
                           height:(size_t)height
                  pixelFormatType:(OSType)pixelFormatType
                           stride:(size_t)stride {
    CVPixelBufferRef pixelBuffer;
    CVPixelBufferCreateWithBytes(NULL, width, height, pixelFormatType, baseAddress, stride, NULL, NULL, NULL, &pixelBuffer);
    return pixelBuffer;
}

- (void)setupCapture {
    NSLog(@"configuring AVCaptureSession...");
    
    self.session = [[AVCaptureSession alloc] init];
    [self.session setSessionPreset:AVCaptureSessionPresetMedium];
    
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    [self.session addInput:input];
    
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    dispatch_queue_t queue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    [output setSampleBufferDelegate:self queue:queue];
    [self.session addOutput:output];
    /*
    NSString *mediaType = AVMediaTypeVideo;
    [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
        if (granted) {
            [self setDeviceAuthorized:YES];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setDeviceAuthorized:NO];
            });
        }
    }];
    */
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
        @"kCVPixelBufferPixelFormatTypeKey": [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32ARGB],
        @"kCVPixelBufferWidthKey": [NSNumber numberWithFloat:size.width],
        @"kCVPixelBufferHeightKey": [NSNumber numberWithFloat:size.height]
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
