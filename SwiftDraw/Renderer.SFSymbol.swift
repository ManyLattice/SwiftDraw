//
//  Renderer.SFSymbol.swift
//  SwiftDraw
//
//  Created by Simon Whitty on 18/8/22.
//  Copyright 2022 Simon Whitty
//
//  Distributed under the permissive zlib license
//  Get the latest version from here:
//
//  https://github.com/swhitty/SwiftDraw
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//

import Foundation

public struct SFSymbolRenderer {
    
    private let options: DOM.Options
    private let insets: Insets
    private let insetsUltralight: Insets
    private let insetsBlack: Insets
    private let formatter: CoordinateFormatter
    
    public init(options: DOM.Options,
                insets: Insets,
                insetsUltralight: Insets,
                insetsBlack: Insets,
                precision: Int) {
        self.options = options
        self.insets = insets
        self.insetsUltralight = insetsUltralight
        self.insetsBlack = insetsBlack
        self.formatter = CoordinateFormatter(delimeter: .comma,
                                             precision: .capped(max: precision))
    }
    
    public func render(regular: URL, ultralight: URL?, black: URL?) throws -> String {
        let regular = try DOM.SVG.parse(fileURL: regular)
        let ultralight = try ultralight.map { try DOM.SVG.parse(fileURL: $0) }
        let black = try black.map { try DOM.SVG.parse(fileURL: $0) }
        return try render(default: regular, ultralight: ultralight, black: black)
    }
    
    public func render(regular: Data, ultralight: Data?, black: Data?) throws -> String {
        let regular = try DOM.SVG.parse(data: regular)
        let ultralight = try ultralight.map({ try DOM.SVG.parse(data: $0) })
        let black = try black.map({ try DOM.SVG.parse(data: $0) })
        return try render(default: regular, ultralight: ultralight, black: black)
    }
    
    func render(default image: DOM.SVG, ultralight: DOM.SVG?, black: DOM.SVG?) throws -> String {
        guard let pathsRegular = Self.getPaths(for: image) else {
            throw Error("No valid content found.")
        }
        var template = try SFSymbolTemplate.make()
        
        template.svg.styles = image.styles.map(makeSymbolStyleSheet)
        
        let boundsRegular = try makeBounds(svg: image, auto: Self.makeBounds(for: pathsRegular), for: .regular)
        template.regular.appendPaths(pathsRegular, from: boundsRegular)
        
        if let ultralight = ultralight,
           let paths = Self.getPaths(for: ultralight) {
            let bounds = try makeBounds(svg: ultralight, auto: Self.makeBounds(for: paths), for: .ultralight)
            template.ultralight.appendPaths(paths, from: bounds)
        } else {
            let bounds = try makeBounds(svg: image, auto: Self.makeBounds(for: pathsRegular), for: .ultralight)
            template.ultralight.appendPaths(pathsRegular, from: bounds)
        }
        
        if let black = black,
           let paths = Self.getPaths(for: black) {
            let bounds = try makeBounds(svg: black, auto: Self.makeBounds(for: paths), for: .black)
            template.black.appendPaths(paths, from: bounds)
        } else {
            let bounds = try makeBounds(svg: image, auto: Self.makeBounds(for: pathsRegular), for: .black)
            template.black.appendPaths(pathsRegular, from: bounds)
        }
        
        let element = try XML.Formatter.SVG(formatter: formatter).makeElement(from: template.svg)
        let formatter = XML.Formatter(spaces: 4)
        let result = formatter.encodeRootElement(element)
        return result
    }
    
    func makeSymbolStyleSheet(from stylesheet: DOM.StyleSheet) -> DOM.StyleSheet {
        var copy = stylesheet
        for selector in stylesheet.attributes.keys {
            switch selector {
            case .class(let name):
                if SFSymbolRenderer.containsAcceptedName(name) {
                    copy.attributes[selector] = stylesheet.attributes[selector]
                }
            case .id, .element:
                ()
            }
        }
        return copy
    }
    
    static func containsAcceptedName(_ string: String?) -> Bool {
        guard let string = string else { return false }
        return string.contains("hierarchical-") ||
        string.contains("monochrome-") ||
        string.contains("multicolor-") ||
        string.contains("SFSymbolsPreview")
    }
}

extension SFSymbolRenderer {
    
    public struct Insets: Equatable {
        public var top: Double?
        public var left: Double?
        public var bottom: Double?
        public var right: Double?
        
