// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
import SwiftUI
import AppKit

/// Bounded, local Markdown. Remote images are represented by their alt text;
/// rendering a message never loads a URL or executes HTML.
public enum IslandMarkdown {
    public struct Block:Identifiable,Equatable,Sendable {
        public enum Kind:Equatable,Sendable {case paragraph,heading(Int),list(String),quote,code(String),table,rule}
        public var id:Int
        public var kind:Kind
        public var text:String
    }
    public static func blocks(_ source:String)->[Block] {
        let lines=source.replacingOccurrences(of:"\r\n",with:"\n").components(separatedBy:"\n")
        var result:[Block]=[],paragraph:[String]=[],paragraphStart=0
        var fence:Character?,fenceCount=0,code:[String]=[],codeStart=0,language="",skipUntil=0
        func flush() {
            if !paragraph.isEmpty {result.append(Block(id:paragraphStart,kind:.paragraph,text:paragraph.joined(separator:"\n")));paragraph=[]}
        }
        for (index,line) in lines.enumerated() {
            if index<skipUntil {continue}
            let trimmed=line.trimmingCharacters(in:.whitespaces)
            if let marker=fence {
                let count=trimmed.prefix(while:{$0==marker}).count
                if count>=fenceCount,trimmed.dropFirst(count).trimmingCharacters(in:.whitespaces).isEmpty {
                    result.append(Block(id:codeStart,kind:.code(language),text:code.joined(separator:"\n")));code=[];fence=nil
                } else {code.append(line)}
                continue
            }
            if let first=trimmed.first,first=="`" || first=="~" {
                let count=trimmed.prefix(while:{$0==first}).count
                if count>=3 {flush();fence=first;fenceCount=count;codeStart=index;language=String(trimmed.dropFirst(count)).trimmingCharacters(in:.whitespaces);continue}
            }
            if trimmed.isEmpty {flush();continue}
            if line.contains("|"),index+1<lines.count,isTableSeparator(lines[index+1]) {
                flush();var rows=[line],end=index+2
                while end<lines.count,lines[end].contains("|"),!lines[end].trimmingCharacters(in:.whitespaces).isEmpty {rows.append(lines[end]);end+=1}
                result.append(Block(id:index,kind:.table,text:rows.joined(separator:"\n")));skipUntil=end;continue
            }
            let hashes=trimmed.prefix(while:{$0=="#"}).count
            if (1...6).contains(hashes),trimmed.dropFirst(hashes).first==" " {
                flush();result.append(Block(id:index,kind:.heading(hashes),text:String(trimmed.dropFirst(hashes+1))));continue
            }
            if trimmed.hasPrefix(">") {flush();result.append(Block(id:index,kind:.quote,text:String(trimmed.dropFirst()).trimmingCharacters(in:.whitespaces)));continue}
            let rule=trimmed.filter{!$0.isWhitespace}
            if rule.count>=3,let marker=rule.first,["-","*","_"].contains(marker),rule.allSatisfy({$0==marker}) {flush();result.append(Block(id:index,kind:.rule,text:""));continue}
            if let marker=listMarker(trimmed) {
                flush();result.append(Block(id:index,kind:.list(marker.label),text:String(trimmed.dropFirst(marker.length))));continue
            }
            if paragraph.isEmpty {paragraphStart=index}
            paragraph.append(line)
        }
        flush()
        if fence != nil {result.append(Block(id:codeStart,kind:.code(language),text:code.joined(separator:"\n")))}
        return result
    }
    public static func tableCells(_ line:String)->[String] {
        var value=line.trimmingCharacters(in:.whitespaces)
        if value.hasPrefix("|"){value.removeFirst()};if value.hasSuffix("|"){value.removeLast()}
        return value.components(separatedBy:"|").map{$0.trimmingCharacters(in:.whitespaces)}
    }
    private static func isTableSeparator(_ line:String)->Bool {
        let cells=tableCells(line)
        return cells.count>1 && cells.allSatisfy {let value=$0.trimmingCharacters(in:CharacterSet(charactersIn:":"));return value.count>=3 && value.allSatisfy{$0=="-"}}
    }
    private static func listMarker(_ line:String)->(label:String,length:Int)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {return("•",2)}
        let digits=line.prefix(while:{$0.isNumber})
        guard !digits.isEmpty,digits.count<=9 else{return nil}
        let rest=line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else{return nil}
        return(String(digits)+".",digits.count+2)
    }
    public static func inline(_ text:String)->AttributedString {
        (try? AttributedString(markdown:text,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
    public static func commonPrefix(_ lhs:String,_ rhs:String)->Int {zip(lhs,rhs).prefix(while:{$0==$1}).count}
    public static func tail(_ source:String,maxBytes:Int=3600)->String {
        guard source.utf8.count>maxBytes else{return source}
        let allowance=max(0,maxBytes-12)
        var size=0,characters:[Character]=[]
        for character in source.reversed() {
            let count=String(character).utf8.count
            if size+count>allowance {break}
            characters.append(character);size+=count
        }
        var tail=String(characters.reversed())
        if let newline=tail.firstIndex(of:"\n"),tail.distance(from:tail.startIndex,to:newline)<tail.count/2 {tail=String(tail[tail.index(after:newline)...])}
        let prefix=String(source.dropLast(tail.count))
        var fence:String?
        for line in prefix.components(separatedBy:"\n") {
            let line=line.trimmingCharacters(in:.whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {fence=fence==nil ? String(line.prefix(3)):nil}
        }
        return (fence.map{$0+"\n"} ?? "")+tail
    }
}

public struct IslandMarkdownText:View {
    public var source:String
    public var fadesChanges:Bool
    public init(_ source:String,fadesChanges:Bool=true) {self.source=source;self.fadesChanges=fadesChanges}
    public var body:some View {
        if SilentCredentialPolicy.memoryOnly {content.environment(\.openURL,OpenURLAction{_ in .discarded})}
        else {content}
    }
    private var content:some View {
        VStack(alignment:.leading,spacing:8) {
            ForEach(IslandMarkdown.blocks(source)) {block in
                switch block.kind {
                case .paragraph: StreamingMarkdownRun(block.text,fadesChanges:fadesChanges)
                case .heading(let level): StreamingMarkdownRun(block.text,fadesChanges:fadesChanges).font(.system(size:level==1 ? 17:level==2 ? 15:13,weight:.semibold))
                case .list(let marker):
                    HStack(alignment:.firstTextBaseline,spacing:7) {Text(marker).foregroundStyle(.secondary);StreamingMarkdownRun(block.text,fadesChanges:fadesChanges).frame(maxWidth:.infinity,alignment:.leading)}
                case .quote:
                    HStack(spacing:9) {RoundedRectangle(cornerRadius:1).fill(.white.opacity(0.3)).frame(width:2);StreamingMarkdownRun(block.text,fadesChanges:fadesChanges).foregroundStyle(.white.opacity(0.75))}.fixedSize(horizontal:false,vertical:true)
                case .code:
                    ScrollView(.horizontal) {StreamingMarkdownRun(block.text,fadesChanges:fadesChanges,verbatim:true).font(.system(size:11,design:.monospaced)).padding(9)}.scrollIndicators(.never)
                        .background(.white.opacity(0.075),in:RoundedRectangle(cornerRadius:7))
                case .table:
                    let rows=block.text.components(separatedBy:"\n").map(IslandMarkdown.tableCells)
                    ScrollView(.horizontal) {
                        Grid(alignment:.leading,horizontalSpacing:14,verticalSpacing:7) {
                            ForEach(Array(rows.enumerated()),id:\.offset) {index,row in
                                GridRow {ForEach(Array(row.enumerated()),id:\.offset) {_,cell in StreamingMarkdownRun(cell,fadesChanges:fadesChanges).fontWeight(index==0 ? .semibold:.regular)}}
                            }
                        }.padding(9)
                    }.scrollIndicators(.never).background(.white.opacity(0.075),in:RoundedRectangle(cornerRadius:7))
                case .rule: Rectangle().fill(.white.opacity(0.18)).frame(height:1).padding(.vertical,3)
                }
            }
        }.frame(maxWidth:.infinity,alignment:.leading).tint(.cyan).textSelection(.enabled)
    }
}

/// macOS can scroll a clip view without relaying a SwiftUI geometry preference.
/// Observe only this view's native scroll position, without an input event tap.
private struct MarkdownScrollObserver:NSViewRepresentable {
    let changed:(Bool)->Void
    final class Probe:NSView {
        var changed:((Bool)->Void)?
        private weak var clip:NSClipView?
        private var observer:Any?
        private var previousOffset:Double?
        override func hitTest(_ point:NSPoint)->NSView? {nil}
        override func viewDidMoveToWindow() {super.viewDidMoveToWindow();install()}
        override func viewDidMoveToSuperview() {super.viewDidMoveToSuperview();install()}
        override func layout() {super.layout();install()}
        func install() {
            guard window != nil,let current=enclosingScrollView?.contentView else {detach();return}
            guard current !== clip else{return}
            detach();clip=current;current.postsBoundsChangedNotifications=true
            previousOffset=current.documentVisibleRect.minY
            observer=NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:current,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated {self?.observePosition()}
            }
        }
        private func observePosition() {
            guard let clip,let document=clip.documentView else{return}
            let visible=clip.documentVisibleRect
            let atEnd=document.isFlipped ? visible.maxY>=document.bounds.maxY-14:visible.minY<=document.bounds.minY+14
            let offset=visible.minY
            let towardStart=previousOffset.map{document.isFlipped ? offset<$0-1:offset>$0+1} ?? false
            previousOffset=offset
            guard atEnd || towardStart else{return}
            DispatchQueue.main.async { [weak self,weak clip] in
                guard let self,self.clip===clip else{return}
                self.changed?(atEnd)
            }
        }
        func detach() {if let observer {NotificationCenter.default.removeObserver(observer)};observer=nil;clip=nil;previousOffset=nil}
    }
    func makeNSView(context:Context)->Probe {let view=Probe();view.changed=changed;view.setAccessibilityElement(false);return view}
    func updateNSView(_ view:Probe,context:Context) {view.changed=changed}
    static func dismantleNSView(_ view:Probe,coordinator:()) {view.detach()}
}
/// Keeps the reply controls reachable while long output remains selectable and scrollable.
struct IslandMarkdownPreview:View {
    let source:String
    let lines:Int
    @State private var following=true
    private var limit:Double {Double(max(3,lines))*18}
    var body:some View {
        ViewThatFits(in:.vertical) {
            IslandMarkdownText(source).fixedSize(horizontal:false,vertical:true)
            scrolling
        }.frame(maxHeight:limit,alignment:.topLeading)
    }
    private var scrolling:some View {
        ScrollViewReader {reader in
            VStack(alignment:.trailing,spacing:3) {
                ScrollView {
                    VStack(alignment:.leading,spacing:0) {
                        IslandMarkdownText(source)
                        Color.clear.frame(height:1).id("markdown-end")
                    }.background(MarkdownScrollObserver {atEnd in if following != atEnd {following=atEnd}})
                }.scrollIndicators(.never).frame(height:limit-18)
                Button("Follow output") {following=true;reader.scrollTo("markdown-end",anchor:.bottom)}
                    .buttonStyle(.plain).font(.system(size:10)).foregroundStyle(.secondary)
                    .opacity(following ? 0:1).allowsHitTesting(!following).accessibilityHidden(following).frame(height:14)
            }
            .task(id:source) {
                guard following else{return}
                await Task.yield()
                guard !Task.isCancelled,following else{return}
                reader.scrollTo("markdown-end",anchor:.bottom)
            }
        }
    }
}

private struct StreamingMarkdownRun:View {
    var source:String
    var fadesChanges:Bool
    var verbatim=false
    @State private var previous=""
    @State private var stableCount=0
    @State private var progress=1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandContentActive) private var contentActive
    init(_ source:String,fadesChanges:Bool,verbatim:Bool=false) {self.source=source;self.fadesChanges=fadesChanges;self.verbatim=verbatim}
    private var attributed:AttributedString {verbatim ? AttributedString(source):IslandMarkdown.inline(source)}
    var body:some View {
        FadingMarkdownRun(attributed:attributed,stableCount:stableCount,progress:progress)
            .fixedSize(horizontal:false,vertical:true)
            .task(id:source) {
                let next=String(attributed.characters)
                stableCount=IslandMarkdown.commonPrefix(previous,next);previous=next
                guard fadesChanges,!reduceMotion,contentActive,stableCount<next.count else {progress=1;return}
                var transaction=Transaction();transaction.disablesAnimations=true
                withTransaction(transaction) {progress=0}
                await Task.yield()
                guard !Task.isCancelled else{return}
                withAnimation(.easeOut(duration:0.16)) {progress=1}
            }
    }
}
private struct FadingMarkdownRun:View,Animatable {
    var attributed:AttributedString
    var stableCount:Int
    // The animation engine interpolates this value; rendering stays on the main actor.
    nonisolated var progress:Double
    nonisolated var animatableData:Double {get{progress}set{progress=newValue}}
    var body:some View {
        var text=attributed
        if progress<0.999,stableCount<text.characters.count {
            let start=text.characters.index(text.startIndex,offsetBy:max(0,stableCount))
            text[start..<text.endIndex].foregroundColor = .white.opacity(max(0,min(1,progress)))
        }
        return Text(text)
    }
}
