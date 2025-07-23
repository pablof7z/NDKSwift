import SwiftUI

/// A view that loads content asynchronously and displays it when ready
struct AsyncContentView<Content: View, T>: View {
    let operation: () async -> T
    let content: (T) -> Content
    
    @State private var result: T?
    @State private var isLoading = true
    @State private var error: Error?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let error = error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    
                    Text("Error loading content")
                        .font(.headline)
                    
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else if let result = result {
                content(result)
            } else {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .task {
            isLoading = true
            error = nil
            
            do {
                try Task.checkCancellation() // Check if cancelled
                result = await operation()
            } catch {
                self.error = error
            }
            
            isLoading = false
        }
    }
}

/// A view that observes a data source and displays its content
struct DataSourceContentView<Content: View, DataSource: ObservableObject>: View where DataSource: AnyObject {
    @ObservedObject var dataSource: DataSource
    let loadingView: () -> AnyView
    let errorView: (Error) -> AnyView
    let content: () -> Content
    
    init(
        dataSource: DataSource,
        @ViewBuilder content: @escaping () -> Content,
        loadingView: @escaping () -> AnyView = { AnyView(ProgressView().frame(maxWidth: .infinity).padding()) },
        errorView: @escaping (Error) -> AnyView = { error in
            AnyView(
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    
                    Text("Error")
                        .font(.headline)
                    
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            )
        }
    ) {
        self.dataSource = dataSource
        self.content = content
        self.loadingView = loadingView
        self.errorView = errorView
    }
    
    var body: some View {
        Group {
            // Check if dataSource has isLoading property
            if let mirror = Mirror(reflecting: dataSource).children.first(where: { $0.label == "isLoading" }),
               let isLoading = mirror.value as? Bool,
               isLoading {
                loadingView()
            }
            // Check if dataSource has error property
            else if let mirror = Mirror(reflecting: dataSource).children.first(where: { $0.label == "error" }),
                    let error = mirror.value as? Error {
                errorView(error)
            } else {
                content()
            }
        }
    }
}