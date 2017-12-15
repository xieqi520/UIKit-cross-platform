//
//  Window.swift
//  UIKit
//
//  Created by Chris on 19.06.17.
//  Copyright © 2017 flowkey. All rights reserved.
//

import SDL
import JNI

internal final class Window {
    private let rawPointer: UnsafeMutablePointer<GPU_Target>
    let size: CGSize
    let scale: CGFloat

    // There is an inconsistency between Mac and Android when setting SDL_WINDOW_FULLSCREEN
    // The easiest solution is just to work in 1:1 pixels
    init(size: CGSize, options: SDLWindowFlags) {
        SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)

        GPU_SetPreInitFlags(GPU_INIT_ENABLE_VSYNC)

        UIFont.loadSystemFonts() // should always happen on UIKit-SDL init

        var size = size
        if options.contains(SDL_WINDOW_FULLSCREEN), let displayMode = SDLDisplayMode.current {
            // Fix fullscreen resolution on Mac and make Android easier to reason about:
            GPU_SetPreInitFlags(GPU_GetPreInitFlags() | GPU_INIT_DISABLE_AUTO_VIRTUAL_RESOLUTION)
            size = CGSize(width: CGFloat(displayMode.w), height: CGFloat(displayMode.h))
        }

        guard let gpuTarget = GPU_Init(UInt16(size.width), UInt16(size.height), UInt32(GPU_DEFAULT_INIT_FLAGS) | options.rawValue) else {
            print(SDLError())
            fatalError("GPU_Init failed")
        }
        rawPointer = gpuTarget

        #if os(Android)
            scale = getAndroidDeviceScale()

            GPU_SetVirtualResolution(rawPointer, UInt16(size.width / scale), UInt16(size.height / scale))
            size.width /= scale
            size.height /= scale
        #else
            // Mac:
            scale = CGFloat(rawPointer.pointee.base_h) / CGFloat(rawPointer.pointee.h)
        #endif
        
        self.size = size
    }

    #if os(macOS)
    // SDL scales our touch events for us on Mac, which means we need a special case for it:
    func absolutePointInOwnCoordinates(x inputX: CGFloat, y inputY: CGFloat) -> CGPoint {
        return CGPoint(x: inputX, y: inputY)
    }
    #else
    // On all other platforms, we scale the touch events to the screen size manually:
    func absolutePointInOwnCoordinates(x inputX: CGFloat, y inputY: CGFloat) -> CGPoint {
        return CGPoint(x: inputX / scale, y: inputY / scale)
    }
    #endif

    /// clippingRect behaves like an offset
    func blit(_ texture: Texture, at destination: CGPoint, opacity: Float, clippingRect: CGRect?) {
        if opacity < 1 { GPU_SetRGBA(texture.rawPointer, 255, 255, 255, opacity.normalisedToUInt8()) }

        if let clippingRect = clippingRect {
            var clipGPU_Rect = GPU_Rect(clippingRect)
            GPU_Blit(
                texture.rawPointer,
                &clipGPU_Rect,
                rawPointer,
                Float(destination.x + clippingRect.origin.x),
                Float(destination.y + clippingRect.origin.y)
            )
        } else {
            GPU_Blit(texture.rawPointer, nil, rawPointer, Float(destination.x), Float(destination.y))
        }
    }

    func setShapeBlending(_ newValue: Bool) {
        GPU_SetShapeBlending(newValue)
    }

    func setShapeBlendMode(_ newValue: GPU_BlendPresetEnum) {
        GPU_SetShapeBlendMode(newValue)
    }

    func clear() {
        GPU_Clear(rawPointer)
    }

    func fill(_ rect: CGRect, with color: UIColor, cornerRadius: CGFloat) {
        if cornerRadius >= 1 {
            GPU_RectangleRoundFilled(rawPointer, GPU_Rect(rect), cornerRadius: Float(cornerRadius), color: color.sdlColor)
        } else {
            GPU_RectangleFilled(rawPointer, GPU_Rect(rect), color: color.sdlColor)
        }
    }

    func outline(_ rect: CGRect, lineColor: UIColor, lineThickness: CGFloat) {
        GPU_SetLineThickness(Float(lineThickness))
        GPU_Rectangle(rawPointer, GPU_Rect(rect), color: lineColor.sdlColor)
    }

    func outline(_ rect: CGRect, lineColor: UIColor, lineThickness: CGFloat, cornerRadius: CGFloat) {
        if cornerRadius > 1 {
            GPU_SetLineThickness(Float(lineThickness))
            GPU_RectangleRound(rawPointer, GPU_Rect(rect), cornerRadius: Float(cornerRadius), color: lineColor.sdlColor)
        } else {
            outline(rect, lineColor: lineColor, lineThickness: lineThickness)
        }
    }

    func flip() {
        GPU_Flip(rawPointer)
    }

    deinit {
        defer { GPU_Quit() }

        // get and destroy existing Window because only one SDL_Window can exist on Android at the same time
        guard let gpuContext = self.rawPointer.pointee.context else {
            assertionFailure("window gpuContext not found")
            return
        }

        let existingWindowID = gpuContext.pointee.windowID
        let existingWindow = SDL_GetWindowFromID(existingWindowID)
        SDL_DestroyWindow(existingWindow)
    }
}

extension SDLWindowFlags: OptionSet {}

#if os(Android)
    fileprivate func getAndroidDeviceScale() -> CGFloat {
        if
            let mainActivity = SDL_AndroidGetActivity(),
            let density: Double = try? jni.call("getDeviceDensity", on: mainActivity)
        {
            return CGFloat(density)
        } else {
            return 2.0 // assume retina
        }
    }
#endif
