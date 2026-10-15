#pragma once

#import "Fog.h"
#import "ShaderMaterial.h"
#import "ShadowMask.h"
#import "Particles.h"
#import "PostProcessing.h"

#ifdef __OBJC__
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface NSBundle (MetalSprocketsSceneGraphShaders)
+ (NSBundle *)metalSprocketsSceneGraphShadersBundle;
@end
NS_ASSUME_NONNULL_END
#endif
