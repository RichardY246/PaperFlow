import SwiftUI

/// 所有入口复用同一配置组件；草稿测试成功后才启用，失败不会覆盖当前连接。
struct AISettingsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:20) { APISetupContent(); Button("封面生成 · GLM-Image") { store.go(.imageSettings) }; Button("Token 用量与额度") { store.go(.usage) }; Button("语言与外观") { store.go(.preferences) } }.padding(18) }
            .navigationTitle("AI 设置").navigationBarTitleDisplayMode(.inline).flowFont(.body)
    }
}
struct APISetupContent: View {
    @Environment(AppStore.self) private var store
    var onboarding = false
    @State private var editing = false
    @State private var selected: AIConfiguration?
    @State private var configuringDemo = false
    @State private var demoKey = ""
    @State private var status = ""
    @State private var demoBusy = false
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("选择使用方式").flowFont(.headline)
            Text("个人 API 使用自己的服务额度。课堂体验由本机控制额度，手机直接联网，不依赖电脑。").flowFont(.body).foregroundStyle(.secondary)
            Button { selected = nil; editing = true } label: { Label("配置个人 API",systemImage:"key").frame(maxWidth:.infinity,minHeight:44) }.buttonStyle(.borderedProminent)
            Button {
                store.state.apiMode = "demo"; store.configurationRevision += 1; store.refreshQuota()
                if !store.hasAIKey() { configuringDemo = true }
                else { status = "已选择课堂演示；最多 3 篇或 30000 Token，以先到为准。" }
            } label: { Label("先体验演示额度",systemImage:"sparkles").frame(maxWidth:.infinity,minHeight:44) }.buttonStyle(.bordered)
            Text("当前：" + (store.isDemo ? "课堂演示 · glm-5.2" : (store.state.aiConfiguration.name ?? store.state.aiConfiguration.model))).flowFont(.body)
            if let quota = store.state.demoQuota { QuotaSummary(quota:quota) }
            ForEach(Array(store.state.apiProfiles.enumerated()),id:\.offset) { _,profile in
                HStack {
                    Button { selected = profile; editing = true } label: { VStack(alignment:.leading) { Text(profile.name ?? profile.model); Text(URL(string:profile.baseURL)?.host ?? profile.baseURL).flowFont(.subheadline).foregroundStyle(.secondary) } }
                    Spacer()
                    if profile == store.state.aiConfiguration && !store.isDemo { Image(systemName:"checkmark.circle.fill").foregroundStyle(Color.flow) }
                    else { Button("启用") {
                        if !((try? APIKeyStore.read(profile)) ?? "").isEmpty { store.state.aiConfiguration = profile; store.state.apiMode = "personal"; store.cancelAutomaticReadings(); store.configurationRevision += 1; status = "已启用 " + (profile.name ?? profile.model) }
                        else { selected = profile; editing = true }
                    }.flowFont(.body) }
                    Button { selected = profile; editing = true } label: { Image(systemName:"ellipsis").frame(width:44,height:44) }.accessibilityLabel("编辑 API 配置")
                }
            }
            if !status.isEmpty { Text(status).flowFont(.body).foregroundStyle(.secondary) }
            DisclosureGroup("课堂演示设备设置") {
                Text("由演示维护人在这台手机设置一次智谱密钥，之后参与体验的人无需重复填写。密钥不随 App 分发；本地额度仅用于课堂。").flowFont(.body)
                Button("设置或更换演示密钥") { configuringDemo = true }
            }
        }
        .sheet(isPresented:$editing) { APIProfileEditor(initial:selected) }
        .sheet(isPresented:$configuringDemo) {
            NavigationStack {
                Form {
                    ReadableSection("演示维护人设置") { Text("智谱 glm-5.2 · 密钥只保存在本机钥匙串"); SecureField("演示 API Key",text:$demoKey).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive() }
                    Button(demoBusy ? "正在测试…" : "测试并保存演示密钥") {
                        let secret = demoKey; demoBusy = true; status = ""
                        Task { @MainActor in
                            defer { demoBusy = false }
                            do {
                                _ = try await store.performAI(operation:"演示连接测试",input:"Connection test.",forceDemo:true,keyOverride:secret) { service,config,key in try await service.complete(configuration:config,key:key,system:"Reply only OK.",user:"Connection test.") }
                                try DemoAccess.saveKey(secret); demoKey = ""; store.state.apiMode = "demo"; store.refreshQuota(); store.configurationRevision += 1; configuringDemo = false; status = "测试成功，演示密钥已保存。"
                            } catch { status = error.localizedDescription }
                        }
                    }.disabled(demoBusy || demoKey.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    if !status.isEmpty { Text(status) }
                }.flowFont(.body).navigationTitle("演示密钥").toolbar { Button("关闭") { configuringDemo = false; demoKey = "" } }
            }
        }
        .onAppear { store.refreshQuota() }
    }
}
struct APIProfileEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let initial: AIConfiguration?
    @State private var draft = AIConfiguration()
    @State private var key = ""
    @State private var showKey = false
    @State private var advanced = false
    @State private var busy = false
    @State private var status = ""
    @State private var tested: AIConfiguration?
    @State private var testedKey = ""
    @State private var task: Task<Void,Never>?
    var body: some View {
        NavigationStack {
            Form {
                ReadableSection("服务商") {
                    Menu("选择服务商预设") {
                        Button("智谱 GLM") { preset("智谱","https://open.bigmodel.cn/api/paas/v4","glm-5.2") }
                        Button("DeepSeek") { preset("DeepSeek","https://api.deepseek.com","deepseek-flash") }
                        Button("通义千问") { preset("通义千问","https://dashscope.aliyuncs.com/compatible-mode/v1","qwen-plus") }
                        Button("自定义兼容接口") { draft.baseURL = "https://"; draft.model = ""; advanced = true; key = "" }
                    }
                    TextField("配置名称",text:Binding(get:{draft.name ?? ""},set:{draft.name = $0}))
                    TextField("模型名称",text:$draft.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                ReadableSection("密钥") {
                    Group { if showKey { TextField("API Key",text:$key) } else { SecureField("API Key",text:$key) } }.textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    Toggle("临时显示密钥",isOn:$showKey)
                }
                DisclosureGroup("高级设置",isExpanded:$advanced) { TextField("HTTPS 接口地址",text:$draft.baseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled() }
                Section {
                    Button(busy ? "正在测试…" : "测试连接") { test() }.disabled(busy || key.isEmpty)
                    if busy { Button("取消") { task?.cancel() } }
                    Button("保存并启用个人 API") { save() }.disabled(busy || tested != draft || testedKey != key)
                    Text("测试通过后才启用。测试也会调用一次接口，并记录 Token 用量。").flowFont(.subheadline).foregroundStyle(.secondary)
                    if !status.isEmpty { Text(status).flowFont(.body) }
                }
                if let initial { Button("删除这份配置",role:.destructive) {
                    do { try APIKeyStore.delete(initial); store.state.apiProfiles.removeAll { $0 == initial }; if store.state.aiConfiguration == initial { store.state.apiMode = "demo"; store.cancelAutomaticReadings(); store.configurationRevision += 1 }; dismiss() }
                    catch { status = error.localizedDescription }
                } }
            }.flowFont(.body).navigationTitle("个人 API").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("取消") { dismiss() } }
                .onAppear { draft = initial ?? AIConfiguration(id:UUID().uuidString,name:"智谱"); key = (try? APIKeyStore.read(draft)) ?? "" }
                .onChange(of:draft.baseURL) { _,_ in tested = nil; testedKey = ""; key = (try? APIKeyStore.read(draft)) ?? "" }
                .onDisappear { task?.cancel(); key = ""; testedKey = "" }
        }
    }
    private func preset(_ name:String,_ base:String,_ model:String) { draft.name = name; draft.baseURL = base; draft.model = model; advanced = false; key = (try? APIKeyStore.read(draft)) ?? "" }
    private func test() {
        let config = draft, secret = key; busy = true; status = ""; tested = nil
        task = Task { @MainActor in
            let service = AIService()
            do {
                _ = try await service.complete(configuration:config,key:secret,system:"Reply only OK.",user:"Connection test.")
                try Task.checkCancellation(); tested = config; testedKey = secret; status = "连接成功，可以保存。"
            } catch { status = Task.isCancelled ? "已取消" : error.localizedDescription }
            if service.sentRequest { store.recordUsage(UsageRecord(operation:"连接测试",model:config.model,provider:URL(string:config.baseURL)?.host ?? "",mode:"个人",usage:service.lastUsage,succeeded:tested != nil)) }
            busy = false
        }
    }
    private func save() {
        do {
            try APIKeyStore.save(key,configuration:draft)
            if let initial, initial.baseURL != draft.baseURL { try? APIKeyStore.delete(initial) }
            if let i = store.state.apiProfiles.firstIndex(where:{ draft.id != nil ? $0.id == draft.id : ($0.id == nil && $0.baseURL == draft.baseURL) }) { store.state.apiProfiles[i] = draft } else { store.state.apiProfiles.append(draft) }
            store.state.aiConfiguration = draft; store.state.apiMode = "personal"; store.cancelAutomaticReadings(); store.configurationRevision += 1; store.aiPauseReason = nil; dismiss()
        } catch { status = error.localizedDescription }
    }
}
struct QuotaBanner: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if store.isDemo, let quota = store.state.demoQuota, quota.exhausted || store.quotaNotice {
            VStack(alignment:.leading,spacing:10) {
                Text("课堂体验额度已满或不足，已完成的内容可以继续阅读。").flowFont(.body)
                HStack { Button("配置个人 API") { store.go(.aiSettings) }; Spacer(); Button("模拟充值") { store.go(.demoRecharge) } }.flowFont(.body)
            }.padding(14).background(Color.flow.opacity(0.08),in:RoundedRectangle(cornerRadius:14))
        }
    }
}
struct UsageLabel: View {
    var usage: TokenUsage?
    var body: some View {
        DisclosureGroup(usage?.total.map { "本次 \($0) Token" } ?? "本次用量未提供") {
            Text("输入：\(usage?.prompt_tokens.map(String.init) ?? "未提供") · 输出：\(usage?.completion_tokens.map(String.init) ?? "未提供")").flowFont(.subheadline)
        }.flowFont(.subheadline).foregroundStyle(.secondary)
    }
}
struct QuotaSummary: View {
    var quota: DemoQuota
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            Text("课堂体验：\(quota.usedPapers) / \(quota.paperLimit) 篇 · \(quota.usedTokens) / \(quota.tokenLimit) Token").flowFont(.body)
            Text("当前可用：\(quota.remainingTokens) Token · \(max(0,quota.paperLimit - quota.usedPapers - quota.reservedPapers)) 篇").flowFont(.subheadline).foregroundStyle(.secondary)
            if quota.reservedTokens > 0 { Text("预留或待确认：\(quota.reservedTokens) Token").flowFont(.subheadline).foregroundStyle(.secondary) }
            if quota.exhausted { Text("体验额度已到上限，已完成的文献仍可阅读。").flowFont(.body) }
        }
    }
}
struct UsageView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        List {
            ReadableSection("当前服务") { Text(store.isDemo ? "课堂演示 · glm-5.2" : (store.state.aiConfiguration.name ?? store.state.aiConfiguration.model)); Button("配置 API") { store.go(.aiSettings) } }
            if let quota = store.state.demoQuota { ReadableSection("演示额度") { QuotaSummary(quota:quota); Button("模拟充值") { store.go(.demoRecharge) } } }
            ReadableSection("封面生成") { ImageBudgetSummary(); Button("设置与生图记录") { store.go(.imageSettings) } }
            ReadableSection("实际用量") {
                Text("累计：\(store.totalTokens) Token")
                Text("今天：\(store.tokens(on:Date())) Token")
            }
            ReadableSection("最近调用") { ForEach(store.state.usageRecords.prefix(100)) { record in
                VStack(alignment:.leading,spacing:6) { Text(record.operation + " · " + record.mode); Text(record.model + " · " + Date(timeIntervalSince1970:record.timestamp).formatted(date:.abbreviated,time:.shortened)).flowFont(.subheadline); UsageLabel(usage:record.usage); if !record.succeeded { Text("未完成；若接口已计费，用量仍保留。").flowFont(.subheadline) } }
            } }
        }.flowFont(.body).navigationTitle("Token 用量").onAppear { store.refreshQuota() }
    }
}
struct DemoRechargeView: View {
    @Environment(AppStore.self) private var store
    @State private var status = ""
    var body: some View {
        Form {
            Section { Text("仅演示，不产生真实扣款").flowFont(.title2,weight:.bold); Text("模拟增加 30000 Token、3 篇体验文献与 3 张生图，不对应服务商真实余额。") }
            Button("确认模拟充值") { do { try store.simulateRecharge(); status = "演示额度已增加；未发生支付。" } catch { status = error.localizedDescription } }
            if !status.isEmpty { Text(status) }
            ReadableSection("演示记录") { ForEach((try? DemoAccess.load().transactions) ?? [],id:\.self) { Text($0.components(separatedBy:"|").last ?? $0) } }
        }.flowFont(.body).navigationTitle("模拟充值")
    }
}
struct AIReadingView: View {
    @Environment(AppStore.self) private var store
    var paperID:String
    @State private var question = ""
    @State private var answer = ""
    @State private var answerUsage: TokenUsage?
    @State private var busy = false
    @State private var error = ""
    @State private var request:Task<Void,Never>?
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:20) {
            if let paper = store.paper(paperID) {
                QuotaBanner()
                Text(paper.title).flowFont(.headline)
                Text("针对具体问题给出结论与证据。回答仅基于当前可用的摘要或正文页。").flowFont(.body).foregroundStyle(.secondary)
                Button("API 设置与额度") { store.go(.aiSettings) }
                if let saved = store.reading(paperID) { DisclosureGroup("查看概览与本次资料") { Text(saved.clarification); Text(saved.body); UsageLabel(usage:saved.usage); Text(saved.sourceLabel).foregroundStyle(.secondary) } }
                TextField("想了解这篇论文的什么？",text:$question,axis:.vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
                HStack { Button("发送问题") { run(paper:paper,generate:false) }.buttonStyle(.borderedProminent).disabled(busy || question.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty); Button(store.reading(paperID) == nil ? "生成概览" : "重新生成概览") { run(paper:paper,generate:true) }.buttonStyle(.bordered).disabled(busy) }
                if busy { ProgressView("正在处理…"); Button("取消") { request?.cancel() } }
                if !answer.isEmpty { Text(answer.components(separatedBy:"\n").first ?? answer).flowFont(.headline); DisclosureGroup("展开依据与说明") { Text(answer).textSelection(.enabled) }; UsageLabel(usage:answerUsage) }
                if !error.isEmpty { Text(error).foregroundStyle(.secondary); Button("配置 API / 查看额度") { store.go(.usage) } }
                Button("阅读原文") { store.go(.reader(paperID)) }
            }
        }.flowFont(.body).padding(18) }.navigationTitle("AI 阅读助手").navigationBarTitleDisplayMode(.inline).onDisappear { request?.cancel() }
    }
    private func run(paper:Paper,generate:Bool) {
        busy = true; error = ""
        request = Task { @MainActor in
            var prepared = false
            defer { busy = false; if prepared { store.abandonDemoPaper(paper.id) } }
            do {
                if generate { let reading = try await store.generateReading(paper); prepared = true; try Task.checkCancellation(); store.saveReading(reading,for:paper.id,language:reading.language ?? store.state.targetLanguage); try store.deliverDemoPaper(paper.id) }
                else { let result = try await store.askPaper(paper,question:String(question.prefix(2000))); try Task.checkCancellation(); answer = result.0; answerUsage = result.1 }
            } catch { self.error = Task.isCancelled ? "已取消，旧结果保留。" : error.localizedDescription }
        }
    }
}
