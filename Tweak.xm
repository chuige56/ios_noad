//
// ============================================================
//  NoAd.dylib — iOS 通用去广告插件 (TrollStore 注入)
//  覆盖: 开屏广告 / 摇一摇广告 / 横幅广告
//  适配 SDK: 穿山甲 / GDT腾讯 / 百度 / 快手 / Sigmob / AdMob
//  用法: 巨魔注入 IPA 后安装，或直接注入已安装 App 的 Frameworks
// ============================================================
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// Forward declarations
static void hookBytedance(void);
static void hookGDT(void);
static void hookBaidu(void);
static void hookKuaishou(void);
static void hookSigmob(void);
static void hookAdMob(void);
static void hookWeChat(void);
static void hookAdSDKs(void);

// ============================================================
// 全局开关 — 可通过偏好设置控制
// ============================================================
static BOOL g_blockSplashAd = YES;    // 屏蔽开屏广告
static BOOL g_blockShakeAd  = YES;    // 屏蔽摇一摇广告
static BOOL g_blockBanner   = YES;    // 屏蔽横幅/信息流广告
static BOOL g_verboseLog    = YES;    // 调试日志
// ============================================================

#define NLog(fmt, ...) if(g_verboseLog) NSLog(@"[NoAd] " fmt, ##__VA_ARGS__)

// ════════════════════════════════════════════════════════════
// 通用 Method Swizzle 工具
// ════════════════════════════════════════════════════════════
static void swizzle(Class cls, SEL orig, SEL repl) {
    Method m1 = class_getInstanceMethod(cls, orig);
    Method m2 = class_getInstanceMethod(cls, repl);
    if (m1 && m2) {
        method_exchangeImplementations(m1, m2);
        NLog(@"swizzled: %@.%@", NSStringFromClass(cls), NSStringFromSelector(orig));
    }
}
static void swizzleClass(Class cls, SEL orig, SEL repl) {
    Method m1 = class_getClassMethod(cls, orig);
    Method m2 = class_getClassMethod(cls, repl);
    if (m1 && m2) {
        method_exchangeImplementations(m1, m2);
        NLog(@"swizzled class: %@.%@", NSStringFromClass(cls), NSStringFromSelector(orig));
    }
}

// ════════════════════════════════════════════════════════════
//  通用 Hook: 拦截所有 UIView addSubview → 过滤广告View
//  这是兜底方案，不依赖具体SDK版本
// ════════════════════════════════════════════════════════════
@interface UIView (NoAdHook)
@end
@implementation UIView (NoAdHook)
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                [self startHooking];
            }];
    });
}
+ (void)startHooking {
    NLog(@"NoAd initializing...");
    // GCD 延迟执行，等所有动态库加载完成
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        hookAdSDKs();
    });
}
@end

