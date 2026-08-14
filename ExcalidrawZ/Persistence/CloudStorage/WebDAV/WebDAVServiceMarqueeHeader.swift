//
//  WebDAVServiceMarqueeHeader.swift
//  ExcalidrawZ
//

import SwiftUI

struct WebDAVServiceMarqueeHeader: View {
    private let services = WebDAVService.allCases

    var body: some View {
        VStack(spacing: 12) {
            WebDAVServiceMarqueeRow(
                services: services,
                direction: .leading,
                duration: 28
            )

            WebDAVServiceMarqueeRow(
                services: staggeredServices,
                direction: .trailing,
                duration: 34
            )
        }
        .padding(.top, 66)
        .padding(.bottom, 18)
        .frame(height: 218)
        .background {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.22),
                            Color.accentColor.opacity(0.13),
                            Color.accentColor.opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.68),
                    .init(color: .black.opacity(0.86), location: 0.80),
                    .init(color: .black.opacity(0.48), location: 0.92),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.06),
                        .init(color: .black, location: 0.94),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var staggeredServices: [WebDAVService] {
        let splitIndex = services.index(
            services.startIndex,
            offsetBy: services.count / 2
        )
        return Array(services[splitIndex...]) + Array(services[..<splitIndex])
    }
}

private struct WebDAVServiceMarqueeRow: View {
    enum Direction {
        case leading
        case trailing
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let services: [WebDAVService]
    let direction: Direction
    let duration: TimeInterval

    private static let iconLength: CGFloat = 52
    private static let spacing: CGFloat = 16

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            GeometryReader { _ in
                HStack(spacing: 0) {
                    serviceSequence
                    serviceSequence
                }
                .fixedSize(horizontal: true, vertical: false)
                .compositingGroup()
                .offset(x: offset(at: timeline.date))
            }
        }
        .frame(height: 60)
    }

    private var serviceSequence: some View {
        HStack(spacing: Self.spacing) {
            ForEach(services, id: \.self) { service in
                Circle()
                    .fill(.background.opacity(0.82))
                    .frame(width: Self.iconLength, height: Self.iconLength)
                    .overlay {
                        Image(service.imageAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                    }
                    .overlay {
                        Circle()
                            .stroke(.secondary.opacity(0.12), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            }

            Color.clear
                .frame(width: 0, height: Self.iconLength)
        }
    }

    private var sequenceWidth: CGFloat {
        CGFloat(services.count) * (Self.iconLength + Self.spacing)
    }

    private func offset(at date: Date) -> CGFloat {
        guard !reduceMotion else {
            return direction == .leading ? 0 : -sequenceWidth
        }
        let elapsed = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: duration)
        let progress = CGFloat(elapsed / duration)
        switch direction {
            case .leading:
                return -sequenceWidth * progress
            case .trailing:
                return -sequenceWidth + sequenceWidth * progress
        }
    }
}
