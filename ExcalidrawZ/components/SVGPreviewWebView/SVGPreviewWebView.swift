//
//  SVGPreviewWebView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/4/25.
//

import SwiftUI
import WebKit

struct SVGPreviewView: View {
    var svgContent: String
    
    @State private var webViewSize: CGSize = .zero
    
    init(svgURL: URL) {
        self.svgContent = String(data: (try? Data(contentsOf: svgURL)) ?? Data(), encoding: .utf8) ?? ""
    }
    
    init(svg: String) {
        self.svgContent = svg
    }
    
//    var config = Config()
    
    var body: some View {
        SVGPreviewWebView(svg: svgContent, contentSize: $webViewSize)
            .frame(width: webViewSize.width, height: webViewSize.height)
    }
    
//    class Config {
//        var contentPaddings: (Edge.Set, CGFloat) = (.all, 0)
//    }
//    public func contentPadding(_ edges: Edge.Set, _ length: CGFloat) -> Self {
//        self.config.contentPaddings = (edges, length)
//        return self
//    }
}

struct SVGPreviewWebView {
    var svgURL: URL?
    var svgContent: String?
    @Binding private var contentSize: CGSize

    init(svgURL: URL, contentSize: Binding<CGSize>) {
        self.svgURL = svgURL
        self._contentSize = contentSize
    }
    
    init(svg: String, contentSize: Binding<CGSize>) {
        self.svgContent = svg
        self._contentSize = contentSize
    }
}

#if canImport(AppKit)
extension SVGPreviewWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        makePlatformView(context: context)
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        updatePlatformView(webView, context: context)
    }
}
#elseif canImport(UIKit)
extension SVGPreviewWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        makePlatformView(context: context)
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        updatePlatformView(webView, context: context)
    }
}
#endif


extension SVGPreviewWebView {
    private func loadSVG(in webView: WKWebView) {
        if let svgContent = svgContent, let data = svgContent.data(using: .utf8) {
            // 直接加载 svg 数据，mimeType 为 image/svg+xml
            webView.load(data, mimeType: "image/svg+xml", characterEncodingName: "utf-8", baseURL: URL(string: "about:blank")!)
        } else if let svgURL = svgURL {
            webView.loadFileURL(svgURL, allowingReadAccessTo: svgURL.deletingLastPathComponent())
        }
    }
    
    
    func makePlatformView(context: Context) -> WKWebView {
        let webView = WKWebView()
        if #available(macOS 13.3, iOS 16.4, *) {
            webView.isInspectable = true
        }
        webView.navigationDelegate = context.coordinator
        loadSVG(in: webView)
        return webView
    }
    
    func updatePlatformView(_ webView: WKWebView, context: Context) {
        DispatchQueue.main.async {
            loadSVG(in: webView)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(contentSize: $contentSize)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var contentSize: CGSize
        
        init(contentSize: Binding<CGSize>) {
            self._contentSize = contentSize
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 通过 JS 获取 svg 的尺寸
            let js = """
                (function() {
                    var svg = document.querySelector('svg');
                    if (svg) {
                        var bbox = svg.getBoundingClientRect();
                        return [bbox.width, bbox.height];
                    }
                    return [0, 0];
                })();
                """
            webView.evaluateJavaScript(js) { result, error in
                if let arr = result as? [Double], arr.count == 2 {
                    print("result", result)
                    DispatchQueue.main.async {
                        self.contentSize = CGSize(width: arr[0], height: arr[1])
                    }
                } else if let error = error {
                    print("Error evaluating JavaScript: \(error)")
                }
            }
        }
    }
}

