//
//  TUIImageMessageCellData_Minimalist.m
//  TXIMSDK_TUIKit_iOS
//
//  Created by annidyfeng on 2019/5/21.
//

#import "TUIImageMessageCellData_Minimalist.h"
#import "TUIDefine.h"
#import "NSString+TUIUtil.h"

@interface TUIImageMessageCellData_Minimalist ()
@property (nonatomic, assign) BOOL isDownloading;
@property (nonatomic, copy) TUIImageMessageDownloadCallback onFinish;
@end

@implementation TUIImageMessageCellData_Minimalist

+ (TUIMessageCellData *)getCellData:(V2TIMMessage *)message {
    V2TIMImageElem *elem = message.imageElem;
    TUIImageMessageCellData_Minimalist *imageData = [[TUIImageMessageCellData_Minimalist alloc] initWithDirection:(message.isSelf ? MsgDirectionOutgoing : MsgDirectionIncoming)];
    imageData.path = [elem.path safePathString];
    imageData.items = [NSMutableArray array];
    for (V2TIMImage *item in elem.imageList) {
        TUIImageItem *itemData = [[TUIImageItem alloc] init];
        itemData.uuid = item.uuid;
        itemData.size = CGSizeMake(item.width, item.height);
//        itemData.url = item.url;
        if(item.type == V2TIM_IMAGE_TYPE_THUMB){
            itemData.type = TImage_Type_Thumb;
        }
        else if(item.type == V2TIM_IMAGE_TYPE_LARGE){
            itemData.type = TImage_Type_Large;
        }
        else if(item.type == V2TIM_IMAGE_TYPE_ORIGIN){
            itemData.type = TImage_Type_Origin;
        }
        [imageData.items addObject:itemData];
    }
    imageData.reuseId = TImageMessageCell_ReuseId;
    return imageData;
}

+ (NSString *)getDisplayString:(V2TIMMessage *)message {
    return TUIKitLocalizableString(TUIkitMessageTypeImage); // @"[图片]";
}

- (Class)getReplyQuoteViewDataClass
{
    return NSClassFromString(@"TUIImageReplyQuoteViewData_Minimalist");
}

- (Class)getReplyQuoteViewClass
{
    return NSClassFromString(@"TUIImageReplyQuoteView_Minimalist");
}

- (instancetype)initWithDirection:(TMsgDirection)direction {
    self = [super initWithDirection:direction];
    if (self) {
        _uploadProgress = 100;
    }
    return self;
}

- (NSString *)getImagePath:(TUIImageType)type isExist:(BOOL *)isExist
{
    NSString *path = nil;
    BOOL isDir = NO;
    *isExist = NO;
    if(self.direction == MsgDirectionOutgoing) {
        path = [NSString stringWithFormat:@"%@%@", TUIKit_Image_Path, _path.lastPathComponent];
        if([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]){
            if(!isDir){
                *isExist = YES;
            }
        }
    }

    if(!*isExist) {
        TUIImageItem *tImageItem = [self getTImageItem:type];
        path = [NSString stringWithFormat:@"%@%@", TUIKit_Image_Path, tImageItem.uuid];
        if([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]){
            if(!isDir){
                *isExist = YES;
            }
        }
    }

    return path;
}

- (void)downloadImage:(TUIImageType)type finish:(TUIImageMessageDownloadCallback)finish
{
    self.onFinish = finish;
    [self downloadImage:type];
}

- (void)downloadImage:(TUIImageType)type
{
    BOOL isExist = NO;
    NSString *path = [self getImagePath:type isExist:&isExist];
    if(isExist)
    {
        [self decodeImage:type];
        return;
    }

    if(self.isDownloading) {
        return;
    }
    self.isDownloading = YES;

    //网络下载
    V2TIMImage *imImage = [self getIMImage:type];

    @weakify(self)
    [imImage downloadImage:path progress:^(NSInteger curSize, NSInteger totalSize) {
        @strongify(self)
        [self updateProgress:curSize * 100 / totalSize withType:type];
    } succ:^{
        @strongify(self)
        self.isDownloading = NO;
        [self updateProgress:100 withType:type];
        [self decodeImage:type];
    } fail:^(int code, NSString *msg) {
        @strongify(self)
        self.isDownloading = NO;
        /**
         * 如果图片的 uuid 一样（同一个用户连续发送同一张图片），同一个 path 可能触发多次下载操作，除了第一次，后面的下载会报错，这时候要再去判断下本地文件是否存在
         * If the uuid of the picture is the same (the same user sends the same picture continuously), the same path may trigger multiple download operations. Except for the first time,
         * subsequent downloads will report an error. At this time, it is necessary to judge whether the local file exists.
         */
        [self decodeImage:type];
    }];
}

