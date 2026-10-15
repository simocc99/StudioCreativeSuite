import Foundation
import PDFKit
import StudioCore
import UIKit

/// Structural PDF operations on top of PDFKit. These change the page tree (order, presence,
/// rotation); they do not edit the drawing operators inside a page's content stream.
public enum PDFOperations {
    public static func open(_ url: URL) throws -> PDFDocument {
        guard let d = PDFDocument(url: url) else { throw StudioError.unsupportedFile("\(url.lastPathComponent): PDF non leggibile") }
        if d.isLocked { throw StudioError.notAvailable("PDF protetto da password") }
        return d
    }

    /// Appends all pages of `other` to `doc`.
    public static func merge(_ doc: PDFDocument, with other: PDFDocument) {
        for i in 0 ..< other.pageCount {
            if let p = other.page(at: i)?.copy() as? PDFPage { doc.insert(p, at: doc.pageCount) }
        }
    }

    public static func movePage(_ doc: PDFDocument, from: Int, to: Int) {
        guard from != to, let p = doc.page(at: from) else { return }
        doc.removePage(at: from)
        doc.insert(p, at: min(max(0, to), doc.pageCount))
    }

    public static func rotate(_ doc: PDFDocument, page i: Int, by degrees: Int) {
        guard let p = doc.page(at: i) else { return }
        p.rotation = (p.rotation + degrees + 360) % 360
    }

    public static func delete(_ doc: PDFDocument, page i: Int) {
        guard doc.pageCount > 1 else { return }
        doc.removePage(at: i)
    }

    public static func insertBlankPage(_ doc: PDFDocument, at i: Int) {
        let size = doc.page(at: max(0, i - 1))?.bounds(for: .mediaBox).size ?? CGSize(width: 595, height: 842)
        let data = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { $0.beginPage() }
        if let blank = PDFDocument(data: data)?.page(at: 0) { doc.insert(blank, at: min(i, doc.pageCount)) }
    }

    /// Full-text search; returns selections (one per hit).
    public static func search(_ doc: PDFDocument, _ text: String) -> [PDFSelection] {
        guard !text.isEmpty else { return [] }
        return doc.findString(text, withOptions: [.caseInsensitive, .diacriticInsensitive])
    }

    /// Adds highlight annotations over a selection (annotation: the page content is unchanged).
    public static func highlight(_ sel: PDFSelection, color: UIColor = .systemYellow) {
        for line in sel.selectionsByLine() {
            for page in line.pages {
                let b = line.bounds(for: page)
                let a = PDFAnnotation(bounds: b, forType: .highlight, withProperties: nil)
                a.color = color.withAlphaComponent(0.45)
                page.addAnnotation(a)
            }
        }
    }

    public static func addNote(_ page: PDFPage, at p: CGPoint, text: String) {
        let a = PDFAnnotation(bounds: CGRect(x: p.x, y: p.y, width: 24, height: 24), forType: .text, withProperties: nil)
        a.contents = text
        a.color = .systemYellow
        page.addAnnotation(a)
    }

    /// Ink annotation from a stroke in page coordinates.
    public static func addInk(_ page: PDFPage, points: [CGPoint], color: UIColor, width: CGFloat) {
        guard points.count > 1 else { return }
        let path = UIBezierPath()
        path.move(to: points[0])
        for p in points.dropFirst() { path.addLine(to: p) }
        let bounds = path.bounds.insetBy(dx: -width, dy: -width)
        // ink paths are relative to the annotation bounds
        path.apply(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        let a = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        let border = PDFBorder()
        border.lineWidth = width
        a.border = border
        a.color = color
        a.add(path)
        page.addAnnotation(a)
    }

    public static func annotationCount(_ doc: PDFDocument) -> Int {
        (0 ..< doc.pageCount).reduce(0) { $0 + (doc.page(at: $1)?.annotations.count ?? 0) }
    }
}
