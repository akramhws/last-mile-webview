import SwiftUI
import WebKit
import Network

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var vm = WebViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                if vm.isOffline {
                    OfflineFallbackView(primaryColor: AppConfig.primaryColor) {
                        vm.retry()
                    }
                } else {
                    WebView(url: AppConfig.appURL, vm: vm)
                        .ignoresSafeArea(edges: .bottom)

                    if vm.isLoading {
                        Rectangle()
                            .fill(.white.opacity(0.7))
                            .ignoresSafeArea()
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(AppConfig.primaryColor)
                                    .scaleEffect(1.4)
                            )
                    }
                }
            }
            .navigationTitle(AppConfig.navBarStyle != .hidden ? AppConfig.appName : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(AppConfig.navBarStyle == .hidden ? .hidden : .visible, for: .navigationBar)
            .toolbarBackground(
                AppConfig.navBarStyle == .colored ? AppConfig.primaryColor : Color.clear,
                for: .navigationBar
            )
            .toolbarBackground(
                AppConfig.navBarStyle == .hidden ? .hidden : .visible,
                for: .navigationBar
            )
            .toolbarColorScheme(
                AppConfig.navBarStyle == .colored ? .dark : nil,
                for: .navigationBar
            )
        }
        .onAppear { vm.startNetworkMonitoring() }
    }
}

// MARK: - WebView
struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var vm: WebViewModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = AppConfig.pullToRefresh

        if !AppConfig.allowZoom {
            let script = WKUserScript(
                source: "var meta = document.createElement('meta'); meta.name='viewport'; meta.content='width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no'; document.getElementsByTagName('head')[0].appendChild(meta);",
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(script)
        }

        if AppConfig.pullToRefresh {
            let refresh = UIRefreshControl()
            refresh.tintColor = UIColor(AppConfig.primaryColor)
            refresh.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh(_:)), for: .valueChanged)
            webView.scrollView.refreshControl = refresh
            context.coordinator.refreshControl = refresh
        }

        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let vm: WebViewModel
        weak var webView: WKWebView?
        var refreshControl: UIRefreshControl?

        init(vm: WebViewModel) { self.vm = vm }

        func webView(_ wv: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            vm.isLoading = true
        }
        func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
            vm.isLoading = false
            refreshControl?.endRefreshing()
        }
        func webView(_ wv: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            vm.isLoading = false
            refreshControl?.endRefreshing()
        }
        func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            vm.isLoading = false
            vm.isOffline = true
            refreshControl?.endRefreshing()
        }
        func webView(_ wv: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow all navigations inside the webview
            decisionHandler(.allow)
        }

        @objc func handleRefresh(_ sender: UIRefreshControl) {
            webView?.reload()
        }
    }
}

// MARK: - ViewModel
final class WebViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var isOffline = false
    private var monitor: NWPathMonitor?

    func startNetworkMonitoring() {
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                if path.status == .satisfied && self?.isOffline == true {
                    self?.retry()
                }
            }
        }
        monitor?.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    func retry() {
        isOffline = false
        isLoading = true
    }

    deinit { monitor?.cancel() }
}

// MARK: - Offline Fallback
struct OfflineFallbackView: View {
    let primaryColor: Color
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(primaryColor.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: "wifi.slash")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(primaryColor)
            }
            VStack(spacing: 8) {
                Text("لا يوجد اتصال بالإنترنت")
                    .font(.title3.bold())
                Text("تحقق من اتصالك بالإنترنت\nوحاول مجدداً")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: onRetry) {
                Label("إعادة المحاولة", systemImage: "arrow.clockwise")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(primaryColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding()
    }
}