// ════════════════════════════════════════════════════════════
//  1. 穿山甲 (CSJ / Pangle / BUAdSDK)
//  开屏: BUSplashAdView / BUNativeExpressSplashView
//  摇一摇: CSJSplashAd 内部用 CoreMotion
// ════════════════════════════════════════════════════════════
static void hookBytedance(void) {
    // --- 开屏广告 View ---
    Class splashClass = NSClassFromString(@"BUSplashAdView");
    if (!splashClass) splashClass = NSClassFromString(@"BUNativeExpressSplashView");
    if (!splashClass) splashClass = NSClassFromString(@"CSJSplashView");
    if (splashClass) {
        NLog(@"✓ 穿山甲开屏 hook 就绪");
        static SEL s_init1 = NULL, s_init2 = NULL;
        if (!s_init1) { s_init1 = @selector(initWithSlotID:frame:); s_init2 = @selector(initWithSlotID:adSize:); }
        SEL sel = NULL;
        Method m = class_getInstanceMethod(splashClass, s_init1);
        if (m) { sel = s_init1; } else { m = class_getInstanceMethod(splashClass, s_init2); sel = s_init2; }
        if (m && sel) {
            IMP orig = method_getImplementation(m);
            IMP newImp = imp_implementationWithBlock(^(id self, id slotID, CGRect frame) {
                ((void(*)(id,SEL,id,CGRect))orig)(self, sel, slotID, frame);
                if (g_blockSplashAd) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self removeFromSuperview];
                        NLog(@"🚫 穿山甲开屏已拦截");
                    });
                }
            });
            method_setImplementation(m, newImp);
            NLog(@"  hooked init method");
        }
    }

    // --- 插屏/激励视频 ---
    Class fullScreenClass = NSClassFromString(@"BUFullscreenVideoAd");
    Class rewardedClass = NSClassFromString(@"BUNativeExpressRewardedVideoAd");
    for (Class c in @[fullScreenClass, rewardedClass]) {
        if (c) {
            SEL loadAd = @selector(loadAdData);
            Method m = class_getInstanceMethod(c, loadAd);
            if (m) {
                IMP newImp = imp_implementationWithBlock(^(id self) {
                    if (g_blockBanner) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if ([self respondsToSelector:@selector(adDidClose)]) {
                                [(id)self performSelector:@selector(adDidClose)];
                            }
                        });
                        NLog(@"🚫 穿山甲视频广告已拦截");
                    }
                });
                method_setImplementation(m, newImp);
                NLog(@"  已 hook 视频广告");
            }
        }
    }

    // --- 横幅 ---
    Class bannerClass = NSClassFromString(@"BUNativeExpressBannerView");
    if (bannerClass) {
        SEL initBanner = @selector(initWithSlotID:rootViewController:adSize:);
        Method m = class_getInstanceMethod(bannerClass, initBanner);
        if (m) {
            IMP orig = method_getImplementation(m);
            IMP newImp = imp_implementationWithBlock(^(id self, id a, id b, CGSize s) {
                ((void(*)(id,SEL,id,id,CGSize))orig)(self, initBanner, a, b, s);
                if (g_blockBanner) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self setHidden:YES];
                        NLog(@"🚫 穿山甲横幅已拦截");
                    });
                }
            });
            method_setImplementation(m, newImp);
            NLog(@"✓ 穿山甲横幅 hook 就绪");
        }
    }
}

// ════════════════════════════════════════════════════════════
//  2. 腾讯广告 (GDTMobSDK)
//  开屏: GDTSplashAd → loadAd  / loadAdAndShow
// ════════════════════════════════════════════════════════════
static void hookGDT(void) {
    Class splashClass = NSClassFromString(@"GDTSplashAd");
    Class expressSplash = NSClassFromString(@"GDTNativeExpressSplashAd");
    for (Class c in @[splashClass, expressSplash]) {
        if (!c) continue;
        NLog(@"✓ GDT 开屏 hook 就绪");

        SEL loadSel = @selector(loadAd);
        Method m = class_getInstanceMethod(c, loadSel);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([self respondsToSelector:@selector(splashAdDidDismiss)]) {
                            [(id)self performSelector:@selector(splashAdDidDismiss)];
                        }
                        NLog(@"🚫 GDT 开屏已拦截");
                    });
                }
            });
            method_setImplementation(m, newImp);
        }
    }

    // 横幅
    Class banner = NSClassFromString(@"GDTUnifiedBannerView");
    if (banner) {
        SEL loadB = @selector(loadAd);
        Method m = class_getInstanceMethod(banner, loadB);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockBanner) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self setHidden:YES];
                        NLog(@"🚫 GDT 横幅已拦截");
                    });
                }
            });
            method_setImplementation(m, newImp);
            NLog(@"✓ GDT 横幅 hook 就绪");
        }
    }
}

// ════════════════════════════════════════════════════════════
//  3. 百度广告 (Baidu Mobads)
// ════════════════════════════════════════════════════════════
static void hookBaidu(void) {
    Class splash = NSClassFromString(@"BaiduMobAdSplash");
    if (splash) {
        NLog(@"✓ 百度开屏 hook 就绪");
        SEL show = @selector(showSplashAd);
        Method m = class_getInstanceMethod(splash, show);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    NLog(@"🚫 百度开屏已拦截");
                    return; // 不展示
                }
            });
            method_setImplementation(m, newImp);
        }
    }
}

// ════════════════════════════════════════════════════════════
//  4. 快手广告 (KuaiShou KSAdSDK)
// ════════════════════════════════════════════════════════════
static void hookKuaiShou(void) {
    Class splash = NSClassFromString(@"KSSplashAdView");
    if (splash) {
        NLog(@"✓ 快手开屏 hook 就绪");
        SEL load = @selector(loadAdData);
        Method m = class_getInstanceMethod(splash, load);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([self respondsToSelector:@selector(splashAdClosed)]) {
                            [(id)self performSelector:@selector(splashAdClosed)];
                        }
                        NLog(@"🚫 快手开屏已拦截");
                    });
                }
            });
            method_setImplementation(m, newImp);
        }
    }
}

