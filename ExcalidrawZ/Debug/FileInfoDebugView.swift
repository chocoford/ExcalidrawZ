//
//  FileInfoDebugView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/14/25.
//

import SwiftUI

#if DEBUG
@available(macOS 15.0, iOS 18.0, *)
struct FileInfoDebugView: View {
    var file: ExcalidrawFile
    
    var body: some View {
        VStack {
            Text("Current File: ")
            
            ScrollView {
                VStack(spacing: 20) {
                    Text(String(describing: file))
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.background)
                                .stroke(.separator)
                        }
                    Text(String(data: file.content ?? Data(), encoding: .utf8) ?? "")
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.background)
                                .stroke(.separator)
                        }
                }
                .padding()
            }
        }
        
//        TextEditor(
//            text: .constant(
//                (try? file.content?.jsonStringified(options: .prettyPrinted)) ?? ""
//            )
//        )
//        .disabled(true)
    }
}

#Preview {
    if #available(macOS 15.0, iOS 18.0, *) {
        FileInfoDebugView(file: .preview)
    }
}
#endif
