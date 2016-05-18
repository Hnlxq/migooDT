//
//  PlayViewController.m
//  SUMusic
//
//  Created by KevinSu on 16/1/17.
//  Copyright © 2016年 KevinSu. All rights reserved.
//

#import "PlayViewController.h"
#import "OffLineManager.h"
#import <UMSocial.h>
#import <MediaPlayer/MPNowPlayingInfoCenter.h>
#import "LyricView.h"
#import "ShareView.h"

@interface PlayViewController ()

@property (nonatomic, strong) SUPlayerManager * player; //播放器类
@property (nonatomic, strong) LyricView * lycView;      //歌词
@property (nonatomic, strong) ShareView * shareView;    //分享
@property (nonatomic, strong) NSTimer * timer;          //界面刷新定时器
@property (nonatomic, assign) BOOL isShow;

@property (weak, nonatomic) IBOutlet UILabel *channelName;

@property (weak, nonatomic) IBOutlet UILabel *songName;
@property (weak, nonatomic) IBOutlet UILabel *singer;

@property (weak, nonatomic) IBOutlet UIButton *loveSong;
@property (weak, nonatomic) IBOutlet UIButton *nextSong;
@property (weak, nonatomic) IBOutlet UIButton *banSong;

@property (weak, nonatomic) IBOutlet UIView *progressView;
@property (weak, nonatomic) IBOutlet UIView *progressBar;
@property (weak, nonatomic) IBOutlet UIView *currentProgress;
@property (weak, nonatomic) IBOutlet UIView *progressPoint;
@property (weak, nonatomic) IBOutlet UILabel *playTime;
@property (weak, nonatomic) IBOutlet UILabel *totalTime;

@property (weak, nonatomic) IBOutlet UIView *coverView;
@property (weak, nonatomic) IBOutlet UIImageView *songCover;
@property (weak, nonatomic) IBOutlet UIView *playBtnBg;
@property (weak, nonatomic) IBOutlet UIImageView *playBtn;

@property (weak, nonatomic) IBOutlet UIButton *lyricsBtn;
@property (weak, nonatomic) IBOutlet UIButton *favorBtn;
@property (weak, nonatomic) IBOutlet UIButton *shareBtn;
@property (weak, nonatomic) IBOutlet UIButton *downBtn;

@end

@implementation PlayViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.player = [AppDelegate delegate].player;

    [self resetUI];
    
    //监听状态变化
    RegisterNotify(SONGPLAYSTATUSCHANGE, @selector(observeSongPlayStatus))
    RegisterNotify(PLAYMODECHANGE, @selector(playModeChange))
    //音频打断监听
    RegisterNotify(AVAudioSessionInterruptionNotification, @selector(audioInterruption:))
    //播出耳机通知
    RegisterNotify(AVAudioSessionRouteChangeNotification, @selector(routeChangeObserve:))
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        //进度条
        self.progressPoint.layer.masksToBounds = YES;
        self.progressPoint.layer.cornerRadius = self.progressPoint.h / 2.0;
        
        //封面
        self.songCover.layer.masksToBounds = YES;
        self.songCover.layer.cornerRadius = self.songCover.h / 2.0;
        self.songCover.layer.borderWidth = 5.0;
        self.songCover.layer.borderColor = [UIColor lightGrayColor].CGColor;

        self.playBtnBg.layer.masksToBounds = YES;
        self.playBtnBg.layer.cornerRadius = self.playBtnBg.h / 2.0;
        
        //歌词
        self.lycView = [[LyricView alloc]initWithFrame:CGRectMake(0, self.coverView.y, ScreenW, self.progressView.y + self.progressView.h - self.coverView.y)];
        [self.view addSubview:self.lycView];
    });
    
    if (_player.isPlaying) {
        [self addTimer];
        [self.lycView startRoll];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (_timer) [self removeTimer];
    [self.lycView stopRoll];
}

#pragma mark - 界面出现和隐藏
- (void)show {
    
    if (self.isShow) return;
    
    self.isShow = YES;
    
    UIWindow * keyWindow = [UIApplication sharedApplication].keyWindow;
    self.view.frame = CGRectMake(0, ScreenH, ScreenW, ScreenH);
    [keyWindow addSubview:self.view];
    
    keyWindow.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.4 animations:^{
        self.view.y = 0;
    } completion:^(BOOL finished) {
        keyWindow.userInteractionEnabled = YES;
    }];
}

