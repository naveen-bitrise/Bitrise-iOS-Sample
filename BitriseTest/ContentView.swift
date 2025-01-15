//
//  ContentView.swift
//  BitriseTest
//
//  Created by Damien Murphy on 1/28/21.
//

import SwiftUI
import Swifter

struct ContentView: View {
    @State private var resultText = ""
    private let server = HttpServer()
    
    var body: some View {
        VStack {
            Button("Start Server") {  // Add a button to start server
                do {
                    try server.start(8080)
                    server.GET["/test"] = { request in
                        HttpResponse.ok(.text("Hello from Swifter!"))
                    }
                    resultText = "Server started!"
                } catch {
                    resultText = "Server error: \(error)"
                }
            }
            .padding()
            
            Button("Make HTTP Call") {
                Task {
                    await makeHTTPCall()
                }
            }
            .padding()
            
            Text(resultText)
                .padding()
        }
    }
    
    func makeHTTPCall() async {
        guard let url = URL(string: "http://localhost:8080/test") else {
            resultText = "Error: Invalid URL"
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let responseString = String(data: data, encoding: .utf8) {
                resultText = "Success: \(responseString)"
            }
        } catch {
            resultText = "Error: \(error.localizedDescription)"
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
