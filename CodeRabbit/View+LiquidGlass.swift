//
//  View+LiquidGlass.swift
//  CodeRabbit
//

import SwiftUI

extension View {
    @ViewBuilder
    func liquidGlassCard(cornerRadius: CGFloat, borderColor: Color, lineWidth: CGFloat = 1) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: lineWidth)
                )
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: lineWidth)
                )
        }
    }

    @ViewBuilder
    func liquidGlassField(cornerRadius: CGFloat, borderColor: Color, lineWidth: CGFloat = 1) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: lineWidth)
                )
        } else {
            background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: lineWidth)
                )
        }
    }
}
