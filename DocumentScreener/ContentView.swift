//
//  ContentView.swift
//  DocumentScreener
//
//  Created by Christopher Guirguis on 9/8/23.
//

import SwiftUI
import PDFKit

class PDFHandler{
    static func readPDF(at url: URL) -> DocumentObject? {
        let pdfDocument = PDFDocument(url: url)
        return .init(filename: url.lastPathComponent,
                     fullURL: url,
                     textContent: pdfDocument?.string,
                     creationDate: pdfDocument?.documentAttributes?[PDFDocumentAttribute.creationDateAttribute] as? Date,
                     modificationDate: pdfDocument?.documentAttributes?[PDFDocumentAttribute.modificationDateAttribute] as? Date)
        
    }
}

struct DocumentObject: Codable, Hashable {
    var filename: String?
    var fullURL: URL
    var textContent: String?
    var creationDate: Date?
    var modificationDate: Date?
    
    func createSummaryFile(summary: String) {
        do {
        try FileManager().createDirectory(at: fullURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        let summaryFileName = fullURL.deletingPathExtension().lastPathComponent + "_summarized.txt"
        let summarizedPDFURL = fullURL.deletingLastPathComponent().appendingPathComponent(summaryFileName)
            
            
            try summary.write(to: summarizedPDFURL, atomically: true, encoding: .utf8)
            print("File successfully created")
        } catch {
            print("Failed to write summarized PDF: \(error)")
        }
    }
}

struct ProcessedDocument: Codable {
    var rawObject: DocumentObject
    var summary: String?
    var isProcessing: Bool = false
    var summaryGenerated: Bool { summary != nil }
}

class ViewModel: ObservableObject{
    @Published var path: NavigationPath = .init()
    @Published var fileContent = [String: ProcessedDocument]()
    var sortedFiles: [(String, ProcessedDocument)] {
        let keys = fileContent.keys.sorted()
        
        return keys.compactMap { key -> (String, ProcessedDocument)? in
            guard let content = fileContent[key] else {
                print("key had no matching content")
                return nil
            }
            return (key, content)
        }
    }
    @Published var successCount = 0
    @Published var failedCount = 0
    @Published var showAlert = false
    
    func openFolder() {
        let dialog = NSOpenPanel();
        dialog.directoryURL = nil
        dialog.allowsMultipleSelection = true
        dialog.canChooseDirectories = true
        dialog.allowedContentTypes = [.pdf]
        
        if (dialog.runModal() == NSApplication.ModalResponse.OK){
            guard let result = dialog.url else {
                print("No directory chosen!")
                return
            }
            
            let fileManager = FileManager.default
            let enumerator = fileManager.enumerator(atPath: result.path)
            var urls: [URL] = []
            
            while let element = enumerator?.nextObject() as? String {
                if element.hasSuffix("pdf") {
                    urls.append(result.appendingPathComponent(element))
                }
            }
            
            self.createDictionary(from: urls)
        }
    }
    
    func createDictionary(from urls: [URL]) {
        for url in urls{
            if let content = PDFHandler.readPDF(at: url) {
                self.fileContent[url.lastPathComponent] = .init(rawObject: content)
                self.successCount += 1
            } else {
                self.failedCount += 1
            }
        }
        self.showAlert = true
    }
    @Published var screen: Screens = .home
}

enum Screens: Hashable {
    case home
    case advanced
    case documents(documentID: String)
}
struct ContentView: View {
    @StateObject var viewModel = ViewModel()
    var body: some View {
        NavigationSplitView {
            List(selection: $viewModel.screen){
                Section("Views"){
                    NavigationLink(value: Screens.home) {
                        Label("Home", systemImage: "house")
                    }
                    NavigationLink(value: Screens.advanced) {
                        Label("Advanced", systemImage: "brain.head.profile")
                    }
                }
                
                if !viewModel.fileContent.isEmpty {
                    Section("Documents"){
                        ForEach(viewModel.sortedFiles, id: \.0) {file in
                            NavigationLink(value: Screens.documents(documentID: file.0)) {
                                HStack {
                                    if file.1.isProcessing {
                                        ProgressView()
                                            .scaleEffect(0.3)
                                    } else {
                                        Text("\(file.1.summary == nil ? "⌛️" : "✅")")
                                    }
                                    Text(file.0)
                                }.frame(height: 20)
                            }
                            
                        }
                    }
                }
            }
        } detail: {
            switch viewModel.screen {
            case .home:
                HomeView(viewModel: viewModel)
            case .documents(let documentID):
                if let processedDocument = viewModel.fileContent[documentID] {
                    DocumentViewingScreen(object: processedDocument)
                }
            case .advanced:
                AdvancedSettingsView()
            }
        }
    }
}

struct AdvancedSettingsView: View {
    @ObservedObject var apiService: APIService = .shared
    