        public init(top: Double? = nil, left: Double? = nil, bottom: Double? = nil, right: Double? = nil) {
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
        }
        
        var isEmpty: Bool {
            top == nil && left == nil && bottom == nil && right == nil
        }
    }
    
    enum Variant: String {
        case regular
        case ultralight
        case black
    }
    
    func getInsets(for variant: Variant) -> Insets {
        switch variant {
        case .regular:
            return insets
        case .ultralight:
            return insetsUltralight
        case .black:
            return insetsBlack
        }
    }
    
    func makeBounds(svg: DOM.SVG, auto: LayerTree.Rect, for variant: Variant) throws -> LayerTree.Rect {
        let insets = getInsets(for: variant)
        let width = LayerTree.Float(svg.width)
        let height = LayerTree.Float(svg.height)
        let top = insets.top ?? Double(auto.minY)
        let left = insets.left ?? Double(auto.minX)
        let bottom = insets.bottom ?? Double(height - auto.maxY)
        let right = insets.right ?? Double(width - auto.maxX)
        
        Self.printInsets(top: top, left: left, bottom: bottom, right: right, variant: variant)
        guard !insets.isEmpty else {
            return auto
        }
        let bounds = LayerTree.Rect(
            x: LayerTree.Float(left),
            y: LayerTree.Float(top),
            width: width - LayerTree.Float(left + right),
            height: height - LayerTree.Float(top + bottom)
        )
        guard bounds.width > 0 && bounds.height > 0 else {
            throw Error("Invalid insets")
        }
        return bounds
    }
    
    static func getPaths(for svg: DOM.SVG) -> [SymbolPath]? {
        let layer = LayerTree.Builder(svg: svg).makeLayer()
        let paths = getSymbolPaths(for: layer)
        return paths.isEmpty ? nil : paths
    }
    
    struct SymbolPath {
        var `class`: String?
        var path: LayerTree.Path
    }
    
    static func getSymbolPaths(for layer: LayerTree.Layer,
                               ctm: LayerTree.Transform.Matrix = .identity) -> [SymbolPath] {
        
        let isSFSymbolLayer = containsAcceptedName(layer.class)
        guard isSFSymbolLayer || layer.opacity > 0 else { return [] }
        guard layer.clip.isEmpty else {
            print("Warning:", "clip-path unsupported in SF Symbols.", to: &.standardError)
            return []
        }
        guard layer.mask == nil else {
            print("Warning:", "mask unsupported in SF Symbols.", to: &.standardError)
            return []
        }
        
        let ctm = ctm.concatenated(layer.transform.toMatrix())
        var paths = [SymbolPath]()
        
        let symbolClass = isSFSymbolLayer ? layer.class : nil
        
        for c in layer.contents {
            switch c {
            case let .shape(shape, stroke, fill):
                
                if let fillPath = makeFillPath(for: shape, fill: fill, preserve: isSFSymbolLayer) {
                    if fill.rule == .evenodd {
                        paths.append(SymbolPath(class: symbolClass, path: fillPath.applying(matrix: ctm).makeNonZero()))
                    } else {
                        paths.append(SymbolPath(class: symbolClass, path: fillPath.applying(matrix: ctm)))
                    }
                } else if let strokePath = makeStrokePath(for: shape, stroke: stroke, preserve: isSFSymbolLayer) {
                    paths.append(SymbolPath(class: symbolClass, path: strokePath.applying(matrix: ctm)))
                }
                
            case let .text(text, point, attributes):
                if let path = makePath(for: text, at: point, with: attributes) {
                    paths.append(SymbolPath(class: symbolClass, path: path.applying(matrix: ctm)))
                }
            case .layer(let l):
                paths.append(contentsOf: getSymbolPaths(for: l, ctm: ctm))
            default:
                ()
            }
        }
        
        return paths
    }
    
    static func makeFillPath(for shape: LayerTree.Shape,
                             fill: LayerTree.FillAttributes,
                             preserve: Bool) -> LayerTree.Path? {
        if preserve || (fill.fill != .none && fill.opacity > 0) {
            return shape.path
        }
        return nil
    }
    
    static func makeStrokePath(for shape: LayerTree.Shape,
                               stroke: LayerTree.StrokeAttributes,
                               preserve: Bool) -> LayerTree.Path? {
        if preserve || (stroke.color != .none && stroke.width > 0) {
#if canImport(CoreGraphics)
            return expandOutlines(for: shape.path, stroke: stroke)
#else
            print("Warning:", "expanding stroke outlines requires macOS.", to: &.standardError)
            return nil
#endif
        }
        
        return nil
    }
    
