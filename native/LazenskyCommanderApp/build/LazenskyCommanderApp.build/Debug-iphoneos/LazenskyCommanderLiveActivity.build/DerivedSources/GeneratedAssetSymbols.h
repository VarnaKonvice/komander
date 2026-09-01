#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "BrandCircularMark" asset catalog image resource.
static NSString * const ACImageNameBrandCircularMark AC_SWIFT_PRIVATE = @"BrandCircularMark";

/// The "BrandSmallGlyph" asset catalog image resource.
static NSString * const ACImageNameBrandSmallGlyph AC_SWIFT_PRIVATE = @"BrandSmallGlyph";

#undef AC_SWIFT_PRIVATE
