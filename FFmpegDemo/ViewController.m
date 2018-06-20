//
//  ViewController.m
//  FFmpegDemo
//
//  Created by chengshun on 2018/6/14.
//  Copyright © 2018年 chengshun. All rights reserved.
//

#import "ViewController.h"
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>

@interface ViewController ()
{
    AVFormatContext *_formatContext;
    int _videoStream;
    AVStream *_stream;
    AVCodecContext *_codecContext;
    AVFrame *_frame;
    double _fps;
}

@property (nonatomic,assign) int outputWidth, outputHeight;

@property (nonatomic, strong) UIImageView *movieView;

@end

@implementation ViewController

+(NSString *)bundlePath:(NSString *)fileName
{
    return [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:fileName];
}

- (void)seekTime:(double)seconds
{
    AVRational timeBase = _stream->time_base;
    int64_t targetFrame = (int64_t)((double)timeBase.den / timeBase.num * seconds);
    avformat_seek_file(_formatContext, _videoStream, 0, targetFrame, targetFrame, AVSEEK_FLAG_FRAME);
    avcodec_flush_buffers(_codecContext);
    
    
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    
    
    
    NSString *videoPath = [self.class bundlePath:@"for_the_birds.avi"];
    
    // 初始化
    avcodec_register_all();
    av_register_all();
    avformat_network_init();
    
    if (avformat_open_input(&_formatContext, [videoPath UTF8String], NULL, NULL)) {
        NSLog(@"打开文件失败");
        return;
    }
    
    if (avformat_find_stream_info(_formatContext, NULL) < 0) {
        NSLog(@"检查数据流失败");
        return;
    }
    
    if ((_videoStream = av_find_best_stream(_formatContext, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0)) < 0) {
        NSLog(@"没有找到第一个视频流");
        return;
    }
    
    _stream = _formatContext->streams[_videoStream];
    _codecContext = _stream->codec;
    
    av_dump_format(_formatContext, _videoStream, [videoPath UTF8String], 0);
    
    if(_stream->avg_frame_rate.den && _stream->avg_frame_rate.num) {
        _fps = av_q2d(_stream->avg_frame_rate);
    } else {
        _fps = 30;
    }
    
    AVCodec *codec = avcodec_find_decoder(_stream->codecpar->codec_id);
    _codecContext = avcodec_alloc_context3(codec);
    _codecContext->opaque = NULL;
    _codecContext->extradata = _stream->codecpar->extradata;
    _codecContext->extradata_size = _stream->codecpar->extradata_size;
    _codecContext->width = _stream->codecpar->width;
    _codecContext->height = _stream->codecpar->height;
    _codecContext->coded_width = _stream->codecpar->width;
    _codecContext->coded_height = _stream->codecpar->height;
    _codecContext->pix_fmt = _stream->codecpar->format;
    
    int ret = avcodec_open2(_codecContext, codec, NULL);
    
    _outputWidth = _codecContext->width;
    _outputHeight = _codecContext->height;
    
    
    self.movieView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, _outputWidth, _outputHeight)];
    [self.view addSubview:self.movieView];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self seekTime:0];
        [NSTimer scheduledTimerWithTimeInterval: 1 / self->_fps
                                         target:self
                                       selector:@selector(displayNextFrame:)
                                       userInfo:nil
                                        repeats:YES];
    });
}

- (void)displayNextFrame:(NSTimer *)timer
{
    AVPacket packet;
    
    while (av_read_frame(_formatContext, &packet) >= 0) {
        if (packet.stream_index == _videoStream) {
            if (_frame) {
                if(_frame->data[0] != NULL) {
                    av_frame_unref(_frame);
                }
                av_frame_free(&_frame);
            }
            _frame = av_frame_alloc();
            
            int rtn1 = avcodec_send_packet(_codecContext, &packet);
            int rtn2 = avcodec_receive_frame(_codecContext, _frame);
            if (rtn2 == 0) {
                break;
            }
            break;
        }
    }
    
    self.movieView.image = [self imageFromAVPicture];
}

- (UIImage *)imageFromAVPicture
{
    AVPicture picture;
    avpicture_alloc(&picture, AV_PIX_FMT_RGB24, _outputWidth, _outputHeight);
    
    struct SwsContext *imgConvertCtx = sws_getContext(_frame->width,
                                                      _frame->height,
                                                      AV_PIX_FMT_YUV420P,
                                                      _outputWidth,
                                                      _outputHeight,
                                                      AV_PIX_FMT_RGB24,
                                                      SWS_FAST_BILINEAR,
                                                      NULL,
                                                      NULL,
                                                      NULL);
    sws_freeContext(imgConvertCtx);
    
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    CFDataRef data = CFDataCreate(kCFAllocatorDefault,
                                  picture.data[0],
                                  picture.linesize[0] * _outputHeight);
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef cgImage = CGImageCreate(_outputWidth,
                                       _outputHeight,
                                       8,
                                       24,
                                       picture.linesize[0],
                                       colorSpace,
                                       bitmapInfo,
                                       provider,
                                       NULL,
                                       NO,
                                       kCGRenderingIntentDefault);
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    CFRelease(data);
    
    return image;
    
}

@end