// ════════════════════════════════════════════════════════════
//  5. Sigmob
// ════════════════════════════════════════════════════════════
static void hookSigmob(void) {
    Class splash = NSClassFromString(@"SigSplashAd");
    if (splash) {
        NLog(@"✓ Sigmob 开屏 hook 就绪");
        SEL load = @selector(loadAd);
        Method m = class_getInstanceMethod(splash, load);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) { NLog(@"🚫 Sigmob 开屏已拦截"); }
            });
            method_setImplementation(m, newImp);
        }
    }
}

// ════════════════════════════════════════════════════════════
//  6. Google AdMob
// ════════════════════════════════════════════════════════════
static void hookAdMob(void) {
    Class appOpen = NSClassFromString(@"GADAppOpenAd");
    if (appOpen) {
        NLog(@"✓ AdMob AppOpen hook 就绪");
        SEL load = @selector(loadWithAdUnitID:request:orientation:completionHandler:);
        Method m = class_getInstanceMethod(appOpen, load);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self, id uid, id req, int o, id cb) {
                if (g_blockSplashAd) {
                    NLog(@"🚫 AdMob AppOpen 已拦截 → 模拟加载失败");
                    void (^handler)(id, NSError*) = cb;
                    if (handler) handler(nil, [NSError errorWithDomain:@"com.noad" code:-1 userInfo:nil]);
                }
            });
            method_setImplementation(m, newImp);
        }
    }
    // 横幅
    Class banner = NSClassFromString(@"GADBannerView");
    if (banner) {
        SEL loadB = @selector(loadRequest:);
        Method m = class_getInstanceMethod(banner, loadB);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self, id req) {
                if (g_blockBanner) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self setHidden:YES];
                        NLog(@"🚫 AdMob 横幅已拦截");
                    });
                }
            });
            method_setImplementation(m, newImp);
            NLog(@"✓ AdMob 横幅 hook 就绪");
        }
    }
}

// ════════════════════════════════════════════════════════════
//  7. 任意 View 摇一摇兜底检测 — Hook CoreMotion
//  所有广告SDK的摇一摇最终都调 CMMotionManager
// ════════════════════════════════════════════════════════════
@interface CMMotionManager (NoAd)
- (void)noad_startAccelerometerUpdates;
- (void)noad_startAccelerometerUpdatesToQueue:(NSOperationQueue *)queue withHandler:(id)handler;
- (void)noad_startDeviceMotionUpdates;
- (void)noad_startDeviceMotionUpdatesToQueue:(NSOperationQueue *)queue withHandler:(id)handler;
@end
@implementation CMMotionManager (NoAd)
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        swizzle([CMMotionManager class],
                @selector(startAccelerometerUpdates),
                @selector(noad_startAccelerometerUpdates));
        swizzle([CMMotionManager class],
                @selector(startAccelerometerUpdatesToQueue:withHandler:),
                @selector(noad_startAccelerometerUpdatesToQueue:withHandler:));
        swizzle([CMMotionManager class],
                @selector(startDeviceMotionUpdates),
                @selector(noad_startDeviceMotionUpdates));
        swizzle([CMMotionManager class],
                @selector(startDeviceMotionUpdatesToQueue:withHandler:),
                @selector(noad_startDeviceMotionUpdatesToQueue:withHandler:));
        NLog(@"✓ CoreMotion 摇一摇 hook 就绪");
    });
}
- (void)noad_startAccelerometerUpdates {
    if (g_blockShakeAd) return; // 不启动，广告 SDK 收不到数据
    [self noad_startAccelerometerUpdates];
}
- (void)noad_startAccelerometerUpdatesToQueue:(NSOperationQueue *)queue
                                 withHandler:(id)handler {
    if (g_blockShakeAd) {
        NLog(@"🚫 摇一摇已拦截");
        return;
    }
    [self noad_startAccelerometerUpdatesToQueue:queue withHandler:handler];
}
- (void)noad_startDeviceMotionUpdates {
    if (g_blockShakeAd) return;
    [self noad_startDeviceMotionUpdates];
}
- (void)noad_startDeviceMotionUpdatesToQueue:(NSOperationQueue *)queue
                                 withHandler:(id)handler {
    if (g_blockShakeAd) {
        NLog(@"🚫 摇一摇已拦截");
        return;
    }
    [self noad_startDeviceMotionUpdatesToQueue:queue withHandler:handler];
}
@end

