//
//  ColorPickerView.swift
//  Relational
//
//  Created by Chris Campbell on 6/8/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import Binding

enum ColorItem: Equatable { case
    Preset(Color),
    Custom,
    Other
}

func ==(a: ColorItem, b: ColorItem) -> Bool {
    switch (a, b) {
    case let (.Preset(acolor), .Preset(bcolor)):
        return acolor == bcolor
    case (.Custom, .Custom):
        return true
    case (.Other, .Other):
        return true
    default:
        return false
    }
}

class ColorPickerView: NSView {
    
    private let bindings = BindingSet()
    
    var color: BidiValueBinding<CommonValue<Color>>? {
        didSet {
            bindings.register("color", color, { [weak self] value in
                guard let weakSelf = self else { return }
                switch value {
                case .None:
                    // TODO: Clear opacity chooser
                    weakSelf.colorPopup.defaultItemContent = MenuItemContent(
                        object: ColorItem.Other,
                        title: ValueBinding.constant("Default"),
                        image: ValueBinding.constant(Image(unsetColorSwatchImage()))
                    )
                case .One(let color):
                    // TODO: Update the popup selection
                    // TODO: Update opacity chooser
                    break
                case .Multi:
                    // TODO: Clear opacity chooser
                    weakSelf.colorPopup.defaultItemContent = MenuItemContent(
                        object: ColorItem.Other,
                        title: ValueBinding.constant("Multiple"),
                        image: ValueBinding.constant(Image(multipleColorSwatchImage()))
                    )
                }
            })
        }
    }
    
    private let colorPopup: PopUpButton<ColorItem>
    private let opacityCombo: ComboBox<Double>
    
