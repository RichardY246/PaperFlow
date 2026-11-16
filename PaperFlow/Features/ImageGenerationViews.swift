import SwiftUI

struct ImageBudgetSummary: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text("演示生图：已用 \(store.imageBudget.used) / \(store.imageBudget.limit) 张 · 可用 \(store.imageBudget.remaining) 张")
            if !store.imageBudget.pending.isEmpty { Text("预占或待确认：\(store.imageBudget.pending.count) 张").foregroundStyle(.secondary) }
            Text("生图按次记录，与文字 Token 分开。个人 Key 不受本地演示次数限制。").foregroundStyle(.secondary)
        }.flowFont(.body)
    }
}

/// 同一个恢复入口放在首页和设置里；点击前显示本次最多张数与费用。
struct ImageBalanceRecoveryView: View {
    var showSettings = true
    @Environment(AppStore.self) private var store
    var body: some View {
        let total = store.balanceRecoveryPapers.count
        let count = store.isDemo ? min(total,store.imageBudget.remaining) : total
        if total > 0 || store.imageRecoveryRunning || !store.imageRecoveryStatus.isEmpty {
            VStack(alignment:.leading,spacing:10) {
                if store.imageRecoveryRunning {
                    Text(store.imageRecoveryStatus)
                    ProgressView()
                    Button("停止后续重试") { store.imageRecoveryStopRequested = true }
                    Text("当前已提交的生图会继续保存结果。").foregroundStyle(.secondary)
                } else {
                    if total > 0 {
                        Text("\(total) 张论文封面曾因余额不足未生成。")
                        Button("余额已恢复，重试 \(count) 张封面") { store.startBalanceRecovery() }.disabled(count == 0)
                        Text("预计最多 \(String(format:"%.1f",Double(count)*0.1)) 元；有原图时直接恢复原图。结果不明的请求不会重复提交。").foregroundStyle(.secondary)
                        if count == 0 && showSettings { Button("查看生图额度") { store.go(.imageSettings) } }
                    }
                    if !store.imageRecoveryStatus.isEmpty {
                        Text(store.imageRecoveryStatus).foregroundStyle(.secondary)
                        Button("收起结果") { store.imageRecoveryStatus = "" }
                    }
                }
            }.flowFont(.body).buttonStyle(.borderless)
        }
    }
}