// ════════════════════════════════════════════════════════════
//  7. 微信 去广告 (WCAD / SnsAd / Moments / MiniGame / Article)
//  微信广告系统是自研的，不走 GDT SDK
// ════════════════════════════════════════════════════════════
static void hookWeChat(void) {
    // --- 开屏广告 ---
    Class wcSplash = NSClassFromString(@"WCTimeLineAdSplash");
    if (!wcSplash) wcSplash = NSClassFromString(@"WCAdSplashView");
    if (!wcSplash) wcSplash = NSClassFromString(@"WCAdvertiseSplashLogic");
    if (wcSplash) {
        NLog(@"✓ 微信开屏 hook 就绪");
        SEL show = @selector(show);
        if (!show) show = @selector(tryShowSplash);
        Method m = class_getInstanceMethod(wcSplash, show);
        if (!m) {
            // fallback: hook init to set skip flag
            SEL init = @selector(init);
            m = class_getInstanceMethod(wcSplash, init);
        }
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    NLog(@"🚫 微信开屏已拦截");
                    return nil;
                }
                return nil; // never actually create
            });
            method_setImplementation(m, newImp);
        }
    }

    // --- 公众号文章广告 (MPPageFastLoad / WKWebView ad) ---
    Class mpAd = NSClassFromString(@"MPFastLoadAdView");
    if (!mpAd) mpAd = NSClassFromString(@"MPPageFastLoadAdView");
    if (mpAd) {
        NLog(@"✓ 微信文章广告 hook 就绪");
        SEL init = @selector(initWithFrame:);
        Method m = class_getInstanceMethod(mpAd, init);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self, CGRect f) {
                if (g_blockBanner) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self setHidden:YES];
                        NLog(@"🚫 微信文章广告已拦截");
                    });
                }
                return self;
            });
            method_setImplementation(m, newImp);
        }
    }

    // --- 朋友圈广告 (SnsAd) ---
    Class snsAd = NSClassFromString(@"WCSnsAdFeedView");
    if (!snsAd) snsAd = NSClassFromString(@"SnsAdFeedView");
    if (!snsAd) snsAd = NSClassFromString(@"WCAdvertiseSnsAdView");
    if (snsAd) {
        NLog(@"✓ 微信朋友圈广告 hook 就绪");
        SEL layout = @selector(layoutSubviews);
        Method m = class_getInstanceMethod(snsAd, layout);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockBanner) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self setHidden:YES];
                        [self setAlpha:0];
                        CGRect f = [self frame];
                        f.size.height = 0;
                        [self setFrame:f];
                        NLog(@"🚫 微信朋友圈广告已拦截");
                    });
                }
            });
            method_setImplementation(m, newImp);
        }
    }

    // --- 小程序广告 (WAAppTask) ---
    Class miniGameAd = NSClassFromString(@"WAMiniGameAdView");
    if (!miniGameAd) miniGameAd = NSClassFromString(@"WAMiniProgramAdView");
    if (!miniGameAd) miniGameAd = NSClassFromString(@"WAJSEventHandler_showAd");
    if (miniGameAd) {
        NLog(@"✓ 微信小程序广告 hook 就绪");
        SEL show = @selector(show);
        Method m = class_getInstanceMethod(miniGameAd, show);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockBanner) {
                    NLog(@"🚫 微信小程序广告已拦截");
                    return;
                }
            });
            method_setImplementation(m, newImp);
        }
    }
}

