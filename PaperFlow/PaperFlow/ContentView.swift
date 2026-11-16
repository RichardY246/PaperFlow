// 决定先显示引导还是首页；同时负责启动 Logo 和本机数据错误提示。
import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var showingStorageWarning = false
    @State private var launching = true
    var body: some View {
        ZStack {
            Group {
                if store.state.completedOnboarding { RootView() }
                else { OnboardingView() }
            }
            if launching {
                VStack(spacing: 24) {
                    BrandMark(size: 112)
                    Text("PaperFlow").flowFont(.largeTitle, weight: .bold).foregroundStyle(Color.flow)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.paperBackground).transition(.opacity).zIndex(1)
            }
        }.tint(.flow).flowFont(.body)
            .onAppear { ThemePalette.shared.name = store.state.theme }
            .onChange(of: store.state.theme) { _, value in ThemePalette.shared.name = value }
            .onChange(of: scenePhase) { _, phase in if phase == .background { store.cancelAutomaticReadings(); Task { await store.flushStorage() } }; if phase == .active { store.configurationRevision += 1 } }
            .task {
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { launching = false }
                if store.storageError != nil { showingStorageWarning = true }
            }
            .onChange(of: store.storageError) { _, message in if message != nil && !launching { showingStorageWarning = true } }
            .alert("本地数据提示", isPresented: $showingStorageWarning) { Button("知道了", role: .cancel) { } } message: { Text(store.storageError ?? "") }
    }
}

#Preview { ContentView().environment(AppStore()) }