- (void)launchShow {
    
    if (self.isShow) return;
    
    self.isShow = YES;
    
    UIWindow * keyWindow = [UIApplication sharedApplication].keyWindow;
    self.view.frame = CGRectMake(0, 0, ScreenW, ScreenH);
    self.view.alpha = 0.f;
    [keyWindow addSubview:self.view];
    
    [UIView animateWithDuration:0.4 animations:^{
        self.view.alpha = 1.0;
    } completion:^(BOOL finished) {
        keyWindow.userInteractionEnabled = YES;
    }];
}

- (IBAction)hide:(UIButton *)sender {
    
    if (!self.isShow) return;
    
    self.isShow = NO;
    
    UIWindow * keyWindow = [UIApplication sharedApplication].keyWindow;
    keyWindow.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.4 animations:^{
        self.view.y = ScreenH;
    } completion:^(BOOL finished) {
        keyWindow.userInteractionEnabled = YES;
        [self.view removeFromSuperview];
    }];
}


#pragma mark - 通知处理
- (void)observeSongPlayStatus {
    switch (_player.status) {
        case SUPlayStatusNon:
            BASE_INFO_FUN(@"播放界面：未知状态");
            break;
        case SUPlayStatusLoadSongInfo:
            BASE_INFO_FUN(@"播放界面：加载信息");
            [self synUI];
            break;
        case SUPlayStatusReadyToPlay:
            BASE_INFO_FUN(@"播放界面：准备播放");
            [self addTimer];
            break;
        case SUPlayStatusPlay:
            BASE_INFO_FUN(@"播放界面：继续播放");
            [self refreshCoverPlayingStatus];
            [self addTimer];
            break;
        case SUPlayStatusPause:
            BASE_INFO_FUN(@"播放界面：暂停播放");
            [self removeTimer];
            [self refreshCoverPlayingStatus];
            break;
        case SUPlayStatusStop:
            BASE_INFO_FUN(@"播放界面：停止播放");
            [self removeTimer];
            [self resetUI];
            break;
        default:
            break;
    }
}

- (void)playModeChange {
    //离线：变为上一首
    if (_player.isOffLinePlay) {
        [self.banSong setImage:[UIImage imageNamed:@"ic_action_prev"] forState:UIControlStateNormal];
        [self.banSong setImage:[UIImage imageNamed:@"ic_action_prev_pressed"] forState:UIControlStateHighlighted];
    }
    //在线：变为ban歌
    else {
        [self.banSong setImage:[UIImage imageNamed:@"ic_action_ban"] forState:UIControlStateNormal];
        [self.banSong setImage:[UIImage imageNamed:@"ic_action_ban_pressed"] forState:UIControlStateHighlighted];
    }
}

- (void)audioInterruption:(NSNotification *)notification {
    
//    BASE_INFO_FUN(notification.userInfo);
    NSDictionary * interruptionDict = notification.userInfo;
    NSNumber * interruptionType = [interruptionDict valueForKey:AVAudioSessionInterruptionTypeKey];
    if (interruptionType.intValue == AVAudioSessionInterruptionTypeBegan) {
        BASE_INFO_FUN(@"打断开始");
        [self pausePlaying:nil];
    }
    else if (interruptionType.intValue == AVAudioSessionInterruptionTypeEnded) {
        BASE_INFO_FUN(@"打断结束");
        //在后台不能恢复播放
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
            BASE_INFO_FUN(@"APP在后台，不能继续播放");
        }
        //在前台继续播放
        else {
            [self goOnPlaying:nil];
        }
    }
}