// ════════════════════════════════════════════════════════════
//  8. QQ 去广告 (内部广告系统: QQAd / Splash / Banner)
// ════════════════════════════════════════════════════════════
static void hookQQ(void) {
    // --- QQ 开屏 ---
    Class qqSplash = NSClassFromString(@"QQSplashAdView");
    if (!qqSplash) qqSplash = NSClassFromString(@"SplashAdManager");
    if (!qqSplash) qqSplash = NSClassFromString(@"QQSplashViewController");
    if (qqSplash) {
        NLog(@"✓ QQ开屏 hook 就绪");
        SEL show = @selector(showSplash); // or launch sequence
        Method m = class_getInstanceMethod(qqSplash, show);
        if (!m) {
            SEL init = @selector(init);
            m = class_getInstanceMethod(qqSplash, init);
        }
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    NLog(@"🚫 QQ开屏已拦截 — 跳过广告页");
                    return nil;
                }
                return self;
            });
            method_setImplementation(m, newImp);
        }
    }

    // --- QQ 横幅/信息流 (QQDynamicAd) ---
    Class qqBanner = NSClassFromString(@"QQAdView");
    if (!qqBanner) qqBanner = NSClassFromString(@"QQDynamicBannerView");
    if (!qqBanner) qqBanner = NSClassFromString(@"TADBannerView");
    if (qqBanner) {
        NLog(@"✓ QQ横幅 hook 就绪");
        SEL load = @selector(loadAd);
        Method m = class_getInstanceMethod(qqBanner, load);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockBanner) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self setHidden:YES];
                        NLog(@"🚫 QQ横幅已拦截");
                    });
                }
            });
            method_setImplementation(m, newImp);
        }
    }

    // --- QQ看点 / QQ空间 广告流 ---
    Class qqFeed = NSClassFromString(@"QQFeedAdCell");
    if (!qqFeed) qqFeed = NSClassFromString(@"QZoneFeedAdView");
    if (qqFeed) {
        NLog(@"✓ QQ看点/空间广告 hook 就绪");
        SEL layout = @selector(layoutSubviews);
        Method m = class_getInstanceMethod(qqFeed, layout);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockBanner) {
                    [self setHidden:YES];
                    CGRect f = [self frame];
                    f.size.height = 0;
                    [self setFrame:f];
                }
            });
            method_setImplementation(m, newImp);
        }
    }
}

// ════════════════════════════════════════════════════════════
//  9. 抖音 去广告 (内部引擎: AWESplashAd / Feed Ads / Live Banner)
// ════════════════════════════════════════════════════════════
static void hookDouyin(void) {
    // --- 抖音开屏 ---
    Class dySplash = NSClassFromString(@"AWESplashAdViewController");
    if (!dySplash) dySplash = NSClassFromString(@"AWESplashViewController");
    if (dySplash) {
        NLog(@"✓ 抖音开屏 hook 就绪");
        SEL viewDidLoad = @selector(viewDidLoad);
        Method m = class_getInstanceMethod(dySplash, viewDidLoad);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    // Skip splash entirely — call completion immediately
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.01 * NSEC_PER_SEC),
                        dispatch_get_main_queue(), ^{
                            if ([self respondsToSelector:@selector(closeAction)]) {
                                [(id)self performSelector:@selector(closeAction)];
                            }
                            if ([self respondsToSelector:@selector(splashDidDismiss)]) {
                                [(id)self performSelector:@selector(splashDidDismiss)];
                            }
                            NLog(@"🚫 抖音开屏已拦截");
                        });
                }
            });
            method_setImplementation(m, newImp);
        }
    }

    // --- 抖音信息流广告 ---
    Class dyFeed = NSClassFromString(@"AWEFeedAdTableViewCell");
    if (!dyFeed) dyFeed = NSClassFromString(@"AWEFeedAdCell");
    if (dyFeed) {
        NLog(@"✓ 抖音信息流广告 hook 就绪");
        SEL layout = @selector(layoutSubviews);
        Method m = class_getInstanceMethod(dyFeed, layout);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockBanner) {
                    [self setHidden:YES];
                    CGRect f = [self frame];
                    f.size.height = 0;
                    [self setFrame:f];
                }
            });
            method_setImplementation(m, newImp);
        }
    }

    // --- 抖音直播 Banner ---
    Class dyLiveAd = NSClassFromString(@"AWELiveAdBannerView");
    if (dyLiveAd) {
        NLog(@"✓ 抖音直播广告 hook 就绪");
        SEL init = @selector(initWithFrame:);
        Method m = class_getInstanceMethod(dyLiveAd, init);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self, CGRect f) {
                if (g_blockBanner) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self setHidden:YES];
                        NLog(@"🚫 抖音直播广告已拦截");
                    });
                }
                return self;
            });
            method_setImplementation(m, newImp);
        }
    }
}