    init() {
        var popupItems: [MenuItem<ColorItem>] = []
        
        func addPreset(name: String, _ color: Color) {
            let colorItem = ColorItem.Preset(color)
            let content = MenuItemContent(
                object: colorItem,
                title: ValueBinding.constant(name),
                image: ValueBinding.constant(Image(colorSwatchImage(color, f: { _ in })))
            )
            let menuItem = MenuItem.Normal(content)
            popupItems.append(menuItem)
        }
        
        func addSeparator() {
            popupItems.append(MenuItem.Separator)
        }

        func addOther() {
            let content = MenuItemContent(object: ColorItem.Other, title: ValueBinding.constant("Other…"))
            let menuItem = MenuItem.Normal(content)
            popupItems.append(menuItem)
        }

        addPreset("Black", Color.black)
        addPreset("White", Color.white)
        addPreset("Red", Color.red)
        addPreset("Orange", Color.orange)
        addPreset("Yellow", Color.yellow)
        addPreset("Green", Color.green)
        addPreset("Blue", Color.blue)
        addPreset("Purple", Color.purple)
        addSeparator()
        addOther()

        colorPopup = PopUpButton(frame: NSZeroRect, pullsDown: false)
        colorPopup.items = ValueBinding.constant(popupItems)
        
        let opacityValues: [Double] = 0.stride(through: 100, by: 10).map{ $0 / 100.0 }
        opacityCombo = ComboBox(frame: NSZeroRect)
        opacityCombo.formatter = OpacityFormatter()
        opacityCombo.items = ValueBinding.constant(opacityValues)
        let opacityValueBinding = bidiValueBinding(1.0)
        opacityCombo.value = opacityValueBinding
        _ = opacityValueBinding.addChangeObserver({ _ in
            Swift.print("NEW OPACITY VALUE: \(opacityValueBinding.value)")
        })
        
        super.init(frame: NSZeroRect)
        
        let horizontalStack = NSStackView(views: [colorPopup, opacityCombo])
        horizontalStack.orientation = .Horizontal
        
        let verticalStack = NSStackView(views: [horizontalStack])
        verticalStack.orientation = .Vertical
        verticalStack.alignment = .Leading
        verticalStack.spacing = 2
        
//        if let label = label {
//            verticalStack.insertView(setupLabel(label), atIndex: 0, inGravity: .Leading)
//        }
        
        self.addSubview(verticalStack)
        self.addConstraints([
            NSLayoutConstraint(item: self, attribute: .Left, relatedBy: .Equal, toItem: verticalStack, attribute: .Left, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: self, attribute: .Right, relatedBy: .Equal, toItem: verticalStack, attribute: .Right, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: self, attribute: .Top, relatedBy: .Equal, toItem: verticalStack, attribute: .Top, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: self, attribute: .Bottom, relatedBy: .Equal, toItem: verticalStack, attribute: .Bottom, multiplier: 1, constant: 0),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Returns a swatch image for the default/unset color case.
private func unsetColorSwatchImage() -> NSImage {
    return colorSwatchImage(Color.white, f: { rect in
        let topRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.minY)
        
        let path = NSBezierPath()
        path.moveToPoint(topRight)
        path.lineToPoint(bottomLeft)
        NSColor.redColor().setStroke()
        path.stroke()
    })
}

/// Returns a swatch image for the multiple color case.
private func multipleColorSwatchImage() -> NSImage {
    return colorSwatchImage(Color.white, f: { rect in
        NSColor.redColor().setStroke()
        NSBezierPath.strokeLineFromPoint(NSMakePoint(rect.minX + 4, rect.midY), toPoint: NSMakePoint(rect.maxX - 4, rect.midY))
    })
}

/// Returns a color swatch image.
private func colorSwatchImage(color: Color, f: (NSRect) -> ()) -> NSImage {
    let size = NSMakeSize(20, 12)
    let rect = NSRect(origin: NSZeroPoint, size: size)
    let image = NSImage(size: size)
    image.lockFocusFlipped(false)
    drawSwatch(rect, color: color.nscolor)
    f(rect)
    NSColor.blackColor().setStroke()
    NSBezierPath.strokeRect(rect.insetBy(dx: 0.5, dy: 0.5))
    image.unlockFocus()
    return image
}

/// Draws a color swatch into the current graphics context.
private func drawSwatch(rect: NSRect, color: NSColor) {
    NSColor.blackColor().setFill()
    NSRectFill(rect)
    
    let path = NSBezierPath()
    path.moveToPoint(NSMakePoint(rect.minX, rect.minY))
    path.lineToPoint(NSMakePoint(rect.maxX, rect.minY))
    path.lineToPoint(NSMakePoint(rect.maxX, rect.maxY))
    path.closePath()
    NSColor.whiteColor().setFill()
    path.fill()
    
    color.setFill()
    NSRectFillUsingOperation(rect, .CompositeSourceOver)
}

private class OpacityFormatter: NSNumberFormatter {
    
    override init() {
        super.init()
        
        numberStyle = .PercentStyle
        minimum = 0.0
        maximum = 1.0
        maximumFractionDigits = 0
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func getObjectValue(obj: AutoreleasingUnsafeMutablePointer<AnyObject?>, forString string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>) -> Bool {
        // Include the '%' suffix if it wasn't already there, just to make the formatter happy;
        // this allows the user to go away from the combo box even if the user left off the '%' or
        // left the box empty
        var s = string
        // XXX: This is locale-sensitive
        if s.isEmpty {
            s = "100%"
        } else if !s.hasSuffix("%") {
            s = "\(string)%"
        }
        return super.getObjectValue(obj, forString: s, errorDescription: error)
    }
    
    override func isPartialStringValid(partialString: String, newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>) -> Bool {
        var s = partialString
        
        if s.isEmpty {
            return true
        }
        
        if s.hasSuffix("%") {
            s = s[s.startIndex..<s.endIndex.predecessor()]
        }
        
        if let intValue = Int(s) {
            if intValue >= 0 && intValue <= 100 {
                return true
            }
        }
        
        NSBeep()
        return false
    }
}
