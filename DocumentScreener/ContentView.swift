//
//  ContentView.swift
//  DocumentScreener
//
//  Created by Christopher Guirguis on 9/8/23.
//

import SwiftUI
import PDFKit

extension PDFDocument {
    var attributedContent: [NSAttributedString] {
        let pageCount = self.pageCount
        var documentContent = [NSAttributedString]()
        
        for i in 0 ..< pageCount {
            guard let page = self.page(at: i) else { continue }
            guard let pageContent = page.attributedString else { continue }
            documentContent.append(pageContent)
        }
        return documentContent
    }
}
class PDFHandler{
    static func readPDF(at url: URL) -> DocumentObject? {
        let pdfDocument = PDFDocument(url: url)
        return .init(filename: url.lastPathComponent,
                     fullURL: url,
                     textContent: pdfDocument?.string,
                     attributedContent: pdfDocument?.attributedContent ?? [],
                     creationDate: pdfDocument?.documentAttributes?[PDFDocumentAttribute.creationDateAttribute] as? Date,
                     modificationDate: pdfDocument?.documentAttributes?[PDFDocumentAttribute.modificationDateAttribute] as? Date)
        
    }
}

struct DocumentObject: Hashable {
    enum CodingKeys: CodingKey {
        case filename
        case fullURL
        case textContent
//        case attributedContent
        case creationDate
        case modificationDate
    }
    var filename: String?
    var fullURL: URL
    var textContent: String?
    var attributedContent: [NSAttributedString]
    var creationDate: Date?
    var modificationDate: Date?
    
    func createSummaryFile(startTime: Date, summary: String) {
        do {
            try FileManager().createDirectory(at: fullURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            
            let timestamp = startTime.formatted(.dateTime.year().month().day().hour().minute().second())
            let summaryFolderName = "summary-\(timestamp)"
            let summaryFileName = fullURL.deletingPathExtension().lastPathComponent + "_summarized.txt"
            
            let fileManager = FileManager.default
            let folderPath = fullURL.deletingLastPathComponent().appendingPathComponent(summaryFolderName)
            
            
            try fileManager.createDirectory(at: folderPath, withIntermediateDirectories: true, attributes: nil)
            
            let summarizedPDFURL = folderPath.appendingPathComponent(summaryFileName)
            
            try summary.write(to: summarizedPDFURL, atomically: true, encoding: .utf8)
            
            print("File successfully created")
        } catch {
            print("Failed to create directory or write summarized PDF: \(error)")
        }
    }
}

struct ProcessedDocument {
    var rawObject: DocumentObject
    var summary: String?
    var componentsCompletedProcessed: [Int: Bool]? = nil
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
                                    if file.1.componentsCompletedProcessed != nil {
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
            Toggle(isOn: $apiService.showPromptInSummary) {
                Text("Show Prompt In Summary")
            }.frame(maxWidth: .infinity, alignment: .leading)
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
                    Text("Keyphrases")
                    TextField("Phrases", text: $apiService.parsingKeyphrases, axis: .vertical)
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
                            let startTime = Date()
                            for objectPair in viewModel.fileContent {
                                var object = objectPair.value
                                guard let content = objectPair.value.rawObject.textContent else { return }
                                //Split the string up:
                                let subStrings = content.splitStringWithKeywords(keywords: APIService.shared.parsingKeyphrases.components(separatedBy: ","))
                                viewModel.fileContent[objectPair.key]?.componentsCompletedProcessed = subStrings.enumerated().reduce(into: [Int: Bool](), { partialResult, nextElement in
                                    partialResult[nextElement.offset] = false
                                })
                                Task {
                                    
                                    do {
                                        
                                        print("analyzing \(subStrings.count) substrings")
                                        var summary = APIService.shared.showPromptInSummary ? APIService.shared.assistantPrompt + "\n\n ==================== \n\n" : ""
                                        for item in subStrings.enumerated() {
                                            let string = item.element
                                            let subSectionsSummary = try await APIService.shared.summarizeDocument(string, model: APIService.shared.modelId)
                                            print("finished analyzing substring \(item.offset)")
                                            viewModel.fileContent[objectPair.key]?.componentsCompletedProcessed?[item.offset] = true
                                            summary += subSectionsSummary + "\n\n ==================== \n\n"
                                        }
                                        
                                        objectPair.value.rawObject.createSummaryFile(startTime: startTime, summary: summary)
                                        object.summary = summary
                                        
                                    } catch {
                                        print("🔥 Failed to summarize")
                                        print(error)
                                        print(error.localizedDescription)
                                    }
                                    object.componentsCompletedProcessed = nil
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
            if let componentsCompletedProcessed = object.componentsCompletedProcessed {
                HStack {
                    ForEach(componentsCompletedProcessed.keys.sorted(), id: \.self) { key in
                        if let value = componentsCompletedProcessed[key] {
                            Text(value ? "✅" : "⏳")
                        }
                    }
                }
            }
            SheetButton { _ in
                ScrollView {
                    Text(object.rawObject.textContent ?? "--").textSelection(.enabled)
                        .padding()
                }
            } buttonContent: {
                Text("See original text")
            }
            .buttonStyle(.bordered)

            
            
            ScrollView {
//                let attString = object.rawObject.attributedContent.asSingularString(delimiter: "🔵🔵🔵🔵🔵🔵🔵🔵")
//                if !attString.string.isEmpty {
//                    Text(AttributedString(attString)).textSelection(.enabled)
//                }
                
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
    @AppStorage("showPromptInSummary") var showPromptInSummary: Bool = true
    @AppStorage("openAIKey") var apiKey: String = ""
    @AppStorage("modelId") var modelId: String = ""
    @AppStorage("assistantPrompt") var assistantPrompt: String = ""
    @AppStorage("maxTokens") var maxTokens: Int = 200
    @AppStorage("parsingKeyphrases") var parsingKeyphrases: String = ""
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

extension Array where Element == NSAttributedString {
    func asSingularString(delimiter: String = "") -> NSAttributedString {
        let returnValue = NSMutableAttributedString()
        
        for item in self {
            returnValue.append(item)
            returnValue.append(.init(string: delimiter))
        }
        return returnValue
    }
}

extension String {
    func splitStringWithKeywords(keywords: [String]) -> [String] {
        var splitStrings: [String] = []
        var stringToParse = self.lowercased()
        for item in keywords.enumerated() {
            let keyword = item.element
            let isLastWord = item.offset == keywords.count - 1
            print("searching for `\(keyword)`")
            var components = stringToParse.components(separatedBy: keyword.lowercased())
            if components.count > 1 {
                splitStrings.append(components.removeFirst() + keyword)
                
                let newStringToParse = components.joined(separator: keyword)
                stringToParse = newStringToParse
            } else {
                print("\(keyword) not found")
            }
            if isLastWord {
                splitStrings.append(stringToParse)
            }
        }
        
        return splitStrings
    }
}

struct SheetButton<S: View, B: View>: View {
    @State var showSheet = false
    @ViewBuilder let sheetContent: (Binding<Bool>) -> S
    @ViewBuilder let buttonContent: () -> B
    var body: some View {
        buttonContent().onTapGesture {
            self.showSheet = true
        }
        .sheet(isPresented: $showSheet){
            sheetContent($showSheet)
        }
    }
}