// ════════════════════════════════════════════════════════════
// 10. 快手 App 原生广告 (KSFeedAd / KSLiveAd)
//     (KSAdSDK 已在 hookKuaiShou 中覆盖)
// ════════════════════════════════════════════════════════════
static void hookKuaiShouApp(void) {
    // --- 快手开屏 (App 层) ---
    Class ksSplash = NSClassFromString(@"KSSplashViewController");
    if (!ksSplash) ksSplash = NSClassFromString(@"KSLaunchSplashViewController");
    if (ksSplash) {
        NLog(@"✓ 快手App开屏 hook 就绪");
        SEL viewDidLoad = @selector(viewDidLoad);
        Method m = class_getInstanceMethod(ksSplash, viewDidLoad);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.01 * NSEC_PER_SEC),
                        dispatch_get_main_queue(), ^{
                            if ([self respondsToSelector:@selector(dismissAction)]) {
                                [(id)self performSelector:@selector(dismissAction)];
                            }
                            NLog(@"🚫 快手开屏已拦截");
                        });
                }
            });
            method_setImplementation(m, newImp);
        }
    }

    // --- 快手信息流广告 ---
    Class ksFeedAd = NSClassFromString(@"KSFeedAdCell");
    if (!ksFeedAd) ksFeedAd = NSClassFromString(@"KSFeedAdVideoCell");
    if (ksFeedAd) {
        NLog(@"✓ 快手信息流广告 hook 就绪");
        SEL layout = @selector(layoutSubviews);
        Method m = class_getInstanceMethod(ksFeedAd, layout);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockBanner) {
                    [self setHidden:YES];
                    CGRect f = [self frame];
                    f.size.height = 0;
                    [self setFrame:f];
                }
            });
            method_setImplementation(m, newImp);
        }
    }
}

// ════════════════════════════════════════════════════════════
// 11. 其他主流 App 通用开屏 Hook
// ════════════════════════════════════════════════════════════
static void hookCommonApps(void) {
    // 淘宝 — 开屏广告
    Class tbSplash = NSClassFromString(@"TBSplashAdView");
    if (!tbSplash) tbSplash = NSClassFromString(@"TaoBaoSplashViewController");
    if (tbSplash) {
        NLog(@"✓ 淘宝开屏 hook 就绪");
        SEL viewDidLoad = @selector(viewDidLoad);
        Method m = class_getInstanceMethod(tbSplash, viewDidLoad);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.01 * NSEC_PER_SEC),
                        dispatch_get_main_queue(), ^{
                            [self dismissViewControllerAnimated:NO completion:nil];
                            NLog(@"🚫 淘宝开屏已拦截");
                        });
                }
            });
            method_setImplementation(m, newImp);
        }
    }

    // 微博 — 开屏广告
    Class wbSplash = NSClassFromString(@"WBSplashViewController");
    if (!wbSplash) wbSplash = NSClassFromString(@"WBSplashAdManager");
    if (wbSplash) {
        NLog(@"✓ 微博开屏 hook 就绪");
        SEL show = @selector(show);
        Method m = class_getInstanceMethod(wbSplash, show);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    NLog(@"🚫 微博开屏已拦截");
                    return;
                }
            });
            method_setImplementation(m, newImp);
        }
    }

    // 拼多多 — 开屏广告
    Class pddSplash = NSClassFromString(@"PDDSplashAdViewController");
    if (!pddSplash) pddSplash = NSClassFromString(@"PDDAdSplashView");
    if (pddSplash) {
        NLog(@"✓ 拼多多开屏 hook 就绪");
        SEL load = @selector(loadSplashAd);
        Method m = class_getInstanceMethod(pddSplash, load);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    NLog(@"🚫 拼多多开屏已拦截");
                    return;
                }
            });
            method_setImplementation(m, newImp);
        }
    }

    // 小红书 — 开屏广告
    Class xhsSplash = NSClassFromString(@"REDSplashViewController");
    if (!xhsSplash) xhsSplash = NSClassFromString(@"REDLaunchAdManager");
    if (xhsSplash) {
        NLog(@"✓ 小红书开屏 hook 就绪");
        SEL show = @selector(showSplashAd);
        Method m = class_getInstanceMethod(xhsSplash, show);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    NLog(@"🚫 小红书开屏已拦截");
                    return;
                }
            });
            method_setImplementation(m, newImp);
        }
    }

    // B站 — 开屏广告
    Class biliSplash = NSClassFromString(@"BiliSplashAdView");
    if (!biliSplash) biliSplash = NSClassFromString(@"BilibiliSplashAdManager");
    if (biliSplash) {
        NLog(@"✓ B站开屏 hook 就绪");
        SEL show = @selector(showAd);
        Method m = class_getInstanceMethod(biliSplash, show);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    NLog(@"🚫 B站开屏已拦截");
                    return;
                }
            });
            method_setImplementation(m, newImp);
        }
    }

    // 京东 — 开屏广告
    Class jdSplash = NSClassFromString(@"JDSplashAdView");
    if (!jdSplash) jdSplash = NSClassFromString(@"JDAdSplashViewController");
    if (jdSplash) {
        NLog(@"✓ 京东开屏 hook 就绪");
        SEL show = @selector(showAd);
        Method m = class_getInstanceMethod(jdSplash, show);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    NLog(@"🚫 京东开屏已拦截");
                    return;
                }
            });
            method_setImplementation(m, newImp);
        }
    }

    // 网易云音乐 — 开屏
    Class wySplash = NSClassFromString(@"NetEaseMusicSplashAdView");
    if (!wySplash) wySplash = NSClassFromString(@"NEMusicSplashViewController");
    if (wySplash) {
        NLog(@"✓ 网易云开屏 hook 就绪");
        SEL show = @selector(show);
        Method m = class_getInstanceMethod(wySplash, show);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    NLog(@"🚫 网易云开屏已拦截");
                    return;
                }
            });
            method_setImplementation(m, newImp);
        }
    }

    // 美团 — 开屏
    Class mtSplash = NSClassFromString(@"MeiTuanSplashAdView");
    if (!mtSplash) mtSplash = NSClassFromString(@"MTSplashViewController");
    if (mtSplash) {
        NLog(@"✓ 美团开屏 hook 就绪");
        SEL viewDidLoad = @selector(viewDidLoad);
        Method m = class_getInstanceMethod(mtSplash, viewDidLoad);
        if (m) {
            IMP newImp = imp_implementationWithBlock(^(id self) {
                if (g_blockSplashAd) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.01 * NSEC_PER_SEC),
                        dispatch_get_main_queue(), ^{
                            [self dismissViewControllerAnimated:NO completion:nil];
                            NLog(@"🚫 美团开屏已拦截");
                        });
                }
            });
            method_setImplementation(m, newImp);
        }
    }
}