#Preview {
    SVGPreviewView(svg: """
<svg style="vertical-align: -0.488ex;" xmlns="http://www.w3.org/2000/svg" width="11.397ex" height="2.107ex" role="img" focusable="false" viewBox="0 -716 5037.7 931.5" xmlns:xlink="http://www.w3.org/1999/xlink"><defs><style>svg a{fill:blue;stroke:blue}[data-mml-node="merror"]>g{fill:red;stroke:red}[data-mml-node="merror"]>rect[data-background]{fill:yellow;stroke:none}[data-frame],[data-line]{stroke-width:70px;fill:none}.mjx-dashed{stroke-dasharray:140}.mjx-dotted{stroke-linecap:round;stroke-dasharray:0,140}use[data-c]{stroke-width:3px}</style><path id="MJX-1-TEX-N-48" d="M128 622Q121 629 117 631T101 634T58 637H25V683H36Q57 680 180 680Q315 680 324 683H335V637H302Q262 636 251 634T233 622L232 500V378H517V622Q510 629 506 631T490 634T447 637H414V683H425Q446 680 569 680Q704 680 713 683H724V637H691Q651 636 640 634T622 622V61Q628 51 639 49T691 46H724V0H713Q692 3 569 3Q434 3 425 0H414V46H447Q489 47 498 49T517 61V332H232V197L233 61Q239 51 250 49T302 46H335V0H324Q303 3 180 3Q45 3 36 0H25V46H58Q100 47 109 49T128 61V622Z"></path><path id="MJX-1-TEX-N-65" d="M28 218Q28 273 48 318T98 391T163 433T229 448Q282 448 320 430T378 380T406 316T415 245Q415 238 408 231H126V216Q126 68 226 36Q246 30 270 30Q312 30 342 62Q359 79 369 104L379 128Q382 131 395 131H398Q415 131 415 121Q415 117 412 108Q393 53 349 21T250 -11Q155 -11 92 58T28 218ZM333 275Q322 403 238 411H236Q228 411 220 410T195 402T166 381T143 340T127 274V267H333V275Z"></path><path id="MJX-1-TEX-N-6C" d="M42 46H56Q95 46 103 60V68Q103 77 103 91T103 124T104 167T104 217T104 272T104 329Q104 366 104 407T104 482T104 542T103 586T103 603Q100 622 89 628T44 637H26V660Q26 683 28 683L38 684Q48 685 67 686T104 688Q121 689 141 690T171 693T182 694H185V379Q185 62 186 60Q190 52 198 49Q219 46 247 46H263V0H255L232 1Q209 2 183 2T145 3T107 3T57 1L34 0H26V46H42Z"></path><path id="MJX-1-TEX-N-6F" d="M28 214Q28 309 93 378T250 448Q340 448 405 380T471 215Q471 120 407 55T250 -10Q153 -10 91 57T28 214ZM250 30Q372 30 372 193V225V250Q372 272 371 288T364 326T348 362T317 390T268 410Q263 411 252 411Q222 411 195 399Q152 377 139 338T126 246V226Q126 130 145 91Q177 30 250 30Z"></path><path id="MJX-1-TEX-N-2C" d="M78 35T78 60T94 103T137 121Q165 121 187 96T210 8Q210 -27 201 -60T180 -117T154 -158T130 -185T117 -194Q113 -194 104 -185T95 -172Q95 -168 106 -156T131 -126T157 -76T173 -3V9L172 8Q170 7 167 6T161 3T152 1T140 0Q113 0 96 17Z"></path><path id="MJX-1-TEX-I-1D447" d="M40 437Q21 437 21 445Q21 450 37 501T71 602L88 651Q93 669 101 677H569H659Q691 677 697 676T704 667Q704 661 687 553T668 444Q668 437 649 437Q640 437 637 437T631 442L629 445Q629 451 635 490T641 551Q641 586 628 604T573 629Q568 630 515 631Q469 631 457 630T439 622Q438 621 368 343T298 60Q298 48 386 46Q418 46 427 45T436 36Q436 31 433 22Q429 4 424 1L422 0Q419 0 415 0Q410 0 363 1T228 2Q99 2 64 0H49Q43 6 43 9T45 27Q49 40 55 46H83H94Q174 46 189 55Q190 56 191 56Q196 59 201 76T241 233Q258 301 269 344Q339 619 339 625Q339 630 310 630H279Q212 630 191 624Q146 614 121 583T67 467Q60 445 57 441T43 437H40Z"></path><path id="MJX-1-TEX-I-1D438" d="M492 213Q472 213 472 226Q472 230 477 250T482 285Q482 316 461 323T364 330H312Q311 328 277 192T243 52Q243 48 254 48T334 46Q428 46 458 48T518 61Q567 77 599 117T670 248Q680 270 683 272Q690 274 698 274Q718 274 718 261Q613 7 608 2Q605 0 322 0H133Q31 0 31 11Q31 13 34 25Q38 41 42 43T65 46Q92 46 125 49Q139 52 144 61Q146 66 215 342T285 622Q285 629 281 629Q273 632 228 634H197Q191 640 191 642T193 659Q197 676 203 680H757Q764 676 764 669Q764 664 751 557T737 447Q735 440 717 440H705Q698 445 698 453L701 476Q704 500 704 528Q704 558 697 578T678 609T643 625T596 632T532 634H485Q397 633 392 631Q388 629 386 622Q385 619 355 499T324 377Q347 376 372 376H398Q464 376 489 391T534 472Q538 488 540 490T557 493Q562 493 565 493T570 492T572 491T574 487T577 483L544 351Q511 218 508 216Q505 213 492 213Z"></path><path id="MJX-1-TEX-I-1D44B" d="M42 0H40Q26 0 26 11Q26 15 29 27Q33 41 36 43T55 46Q141 49 190 98Q200 108 306 224T411 342Q302 620 297 625Q288 636 234 637H206Q200 643 200 645T202 664Q206 677 212 683H226Q260 681 347 681Q380 681 408 681T453 682T473 682Q490 682 490 671Q490 670 488 658Q484 643 481 640T465 637Q434 634 411 620L488 426L541 485Q646 598 646 610Q646 628 622 635Q617 635 609 637Q594 637 594 648Q594 650 596 664Q600 677 606 683H618Q619 683 643 683T697 681T738 680Q828 680 837 683H845Q852 676 852 672Q850 647 840 637H824Q790 636 763 628T722 611T698 593L687 584Q687 585 592 480L505 384Q505 383 536 304T601 142T638 56Q648 47 699 46Q734 46 734 37Q734 35 732 23Q728 7 725 4T711 1Q708 1 678 1T589 2Q528 2 496 2T461 1Q444 1 444 10Q444 11 446 25Q448 35 450 39T455 44T464 46T480 47T506 54Q523 62 523 64Q522 64 476 181L429 299Q241 95 236 84Q232 76 232 72Q232 53 261 47Q262 47 267 47T273 46Q276 46 277 46T280 45T283 42T284 35Q284 26 282 19Q279 6 276 4T261 1Q258 1 243 1T201 2T142 2Q64 2 42 0Z"></path><path id="MJX-1-TEX-N-21" d="M78 661Q78 682 96 699T138 716T180 700T199 661Q199 654 179 432T158 206Q156 198 139 198Q121 198 119 206Q118 209 98 431T78 661ZM79 61Q79 89 97 105T141 121Q164 119 181 104T198 61Q198 31 181 16T139 1Q114 1 97 16T79 61Z"></path></defs><g stroke="currentColor" fill="currentColor" stroke-width="0" transform="scale(1,-1)"><g data-mml-node="math"><g data-mml-node="mtext"><use data-c="48" xlink:href="#MJX-1-TEX-N-48"></use><use data-c="65" xlink:href="#MJX-1-TEX-N-65" transform="translate(750,0)"></use><use data-c="6C" xlink:href="#MJX-1-TEX-N-6C" transform="translate(1194,0)"></use><use data-c="6C" xlink:href="#MJX-1-TEX-N-6C" transform="translate(1472,0)"></use><use data-c="6F" xlink:href="#MJX-1-TEX-N-6F" transform="translate(1750,0)"></use></g><g data-mml-node="mo" transform="translate(2250,0)"><use data-c="2C" xlink:href="#MJX-1-TEX-N-2C"></use></g><g data-mml-node="mi" transform="translate(2694.7,0)"><use data-c="1D447" xlink:href="#MJX-1-TEX-I-1D447"></use></g><g data-mml-node="mspace" transform="translate(3398.7,0)"></g><g data-mml-node="mpadded" transform="translate(3258.7,0)"><g transform="translate(0,-215.5)"><g data-mml-node="TeXAtom" data-mjx-texclass="ORD"><g data-mml-node="mi"><use data-c="1D438" xlink:href="#MJX-1-TEX-I-1D438"></use></g></g></g></g><g data-mml-node="mspace" transform="translate(4022.7,0)"></g><g data-mml-node="mi" transform="translate(3907.7,0)"><use data-c="1D44B" xlink:href="#MJX-1-TEX-I-1D44B"></use></g><g data-mml-node="TeXAtom" data-mjx-texclass="ORD" transform="translate(4759.7,0)"></g><g data-mml-node="mo" transform="translate(4759.7,0)"><use data-c="21" xlink:href="#MJX-1-TEX-N-21"></use></g></g></g></svg>
""")
}
