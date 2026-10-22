#pragma once

#import "BlinnPhong.h"
#import "Fog.h"
#import "ShaderMaterial.h"
#import "ShadowMask.h"
#import "PostProcessing.h"

#ifdef __OBJC__
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface NSBundle (SceneSprocketShaders)
+ (NSBundle *)sceneSprocketShadersBundle;
@end
NS_ASSUME_NONNULL_END
#endif
