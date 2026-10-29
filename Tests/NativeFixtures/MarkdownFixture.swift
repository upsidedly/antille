// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import SwiftUI
import Antille

/// Isolated native UI regression fixture for the exact public text-block path.
/// No producers, credentials, source connections, overlays, audio or saved state.
@main struct MarkdownFixture:App {
    var body:some Scene {
        Window("Antille Markdown Fixture",id:"markdown") {
            MarkdownFixtureView().frame(width:430,height:310)
        }.defaultSize(width:430,height:310)
    }
}
struct MarkdownFixtureView:View {
    @State private var text="# Output\n\n"+(1...14).map{"- Sample line \($0)"}.joined(separator:"\n")
    @State private var count=14
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Markdown scroll fixture").font(.headline)
            IslandBlockView(IslandBlock(id:"output",kind:.text,text:text,lineLimit:9,markdown:true,textIdentity:"stable-message")) {_ in}
                .font(.system(size:12))
            HStack {
                Button("Append line") {count+=1;text+="\n- Sample line \(count)"}
                Spacer()
                Text("\(count) lines").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(22).foregroundStyle(.white).background(.black).preferredColorScheme(.dark)
    }
}