- (void)routeChangeObserve:(NSNotification *)notification {
    
    NSDictionary * routeChangeDict = notification.userInfo;
    //信号路径变更的原因
    AVAudioSessionRouteChangeReason changeReason = [[routeChangeDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    //旧设备描述
    AVAudioSessionRouteDescription * routeDesc = [routeChangeDict valueForKey:AVAudioSessionRouteChangePreviousRouteKey];
    //旧设备输出描述
    AVAudioSessionPortDescription * portDesc = routeDesc.outputs[0];
    
    switch (changeReason) {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            BASE_INFO_FUN(@"插入新设备");
            break;
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            if ([portDesc.portType isEqualToString:@"Headphones"]) {
                BASE_INFO_FUN(@"拔出耳机");
                [self pausePlaying:nil];
            }else {
                BASE_INFO_FUN(@"移除其他设备");
            }
            break;
        default:
            break;
    }
}

#pragma mark - 刷新界面
- (void)synUI {
    
    //激活按钮
    [self changeAllBtnStatus:YES];
    
    //频道
    self.channelName.text = [NSString stringWithFormat:@"🎵 %@ MHz 🎵",self.player.currentChannel.name];
    
    //封面
    self.coverView.userInteractionEnabled = YES;
    [self.songCover sd_setImageWithURL:[NSURL URLWithString:_player.currentSong.picture] placeholderImage:DefaultImg completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
        self.player.coverImg = image;
        [[AppDelegate delegate] configNowPlayingCenter];
    }];
    [self.songCover startTransitionAnimation];
    
    //歌名
    self.songName.text = _player.currentSong.title;
    self.singer.text = [NSString stringWithFormat:@"- %@ -",_player.currentSong.artist];
    [self.songName startTransitionAnimation];
    [self.singer startTransitionAnimation];
    
    //进度条
    self.playTime.hidden = NO;
    self.totalTime.hidden = NO;
    [self.playTime startTransitionAnimation];
    [self.totalTime startTransitionAnimation];
    
    //三大金刚
    self.loveSong.selected = _player.currentSong.like.intValue == 1 ? YES : NO;
    self.loveSong.enabled = !_player.isOffLinePlay;
    
    //四大天王
    [self refreshFavorStatus];
    [self refreshDownLoadStatus];
    
    //设置歌词
    [SUNetwork fetchLyricWithCompletion:^(BOOL isSucc, BOOL isExist, NSDictionary *lyric) {
//        BASE_INFO_FUN(lyric);
        [self.lycView loadLyric:lyric];
    }];
}

- (void)resetUI {
    
    self.channelName.text = [NSString stringWithFormat:@"🎵 %@ MHz 🎵",self.player.currentChannel.name];;
    self.songName.text = @"";
    self.singer.text = @"";
    
    self.songCover.image = DefaultImg;
    self.songCover.transform = CGAffineTransformMakeRotation(0.0);
    self.coverView.userInteractionEnabled = NO;
    self.playBtn.hidden = YES;
    self.playBtnBg.hidden = YES;
    
    self.playTime.text = @"00:00";
    self.playTime.hidden = YES;
    self.totalTime.text = @"00:00";
    self.totalTime.hidden = YES;
    self.progressPoint.x = self.progressBar.x;
    self.currentProgress.w = 1.0;
    
    [self changeAllBtnStatus:NO];
    
    [self.lycView clearLyric];
}

- (void)refreshProgress {
    
    //显示时间
    self.playTime.text = _player.timeNow;
    self.totalTime.text = _player.duration;
    
    //进度条
    float pointW = self.progressPoint.w / 2.0;
    float progress = _player.progress;
    self.currentProgress.w = pointW  + (self.progressBar.w - pointW) * progress;
    self.progressPoint.centerX = self.progressBar.x + self.currentProgress.w;
    
    //图片旋转
    self.songCover.transform = CGAffineTransformRotate(self.songCover.transform, M_PI / 1440);
}


- (void)changeAllBtnStatus:(BOOL)status {
    self.banSong.enabled = status;
    self.loveSong.enabled = status;
    self.nextSong.enabled = status;
    
    self.lyricsBtn.enabled = status;
    self.favorBtn.enabled = status;
    self.downBtn.enabled = status;
    self.shareBtn.enabled = status;
}

- (void)refreshCoverPlayingStatus {
    
    BOOL status = self.player.status == SUPlayStatusPause ? NO : YES;
    self.playBtnBg.hidden = status;
    self.playBtn.hidden = status;
}

- (void)refreshFavorStatus {
    NSArray * favorChannels = [SuDBManager fetchFavorList];
    BOOL isFavor = NO;
    for (ChannelInfo * info in favorChannels) {
        if ([info.channel_id isEqualToString:_player.currentChannel.channel_id]) {
            isFavor = YES;
            break;
        }
    }
    self.favorBtn.selected = isFavor;
}

- (void)refreshDownLoadStatus {
    NSArray * downloadList = [SuDBManager fetchDownList];
    for (SongInfo * info in downloadList) {
        if ([info.sid isEqualToString:_player.currentSong.sid]) {
            self.downBtn.enabled = NO;
            return;
        }
    }
    NSArray * offLineList = [SuDBManager fetchOffLineList];
    for (SongInfo * info in offLineList) {
        if ([info.sid isEqualToString:_player.currentSong.sid]) {
            self.downBtn.enabled = NO;
            return;
        }
    }
    self.downBtn.enabled = YES;
}

#pragma mark - 定时器
- (void)addTimer {
    if (_timer) return;
    BASE_INFO_FUN(@"添加timer");
    _timer = [NSTimer scheduledTimerWithTimeInterval:1.f / 20 target:self selector:@selector(refreshProgress) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop]addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)removeTimer {
    if (_timer == nil) return;
    BASE_INFO_FUN(@"移除timer");
    [_timer invalidate];
    _timer = nil;
}


#pragma mark - 播放控制
- (IBAction)pausePlaying:(UITapGestureRecognizer *)sender {
    [self.player pausePlay];
}

- (IBAction)goOnPlaying:(UITapGestureRecognizer *)sender {
    [self.player startPlay];
}

- (IBAction)skipSong:(UIButton *)sender {
    
    [self.player skipSongWithHandle:^(BOOL isSucc) {
        if (isSucc) {
            BASE_INFO_FUN(@"跳到下一首");
        }else {
            [self ToastMessage:@"网络错误"];
        }
    }];
}

- (IBAction)loveSong:(UIButton *)sender {
    
    OperationType type = sender.selected ? OperationTypeUnHeart : OperationTypeHeart;
    [SUNetwork fetchPlayListWithType:type completion:^(BOOL isSucc) {
        if (isSucc) {
            sender.selected = !sender.selected;
            BASE_INFO_FUN(@"红心/取消红心");
        }else {
            [self ToastMessage:@"网络错误"];
        }
    }];
}

- (IBAction)banSong:(UIButton *)sender {
    [_player banSongWithHandle:^(BOOL isSucc) {
        if (isSucc) {
            BASE_INFO_FUN(@"BAN歌");
        }else {
            [self ToastMessage:@"网络错误"];
        }
    }];
}

#pragma mark - 歌词／收藏／离线／分享
- (IBAction)lyrics:(UIButton *)sender {
    
    if (self.lycView.hidden) {
        [self.lycView show];
    }else {
        [self.lycView hide];
    }
}

- (IBAction)favor:(UIButton *)sender {
    //取消收藏
    if (sender.selected) {
        BASE_INFO_FUN(@"取消收藏");
        [SuDBManager deleteFromFavorListWithSid:_player.currentSong.sid];
        sender.selected = NO;
    }
    //收藏
    else {
        BASE_INFO_FUN(@"收藏成功");
        [SuDBManager saveToFavorList];
        sender.selected = YES;
    }
}

- (IBAction)downLoad:(UIButton *)sender {
    
    [[OffLineManager manager] downLoadSong];
    sender.enabled = NO;
    [TopAlertView showWithType:TopAlertTypeAdd message:[NSString stringWithFormat:@"正在离线%@",_player.currentSong.title]];
}

- (IBAction)share:(UIButton *)sender {
    
    if (_shareView == nil) {
        WEAKSELF
        _shareView = [[NSBundle mainBundle] loadNibNamed:@"ShareView" owner:self options:nil][0];
        _shareView.frame = ScreenB;
        [_shareView setShareBlock:^(NSInteger shareType) {
            [weakSelf shareWithType:shareType];
        }];
    }
    [_shareView showInView:self.view];
}

- (void)shareWithType:(NSInteger)shareType {
    
    NSArray * types = @[UMShareToSina, UMShareToWechatSession, UMShareToWechatTimeline];
    [[UMSocialDataService defaultDataService] postSNSWithTypes:@[types[shareType]] content:[NSString stringWithFormat:@"%@%@",_player.currentSong.title,_player.currentSong.artist] image:DefaultImg location:nil urlResource:nil presentedController:self completion:^(UMSocialResponseEntity *response) {
        
        [_shareView dismiss:nil];
        if (response.responseCode == UMSResponseCodeSuccess) {
            BASE_INFO_FUN(@"分享成功");
            [SuDBManager saveToSharedList];
        }else {
            BASE_INFO_FUN(@"分享失败");
        }
    }];
}

@end