    static func makePath(for text: String,
                         at point: LayerTree.Point,
                         with attributes: LayerTree.TextAttributes) -> LayerTree.Path? {
#if canImport(CoreGraphics)
        let cgPath = CGProvider().createPath(from: text, at: point, with: attributes)
        return cgPath?.makePath()
#else
        print("Warning:", "expanding text outlines requires macOS.", to: &.standardError)
        return nil
#endif
    }
    
    static func makeBounds(for paths: [SymbolPath]) -> LayerTree.Rect {
        var min = LayerTree.Point.maximum
        var max = LayerTree.Point.minimum
        for p in paths {
            let bounds = p.path.bounds
            min = min.minimum(combining: .init(bounds.minX, bounds.minY))
            max = max.maximum(combining: .init(bounds.maxX, bounds.maxY))
        }
        return LayerTree.Rect(
            x: min.x,
            y: min.y,
            width: max.x - min.x,
            height: max.y - min.y
        )
    }
    
    static func makeTransformation(from source: LayerTree.Rect,
                                   to destination: LayerTree.Rect) -> LayerTree.Transform.Matrix {
        let scale = min(destination.width / source.width, destination.height / source.height)
        let scaleMidX = source.midX * scale
        let scaleMidY = source.midY * scale
        let tx = destination.midX - scaleMidX
        let ty =  destination.midY - scaleMidY
        let t = LayerTree.Transform
            .translate(tx: tx, ty: ty)
        return LayerTree.Transform
            .scale(sx: scale, sy: scale)
            .toMatrix()
            .concatenated(t.toMatrix())
    }
    
    static func convertPaths(_ paths: [LayerTree.Path],
                             from source: LayerTree.Rect,
                             to destination: LayerTree.Rect) -> [DOM.Path] {
        let matrix = makeTransformation(from: source, to: destination)
        return paths.map { $0.applying(matrix: matrix) }
            .map(makeDOMPath)
    }
    
    static func makeDOMPath(for path: LayerTree.Path) -> DOM.Path {
        let dom = DOM.Path(x: 0, y: 0)
        dom.segments = path.segments.map {
            switch $0 {
            case let .move(to: p):
                return .move(x: p.x, y: p.y, space: .absolute)
            case let .line(to: p):
                return .line(x: p.x, y: p.y, space: .absolute)
            case let .cubic(to: p, control1: cp1, control2: cp2):
                return .cubic(x1: cp1.x, y1: cp1.y, x2: cp2.x, y2: cp2.y, x: p.x, y: p.y, space: .absolute)
            case .close:
                return .close
            }
        }
        return dom
    }
    
    static func printInsets(top: Double, left: Double, bottom: Double, right: Double, variant: Variant) {
        let formatter = NumberFormatter()
        formatter.locale = .init(identifier: "en_US")
        formatter.maximumFractionDigits = 4
        let top = formatter.string(from: top as NSNumber)!
        let left = formatter.string(from: left as NSNumber)!
        let bottom = formatter.string(from: bottom as NSNumber)!
        let right = formatter.string(from: right as NSNumber)!
        
        switch variant {
        case .regular:
            print("Alignment: --insets \(top),\(left),\(bottom),\(right)")
        case .ultralight:
            print("Alignment: --ultralightInsets \(top),\(left),\(bottom),\(right)")
        case .black:
            print("Alignment: --blackInsets \(top),\(left),\(bottom),\(right)")
        }
    }
    
    struct Error: LocalizedError {
        var errorDescription: String?
        
        init(_ message: String) {
            self.errorDescription = message
        }
    }
}

struct SFSymbolTemplate {
    
    let svg: DOM.SVG
    
    var ultralight: Variant
    var regular: Variant
    var black: Variant
    
    init(svg: DOM.SVG) throws {
        self.svg = svg
        self.ultralight = try Variant(svg: svg, kind: "Ultralight")
        self.regular = try Variant(svg: svg, kind: "Regular")
        self.black = try Variant(svg: svg, kind: "Black")
    }
    
    struct Variant {
        var left: Guide
        var contents: Contents
        var right: Guide
        
        init(svg: DOM.SVG, kind: String) throws {
            let guides = try svg.group(id: "Guides")
            let symbols = try svg.group(id: "Symbols")
            self.left = try Guide(guides.path(id: "left-margin-\(kind)-S"))
            self.contents = try Contents(symbols.group(id: "\(kind)-S"))
            self.right = try Guide(guides.path(id: "right-margin-\(kind)-S"))
        }
        
