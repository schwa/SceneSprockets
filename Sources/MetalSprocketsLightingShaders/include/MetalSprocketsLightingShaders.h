#pragma once

#ifdef __OBJC__
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface NSBundle (MetalSprocketsLightingShaders)
+ (NSBundle *)metalSprocketsLightingShadersBundle;
@end
NS_ASSUME_NONNULL_END
#endif

#include "MetalSprocketsLightingTypes.h"
// Metal-only; empty when compiled for Swift.
#include "MetalSprocketsLightingSupport.h"
#include "MetalSprocketsLightingToneMapping.h"
#include "MetalSprocketsLighting.h"