struct ImageSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var configureAPI = false
    @State private var recharge = false
    @State private var confirmID:String?
    @State private var error = ""
    private var profiles:[AIConfiguration] { store.state.apiProfiles.filter { ImageConfiguration.accepts($0) } }
    private var records:[ImageCoverRecord] { store.state.imageCalls.values.sorted { $0.timestamp > $1.timestamp } }
    var body: some View {
        @Bindable var store = store
        Form {
            Section("封面生成") {
                Text("GLM-Image · 4:3 横版 · 无标题文字")
                Toggle("无原图时自动生成论文封面",isOn:$store.state.imageConfiguration.automatic)
                Text("优先使用手选图片与论文原图。生成图只作为研究主题示意，保留服务商默认水印。").foregroundStyle(.secondary)
                Text("参考价格：0.1 元 / 次；实际费用以智谱账单为准。").foregroundStyle(.secondary)
            }
            Section("复用智谱 Key") {
                if store.isDemo { Text("关联课堂演示钥匙串") }
                else {
                    Picker("智谱配置",selection:$store.state.imageConfiguration.profileID) {
                        Text("自动选择已有智谱配置").tag(String?.none)
                        ForEach(Array(profiles.enumerated()),id:\.offset) { _,profile in Text(profile.name ?? profile.model).tag(profile.id) }
                    }
                    Text("当前关联：" + (store.imageProfile?.name ?? store.imageProfile?.model ?? "尚无智谱配置"))
                }
                Text(store.imageKeyAvailable ? "已有密钥，可尝试生图；模型权限与余额由智谱校验。" : "尚未找到关联密钥。请先保存智谱 API。")
                Button("管理已有 API") { configureAPI = true }
            }
            Section("课堂额度") {
                ImageBudgetSummary()
                Text("模拟充值只增加本机次数；真实生图仍需智谱账户余额或可用资源包。").foregroundStyle(.secondary)
                Link("智谱控制台 · 查看余额与资源包",destination:URL(string:"https://bigmodel.cn/")!)
                Button("模拟充值") { recharge = true }
            }
            Section("恢复失败封面") { ImageBalanceRecoveryView(showSettings:false) }
            Section("生图记录") {
                if records.isEmpty { Text("还没有生图请求。") }
                ForEach(records,id:\.requestID) { record in
                    VStack(alignment:.leading,spacing:8) {
                        Text(record.contentID.hasPrefix("paper:") ? (store.paper(String(record.contentID.dropFirst(6)))?.title ?? "论文封面") : (store.post(String(record.contentID.dropFirst(5)))?.title ?? "笔记封面"))
                        Text(record.statusText + " · " + (record.mode == "demo" ? "演示" : "个人") + " · " + Date(timeIntervalSince1970:record.timestamp).formatted(date:.abbreviated,time:.shortened)).foregroundStyle(.secondary)
                        Text(record.counted ? "已生成/按已使用记录 · 参考 0.1 元" : record.estimatedCost > 0 ? "可能计费约 0.1 元，待核对" : "请求被拒绝，已释放演示次数").foregroundStyle(.secondary)
                        if let message = record.message { Text(message).foregroundStyle(.secondary) }
                        if let code = record.providerCode { Text("服务代码 \(code)" + (record.httpStatus.map { " · HTTP \($0)" } ?? "")).foregroundStyle(.secondary) }
                        if ["requesting","unknown"].contains(record.status),store.imageJobs[record.id] == nil {
                            Button("已核对控制台，结束待确认记录") { confirmID = record.id }
                        }
                    }.padding(.vertical,4)
                }
            }
            if !error.isEmpty { Section { Text(error) } }
        }.flowFont(.body).navigationTitle("封面生成").navigationBarTitleDisplayMode(.inline).onAppear { store.refreshQuota() }
            .sheet(isPresented:$configureAPI) { NavigationStack { ScrollView { APISetupContent().padding(18) }.navigationTitle("API 配置").toolbar { Button("完成") { configureAPI = false } } } }
            .sheet(isPresented:$recharge) { NavigationStack { DemoRechargeView().toolbar { Button("完成") { recharge = false } } } }
            .confirmationDialog("按已使用 1 次结束记录？此操作不会退回可能已发生的费用。",isPresented:Binding(get:{confirmID != nil},set:{if !$0 { confirmID = nil }}),titleVisibility:.visible) {
                Button("确认结束并计入已使用") { do { if let id = confirmID { try store.closeUnknownImage(id) } } catch { self.error = error.localizedDescription };confirmID = nil }
            }
    }
}

/// 手动入口只在没有可靠原图时启用。重试下载与重新生图共用入口，后台按记录判断。
struct ImageGenerationControl: View {
    @Environment(AppStore.self) private var store
    var input:ImageCoverInput
    var hasOriginal = false
    var onStart:(() -> Void)?
    var onReady:((URL) -> Void)?
    @State private var settings = false
    @State private var busy = false
    @State private var error = ""
    private var record:ImageCoverRecord? { store.state.imageGenerations[input.cacheID] }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            if hasOriginal { Text("已有可靠原图，优先使用原图。").foregroundStyle(.secondary) }
            else {
                Button(busy ? "正在处理…" : record?.remoteURL != nil && store.generatedImageURL(input) == nil ? "重试下载已有图片" : store.generatedImageURL(input) != nil ? "使用已生成封面" : "AI 生成封面") {
                    busy = true;error = "";onStart?()
                    Task { @MainActor in
                        defer { busy = false }
                        do { _ = try await store.generateImage(input,retry:true);if let url = store.generatedImageURL(input) { onReady?(url) };store.recordEvent("cover_retry") }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(busy || store.imageActivity.contains(input.cacheID) || input.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                Text(record?.message ?? "GLM-Image · 0.1 元 / 次；已有结果直接复用，不重复生图。").foregroundStyle(.secondary)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.secondary) }
            Button("封面生成设置与额度") { settings = true }
        // Form/List 同一行内有多个按钮时，明确样式，避免一次点击触发整行按钮。
        }.flowFont(.body).buttonStyle(.borderless).sheet(isPresented:$settings) { NavigationStack { ImageSettingsView().toolbar { Button("完成") { settings = false } } } }
    }
}
