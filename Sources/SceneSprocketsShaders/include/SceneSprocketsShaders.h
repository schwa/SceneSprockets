#pragma once

#import "BlinnPhong.h"
#import "Fog.h"
#import "ShaderMaterial.h"
#import "ShadowMask.h"
#import "SkyGradient.h"
#import "PostProcessing.h"

#ifdef __OBJC__
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface NSBundle (SceneSprocketsShaders)
+ (NSBundle *)sceneSprocketsShadersBundle;
@end
NS_ASSUME_NONNULL_END
#endif