        var bounds: LayerTree.Rect {
            let minX = left.x
            let maxX = right.x
            
            let minY = left.y + 26
            
            return .init(x: minX, y: minY, width: maxX - minX, height: 70)
        }
    }
    
    struct Guide {
        private let path: DOM.Path
        
        init(_ path: DOM.Path) {
            self.path = path
        }
        
        var x: DOM.Float {
            get {
                guard case let .move(x, _, _) = path.segments[0] else {
                    fatalError()
                }
                return x
            }
            set {
                guard case let .move(_, y, space) = path.segments[0] else {
                    fatalError()
                }
                path.segments[0] = .move(x: newValue, y: y, space: space)
            }
        }
        
        var y: DOM.Float {
            get {
                guard case let .move(_, y, _) = path.segments[0] else {
                    fatalError()
                }
                return y
            }
            set {
                guard case let .move(x, _, space) = path.segments[0] else {
                    fatalError()
                }
                path.segments[0] = .move(x: x, y: newValue, space: space)
            }
        }
    }
    
    struct Contents {
        private let group: DOM.Group
        
        init(_ group: DOM.Group) {
            self.group = group
        }
        
        var paths: [DOM.Path] {
            get {
                group.childElements as! [DOM.Path]
            }
            set {
                group.childElements = newValue
            }
        }
    }
}

extension SFSymbolTemplate {
    
    static func parse(_ text: String) throws -> Self {
        let element = try XML.SAXParser.parse(data: text.data(using: .utf8)!)
        let parser = XMLParser(options: [], filename: "template.svg")
        let svg = try parser.parseSVG(element)
        return try SFSymbolTemplate(svg: svg)
    }
    
