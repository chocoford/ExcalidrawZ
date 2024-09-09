//
//  SwiftUIView.swift
//  ChocofordKit
//
//  Created by Dove Zachary on 2024/9/8.
//

import SwiftUI
import ChocofordUI

public struct AboutChocofordView: View {
    public init() {}
    
    public var body: some View {
        VStack {
            let height: CGFloat = 80
            HStack(spacing: 20) {
                if let image = avatar() {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: height - 10, height: height - 10)
                        .clipShape(Circle())
                }
                
                VStack(alignment: .leading) {
                    Text("Chocoford")
                        .font(.largeTitle)
                    Spacer()
                    HStack {
                        myLinks()
                    }
                }
                
                Spacer()
                
                Button {
                    
                } label: {
                    Text("Buy me a coffee")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .containerShape(Capsule())
            }
            .padding(.vertical, 10)
            .frame(height: height)
            
            Divider()
            
            Section {
                if #available(macOS 13.0, *) {
                    FlexStack {
                        myApps()
                    }
                } else {
                    
                }
            } header: {
                HStack {
                    Text("My Apps")
                    Spacer()
                }
                .font(.headline)
                .foregroundStyle(.secondary)
            }
        }
        
    }
    
    private func avatar() -> Image? {
        Image("selfie")
//#if canImport(AppKit)
//        if let nsImage = NSImage(contentsOfFile: Bundle.module.path(forResource: "selfie", ofType: "JPG")!) {
//            return Image(nsImage: nsImage)
//        }
//#elseif canImport(UIKit)
//        if let uiImage = UIImage(contentsOfFile: Bundle.module.path(forResource: "selfie", ofType: "JPG")) {
//            return Image(uiImage: uiImage)
//        }
//#endif
//        return nil
    }
    
    @MainActor @ViewBuilder
    private func myLinks() -> some View {
        // twitter
        fastLinkChip(url: URL(string: "https://x.com/Chocoford_")!) {
            HStack(spacing: 4) {
                TwitterLogo()
                    .scaledToFit()
                    .frame(height: 12)
                Text("Chocoford")
                    .font(.footnote)
            }
        }
        
        fastLinkChip(url: URL(string: "https://github.com/chocoford")!) {
            HStack(spacing: 4) {
                GithubLogo()
                    .scaledToFit()
                    .frame(height: 12)
                Text("Chocoford")
                    .font(.footnote)
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func myApps() -> some View {
        Button {
            
        } label: {
            Image("ExcalidrawZ")
                .resizable()
                .scaledToFit()
                .frame(height: 64)
        }
        .buttonStyle(.borderless)
    }
    
    
//    @MainActor @ViewBuilder
//    private func twitterLogo() -> some View {
    
    @MainActor @ViewBuilder
    private func fastLinkChip<Content: View>(
        url: URL,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        Link(destination: url) {
            content()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(.background)
                }
            
        }
    }
}

fileprivate struct TwitterLogo: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.879*width, y: 0.86667*height))
        path.addLine(to: CGPoint(x: 0.58583*width, y: 0.43927*height))
        path.addLine(to: CGPoint(x: 0.58633*width, y: 0.43967*height))
        path.addLine(to: CGPoint(x: 0.85067*width, y: 0.13333*height))
        path.addLine(to: CGPoint(x: 0.76233*width, y: 0.13333*height))
        path.addLine(to: CGPoint(x: 0.547*width, y: 0.38267*height))
        path.addLine(to: CGPoint(x: 0.376*width, y: 0.13333*height))
        path.addLine(to: CGPoint(x: 0.14433*width, y: 0.13333*height))
        path.addLine(to: CGPoint(x: 0.41803*width, y: 0.53237*height))
        path.addLine(to: CGPoint(x: 0.418*width, y: 0.53233*height))
        path.addLine(to: CGPoint(x: 0.12933*width, y: 0.86667*height))
        path.addLine(to: CGPoint(x: 0.21767*width, y: 0.86667*height))
        path.addLine(to: CGPoint(x: 0.45707*width, y: 0.58927*height))
        path.addLine(to: CGPoint(x: 0.64733*width, y: 0.86667*height))
        path.addLine(to: CGPoint(x: 0.879*width, y: 0.86667*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.341*width, y: 0.2*height))
        path.addLine(to: CGPoint(x: 0.75233*width, y: 0.8*height))
        path.addLine(to: CGPoint(x: 0.68233*width, y: 0.8*height))
        path.addLine(to: CGPoint(x: 0.27067*width, y: 0.2*height))
        path.addLine(to: CGPoint(x: 0.341*width, y: 0.2*height))
        path.closeSubpath()
        return path
    }
}

