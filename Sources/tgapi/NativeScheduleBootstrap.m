#import <Foundation/Foundation.h>

extern void TGExtraInstallNativeScheduleHook(void);

__attribute__((constructor))
static void TGExtraNativeScheduleBootstrap(void) {
    TGExtraInstallNativeScheduleHook();
}