    static func make() throws -> Self {
        let svg = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <svg width="3300" height="2200" version="1.1"
            xmlns="http://www.w3.org/2000/svg"
            xmlns:xlink="http://www.w3.org/1999/xlink">
            <g id="Notes">
                <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0" />
                <path style="fill:none;stroke:black;opacity:1;stroke-width:0.5;" d="M263 292L3036 292" />
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;" transform="matrix(1 0 0 1 263 322)">Weight/Scale Variations</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 559.711 322)">Ultralight</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 856.422 322)">Thin</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 1153.13 322)">Light</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 1449.84 322)">Regular</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 1746.56 322)">Medium</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 2043.27 322)">Semibold</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 2339.98 322)">Bold</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 2636.69 322)">Heavy</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 2933.4 322)">Black</text>
                <path style="fill:none;stroke:black;opacity:1;stroke-width:0.5;" d="M263 1903L3036 1903" />
                <g transform="matrix(1 0 0 1 263 1933)">
                    <path d="M9.24805 0.830078Q10.8691 0.830078 12.2949 0.214844Q13.7207-0.400391 14.8096-1.49414Q15.8984-2.58789 16.5186-4.01367Q17.1387-5.43945 17.1387-7.05078Q17.1387-8.66211 16.5186-10.0879Q15.8984-11.5137 14.8047-12.6074Q13.7109-13.7012 12.2852-14.3164Q10.8594-14.9316 9.23828-14.9316Q7.62695-14.9316 6.20117-14.3164Q4.77539-13.7012 3.69141-12.6074Q2.60742-11.5137 1.9873-10.0879Q1.36719-8.66211 1.36719-7.05078Q1.36719-5.43945 1.9873-4.01367Q2.60742-2.58789 3.69629-1.49414Q4.78516-0.400391 6.21094 0.214844Q7.63672 0.830078 9.24805 0.830078ZM9.24805-0.654297Q7.91992-0.654297 6.7627-1.14746Q5.60547-1.64062 4.73145-2.51953Q3.85742-3.39844 3.36426-4.56055Q2.87109-5.72266 2.87109-7.05078Q2.87109-8.37891 3.35938-9.54102Q3.84766-10.7031 4.72168-11.582Q5.5957-12.4609 6.75293-12.9541Q7.91016-13.4473 9.23828-13.4473Q10.5762-13.4473 11.7334-12.9541Q12.8906-12.4609 13.7695-11.582Q14.6484-10.7031 15.1465-9.54102Q15.6445-8.37891 15.6445-7.05078Q15.6445-5.72266 15.1514-4.56055Q14.6582-3.39844 13.7842-2.51953Q12.9102-1.64062 11.748-1.14746Q10.5859-0.654297 9.24805-0.654297ZM5.83984-7.04102Q5.83984-6.71875 6.04492-6.51855Q6.25-6.31836 6.5918-6.31836L8.50586-6.31836L8.50586-4.39453Q8.50586-4.0625 8.70605-3.85742Q8.90625-3.65234 9.22852-3.65234Q9.56055-3.65234 9.76562-3.85742Q9.9707-4.0625 9.9707-4.39453L9.9707-6.31836L11.8945-6.31836Q12.2266-6.31836 12.4316-6.51855Q12.6367-6.71875 12.6367-7.04102Q12.6367-7.37305 12.4316-7.57812Q12.2266-7.7832 11.8945-7.7832L9.9707-7.7832L9.9707-9.69727Q9.9707-10.0391 9.76562-10.2441Q9.56055-10.4492 9.22852-10.4492Q8.90625-10.4492 8.70605-10.2441Q8.50586-10.0391 8.50586-9.69727L8.50586-7.7832L6.5918-7.7832Q6.25-7.7832 6.04492-7.57812Q5.83984-7.37305 5.83984-7.04102Z" />
                </g>
                <g transform="matrix(1 0 0 1 281.867 1933)">
                    <path d="M11.709 2.91016Q13.75 2.91016 15.5518 2.12891Q17.3535 1.34766 18.7305-0.0292969Q20.1074-1.40625 20.8887-3.20801Q21.6699-5.00977 21.6699-7.05078Q21.6699-9.0918 20.8887-10.8936Q20.1074-12.6953 18.7305-14.0723Q17.3535-15.4492 15.5469-16.2305Q13.7402-17.0117 11.6992-17.0117Q9.6582-17.0117 7.85645-16.2305Q6.05469-15.4492 4.68262-14.0723Q3.31055-12.6953 2.5293-10.8936Q1.74805-9.0918 1.74805-7.05078Q1.74805-5.00977 2.5293-3.20801Q3.31055-1.40625 4.6875-0.0292969Q6.06445 1.34766 7.86621 2.12891Q9.66797 2.91016 11.709 2.91016ZM11.709 1.25Q9.98047 1.25 8.47656 0.605469Q6.97266-0.0390625 5.83496-1.17676Q4.69727-2.31445 4.05762-3.81836Q3.41797-5.32227 3.41797-7.05078Q3.41797-8.7793 4.05762-10.2832Q4.69727-11.7871 5.83008-12.9297Q6.96289-14.0723 8.4668-14.7119Q9.9707-15.3516 11.6992-15.3516Q13.4277-15.3516 14.9316-14.7119Q16.4355-14.0723 17.5781-12.9297Q18.7207-11.7871 19.3652-10.2832Q20.0098-8.7793 20.0098-7.05078Q20.0098-5.32227 19.3701-3.81836Q18.7305-2.31445 17.5928-1.17676Q16.4551-0.0390625 14.9463 0.605469Q13.4375 1.25 11.709 1.25ZM7.39258-7.04102Q7.39258-6.68945 7.62695-6.46484Q7.86133-6.24023 8.23242-6.24023L10.8789-6.24023L10.8789-3.57422Q10.8789-3.21289 11.1035-2.9834Q11.3281-2.75391 11.6797-2.75391Q12.0508-2.75391 12.2852-2.9834Q12.5195-3.21289 12.5195-3.57422L12.5195-6.24023L15.1758-6.24023Q15.5371-6.24023 15.7715-6.46484Q16.0059-6.68945 16.0059-7.04102Q16.0059-7.41211 15.7715-7.6416Q15.5371-7.87109 15.1758-7.87109L12.5195-7.87109L12.5195-10.5176Q12.5195-10.8984 12.2852-11.1279Q12.0508-11.3574 11.6797-11.3574Q11.3281-11.3574 11.1035-11.1279Q10.8789-10.8984 10.8789-10.5176L10.8789-7.87109L8.23242-7.87109Q7.85156-7.87109 7.62207-7.6416Q7.39258-7.41211 7.39258-7.04102Z" />
                </g>
                <g transform="matrix(1 0 0 1 305.646 1933)">
                    <path d="M14.9707 5.66406Q17.0605 5.66406 18.96 5.01465Q20.8594 4.36523 22.4512 3.19336Q24.043 2.02148 25.2197 0.429688Q26.3965-1.16211 27.0459-3.06641Q27.6953-4.9707 27.6953-7.05078Q27.6953-9.14062 27.0459-11.04Q26.3965-12.9395 25.2197-14.5312Q24.043-16.123 22.4512-17.2998Q20.8594-18.4766 18.9551-19.126Q17.0508-19.7754 14.9609-19.7754Q12.8711-19.7754 10.9717-19.126Q9.07227-18.4766 7.48535-17.2998Q5.89844-16.123 4.72168-14.5312Q3.54492-12.9395 2.90039-11.04Q2.25586-9.14062 2.25586-7.05078Q2.25586-4.9707 2.90527-3.06641Q3.55469-1.16211 4.72656 0.429688Q5.89844 2.02148 7.49023 3.19336Q9.08203 4.36523 10.9814 5.01465Q12.8809 5.66406 14.9707 5.66406ZM14.9707 3.84766Q13.1641 3.84766 11.5283 3.2959Q9.89258 2.74414 8.53516 1.74805Q7.17773 0.751953 6.17676-0.610352Q5.17578-1.97266 4.62891-3.6084Q4.08203-5.24414 4.08203-7.05078Q4.08203-8.86719 4.62891-10.5029Q5.17578-12.1387 6.17188-13.501Q7.16797-14.8633 8.52539-15.8594Q9.88281-16.8555 11.5186-17.4023Q13.1543-17.9492 14.9609-17.9492Q16.7773-17.9492 18.4131-17.4023Q20.0488-16.8555 21.4111-15.8594Q22.7734-14.8633 23.7695-13.501Q24.7656-12.1387 25.3174-10.5029Q25.8691-8.86719 25.8691-7.05078Q25.8789-5.24414 25.332-3.6084Q24.7852-1.97266 23.7842-0.610352Q22.7832 0.751953 21.4209 1.74805Q20.0586 2.74414 18.4229 3.2959Q16.7871 3.84766 14.9707 3.84766ZM9.45312-7.04102Q9.45312-6.66016 9.71191-6.41113Q9.9707-6.16211 10.3711-6.16211L14.0625-6.16211L14.0625-2.46094Q14.0625-2.06055 14.3115-1.80664Q14.5605-1.55273 14.9414-1.55273Q15.3516-1.55273 15.6055-1.80664Q15.8594-2.06055 15.8594-2.46094L15.8594-6.16211L19.5605-6.16211Q19.9609-6.16211 20.2148-6.41113Q20.4688-6.66016 20.4688-7.04102Q20.4688-7.45117 20.2148-7.70508Q19.9609-7.95898 19.5605-7.95898L15.8594-7.95898L15.8594-11.6504Q15.8594-12.0605 15.6055-12.3145Q15.3516-12.5684 14.9414-12.5684Q14.5605-12.5684 14.3115-12.3096Q14.0625-12.0508 14.0625-11.6504L14.0625-7.95898L10.3711-7.95898Q9.96094-7.95898 9.70703-7.70508Q9.45312-7.45117 9.45312-7.04102Z" />
                </g>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;" transform="matrix(1 0 0 1 263 1953)">Design Variations</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 1971)">Symbols are supported in up to nine weights and three scales.</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 1989)">For optimal layout with text and other symbols, vertically align</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 2007)">symbols with the adjacent text.</text>
                <path style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" d="M776 1919L776 1933" />
                <g transform="matrix(1 0 0 1 776 1933)">
                    <path d="M3.31055 0.15625Q3.70117 0.15625 3.91602-0.00976562Q4.13086-0.175781 4.26758-0.585938L5.52734-4.0332L11.2891-4.0332L12.5488-0.585938Q12.6855-0.175781 12.9004-0.00976562Q13.1152 0.15625 13.4961 0.15625Q13.8867 0.15625 14.1162-0.0585938Q14.3457-0.273438 14.3457-0.644531Q14.3457-0.869141 14.2383-1.17188L9.6582-13.3691Q9.48242-13.8184 9.17969-14.043Q8.87695-14.2676 8.4082-14.2676Q7.5-14.2676 7.17773-13.3789L2.59766-1.16211Q2.49023-0.859375 2.49023-0.634766Q2.49023-0.263672 2.70996-0.0537109Q2.92969 0.15625 3.31055 0.15625ZM6.00586-5.51758L8.37891-12.0898L8.42773-12.0898L10.8008-5.51758Z" />
                </g>
                <path style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" d="M793.197 1919L793.197 1933" />
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;" transform="matrix(1 0 0 1 776 1953)">Margins</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 776 1971)">Leading and trailing margins on the left and right side of each symbol</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 776 1989)">can be adjusted by modifying the x-location of the margin guidelines.</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 776 2007)">Modifications are automatically applied proportionally to all</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 776 2025)">scales and weights.</text>
                <g transform="matrix(1 0 0 1 1289 1933)">
                    <path d="M2.8418 1.86523L4.54102 3.57422Q5.18555 4.22852 5.90332 4.17969Q6.62109 4.13086 7.31445 3.35938L18.0078-8.42773L17.041-9.4043L6.42578 2.27539Q6.16211 2.57812 5.89355 2.61719Q5.625 2.65625 5.27344 2.30469L4.10156 1.14258Q3.75 0.791016 3.79395 0.522461Q3.83789 0.253906 4.14062-0.0195312L15.6152-10.8203L14.6387-11.7871L3.04688-0.898438Q2.30469-0.214844 2.25098 0.498047Q2.19727 1.21094 2.8418 1.86523ZM9.25781-16.3281Q8.94531-16.0254 8.90625-15.6348Q8.86719-15.2441 9.04297-14.9512Q9.21875-14.6777 9.55566-14.541Q9.89258-14.4043 10.3809-14.5215Q11.4746-14.7754 12.5977-14.7314Q13.7207-14.6875 14.7949-13.9844L14.209-12.5293Q13.9551-11.9043 14.0674-11.4404Q14.1797-10.9766 14.5801-10.5664L16.875-8.25195Q17.2363-7.88086 17.5781-7.82227Q17.9199-7.76367 18.3398-7.8418L19.4043-8.03711L20.0684-7.36328L20.0293-6.80664Q20-6.43555 20.1221-6.12305Q20.2441-5.81055 20.6055-5.44922L21.3672-4.70703Q21.7285-4.3457 22.1533-4.33105Q22.5781-4.31641 22.9297-4.66797L25.8398-7.58789Q26.1914-7.93945 26.1816-8.35449Q26.1719-8.76953 25.8105-9.13086L25.0391-9.89258Q24.6875-10.2539 24.3799-10.3857Q24.0723-10.5176 23.7109-10.4883L23.1348-10.4395L22.4902-11.0742L22.7344-12.1973Q22.832-12.6172 22.6953-12.9834Q22.5586-13.3496 22.1191-13.7891L19.9219-15.9766Q18.6719-17.2168 17.2607-17.8369Q15.8496-18.457 14.4189-18.4814Q12.9883-18.5059 11.665-17.959Q10.3418-17.4121 9.25781-16.3281ZM10.752-15.957Q11.6602-16.6211 12.7002-16.9043Q13.7402-17.1875 14.8047-17.085Q15.8691-16.9824 16.8701-16.5137Q17.8711-16.0449 18.7012-15.2051L21.1328-12.793Q21.3086-12.6172 21.3525-12.4512Q21.3965-12.2852 21.3379-12.0312L21.0156-10.5469L22.5195-9.0625L23.5059-9.12109Q23.6914-9.13086 23.7891-9.09668Q23.8867-9.0625 24.0332-8.91602L24.6094-8.33984L22.168-5.89844L21.5918-6.47461Q21.4453-6.62109 21.4062-6.71875Q21.3672-6.81641 21.377-7.01172L21.4453-7.98828L19.9512-9.47266L18.4277-9.21875Q18.1836-9.16992 18.042-9.2041Q17.9004-9.23828 17.7148-9.41406L15.7129-11.416Q15.5176-11.5918 15.4932-11.7529Q15.4688-11.9141 15.5859-12.1875L16.4648-14.2773Q15.293-15.3711 13.8281-15.791Q12.3633-16.2109 10.8398-15.7617Q10.7227-15.7324 10.6885-15.8057Q10.6543-15.8789 10.752-15.957Z" />
                </g>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;" transform="matrix(1 0 0 1 1289 1953)">Exporting</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 1289 1971)">Symbols should be outlined when exporting to ensure the</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 1289 1989)">design is preserved when submitting to Xcode.</text>
                <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1933)">Template v.3.0</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1951)">Requires Xcode 13 or greater</text>
                <text id="descriptive-name" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1969)">Generated from custom.pencil.circle</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1987)">Typeset at 100 points</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 726)">Small</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 1156)">Medium</text>
                <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 1586)">Large</text>
            </g>

            <g id="Guides">
                <g id="H-reference" style="fill:#27AAE1;stroke:none;" transform="matrix(1 0 0 1 339 696)">
                    <path d="M0.976562 0L3.66211 0L29.3457-67.1387L30.0293-67.1387L30.0293-70.459L28.125-70.459ZM11.6699-24.4629L46.9727-24.4629L46.2402-26.709L12.4512-26.709ZM55.127 0L57.7637 0L30.6152-70.459L29.4434-70.459L29.4434-67.1387Z" />
                </g>
                <path id="Baseline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" d="M263 696 L3036 696" />
                <path id="Capline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" d="M263 625.541 L3036 625.541" />
                <g id="H-reference" style="fill:#27AAE1;stroke:none;" transform="matrix(1 0 0 1 339 1126)">
                    <path d="M0.976562 0L3.66211 0L29.3457-67.1387L30.0293-67.1387L30.0293-70.459L28.125-70.459ZM11.6699-24.4629L46.9727-24.4629L46.2402-26.709L12.4512-26.709ZM55.127 0L57.7637 0L30.6152-70.459L29.4434-70.459L29.4434-67.1387Z" />
                </g>
                <path id="Baseline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" d="M263 1126 L3036 1126" />
                <path id="Capline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" d="M263 1055.54 L3036 1055.54" />
                <g id="H-reference" style="fill:#27AAE1;stroke:none;" transform="matrix(1 0 0 1 339 1556)">
                    <path d="M0.976562 0L3.66211 0L29.3457-67.1387L30.0293-67.1387L30.0293-70.459L28.125-70.459ZM11.6699-24.4629L46.9727-24.4629L46.2402-26.709L12.4512-26.709ZM55.127 0L57.7637 0L30.6152-70.459L29.4434-70.459L29.4434-67.1387Z" />
                </g>
                <path id="Baseline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" d="M263 1556 L3036 1556" />
                <path id="Capline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" d="M263 1485.54 L3036 1485.54" />
                <path id="left-margin-Ultralight-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" d="M515.394 600.784 L515.394 720.121" />
                <path id="right-margin-Ultralight-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" d="M604.028 600.784 L604.028 720.121" />
                <path id="left-margin-Regular-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" d="M1403.33 600.784 L1403.33 720.121" />
                <path id="right-margin-Regular-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" d="M1496.36 600.784 L1496.36 720.121" />
                <path id="left-margin-Black-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" d="M2884.32 600.784 L2884.32 720.121" />
                <path id="right-margin-Black-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" d="M2982.48 600.784 L2982.48 720.121" />
            </g>


            <g id="Symbols">
                <g id="Ultralight-S">
                    <!-- Insert Contents -->
                </g>
                <g id="Regular-S">
                    <!-- Insert Contents -->
                </g>
                <g id="Black-S">
                    <!-- Insert Contents -->
                </g>
            </g>
        </svg>
        """
        return try .parse(svg)
    }
}

private extension ContainerElement {
    
    func group(id: String) throws -> DOM.Group {
        try child(id: id, of: DOM.Group.self)
    }
    
    func path(id: String) throws -> DOM.Path {
        try child(id: id, of: DOM.Path.self)
    }
    
    private func child<T>(id: String, of type: T.Type) throws -> T {
        for e in childElements {
            if e.id == id, let match = e as? T {
                return match
            }
        }
        throw ContainerError.missingElement(String(describing: T.self))
    }
}

private extension SFSymbolTemplate.Variant {
    
    mutating func appendPaths(_ paths: [SFSymbolRenderer.SymbolPath], from source: LayerTree.Rect) {
        let matrix = SFSymbolRenderer.makeTransformation(from: source, to: bounds)
        contents.paths = paths
            .map {
                let transformed = $0.path.applying(matrix: matrix)
                let dom = SFSymbolRenderer.makeDOMPath(for: transformed)
                dom.class = $0.class
                return dom
            }
        
        let midX = bounds.midX
        let newWidth = ((source.width * matrix.a) / 2) + 10
        
        let midY = bounds.midY
        let newHeight = ((source.height * matrix.a) / 2) + 10
        
        left.x = min(left.x, midX - newWidth)
        left.y = min(left.y, midY - newHeight)
        
        right.x = max(right.x, midX + newWidth)
        right.y = left.y
    }
}

private enum ContainerError: Error {
    case missingElement(String)
}

private extension DOM.Path {
    var x: DOM.Float {
        get {
            guard case let .move(x, _, _) = segments[0] else {
                fatalError()
            }
            return x
        }
        set {
            guard case let .move(_, y, space) = segments[0] else {
                fatalError()
            }
            segments[0] = .move(x: newValue, y: y, space: space)
        }
    }
}