fileprivate struct GithubLogo: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.49851*width, y: 0))
        path.addCurve(to: CGPoint(x: 0, y: 0.51268*height), control1: CGPoint(x: 0.22285*width, y: 0), control2: CGPoint(x: 0, y: 0.22917*height))
        path.addCurve(to: CGPoint(x: 0.34087*width, y: 0.99903*height), control1: CGPoint(x: 0, y: 0.7393*height), control2: CGPoint(x: 0.14279*width, y: 0.93114*height))
        path.addCurve(to: CGPoint(x: 0.3747*width, y: 0.97443*height), control1: CGPoint(x: 0.36563*width, y: 1.00414*height), control2: CGPoint(x: 0.3747*width, y: 0.988*height))
        path.addCurve(to: CGPoint(x: 0.37389*width, y: 0.87935*height), control1: CGPoint(x: 0.3747*width, y: 0.96254*height), control2: CGPoint(x: 0.37389*width, y: 0.9218*height))
        path.addCurve(to: CGPoint(x: 0.20634*width, y: 0.81824*height), control1: CGPoint(x: 0.23521*width, y: 0.90992*height), control2: CGPoint(x: 0.20634*width, y: 0.81824*height))
        path.addCurve(to: CGPoint(x: 0.15103*width, y: 0.74355*height), control1: CGPoint(x: 0.18405*width, y: 0.75882*height), control2: CGPoint(x: 0.15103*width, y: 0.74355*height))
        path.addCurve(to: CGPoint(x: 0.15434*width, y: 0.71215*height), control1: CGPoint(x: 0.10564*width, y: 0.71215*height), control2: CGPoint(x: 0.15434*width, y: 0.71215*height))
        path.addCurve(to: CGPoint(x: 0.2311*width, y: 0.76477*height), control1: CGPoint(x: 0.20468*width, y: 0.71554*height), control2: CGPoint(x: 0.2311*width, y: 0.76477*height))
        path.addCurve(to: CGPoint(x: 0.37636*width, y: 0.80721*height), control1: CGPoint(x: 0.27566*width, y: 0.84285*height), control2: CGPoint(x: 0.34747*width, y: 0.82079*height))
        path.addCurve(to: CGPoint(x: 0.40772*width, y: 0.73846*height), control1: CGPoint(x: 0.38048*width, y: 0.7741*height), control2: CGPoint(x: 0.39369*width, y: 0.75119*height))
        path.addCurve(to: CGPoint(x: 0.18076*width, y: 0.48551*height), control1: CGPoint(x: 0.29712*width, y: 0.72657*height), control2: CGPoint(x: 0.18076*width, y: 0.68244*height))
        path.addCurve(to: CGPoint(x: 0.23192*width, y: 0.34801*height), control1: CGPoint(x: 0.18076*width, y: 0.42949*height), control2: CGPoint(x: 0.20055*width, y: 0.38366*height))
        path.addCurve(to: CGPoint(x: 0.23688*width, y: 0.2122*height), control1: CGPoint(x: 0.22697*width, y: 0.33528*height), control2: CGPoint(x: 0.20963*width, y: 0.28265*height))
        path.addCurve(to: CGPoint(x: 0.37388*width, y: 0.26482*height), control1: CGPoint(x: 0.23688*width, y: 0.2122*height), control2: CGPoint(x: 0.27897*width, y: 0.19861*height))
        path.addCurve(to: CGPoint(x: 0.62313*width, y: 0.26482*height), control1: CGPoint(x: 0.5406*width, y: 0.24784*height), control2: CGPoint(x: 0.58351*width, y: 0.25379*height))
        path.addCurve(to: CGPoint(x: 0.76014*width, y: 0.2122*height), control1: CGPoint(x: 0.71805*width, y: 0.19861*height), control2: CGPoint(x: 0.76014*width, y: 0.2122*height))
        path.addCurve(to: CGPoint(x: 0.76509*width, y: 0.34801*height), control1: CGPoint(x: 0.78739*width, y: 0.28265*height), control2: CGPoint(x: 0.77004*width, y: 0.33528*height))
        path.addCurve(to: CGPoint(x: 0.81627*width, y: 0.48551*height), control1: CGPoint(x: 0.79729*width, y: 0.38366*height), control2: CGPoint(x: 0.81627*width, y: 0.42949*height))
        path.addCurve(to: CGPoint(x: 0.58847*width, y: 0.73846*height), control1: CGPoint(x: 0.81627*width, y: 0.68244*height), control2: CGPoint(x: 0.6999*width, y: 0.72572*height))
        path.addCurve(to: CGPoint(x: 0.62231*width, y: 0.83352*height), control1: CGPoint(x: 0.60663*width, y: 0.75458*height), control2: CGPoint(x: 0.62231*width, y: 0.78514*height))
        path.addCurve(to: CGPoint(x: 0.62149*width, y: 0.97442*height), control1: CGPoint(x: 0.62231*width, y: 0.90227*height), control2: CGPoint(x: 0.62149*width, y: 0.95745*height))
        path.addCurve(to: CGPoint(x: 0.65533*width, y: 0.99904*height), control1: CGPoint(x: 0.62149*width, y: 0.988*height), control2: CGPoint(x: 0.63057*width, y: 1.00414*height))
        path.addCurve(to: CGPoint(x: 0.99619*width, y: 0.51268*height), control1: CGPoint(x: 0.85341*width, y: 0.93113*height), control2: CGPoint(x: 0.99619*width, y: 0.7393*height))
        path.addCurve(to: CGPoint(x: 0.49851*width, y: 0), control1: CGPoint(x: 0.99701*width, y: 0.22917*height), control2: CGPoint(x: 0.77335*width, y: 0))
        path.closeSubpath()
        return path
    }
}

#Preview {
    if #available(macOS 13.0, *) {
        Form {
            AboutChocofordView()
                .padding()
        }.formStyle(.grouped)
    }
}