    var body: some View {
        VStack {
            Grid(alignment: .topLeading){
                GridRow {
                    Text("API Key")
                    TextField("API Key", text: $apiService.apiKey)
                }
                GridRow {
                    Text("Tokens")
                    TextField("Tokens", value: $apiService.maxTokens, formatter: NumberFormatter())
                }
                GridRow {
                    Text("Asst. Prompt")
                    TextField("Assistant Prompt", text: $apiService.assistantPrompt, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
                GridRow {
                    Text("Model")
                    HStack {
                        TextField("Model", text: $apiService.modelId)
                        Button {
                            Task {
                                do {
                                    let models = try await apiService.fetchModels()
                                    DispatchQueue.main.async {
                                        apiService.availableModels = models
                                    }
                                } catch {
                                    print("Failed to fetch models")
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                            .tint(.blue)

                    }
                }
                
                
            }
            
            HStack {
                ScrollView {
                    Group {
                        if apiService.availableModels.isEmpty {
                            Text("Refresh the models above")
                                .frame(maxWidth: .infinity)
                        } else {
                            VStack(alignment: .leading){
                                ForEach(apiService.availableModels, id: \.self) { model in
                                    HStack {
                                        Text(model)
                                        Button("Select") {
                                            apiService.modelId = model
                                        }
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    .padding()
                }
                .background(Color.black.opacity(0.2))
                .frame(width: 500)
                Spacer()
            }
        }.padding()
    }
}
struct HomeView: View {
    @ObservedObject var viewModel = ViewModel()
    
    var body: some View {
        VStack {
            HStack {
                Group {
                    Button("Open Folder"){
                        self.viewModel.openFolder()
                    }
                    .alert(isPresented: $viewModel.showAlert, content: {
                        Alert(title: Text("Done!"), message: Text("\(viewModel.successCount) files were read successfully. \(viewModel.failedCount) failed to be read."), dismissButton: .default(Text("OK")){
                            self.viewModel.successCount = 0
                            self.viewModel.failedCount = 0
                            self.viewModel.showAlert = false
                        })
                    })
                    if !viewModel.fileContent.isEmpty {
                        Button {
                            for objectPair in viewModel.fileContent {
                                viewModel.fileContent[objectPair.key]?.isProcessing = true
                                Task {
                                    var object = objectPair.value
                                    
                                    guard let content = objectPair.value.rawObject.textContent else { return }
                                    do {
                                        let summary = try await APIService.shared.summarizeDocument(content, model: APIService.shared.modelId)
                                        objectPair.value.rawObject.createSummaryFile(summary: summary)
                                        object.summary = summary
                                        
                                    } catch {
                                        print("🔥 Failed to summarize")
                                        print(error)
                                        print(error.localizedDescription)
                                    }
                                    object.isProcessing = false
                                    viewModel.fileContent[objectPair.key] = object
                                }
                                
                            }
                            
                        } label: {
                            Text("Run Analysis")
                        }
                        
                    }
                }
                .buttonStyle(.plain)
                .padding(8)
                .background(.blue)
                .cornerRadius(10)
                Spacer()
            }
            Spacer()
        }.padding()
    }
}

struct MyPreviewProvider_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct DocumentViewingScreen: View {
    let object: ProcessedDocument
    var body: some View {
        VStack {
            Text("File Name: ").fontWeight(.semibold) + Text(object.rawObject.filename ?? "--")
            Divider()
            Text("File Content: ").fontWeight(.semibold)
            ScrollView {
                Text(object.rawObject.textContent ?? "--")
            }
            .frame(maxHeight: 500)
            Divider()
            if let summary = object.summary {
                Text("Generated Summary:").fontWeight(.semibold)
                ScrollView {
                    Text(summary)
                        .frame(maxHeight: 500)
                }
            }
        }
    }
}

struct ModelListResponse: Codable {
    struct ModelObject: Codable {
        let id: String
        /* Add other fields if needed */
    }
    
    let data: [ModelObject]
}

// MARK: - CompletionResponse
struct CompletionResponse: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [Choice]?
}

// MARK: - Choice
struct Choice: Codable {
    let index: Int?
    let message: Message?
}

// MARK: - Delta
struct Delta: Codable {
    let content: String?
}
enum Role: String, Codable {
    case system
    case user
    case assistant
}
struct Message: Codable {
    var role: Role?
    var content: String?
}
struct Prompt: Codable {
    let model: String
    let messages: [Message]
    let max_tokens: Int
}

class APIService: ObservableObject {
    static let shared = APIService()
    @AppStorage("openAIKey") var apiKey: String = ""
    @AppStorage("modelId") var modelId: String = ""
    @AppStorage("assistantPrompt") var assistantPrompt: String = ""
    @AppStorage("maxTokens") var maxTokens: Int = 200
    var bearer: String { "Bearer \(apiKey)" }
    @Published var availableModels: [String] = []
    let session: URLSession
    
    private init(session: URLSession = URLSession.shared) {
        self.session = session
    }
    
    func fetchModels() async throws -> [String] {
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.addValue(bearer, forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, _) = try await session.data(for: request)
        let modelListResponse = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return modelListResponse.data.map { $0.id }.sorted()
    }
    
    func summarizeDocument(_ documentContent: String, model: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(bearer, forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = Prompt(model: modelId, messages: [
            .init(role: .system, content: "You are a program director for an an otolaryngology residency program. Your job is to read through information/applications and summarize the presence of a specific attribute in their application."),
            .init(role: .user,
                  content:"""
\(assistantPrompt)
\(documentContent)
""")
        ], max_tokens: maxTokens)
        let jsonData = try JSONEncoder().encode(prompt)
        request.httpBody = jsonData
        
        let (data, _) = try await session.data(for: request)
        let documentResponse = try JSONDecoder().decode(CompletionResponse.self, from: data)
        return documentResponse.choices?.first?.message?.content ?? ""
    }
}

extension Sequence {
    func asyncForEach(
        _ operation: (Element) async throws -> Void
    ) async rethrows {
        for element in self {
            try await operation(element)
        }
    }
}

extension Sequence {
    func asyncCompactMap<T>(
        _ transform: (Element) async throws -> T?
    ) async rethrows -> [T] {
        var values = [T]()

        for element in self {
            let transformedElement = try await transform(element)
            if let transformedElement {
                values.append(transformedElement)
            }
        }

        return values
    }
}