- (void)updateProgress:(NSUInteger)progress withType:(TUIImageType)type
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (type == TImage_Type_Thumb)
            self.thumbProgress = progress;
        if (type == TImage_Type_Large)
            self.largeProgress = progress;
        if (type == TImage_Type_Origin)
            self.originProgress = progress;
    });
}

- (void)decodeImage:(TUIImageType)type
{
    BOOL isExist = NO;
    NSString *path = [self getImagePath:type isExist:&isExist];
    if(!isExist)
    {
        return;
    }

    __weak typeof(self) weakSelf = self;
    void (^finishBlock)(UIImage *) = ^(UIImage *image){
        if (type == TImage_Type_Thumb) {
            weakSelf.thumbImage = image;
            weakSelf.thumbProgress = 100;
            weakSelf.uploadProgress = 100;
        }
        if (type == TImage_Type_Large) {
            weakSelf.largeImage = image;
            weakSelf.largeProgress = 100;
        }
        if (type == TImage_Type_Origin) {
            weakSelf.originImage = image;
            weakSelf.originProgress = 100;
        }
        if (weakSelf.onFinish) {
            weakSelf.onFinish();
        }
    };

    NSString *cacheKey = [path substringFromIndex:TUIKit_Image_Path.length];


    UIImage *cacheImage = [[SDImageCache sharedImageCache] imageFromCacheForKey:cacheKey];
    if (cacheImage) {
        finishBlock(cacheImage);
    } else {
        [TUITool asyncDecodeImage:path complete:^(NSString *path, UIImage *image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if(![path containsString:@".gif"]) {
                    /**
                     * gif 图片过大, 不在内存进行缓存
                     * The gif image is too large to be cached in memory
                     */
                    [[SDImageCache sharedImageCache] storeImageToMemory:image forKey:cacheKey];
                }
                finishBlock(image);
            });
        }];
    }
}

- (TUIImageItem *)getTImageItem:(TUIImageType)type
{
    for (TUIImageItem *item in self.items) {
        if(item.type == type){
            return item;
        }
    }
    return nil;
}

- (V2TIMImage *)getIMImage:(TUIImageType)type
{
    V2TIMMessage *imMsg = self.innerMessage;
    if (imMsg.elemType == V2TIM_ELEM_TYPE_IMAGE) {
        for (V2TIMImage *imImage in imMsg.imageElem.imageList) {
            if(type == TImage_Type_Thumb && imImage.type == V2TIM_IMAGE_TYPE_LARGE){
                return imImage;
            }
            else if(type == TImage_Type_Origin && imImage.type == V2TIM_IMAGE_TYPE_ORIGIN){
                return imImage;
            }
            else if(type == TImage_Type_Large && imImage.type == V2TIM_IMAGE_TYPE_LARGE){
                return imImage;
            }
        }
    }
    return nil;
}

- (CGSize)contentSize
{
    CGSize size = CGSizeZero;
    BOOL isDir = NO;
    if(![self.path isEqualToString:@""] &&
       [[NSFileManager defaultManager] fileExistsAtPath:self.path isDirectory:&isDir]){
        if(!isDir){
            size = [UIImage imageWithContentsOfFile:self.path].size;
        }
    }

    if (CGSizeEqualToSize(size, CGSizeZero)) {
        for (TUIImageItem *item in self.items) {
            if(item.type == TImage_Type_Origin){
                size = item.size;
            }
        }
    }
    if (CGSizeEqualToSize(size, CGSizeZero)) {
        for (TUIImageItem *item in self.items) {
            if(item.type == TImage_Type_Large){
                size = item.size;
            }
        }
    }
    if (CGSizeEqualToSize(size, CGSizeZero)) {
        for (TUIImageItem *item in self.items) {
            if(item.type == TImage_Type_Thumb){
                size = item.size;
            }
        }
    }

    if(CGSizeEqualToSize(size, CGSizeZero)){
        return size;
    }
    CGFloat widthMax= kScale390(250);
    CGFloat heightMax= kScale390(250);
    if(size.height > size.width){
        size.width = size.width / size.height * heightMax;
        size.height = heightMax;
    } else {
        size.height = size.height / size.width * widthMax;
        size.width = widthMax;
    }
    return size;
}
@end