// ════════════════════════════════════════════════════════════
//  主入口 — 遍历检测 + Hook
// ════════════════════════════════════════════════════════════
static void hookAdSDKs(void) {
    NLog(@"━━━ 开始检测广告SDK ━━━");

    // SDK 层钩子
    hookBytedance();   // 穿山甲 (抖音/头条系接入)
    hookGDT();         // 腾讯广告 (微信/QQ接入)
    hookBaidu();       // 百度广告
    hookKuaiShou();    // 快手广告 SDK
    hookSigmob();      // Sigmob
    hookAdMob();       // Google AdMob

    // App 层钩子 (自研广告引擎)
    hookWeChat();       // 微信朋友圈/文章/小程序
    hookQQ();           // QQ开屏/看点/空间
    hookDouyin();       // 抖音开屏/信息流/直播
    hookKuaiShouApp();  // 快手App原生

    // 主流大厂 App 开屏
    hookCommonApps();   // 淘宝/微博/拼多多/小红书/B站/京东/网易云/美团

    NLog(@"━━━ 检测完毕 ━━━");
    NLog(@"开屏广告: %@", g_blockSplashAd ? @"屏蔽" : @"放行");
    NLog(@"摇一摇: %@",   g_blockShakeAd  ? @"屏蔽" : @"放行");
    NLog(@"横幅/插屏: %@", g_blockBanner   ? @"屏蔽" : @"放行");
}

// ════════════════════════════════════════════════════════════
//  HookMotion.m / HookAdSDK.m 为可选扩展模块（拆包用）
//  如不需要拆包，直接删除这两个文件引用，所有代码已在上面
// ════════════════════════════════════════════════════════════

__attribute__((constructor))
static void noad_init(void) {
    // 入口标记 — 实际 hook 在 UIApplication 启动后执行
    NSLog(@"[NoAd] dylib loaded");
}
